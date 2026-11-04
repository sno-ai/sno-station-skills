#!/usr/bin/env bash
# Exercise the real recovery command, brief writer and filesystem. External native CLIs and
# Reach agent startup/calls are stand-ins here; real agent action/ownership proof runs in Station.
set -Eeuo pipefail
unset CLAUDE_SESSION_ID CODEX_THREAD_ID
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
command_path="${1:-$here/rotate-agent-resume}"
# The sibling handoff script: the source tree has a skill/ level, the published copy is flat, and a deploy stages
# this unit alone, beside the handoff skill already deployed to the same root.
checkpoint_cmd=''
for candidate in "$here/../../../handoff/skill/scripts/handoff-checkpoint" "$here/../../handoff/scripts/handoff-checkpoint" \
  "$HOME/.claude/skills/handoff/scripts/handoff-checkpoint" "$HOME/.agents/skills/handoff/scripts/handoff-checkpoint"; do
  checkpoint_cmd="$(realpath -e "$candidate" 2>/dev/null)" && break
done
[[ -n "$checkpoint_cmd" ]] || { printf 'rotate-agent-resume.t: handoff-checkpoint not found in source, published or deployed layout\n' >&2; exit 1; }
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin" "$root/reach" "$root/work"
export FIXTURE_ROOT="$root" SNO_REACH_STATE_ROOT="$root/reach" SNO_PROFILE_DIR="$root/profile"
cat >"$root/bin/claude" <<'SH'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >>"$FIXTURE_ROOT/native"
[[ -z "${NATIVE_FAIL:-}" ]] || { printf 'recorded native session is unavailable\n' >&2; exit 1; }
[[ -z "${NATIVE_EMPTY:-}" ]] || exit 0
printf 'continued exact conversation\n'
[[ -n "${NATIVE_NO_ACTION:-}" ]] || printf 'CONTINUITY_ACTION completed\n'
SH
cat >"$root/bin/codex" <<'SH'
#!/usr/bin/env bash
printf 'codex %s\n' "$*" >>"$FIXTURE_ROOT/native"
[[ -z "${NATIVE_FAIL:-}" ]] || { printf 'recorded native session is unavailable\n' >&2; exit 1; }
printf 'CONTINUITY_ACTION completed\n'
SH
cat >"$root/bin/sno" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == subscription-quota-check ]]; then
  printf '%s\n' "{\"vendor\":{\"verdict\":\"${QUOTA_VERDICT:-go}\"}}"
  exit "${QUOTA_STATUS:-0}"
fi
[[ "$1" == reach ]] || exit 64
shift
verb="$1"; shift
if [[ "$verb" == call ]]; then
  seat="$1"; prompt="$2"; shift 2
  printf '%s\n' "$prompt" >>"$FIXTURE_ROOT/prompts"
  nonce="$(sed -n 's/.*HANDOFF_READY \([a-f0-9]*\).*/\1/p' <<<"$prompt" | head -n1)"
  if [[ "$prompt" == HANDOFF_RELEASE* ]]; then
    printf '%s\n' "$seat" >>"$FIXTURE_ROOT/released"
    [[ -z "${RELEASE_FAIL:-}" ]] || { printf 'receiver receipt was not observed\n' >&2; exit 4; }
    nonce="$(awk '{gsub(/\./,"",$2); print $2}' <<<"$prompt")"
    printf 'HANDOFF_RELEASED %s\n' "$nonce"
  elif [[ -n "${READY_LOST:-}" ]]; then printf 'HANDOFF_LOST %s\n' "$nonce"
  else printf 'HANDOFF_READY %s\n' "$nonce"
  fi
  exit 0
fi
seat=''; kind="${1:-}"
while (( $# )); do
  case "$1" in --as) seat="$2"; shift ;; esac
  shift
done
case "$verb" in
  init|watch) exit 0 ;;
  spawn)
    printf '%s %s\n' "$kind" "$seat" >>"$FIXTURE_ROOT/spawned"
    [[ -z "${SPAWN_FAIL:-}" ]] || { printf 'external startup failed\n' >&2; exit 1; }
    mkdir -p "$SNO_REACH_STATE_ROOT/$seat"
    printf '{}\n' >"$SNO_REACH_STATE_ROOT/$seat/reachable.json" ;;
  *) exit 64 ;;
