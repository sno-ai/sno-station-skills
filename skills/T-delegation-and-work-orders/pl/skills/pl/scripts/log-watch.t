#!/usr/bin/env bash
# log-watch.sh — the watch must fire on runner markers, stay silent on echo, ring exactly
# once per terminal outcome, and NEVER end quietly.
#
# Echoed document text must not be mistaken for runner output.
#
# A nonzero tool call is activity, not a terminal failure signal.
#
# The terminal checks cover three silent exits:
# a log that never appears, a tail that dies, and a terminal outcome nobody is told about.
# Each one would otherwise leave the caller believing supervision was live while it was not.
set -Eeuo pipefail

WATCH="${WATCH:-$(dirname "$0")/log-watch.sh}"

root="$(mktemp -d)"
session="a1-log-watch-$$"
trap 'tmux kill-session -t "$session" 2>/dev/null || true; rm -rf -- "$root"' EXIT
host="$(hostname)"
addr="pl.log-watch@$host"
export SNO_REACH_ROOT="$root/reach"

tests=0
failures=0
check() { # $1 label, rest: command
  local label="$1"; shift
  tests=$((tests + 1))
  if "$@"; then printf 'ok %d - %s\n' "$tests" "$label"
  else printf 'not ok %d - %s\n' "$tests" "$label"; failures=$((failures + 1)); fi
}

sent="$root/rings.txt"
cat > "$root/receiver.sh" <<'RECEIVER'
#!/usr/bin/env bash
while IFS= read -r line; do
  printf '%s\n' "$line" >> "$SENT"
  if [[ "$line" =~ ([0-9a-f]{8})\ typed\ by\ the\ mail\ transport ]]; then
    printf 'ACK-%s\n' "${BASH_REMATCH[1]}"
  fi
done
RECEIVER
chmod +x "$root/receiver.sh"
sno reach init --as "$addr" --name Watch >/dev/null
tmux new-session -d -s "$session" "env SENT=$(printf '%q' "$sent") bash $(printf '%q' "$root/receiver.sh")"
sno reach register --as "$addr" --channel tmux \
  --handle "$(tmux list-panes -t "$session" -F '#{pane_id}')" >/dev/null

# One fixture log carrying both classes, interleaved the way a real log does it.
fixture="$root/exec.log"
cat > "$fixture" <<EOF
OpenAI Codex v0.145.0
workdir: $root/example-repo
user
   The document says the step failed in review.
| The example command failed in an earlier draft.
RED: the deploy step failed and the branch is broken
codex
 succeeded in 3505ms:
 exited 1 in 870ms:
tokens used: 412331
[spawn-exec] pipeline rc=0
EOF

pattern="$(bash "$WATCH" --filter)"

# 1-2. every runner marker is caught — activity AND termination, in one pattern
check "catches all five runner markers" test "$(grep -cE "$pattern" "$fixture")" -eq 5
check "catches the nonzero-exit marker" grep -qE "$pattern" <<< ' exited 1 in 870ms:'

# 3. NONE of the domain-vocabulary echo lines match
check "silent on echoed document text" \
  test "$(grep -E "$pattern" "$fixture" | grep -c 'failed in\|RED:' || true)" -eq 0

# 4-5. --print must emit a command that RUNS and filters — a printed line that does not work
#      is worse than none, because the PL pastes it and believes it is watching.
printed="$(bash "$WATCH" --log "$fixture" --from-start --print)"
check "--print names the log" grep -q "exec.log" <<< "$printed"
timeout 3 bash -c "$printed" > "$root/printed.out" 2>/dev/null || true
check "the printed command actually runs and filters" \
  test "$(wc -l < "$root/printed.out")" -eq 5

# 6-9. live behaviour: activity streams and does NOT ring; the run ending DOES ring, exit 2
out="$root/out"
bash "$WATCH" --log "$root/late.log" --ring "$addr" --journey j-t > "$out" 2>/dev/null &
watcher=$!
sleep 1
printf 'codex\nnothing to see here\n exited 2 in 12ms:\n' >> "$root/late.log"
sleep 2
check "still watching after a nonzero tool call (that is activity, not failure)" \
  kill -0 "$watcher" 2>/dev/null
