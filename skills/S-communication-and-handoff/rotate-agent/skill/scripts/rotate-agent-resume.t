#!/usr/bin/env bash
# Behaviour test for rotate-agent-resume. Real git work tree, real progress record and real
# handoff-checkpoint; only the start of an external agent (sno reach spawn / call) is a stand-in.
set -Eeuo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
command_path="${1:-$here/rotate-agent-resume}"
checkpoint_cmd=''
for candidate in "$here/../../../handoff/skill/scripts/handoff-checkpoint" "$here/../../handoff/scripts/handoff-checkpoint" "$here/../../../../handoff/skill/scripts/handoff-checkpoint"; do
    if [[ -x "$candidate" ]]; then checkpoint_cmd="$(realpath -- "$candidate")"; break; fi
done
if [[ -z "$checkpoint_cmd" ]]; then printf 'SKIP: the handoff skill is not installed beside this one\n'; exit 0; fi
command -v tmux >/dev/null || { printf 'SKIP: tmux is not installed\n'; exit 0; }

root="$(mktemp -d)"
session="resume-test-$$"
trap 'tmux kill-session -t "$session" 2>/dev/null || true; rm -rf -- "$root"' EXIT
count=0
ok() { count=$((count + 1)); printf 'ok %s - %s\n' "$count" "$1"; }
fail() { printf 'not ok %s - %s\n' "$((count + 1))" "$1"; [[ -s "$root/out" ]] && sed 's/^/# out: /' "$root/out"; [[ -s "$root/err" ]] && sed 's/^/# err: /' "$root/err"; exit 1; }

