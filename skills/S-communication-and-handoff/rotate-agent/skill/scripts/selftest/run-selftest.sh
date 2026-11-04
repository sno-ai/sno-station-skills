#!/usr/bin/env bash
# Self-test for the rotate-agent skill: exercises scripts/rotate-agent-watch against a fake quota
# command and checks the packaged SKILL.md. Touches nothing outside this skill.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(cd -- "$HERE/../.." && pwd)"
check_resume_text() {
  local text
  text="$(cat "$SKILL/SKILL.md")"
  if grep -Fq 'next_action=completed|unfinished|blocked' <<<"$text" &&
     grep -q 'Startup, readiness and release report the action unfinished' <<<"$text"; then
    printf 'PASS resume text separates recovery outcome from action completion\n'
  else
    printf 'FAIL resume text separates recovery outcome from action completion\n'
    return 1
  fi
}
if [[ "${1:-}" == resume-contract ]]; then check_resume_text; exit; fi
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
export QUOTA_LOG="$TMP/quota.log" QUOTA_FIXTURES="$TMP/fixtures"
mkdir -p "$QUOTA_FIXTURES"
printf '%s\n' '{"ok":true,"agent":"hermes","model":"gpt-test","provider":"openai-codex","model_vendor":"openai","vendor":{"verdict":"short_only","tightest_window":{"used_pct":99.0,"seconds_to_reset":123}}}' >"$QUOTA_FIXTURES/sender.json"
printf '%s\n' '{"ok":true,"from":{"agent":"hermes","model":"gpt-test","provider":"openai-codex","vendor":"openai","verdict":"short_only"},"candidates":[{"agent":"hermes","model":"qwen-test","provider":"local-reason","vendor":"local:local-reason","in_place":true,"verdict":"unread"},{"agent":"claude-code","model":"sonnet-test","provider":"anthropic","vendor":"anthropic","in_place":false,"verdict":"go"}]}' >"$QUOTA_FIXTURES/pick.json"
run() {
  "$WATCH" --from "${FROM_OVERRIDE:-hermes}" --seat sender@host --state "$TMP/watch.state" --cwd "$REPO" --quota-cmd "$FAKE"
}
out=$(run)
check "crossing includes ordered unread and next-agent candidates" 'ROTATE from=hermes seat=sender@host remaining=1%' "$out"
[[ "$out" == *'"model":"qwen-test"'* && "$out" == *'"verdict":"unread"'* && "$out" == *'"agent":"claude-code"'* ]] || fail=1
check "a trigger does not claim a successful handoff" "0" "$(test -e "$TMP/watch.state" && printf 1 || printf 0)"
check "the sender-only read uses its own seat" '--agent hermes --seat sender@host --json' "$(head -n1 "$QUOTA_LOG")"
check "the crossing asks for the ordered handoff pick" '--pick handoff --from hermes --seat sender@host --json' "$(tail -n1 "$QUOTA_LOG")"
printf '%s\n' 'switched 2026-10-09T00:00:00Z model=qwen-test vendor=local:local-reason' >"$TMP/watch.state"
out=$(run)
check "a switched record permits the second crossing" "ROTATE from=hermes" "$out"
sed -i 's/short_only/wait/g;s/99.0/null/g' "$QUOTA_FIXTURES/sender.json"
out=$(run)
check "a direct jump to wait triggers the pick" "ROTATE from=hermes" "$out"
[[ "$out" == *'verdict=wait'* ]] || fail=1
sed -i 's/wait/owner_action/g' "$QUOTA_FIXTURES/sender.json"
check "owner action also triggers" "ROTATE from=hermes" "$(run)"
printf '%s\n' '{"ok":true,"candidates":[],"chosen":null}' >"$QUOTA_FIXTURES/pick.json"
check "no candidate keeps watching" "HOLD no-candidate" "$(run)"
sed -i 's/owner_action/go/g;s/used_pct":null/used_pct":95/g' "$QUOTA_FIXTURES/sender.json"
: >"$QUOTA_LOG"
check "healthy sender holds" "HOLD from=hermes remaining=5%" "$(run)"
check "healthy tick reads no other agent" "1" "$(wc -l <"$QUOTA_LOG" | tr -d ' ')"
for sender in claude-code codex cursor hermes openclaw; do
  check "accepts $sender sender" "HOLD from=$sender" "$(FROM_OVERRIDE="$sender" run)"