check "sends no card while the executor is merely working" test ! -s "$sent"
printf 'tokens used: 91\n' >> "$root/late.log"
sleep 2
rc=0; wait "$watcher" || rc=$?
check "rings by exiting 2 when the run ends" test "$rc" -eq 2
check "labels activity and the ending, and nothing else" \
  bash -c 'test "$(wc -l < "$1")" -eq 3 &&
           grep -q "^ACTIVITY | codex$" "$1" &&
           grep -q "^ACTIVITY |  exited 2 in 12ms:" "$1" &&
           grep -q "^ENDED | tokens used" "$1"' _ "$out"

# 10. The ring must reach the registered terminal, not merely exit the watch.
check "rings the PL terminal when the run ends" grep -q 'REACH-RING' "$sent"

# 11. a log that never appears must not produce an indefinitely silent false watch
: > "$sent"
rc=0; timeout 20 bash "$WATCH" --log "$root/never.log" --startup-deadline 2 \
  --ring "$addr" > "$root/never.out" 2>/dev/null || rc=$?
check "declares NEVER-STARTED instead of waiting forever" test "$rc" -eq 3
check "rings on never-started, and says what to do" \
  bash -c 'grep -q "REACH-RING" "$1" && grep -q "NEVER-STARTED" "$2"' _ "$sent" "$root/never.out"

# 11b. an interactive session prints terminal text with none of the runner markers; any output
# means it started, so a 2 s deadline must not declare NEVER-STARTED while it is still running
printf '> working on the task\nreading files\n' > "$root/tui.log"
rc=0; timeout 6 bash "$WATCH" --log "$root/tui.log" --startup-deadline 2 > "$root/tui.out" 2>/dev/null || rc=$?
check "unmarked output still counts as started (watch keeps running past the deadline)" test "$rc" -eq 124
check "no NEVER-STARTED for a log that has output" test "$(grep -c NEVER-STARTED "$root/tui.out")" -eq 0

# 12. echoed ending text is guarded by requiring the runner's own punctuation
check "bare echoed 'tokens used' prose does not read as an ending" \
  bash -c '! grep -qE "$1" <<< "tokens used by the model are described in the doc"' _ "$pattern"

# 13. the tail dying must be loud — never a quiet exit 0 that reads as a clean finish
: > "$sent"
printf 'codex\n' > "$root/dies.log"
bash "$WATCH" --log "$root/dies.log" --startup-deadline 0 --ring "$addr" \
  --from-start > "$root/dies.out" 2> "$root/dies.err" &
watcher=$!
sleep 2
pkill -P "$watcher" -x tail 2>/dev/null || true
rc=0; wait "$watcher" || rc=$?
check "exits 4, not 0, when the watch loses its tail" test "$rc" -eq 4
check "rings and says supervision has stopped" \
  bash -c 'grep -q "REACH-RING" "$1" && grep -q "WATCH-LOST" "$2"' _ "$sent" "$root/dies.err"

# 14. it must not leave a tail behind — a watch that leaks one per fire accumulates silently.
#     Match on the real process's argv0, never `pgrep -f <pattern>`: any shell whose command
#     line merely mentions the log would match, including this test's own.
check "reaps its own tail process on exit" \
  bash -c 'test -z "$(ps -eo comm,args | awk -v f="$1" "\$1 == \"tail\" && index(\$0, f)")"' _ "$root/late.log"

# 15-16. argument contract: missing --log, unknown flags and a bad deadline are rejected
check "missing --log exits 64" \
  bash -c 'bash "$1" --print 2>/dev/null; test $? -eq 64' _ "$WATCH"
check "unknown flag exits 64" \
  bash -c 'bash "$1" --log /dev/null --nope 2>/dev/null; test $? -eq 64' _ "$WATCH"
check "non-numeric startup deadline exits 64" \
  bash -c 'bash "$1" --log /dev/null --startup-deadline soon 2>/dev/null; test $? -eq 64' _ "$WATCH"

printf '1..%d\n' "$tests"
[[ "$failures" -eq 0 ]] || { printf '%d failure(s)\n' "$failures" >&2; exit 1; }
