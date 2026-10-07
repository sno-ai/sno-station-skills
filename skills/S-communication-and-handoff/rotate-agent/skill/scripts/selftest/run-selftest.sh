#!/usr/bin/env bash
# Self-test for the rotate-agent skill: exercises scripts/rotate-agent-watch against a fake quota
# command and checks the packaged SKILL.md. Touches nothing outside this skill.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(cd -- "$HERE/../.." && pwd)"
WATCH="$SKILL/scripts/rotate-agent-watch"
PREFLIGHT="$SKILL/scripts/rotate-agent-preflight"
FAKE="$HERE/fake-quota"
TMP="$(mktemp -d)"; trap 'rm -rf -- "$TMP"' EXIT
fail=0
# Recording stand-in for `sno observe` (the real tool uploads); FAKE_OBSERVE_EXIT makes it fail.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/sno" <<'OBS'
#!/usr/bin/env bash
[[ "${1:-}" == observe ]] || exit 64
shift
printf '%s\n' "$*" >>"$OBSERVE_LOG"
exit "${FAKE_OBSERVE_EXIT:-0}"
OBS
chmod +x "$TMP/bin/sno"
export OBSERVE_LOG="$TMP/observe.log"; : >"$OBSERVE_LOG"
export PATH="$TMP/bin:$PATH"
REPO="$TMP/repo"; git init -q "$REPO"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
check() { # name expected-prefix actual
  if [[ "$3" == "$2"* ]]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s: got %q\n' "$1" "$3"; fail=1; fi
}
run() { # from to state ; env supplies the fake verdicts
  "$WATCH" --from "$1" --to "$2" --state "$3" --cwd "${CWD_OVERRIDE:-$REPO}" --quota-cmd "$FAKE"
}
out=$(FAKE_FROM_VERDICT=short_only FAKE_FROM_USED=95 FAKE_TO_VERDICT=go run codex claude "$TMP/a")
check "1 above threshold holds" "HOLD from=codex remaining=5%" "$out"
out=$(FAKE_FROM_VERDICT=short_only FAKE_FROM_USED=99 FAKE_TO_VERDICT=wait run codex claude "$TMP/a")
check "2 receiver blocked holds" "HOLD receiver-wait" "$out"
out=$(FAKE_FROM_VERDICT=short_only FAKE_FROM_USED=99 FAKE_TO_VERDICT=go run codex claude "$TMP/a")
check "3 crossing rotates" "ROTATE from=codex to=claude remaining=1%" "$out"
check "3b state file records rotation" "rotated " "$(cat "$TMP/a")"
out=$(FAKE_FROM_VERDICT=short_only FAKE_FROM_USED=99 FAKE_TO_VERDICT=go run codex claude "$TMP/a")
check "4 second tick is locked" "DONE rotated" "$out"
out=$(FAKE_FROM_VERDICT=wait FAKE_FROM_USED=100 FAKE_TO_VERDICT=go run codex claude "$TMP/b")
check "5 sender already blocked is late" "LATE blocked" "$out"
out=$(FAKE_FROM_VERDICT=unknown FAKE_FROM_USED=null FAKE_TO_VERDICT=go run codex claude "$TMP/b")
check "6 unreadable holds" "HOLD unreadable" "$out"
out=$(FAKE_FROM_VENDOR=claude FAKE_FROM_VERDICT=go FAKE_FROM_USED=99 FAKE_TO_VERDICT=go run claude codex "$TMP/c")
check "7 reverse direction rotates" "ROTATE from=claude to=codex" "$out"
if "$WATCH" --from codex --to codex --state "$TMP/d" --cwd "$REPO" --quota-cmd "$FAKE" >/dev/null 2>&1; then rc=0; else rc=$?; fi
check "8 same vendor both seats is usage error" "2" "$rc"
# --- event upload (rotate-agent-watch -> sno observe) ---
check "17 trigger sent once at the order" "1" "$(grep -c '^append handoff.trigger --agent=codex .*--from_harness=codex --to_harness=claude-code --remaining_pct=1 --threshold_pct=2$' "$OBSERVE_LOG")"
check "18 four low ticks on one state send one reading (5% left); the refused sender's reading (0%) is still sent" "2|5|0" "$(grep -c 'handoff.quota --agent=codex' "$OBSERVE_LOG")|$(grep -o 'remaining_pct=[0-9]*' <<<"$(grep 'handoff.quota' "$OBSERVE_LOG")" | cut -d= -f2 | paste -sd'|')"
: >"$OBSERVE_LOG"
FAKE_FROM_VERDICT=go FAKE_FROM_USED=50 FAKE_TO_VERDICT=go run codex claude "$TMP/e" >/dev/null
check "19 a healthy reading sends nothing" "0" "$(wc -l <"$OBSERVE_LOG" | tr -d ' ')"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m second
out=$(FAKE_FROM_VERDICT=short_only FAKE_FROM_USED=99 FAKE_TO_VERDICT=go run codex claude "$TMP/a")
check "20 first new commit after the order completes" "COMPLETE from=codex to=claude seconds=" "$out"
check "20b completion event carries the receiver and both counts" "1" "$(grep -c '^append handoff.complete --agent=claude-code .*--sender_remaining_pct=1 --commits_before=1 --commits_after=2$' "$OBSERVE_LOG")"
: >"$OBSERVE_LOG"
out=$(FAKE_FROM_VERDICT=short_only FAKE_FROM_USED=99 FAKE_TO_VERDICT=go run codex claude "$TMP/a")
check "20c later tick is DONE and sends nothing" "DONE rotated 0" "${out:0:12} $(wc -l <"$OBSERVE_LOG" | tr -d ' ')"
if FAKE_FROM_VERDICT=go FAKE_FROM_USED=50 FAKE_TO_VERDICT=go "$WATCH" --from codex --to claude --state "$TMP/f" --quota-cmd "$FAKE" >/dev/null 2>&1; then rc=0; else rc=$?; fi
check "21 missing --cwd is a usage error" "2" "$rc"
out=$(PATH="$TMP/nobin:/usr/bin:/bin" FAKE_FROM_VERDICT=short_only FAKE_FROM_USED=99 FAKE_TO_VERDICT=go run codex claude "$TMP/g" 2>"$TMP/err")
check "22 tool missing: still ROTATE" "ROTATE from=codex to=claude" "$out"
check "22b tool missing: one not-recorded line" "sno: not found; handoff.trigger event not recorded" "$(grep 'handoff.trigger' "$TMP/err")"
out=$(FAKE_OBSERVE_EXIT=3 FAKE_FROM_VERDICT=short_only FAKE_FROM_USED=99 FAKE_TO_VERDICT=go run codex claude "$TMP/h" 2>"$TMP/err")
check "23 tool failing: still ROTATE" "ROTATE from=codex to=claude" "$out"
check "23b tool failing: names event and exit" "sno observe append handoff.trigger failed (exit 3); event not recorded" "$(grep 'handoff.trigger' "$TMP/err")"
mkdir -p "$TMP/nogit"
out=$(CWD_OVERRIDE="$TMP/nogit" FAKE_FROM_VERDICT=short_only FAKE_FROM_USED=99 FAKE_TO_VERDICT=go run codex claude "$TMP/i" 2>"$TMP/err")
check "24 unreadable checkout does not stop the rotation" "ROTATE from=codex to=claude" "$out"
check "24b unreadable checkout is logged" "rotate-agent-watch: git rev-list failed in " "$(grep 'rev-list' "$TMP/err")"
# macOS: no `timeout`, and BSD date rejects GNU `-d`. Only the tools the watch uses are on PATH.
MAC="$TMP/macbin"; mkdir -p "$MAC"
for c in bash jq git grep mkdir dirname mv cat; do ln -s "$(command -v "$c")" "$MAC/$c"; done
ln -s "$TMP/bin/sno" "$MAC/sno"
cat >"$MAC/date" <<DATE
#!$(command -v bash)
for a in "\$@"; do [[ "\$a" == -d ]] && { echo "date: illegal option -- d" >&2; exit 1; }; done
exec $(command -v date) "\$@"
DATE
chmod +x "$MAC/date"
: >"$OBSERVE_LOG"
out=$(PATH="$MAC" FAKE_FROM_VERDICT=short_only FAKE_FROM_USED=99 FAKE_TO_VERDICT=go run codex claude "$TMP/m" 2>"$TMP/err")
check "25 macOS-like tools: the order is sent without timeout" "1|ROTATE from=codex to=claude" "$(grep -c '^append handoff.trigger ' "$OBSERVE_LOG")|$out"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m third
out=$(PATH="$MAC" FAKE_FROM_VERDICT=short_only FAKE_FROM_USED=99 FAKE_TO_VERDICT=go run codex claude "$TMP/m" 2>"$TMP/err")
check "25b macOS-like tools: the first new commit completes and is sent" "1|COMPLETE from=codex to=claude seconds=" "$(grep -c '^append handoff.complete --agent=claude-code .*--commits_before=2 --commits_after=3$' "$OBSERVE_LOG")|$out"
FAKE_RESET=null FAKE_FROM_VERDICT=go FAKE_FROM_USED=50 FAKE_TO_VERDICT=go run codex claude "$TMP/n" >/dev/null 2>"$TMP/err"
check "26 a healthy reading without a reset time logs nothing" "0" "$(wc -l <"$TMP/err" | tr -d ' ')"
front="$(sed -n '1,/^---$/!d;p' "$SKILL/SKILL.md" | sed -n '2,$p')"
ok=1; grep -q '^name: rotate-agent$' <<<"$front" || ok=0
for p in subscription-quota-check heartbeat reach; do grep -q "name: $p" <<<"$front" || ok=0; done
check "9 SKILL.md frontmatter names unit and programs" "1" "$ok"
body="$(sed '1,/^---$/d' "$SKILL/SKILL.md")"
ok=1; grep -q 'rotate-agent-resume --to <to-vendor> --cwd <checkout> --checkpoint <record> --work <work>' <<<"$body" && grep -q 'spawn --window' <<<"$body" || ok=0
check "10 fallback receiver is started by one command on a tmux window" "1" "$ok"
ok=1; grep -q 'BLOCKED_<work> <reason>' <<<"$body" && grep -q 'never prints `DONE_<work>` while any task waits on the owner' <<<"$body" || ok=0
check "11 resume prompt separates done from blocked" "1" "$ok"
ok=1; grep -q 'A seat marked `stale`.*is not proof that its agent is gone' <<<"$body" || ok=0
check "12 stale seat is not death" "1" "$ok"
if "$PREFLIGHT" --from codex --to codex --cwd "$TMP" >/dev/null 2>&1; then rc=0; else rc=$?; fi
check "13 preflight rejects same vendor both seats" "2" "$rc"
out=$("$PREFLIGHT" --from codex --to claude --cwd "$TMP" --quota-cmd "$TMP/no-such-quota-cmd" || true)
check "14 preflight fails first on a missing tool" "FAIL tools: $TMP/no-such-quota-cmd is not on PATH" "$out"
ok=1; grep -q 'rotate-agent-preflight --from codex --to claude --cwd <checkout>' <<<"$body" && grep -q 'Do not arm on a `FAIL`' <<<"$body" || ok=0
check "15 skill runs the preflight before arming" "1" "$ok"
bash "$SKILL/scripts/rotate-agent-resume.t" >"$TMP/resume.out" 2>&1 && printf 'PASS 16 rotate-agent-resume behaviour test\n' || { printf 'FAIL 16 rotate-agent-resume behaviour test\n'; sed 's/^/# /' "$TMP/resume.out"; fail=1; }
exit "$fail"