done
if "$WATCH" --from codex --to claude-code-code --seat sender@host --state "$TMP/x" --cwd "$REPO" --quota-cmd "$FAKE" >/dev/null 2>&1; then rc=0; else rc=$?; fi
check "removed --to is rejected" "2" "$rc"
printf 'rotated %s from=hermes to=claude-code remaining=1%% commits=1\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$TMP/watch.state"
check "real handoff is done until the receiver commits" 'DONE rotated' "$(run)"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m receiver
check "receiver progress completes recorded handoff" 'COMPLETE from=hermes to=claude-code' "$(run)"
check "completion event uses the real receiver agent id" '1' "$(grep -c 'handoff.complete --agent=claude-code ' "$OBSERVE_LOG")"
# Cursor uses the sender seat and the same ordered candidate mechanism as every agent.
rm -f "$TMP/watch.state"
printf '%s\n' '{"ok":true,"agent":"cursor","model":"gpt-test","provider":"openai-codex","vendor":{"verdict":"short_only","tightest_window":{"used_pct":99,"seconds_to_reset":123}}}' >"$QUOTA_FIXTURES/sender.json"
printf '%s\n' '{"ok":true,"from":{"agent":"cursor","model":"gpt-test","provider":"openai-codex","vendor":"openai","verdict":"short_only"},"candidates":[{"agent":"codex","model":"gpt-test","provider":"openai-codex","vendor":"openai","in_place":false,"verdict":"go"}]}' >"$QUOTA_FIXTURES/pick.json"
: >"$QUOTA_LOG"
out=$(FROM_OVERRIDE=cursor run)
check "a Cursor sender below the threshold requests rotation" 'ROTATE from=cursor seat=sender@host remaining=1%' "$out"
check "Cursor reads its own seat and then requests candidates" '--agent cursor --seat sender@host --json|--pick handoff --from cursor --seat sender@host --json' "$(paste -sd'|' "$QUOTA_LOG")"
check "Cursor retains the selected Codex receiver" 'codex' "$(sed 's/.*candidates=//' <<<"$out" | jq -r '.[0].agent')"
printf '%s\n' '{"ok":true,"from":{"agent":"claude-code","vendor":"anthropic"},"candidates":[{"agent":"cursor","model":"gpt-test","provider":"openai-codex","vendor":"openai","in_place":false,"verdict":"go"}]}' >"$QUOTA_FIXTURES/pick.json"
out=$(FROM_OVERRIDE=claude-code run)
check "Claude can choose a Cursor receiver" 'cursor' "$(sed 's/.*candidates=//' <<<"$out" | jq -r '.[0].agent')"
sed -i 's/used_pct":99/used_pct":98.5/' "$QUOTA_FIXTURES/sender.json"
out=$(FROM_OVERRIDE=cursor run)
check "Cursor fractional quota is compared by its whole part" 'ROTATE from=cursor seat=sender@host remaining=2%' "$out"
# Preflight requires cursor-agent, rather than the IDE launcher.
PF="$TMP/pfbin"; mkdir -p "$PF"
cat >"$PF/sno" <<'SNO'
#!/usr/bin/env bash
case "$*" in "reach --version") echo 2.1.0 ;; "reach seats --json") echo '{"address":"hand.repo@host"}' ;; *) exit 1 ;; esac
SNO
for c in tmux cursor codex; do printf '#!/usr/bin/env bash\nexit 0\n' >"$PF/$c"; done
chmod +x "$PF"/*
out=$(PATH="$PF:/usr/bin:/bin" "$PREFLIGHT" --from claude-code --to cursor --cwd "$REPO" --quota-cmd "$FAKE" || true)
check "preflight rejects an IDE launcher without the Cursor CLI" 'FAIL receiver-command: cursor is not on PATH' "$(grep -m1 FAIL <<<"$out")"
: >"$QUOTA_LOG"
out=$(PATH="$PF:/usr/bin:/bin" "$PREFLIGHT" --from cursor --to codex --cwd "$REPO" --sender hand.repo@host --quota-cmd "$FAKE" || true)
check "preflight reads Cursor quota for the sender seat" 'OK quota-to|--agent cursor --json --seat hand.repo@host' "$(grep -m1 quota-to <<<"$out")|$(head -n1 "$QUOTA_LOG")"
front="$(sed -n '1,/^---$/!d;p' "$SKILL/SKILL.md" | sed -n '2,$p')"
ok=1; grep -q '^name: rotate-agent$' <<<"$front" || ok=0
for p in subscription-quota-check heartbeat reach; do grep -q "name: $p" <<<"$front" || ok=0; done
check "9 SKILL.md frontmatter names unit and programs" "1" "$ok"
body="$(sed '1,/^---$/d' "$SKILL/SKILL.md")"
ok=1; grep -q 'rotate-agent-resume --to <agent> --cwd <checkout> --checkpoint <record> --work <work>' <<<"$body" && grep -q 'spawn --window' <<<"$body" || ok=0
check "10 fallback receiver is started by one command on a tmux window" "1" "$ok"
check_resume_text || fail=1
ok=1; grep -q 'A seat marked `stale`.*is not proof that its agent is gone' <<<"$body" || ok=0
check "12 stale seat is not death" "1" "$ok"
if "$PREFLIGHT" --from codex --to codex --cwd "$TMP" >/dev/null 2>&1; then rc=0; else rc=$?; fi
check "13 preflight rejects identical fixed agents" "2" "$rc"
out=$("$PREFLIGHT" --from codex --to claude-code --cwd "$TMP" --quota-cmd "$TMP/no-such-quota-cmd" || true)
check "14 preflight fails first on a missing tool" "FAIL tools: $TMP/no-such-quota-cmd is not on PATH" "$out"
ok=1; grep -q 'rotate-agent-preflight --from codex --to claude-code --cwd <checkout>' <<<"$body" && grep -q 'Do not arm on a `FAIL`' <<<"$body" || ok=0
check "15 skill runs the preflight before arming" "1" "$ok"
bash "$HERE/switch-provider.t" >"$TMP/switch.out" 2>&1 && printf 'PASS switch and provider behaviour\n' || { cat "$TMP/switch.out"; fail=1; }
bash "$SKILL/scripts/rotate-agent-resume.t" >"$TMP/resume.out" 2>&1 && printf 'PASS 16 rotate-agent-resume behaviour test\n' || { printf 'FAIL 16 rotate-agent-resume behaviour test\n'; sed 's/^/# /' "$TMP/resume.out"; fail=1; }
exit "$fail"