esac
SH
chmod +x "$root/bin/claude" "$root/bin/codex" "$root/bin/sno"
export PATH="$root/bin:/usr/bin:/bin"
git -C "$root/work" init -q -b main
printf 'input\n' >"$root/work/input.txt"
git -C "$root/work" add input.txt
git -C "$root/work" -c user.name=T -c user.email=t@example.invalid commit -qm fixture
record="$root/progress.md"
(cd "$root/work" && CLAUDE_SESSION_ID=exact-claude "$checkpoint_cmd" "$record" >/dev/null)
python3 - "$record" <<'PY2'
from pathlib import Path
import sys
p=Path(sys.argv[1]); text=p.read_text()
for heading,value in {'Objective and authorization':'Owner authorizes the unfinished input calculation only.',
  'Next':'Compute the requested result from input.txt; expected file result.txt contains its real sum.',
  'Known failure':'read missing-input.txt failed: no such file. Do not repeat the failed read.',
  'Report destination':'Owner session; no original work card exists.'}.items():
    text=text.replace('## '+heading+'\n','## '+heading+'\n'+value+'\n')
p.write_text(text)
PY2
count=0
ok() { count=$((count+1)); printf 'ok %s - %s\n' "$count" "$1"; }
fail() { printf 'not ok %s - %s\n' "$((count+1))" "$1"; cat "$root/out" "$root/err" 2>/dev/null || true; exit 1; }
run() { local rc=0; "$command_path" "$@" >"$root/out" 2>"$root/err" || rc=$?; printf '%s' "$rc"; }
recover() { run --to "${TARGET:-codex}" --cwd "$root/work" --checkpoint "${RECORD:-$record}" --work "$1" --checkpoint-cmd "${VERIFY_CMD:-$checkpoint_cmd}"; }
reset_calls() { : >"$root/native"; : >"$root/spawned"; : >"$root/prompts"; : >"$root/released"; }
reset_calls
[[ "$(run)" == 0 && "$(run --help)" == 0 && "$(run --to nobody)" == 2 ]] || fail usage
ok 'usage does not start any agent'
[[ "$(recover native)" == 0 ]] && grep -qx 'resumed next_action=completed session=exact-claude' "$root/out" || fail 'exact native resume'
grep -q '^claude -p --resume exact-claude ' "$root/native" && [[ ! -s "$root/spawned" ]] || fail 'native identity and fallback order'
ok 'exact recorded native conversation is tried before a requested other vendor'
reset_calls
[[ "$(NATIVE_NO_ACTION=1 recover unfinished)" == 0 ]] && grep -q '^resumed next_action=unfinished ' "$root/out" || fail 'process exit is not task completion'
ok 'a native process without an action result does not report completion'
reset_calls
[[ "$(NATIVE_FAIL=1 recover rebuilt)" == 0 ]] && grep -q '^rebuilt next_action=unfinished .*original_conversation=lost$' "$root/out" || fail 'same-vendor rebuild'
grep -q '^claude ' "$root/spawned" && ! grep -q '^codex ' "$root/spawned" || fail 'same vendor before other vendor'
grep -q 'HANDOFF_RELEASED' "$root/prompts" && ! grep -q 'RESUME_' "$root/prompts" || fail 'single handoff receipt protocol'
grep -q 'scoped memory retrieval' "$root/prompts" && grep -q 'Known failure' "$root/prompts" || fail 'complete brief and existing retrieval entry'
ok 'native failure rebuilds with the same vendor and one handoff protocol, action unfinished'
reset_calls
[[ "$(QUOTA_VERDICT='wait' recover exhausted)" == 0 ]] && [[ ! -s "$root/native" ]] && grep -q '^codex ' "$root/spawned" || fail 'known exhaustion skips original vendor'
grep -q 'quota exhausted' "$root/err" || fail 'quota blocker logged'
ok 'known exhausted quota skips original-vendor inference and uses the other vendor'
reset_calls
mv "$root/bin/codex" "$root/bin/codex-disabled"
status="$(QUOTA_VERDICT='wait' recover sole)"
mv "$root/bin/codex-disabled" "$root/bin/codex"
[[ "$status" == 1 && ! -s "$root/native" && ! -s "$root/spawned" && -f "$record" ]] || fail 'single vendor blocked with retained brief'
grep -q 'no recovery completed next_action=blocked.*other-vendor takeover skipped' "$root/out" && ! grep -q '^lost' "$root/out" || fail 'quota blocked is not lost'
ok 'single-vendor exhaustion retains recoverable work and honestly skips takeover'
reset_calls
[[ "$(QUOTA_VERDICT=unknown QUOTA_STATUS=4 recover unknown)" == 0 ]] && [[ -s "$root/native" ]] || fail 'unknown/auth does not mean exhausted'
! grep -q '^quota exhausted' "$root/err" || fail 'authentication was mislabeled exhausted'
ok 'unknown/authentication quota still attempts exact native resume'
reset_calls
sed '/^session-id:/d' "$record" >"$root/no-session.md"
[[ "$(RECORD="$root/no-session.md" recover no-session)" == 0 && ! -s "$root/native" ]] && grep -q '^claude ' "$root/spawned" || fail 'missing optional session identity'
ok 'missing native identity skips only native resume'
reset_calls
[[ "$(NATIVE_FAIL=1 VERIFY_CMD="$root/not-installed" recover verify-failed)" == 0 ]] && grep -q '^rebuilt ' "$root/out" || fail 'auxiliary verification blocks readable brief'
grep -q 'operation=verify' "$root/err" || fail 'auxiliary failure unlogged'
ok 'failed checkout observation logs its cause and retains usable task facts'
reset_calls
[[ "$(NATIVE_FAIL=1 RELEASE_FAIL=1 recover uncertain)" == 1 ]] && [[ "$(wc -l <"$root/spawned")" == 1 ]] || fail 'uncertain release starts competing receiver'
grep -q 'transfer unresolved' "$root/err" && ! grep -q '^rebuilt ' "$root/out" || fail 'uncertain release reported recovery'
ok 'missing release receipt prevents a second receiver and reports unresolved transfer'
reset_calls
[[ "$(NATIVE_FAIL=1 READY_LOST=1 recover lost)" == 1 ]] && grep -q '^lost next_action=blocked ' "$root/out" && [[ ! -s "$root/released" ]] || fail 'receiver cannot recover essential facts'
ok 'receiver-reported missing essential facts is lost and is not released'
reset_calls
printf '# Empty task\n' >"$root/empty.md"
[[ "$(RECORD="$root/empty.md" recover empty)" == 1 ]] && grep -q '^lost next_action=blocked ' "$root/out" && [[ ! -s "$root/spawned" ]] || fail 'missing task facts invented a task'
ok 'missing objective/next action produces lost without inventing work'
reset_calls
[[ "$(NATIVE_FAIL=1 recover duplicate)" == 0 ]] || fail 'initial duplicate scenario'
[[ "$(NATIVE_FAIL=1 recover duplicate)" == 1 && "$(wc -l <"$root/spawned")" == 1 ]] || fail 'Reach existing receiver should prevent another spawn'
grep -q 'receiver already exists' "$root/err" && [[ ! -e "$root/state/rotate-agent" ]] || fail 'a second once registry was created'
ok 'existing Reach receiver is reused for inspection rather than another ownership registry'
reset_calls
sed 's/runtime: claude-code/runtime: codex/; s/session-id: exact-claude/session-id: exact-codex/' "$record" >"$root/codex.md"
[[ "$(RECORD="$root/codex.md" TARGET=claude-code recover codex-native)" == 0 ]] && grep -q '^codex exec resume exact-codex ' "$root/native" && [[ ! -s "$root/spawned" ]] || fail 'exact Codex native entry'
ok 'Codex continuation names its exact native session rather than the latest one'
reset_calls
[[ "$(NATIVE_EMPTY=1 recover empty-native)" == 0 ]] && grep -q '^rebuilt next_action=unfinished ' "$root/out" || fail 'empty native process output is not proof a conversation continued'
ok 'an empty native response falls through to the brief instead of claiming resume'
printf '1..%s\n' "$count"