# A stand-in `sno`: init and unregister succeed, spawn opens a real tmux pane and writes the seat
# record the command reads, watch returns, call stores the prompt it was given and echoes the nonce.
mkdir -p -- "$root/bin" "$root/state" "$root/reach"
cat >"$root/bin/sno" <<'SH'
#!/usr/bin/env bash
[[ "$1" == reach ]] || exit 64
shift
verb="$1"; shift
if [[ "$verb" == call ]]; then
    seat="$1"; prompt="$2"; shift 2; expect=''
    while (( $# )); do [[ "$1" == --expect ]] && expect="$2"; shift; done
    printf '%s' "$prompt" >"$FAKE_ROOT/prompt"
    if [[ -n "${FAKE_UNSENT:-}" ]]; then   # the prompt is typed but its Enter was swallowed: only a later Enter sends it
        tmux send-keys -t "$(jq -r '.identity.value' "$FAKE_ROOT/reach/$seat/reachable.json")" -l 'typed prompt'
        for _ in $(seq 100); do [[ -e "$FAKE_ROOT/submitted" ]] && break; sleep 0.3; done
        [[ -e "$FAKE_ROOT/submitted" ]] || exit 1
    fi
    pane="$(jq -r '.identity.value' "$FAKE_ROOT/reach/$seat/reachable.json")"
    tmux capture-pane -p -t "$pane" | grep -c 'loading' >"$FAKE_ROOT/loading-at-call" || true
    printf '%s\n' "$expect"
    exit 0
fi
seat=''
while (( $# )); do [[ "$1" == --as ]] && seat="$2"; shift; done
case "$verb" in
    spawn)
        [[ -z "${FAKE_SPAWN_FAIL:-}" ]] || { echo 'spawn refused for the test' >&2; exit 1; }
        shell='cat'
        [[ -z "${FAKE_UNSENT:-}" ]] || shell="printf 'OpenAI Codex\\n'; read -r line; printf submitted >'$FAKE_ROOT/submitted'; cat"
        [[ -z "${FAKE_LOADING:-}" ]] || shell="printf 'model: loading\\n'; sleep 4; printf '\\033c'; cat"
        tmux new-session -d -s "$FAKE_SESSION" "$shell" 2>/dev/null || tmux new-window -t "$FAKE_SESSION" "$shell"
        pane="$(tmux list-panes -t "$FAKE_SESSION" -F '#{pane_id}' | head -n1)"
        mkdir -p "$FAKE_ROOT/reach/$seat"
        printf '{"identity":{"value":"%s"}}\n' "$pane" >"$FAKE_ROOT/reach/$seat/reachable.json"
        printf '%s\n' "$seat" >>"$FAKE_ROOT/spawned"
        ;;
    init|watch|unregister) exit 0 ;;
esac
SH
chmod +x "$root/bin/sno"
export PATH="$root/bin:$PATH" SNO_REACH_ROOT="$root/reach" XDG_STATE_HOME="$root/state" FAKE_ROOT="$root" FAKE_SESSION="$session"

repo="$root/work"
mkdir -p -- "$repo"
git -C "$repo" init -q -b main
printf 'a\n' >"$repo/a.txt"
git -C "$repo" add a.txt
git -C "$repo" -c user.name=T -c user.email=t@example.invalid commit -q -m first
record="$root/progress.md"
(cd -- "$repo" && "$checkpoint_cmd" "$record" >/dev/null)
sed -i 's/^## Next$/## Next\n1. write the report/' "$record"

run() { local status=0; "$command_path" "$@" >"$root/out" 2>"$root/err" || status=$?; printf '%s' "$status"; }

# usage
status="$(run)"
[[ "$status" == 0 && "$(head -n1 "$root/out")" == usage:* ]] || fail 'no arguments print usage and exit 0'
status="$(run --help)"
[[ "$status" == 0 && "$(head -n1 "$root/out")" == usage:* ]] || fail '--help prints usage and exits 0'
status="$(run --to nobody)"
[[ "$status" == 2 ]] || fail 'a wrong argument is a usage error (exit 2)'
ok 'no arguments and --help exit 0; a wrong argument exits 2'

# a good resume
status="$(run --to codex --cwd "$repo" --checkpoint "$record" --work demo --checkpoint-cmd "$checkpoint_cmd" --report-to owner.main@host)"
[[ "$status" == 0 ]] || fail "resume exits 0 (got $status)"
grep -Eq '^RESUMED seat=resume\.demo@[a-z0-9.-]+ verify=MATCH$' "$root/out" || fail 'prints RESUMED with the seat and verify=MATCH'
ok 'resume starts a receiver and reports the seat and MATCH'
grep -Fq "$record" "$root/prompt" || fail 'the prompt names the progress record'
grep -Fq "$repo" "$root/prompt" || fail 'the prompt names the checkout'
grep -q 'RESUME_ACK ' "$root/prompt" || fail 'the prompt asks for a fresh acknowledgement line'
grep -q 'DONE_demo' "$root/prompt" && grep -q 'BLOCKED_demo' "$root/prompt" || fail 'the prompt defines the DONE and BLOCKED lines for this work label'
grep -q '^MATCH$' "$root/prompt" || fail 'the prompt carries the verify result'
grep -q 'owner.main@host' "$root/prompt" || fail 'the prompt names where to report'
ok 'the prompt carries record, checkout, verify result, ack line, end markers and report target'

# once per label
seats_before="$(wc -l <"$root/spawned")"
status="$(run --to codex --cwd "$repo" --checkpoint "$record" --work demo --checkpoint-cmd "$checkpoint_cmd")"
[[ "$status" == 1 ]] || fail "a second resume with the same label exits 1 (got $status)"
grep -Eq 'resume\.demo@' "$root/out" || fail 'it names the existing seat'
[[ "$(wc -l <"$root/spawned")" == "$seats_before" ]] || fail 'no second receiver was started'
ok 'the same label resumes only once'

# drift is told to the receiver
printf 'late work\n' >"$repo/late.txt"
status="$(run --to claude --cwd "$repo" --checkpoint "$record" --work drifted --checkpoint-cmd "$checkpoint_cmd")"
[[ "$status" == 0 ]] || fail "resume with drift still exits 0 (got $status)"
grep -q 'verify=DRIFT$' "$root/out" || fail 'prints verify=DRIFT'
grep -qx 'DRIFT new: late.txt' "$root/prompt" || fail 'the prompt carries the DRIFT line'
ok 'drift is reported and passed to the receiver'

# failures
status="$(run --to codex --cwd "$repo" --checkpoint "$root/nope.md" --work missing --checkpoint-cmd "$checkpoint_cmd")"
[[ "$status" == 1 ]] && grep -Eq '^FAIL checkpoint: .* -> ' "$root/out" || fail 'a missing progress record is FAIL checkpoint'
status="$(FAKE_SPAWN_FAIL=1 run --to codex --cwd "$repo" --checkpoint "$record" --work spawnfail --checkpoint-cmd "$checkpoint_cmd")"
[[ "$status" == 1 ]] && grep -Eq '^FAIL spawn: .* -> ' "$root/out" || fail 'a refused spawn is FAIL spawn'
[[ ! -e "$root/state/rotate-agent/spawnfail.resume" ]] || fail 'a failed start leaves no lock, so a retry is possible'
status="$(run --to codex --cwd "$repo" --checkpoint "$record" --work spawnfail --checkpoint-cmd "$checkpoint_cmd")"
[[ "$status" == 0 ]] || fail 'the retry after a failed start works'
ok 'failures print one FAIL line with the next step, and a failed start can be retried'

# a receiver still loading its model when the startup wait ends is not sent the prompt yet
sleep 5; tmux kill-session -t "$session" 2>/dev/null || true
status="$(FAKE_LOADING=1 run --to codex --cwd "$repo" --checkpoint "$record" --work loading --checkpoint-cmd "$checkpoint_cmd")"
[[ "$status" == 0 ]] || fail "resume with a slow-loading receiver exits 0 (got $status)"
[[ "$(cat "$root/loading-at-call")" == 0 ]] || fail 'the prompt was sent while the receiver still showed loading'
ok 'the prompt waits until the receiver has finished loading'

# a prompt typed into a Codex input box whose Enter was swallowed is submitted by a later Enter while the call waits
sleep 5; tmux kill-session -t "$session" 2>/dev/null || true; rm -f "$root/submitted"
status="$(FAKE_UNSENT=1 run --to codex --cwd "$repo" --checkpoint "$record" --work unsent --checkpoint-cmd "$checkpoint_cmd")"
[[ "$status" == 0 ]] || fail "resume with an unsubmitted startup text exits 0 (got $status)"
[[ -e "$root/submitted" ]] || fail 'the swallowed-Enter prompt was never submitted'
ok 'a prompt left unsent in a Codex input box is submitted while the call waits'

# a failure before the lock is taken must not delete the lock of an earlier successful resume
status="$(run --to codex --cwd "$repo" --checkpoint "$record" --work keeplock --checkpoint-cmd "$checkpoint_cmd")"
[[ "$status" == 0 && -e "$root/state/rotate-agent/keeplock.resume" ]] || fail 'the first resume of the label works and leaves its lock'
status="$(run --to codex --cwd "$repo" --checkpoint "$root/moved-away.md" --work keeplock --checkpoint-cmd "$checkpoint_cmd")"
[[ "$status" == 1 ]] && grep -Eq '^FAIL checkpoint: ' "$root/out" || fail 'a later call with a missing progress record fails at the checkpoint step'
[[ -e "$root/state/rotate-agent/keeplock.resume" ]] || fail 'the failed later call deleted the lock of the earlier successful resume'
seats_before="$(wc -l <"$root/spawned")"
status="$(run --to codex --cwd "$repo" --checkpoint "$record" --work keeplock --checkpoint-cmd "$checkpoint_cmd")"
[[ "$status" == 1 ]] && grep -Eq '^FAIL once: ' "$root/out" && [[ "$(wc -l <"$root/spawned")" == "$seats_before" ]] || fail 'the label is still resumed only once after the failed call'
ok 'a failure before the lock is taken keeps the lock of an earlier successful resume'

# a progress record belongs to one checkout: a different --cwd is refused before anything is started
other="$root/other-checkout"; mkdir -p "$other"; git -C "$other" init -q -b main
seats_before="$(wc -l <"$root/spawned")"
status="$(run --to codex --cwd "$other" --checkpoint "$record" --work wrongdir --checkpoint-cmd "$checkpoint_cmd")"
[[ "$status" == 1 ]] && grep -Eq "^FAIL checkout: .*$repo.*$other.* -> " "$root/out" || fail 'a record of another checkout is FAIL checkout, naming both directories and what to do'
[[ "$(wc -l <"$root/spawned")" == "$seats_before" && ! -e "$root/state/rotate-agent/wrongdir.resume" ]] || fail 'nothing was started and no lock was left'
ok 'a record that belongs to another checkout is refused before anything starts'

# the checkout may be given as a folder inside it, or through a symlink: it is still the record's checkout
mkdir -p "$repo/sub/dir"; ln -sfn "$repo" "$root/linked-checkout"
status="$(run --to codex --cwd "$repo/sub/dir" --checkpoint "$record" --work insidedir --checkpoint-cmd "$checkpoint_cmd")"
[[ "$status" == 0 ]] && grep -Eq '^RESUMED seat=resume\.insidedir@' "$root/out" || fail 'a --cwd inside the recorded checkout is accepted'
status="$(run --to codex --cwd "$root/linked-checkout" --checkpoint "$record" --work viasymlink --checkpoint-cmd "$checkpoint_cmd")"
[[ "$status" == 0 ]] && grep -Eq '^RESUMED seat=resume\.viasymlink@' "$root/out" || fail 'a --cwd that is a symlink to the recorded checkout is accepted'
rm -rf "$repo/sub"
ok 'a folder inside the checkout, or a symlink to it, is accepted as the recorded checkout'

# relative --cwd and --checkpoint: the receiver works in another directory, so it must get absolute paths
rm -f "$root/prompt"
status="$( (cd "$root" && run --to codex --cwd work --checkpoint progress.md --work relpaths --checkpoint-cmd "$checkpoint_cmd") )"
[[ "$status" == 0 ]] || fail "resume with relative paths exits 0 (got $status)"
grep -Fq "Checkout: $root/work" "$root/prompt" && grep -Fq "Progress record: $root/progress.md" "$root/prompt" || fail 'the prompt carries the absolute checkout and progress record paths'
grep -Fq "$checkpoint_cmd $root/progress.md" "$root/prompt" || fail 'the refresh command in the prompt uses the absolute progress record path'
ok 'relative paths are turned into absolute paths before the receiver is told'

printf '1..%s\n' "$count"
