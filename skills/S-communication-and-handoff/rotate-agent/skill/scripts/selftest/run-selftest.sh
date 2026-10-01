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
check() { # name expected-prefix actual
  if [[ "$3" == "$2"* ]]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s: got %q\n' "$1" "$3"; fail=1; fi
}
run() { # from to state ; env supplies the fake verdicts
  "$WATCH" --from "$1" --to "$2" --state "$3" --quota-cmd "$FAKE"
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
if "$WATCH" --from codex --to codex --state "$TMP/d" --quota-cmd "$FAKE" >/dev/null 2>&1; then rc=0; else rc=$?; fi
check "8 same vendor both seats is usage error" "2" "$rc"
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
