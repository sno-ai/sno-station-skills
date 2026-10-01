#!/usr/bin/env bash
# log-watch.sh — live watch of an executor log that rings a supervisor when the run ends.
#
# Anything running longer than five minutes is watched live, not polled. This streams what
# matters and RINGS when the run ends (or the watch itself dies), so a supervisor that
# cannot wake itself is woken by the one event that otherwise produces no signal.
#
# Exiting is not waking anyone. On the Claude runtime a completed background task
# re-invokes the session, so this script's exit is a doorbell. On Codex a background exit
# does not wake the supervisor, so `--ring <addr>` (Reach address of the supervisor) is
# needed there: without it the watch is only a log filter.
#
# The markers are runner markers only, anchored at line start, so that echoed document
# text (feature names, "failed", "RED", "deploy" ...) does not trigger them:
#
#   ACTIVITY — the executor is working; stream it, wake nobody
#     " succeeded in <N>ms:"   a tool call returned 0        (codex exec output)
#     " exited <N> in <N>ms:"  a tool call returned nonzero  (codex exec output)
#     "codex"                  assistant turn boundary       (codex exec output)
#     "sessionUpdate":"tool_call" / "tool_call_update" / "agent_message_chunk"
#                              the JSON stream of an agent speaking the Agent Client
#                              Protocol (ACP)
#   ENDED — the run is over; ring, then exit 2
#     "tokens used: <N>"       codex exec printed its final accounting
#     "[spawn-exec] "          the launcher epilogue after the runtime returned
#     "stopReason":"           the ACP prompt returned
#
# Limit: the ACTIVITY markers describe `codex exec` and ACP output. The transcript of an
# interactive terminal session (what spawn-exec.sh records) contains none of them, so only
# the launcher epilogue (ENDED) is reported there. Any output at all counts as started, so
# NEVER-STARTED means the log stayed silent for the whole startup deadline.
#
# A nonzero tool call is not a failure signal (a grep that finds nothing exits 1); ringing
# on it would ring constantly. What needs a supervisor awake is the executor stopping.
#
# Three silent failures are closed: the watch never ends quietly.
#   1. The log never appears (stale path) and `tail -F` would retry forever → the startup
#      deadline fires, rings, exits 3.
#   2. The tail child dies and the read loop reaches EOF → reaped and checked, rings,
#      exits 4.
#   3. An ending marker in text the agent merely read stops the watch early → the patterns
#      require the runner's own punctuation. This reduces the risk; it cannot remove it.
#
# It does not tell you whether the executor works in the right tree, branch and files: a
# filter tuned for failure stays quiet through a flawless run in the wrong directory. That
# needs an unfiltered read of the log (pl-watch).
#
# exit 0 = you stopped it · 2 = the run ended · 3 = no marker seen before the startup
#      deadline · 4 = the watch died · 5 = outcome reached but a ring failed · 64 = bad usage · 69 = missing dependency
set -Eeuo pipefail

ACTIVITY='^( succeeded in [0-9]+ms:| exited [0-9]+ in [0-9]+ms:|codex$)|"sessionUpdate":"(tool_call|tool_call_update|agent_message_chunk)"'
ENDED='^(tokens used: [0-9]|\[spawn-exec\] )|"stopReason":"'

usage() {
  cat <<'EOF'
usage: log-watch.sh --log <path> [--ring <addr>] [--from <addr>] [--journey <id>]
                    [--startup-deadline <seconds>] [--print] [--since-bytes <n>]
  (default)            stream ACTIVITY, ring and exit 2 on ENDED — arm at spawn, backgrounded
  --ring <addr>        ring the supervisor on every terminal outcome. REQUIRED on Codex,
                       where a background exit wakes nobody. Repeatable.
  --from <addr>        sender address for the ring (default: the first --ring address)
  --journey <id>       journey id in diagnostics (default: unknown)
  --startup-deadline N seconds to wait for the log to show life before declaring the spawn
                       dead (default 600 — the launch window; 0 disables). Only the
                       markers above count as life.
  --since-bytes <n>    start at byte n of the log, for a resume appending to the log its
                       previous attempt wrote (default: the whole log, which is this run)
  --print              print a plain read-only stream command instead; it does NOT ring
  --filter             print the combined marker pattern and exit
EOF
}

log=""
print_only=0
journey="unknown"
from_addr=""
deadline=600
# From the first line, not the tail: a short run can finish before this is armed, and
# skipping what is already written would lose its ENDED marker.
start=(-n +1)
ring_to=()
since_bytes=""
since_given=0
from_given=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)               log="${2:-}"; shift 2 ;;
    --ring)              ring_to+=( "${2:-}" ); shift 2 ;;
    --from)              from_addr="${2:-}"; from_given=1; shift 2 ;;
    --journey)           journey="${2:-}"; shift 2 ;;
    --startup-deadline)  deadline="${2:-}"; shift 2 ;;
    --print)             print_only=1; shift ;;
    --from-start)        start=(-n +1); shift ;;  # the default; accepted and ignored
    --since-bytes)       since_bytes="${2:-}"; since_given=1; shift 2 ;;
    --filter)            printf '%s|%s\n' "$ACTIVITY" "$ENDED"; exit 0 ;;
    -h|--help)           usage; exit 0 ;;
    *) printf 'log-watch: unknown argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
done

[[ -n "$log" ]] || { printf 'log-watch: --log <path> is required\n' >&2; usage >&2; exit 64; }
# A resumed run appends to the log its previous attempt wrote, and that log already carries an
# ENDED marker, so a resume passes the size the log had before the spawn (--since-bytes) and
# the watch starts there. A fresh log needs nothing.
# A blank address means the caller's variable was empty; refuse it now rather than arm a watch
# that rings into nowhere.
for _addr in "${ring_to[@]}"; do
  [[ -n "${_addr// /}" ]] || {
    printf 'log-watch: --ring takes a Reach address\n' >&2; usage >&2; exit 64; }
done
if (( from_given )); then
  [[ -n "${from_addr// /}" ]] || {
    printf 'log-watch: --from takes a Reach address\n' >&2; usage >&2; exit 64; }
fi

# An empty value means the caller failed to read the old size; refuse it rather than start at
# the first line.
if (( since_given )); then
  [[ "$since_bytes" =~ ^[0-9]+$ ]] || {
    printf 'log-watch: --since-bytes takes a byte count\n' >&2; usage >&2; exit 64; }
  start=(-c "+$(( since_bytes + 1 ))")
fi
[[ "$deadline" =~ ^[0-9]+$ ]] || {
  printf 'log-watch: --startup-deadline takes whole seconds, got: %s\n' "$deadline" >&2; exit 64; }
[[ ${#ring_to[@]} -eq 0 || -n "$from_addr" ]] || from_addr="${ring_to[0]}"

# Prerequisites (sno only when ringing); one message, checked before anything starts.
missing=()
for _tool in tail mktemp mkfifo timeout; do command -v "$_tool" >/dev/null || missing+=("$_tool"); done
if (( ${#ring_to[@]} > 0 )); then command -v sno >/dev/null || missing+=("sno"); fi
if (( ${#missing[@]} > 0 && ! print_only )); then
  printf 'log-watch: missing dependency: %s (needs Linux with GNU coreutils, and the sno CLI when --ring is used)\n' "${missing[*]}" >&2
  exit 69
fi

if (( print_only )); then
  # The pattern has no single quote in it, so single-quoting keeps the printed line readable
  # and pasteable (%q would escape every space and bracket).
  printf "tail -F %s %s -- %q | grep --line-buffered -E '%s|%s'\n" \
    "${start[0]}" "${start[1]}" "$log" "$ACTIVITY" "$ENDED"
  exit 0
fi

# Every terminal outcome rings when --ring was given, failure states included. A failed ring
# is named on stderr and changes the exit status (5), so a supervisor that was never woken is
# not reported as notified.
ring_failed=0
ring() {
  local subject="$1" body="$2" to
  [[ ${#ring_to[@]} -gt 0 ]] || return 0
  for to in "${ring_to[@]}"; do
    if ! SNO_REACH_ADDR="$from_addr" timeout 10 sno reach ring "$to" >/dev/null; then
        ring_failed=1
        printf 'log-watch: RING FAILED to %s for %s: %s — %s\n' "$to" "$journey" "$subject" "$body" >&2
    fi
  done
}

# -F, not -f: the log may be created a moment after this is armed, and -F waits for it. The
# startup deadline below keeps that patience from becoming an indefinite silent wait.
fifo="$(mktemp -u -t log-watch.XXXXXX)"
mkfifo "$fifo"
# Every line here tolerates failure: an EXIT trap that returns nonzero replaces the script's
# exit status, so a `kill` against an already-dead child could rewrite `exit 3` into `exit 1`.
cleanup() {
  local rc=$?
  [[ -n "${tail_pid:-}" ]] && kill "$tail_pid" 2>/dev/null || true
  [[ -n "${timer_pid:-}" ]] && kill "$timer_pid" 2>/dev/null || true
  rm -f -- "$fifo" 2>/dev/null || true
  return "$rc"
}
trap cleanup EXIT

# Exit code 5: the outcome happened but the supervisor was not told; it must not be reported
# as the outcome's own code.
finish() { (( ring_failed )) && exit 5; exit "$1"; }

tail "${start[@]}" -F -- "$log" > "$fifo" 2>/dev/null &
tail_pid=$!

# The deadline is a separate process that injects a sentinel line, so a log that never shows
# a marker cannot hold the watch open forever. The first matching line disarms it.
started=0
if (( deadline > 0 )); then
  ( sleep "$deadline"; printf '\004STARTUP-DEADLINE\n' > "$fifo" 2>/dev/null ) &
  timer_pid=$!
fi

while IFS= read -r line; do
  if [[ "$line" == $'\004STARTUP-DEADLINE' ]]; then
    (( started )) && continue
    printf 'NEVER-STARTED | no recognized marker in %ss — the spawn may be dead, or an interactive session that does not print these markers: read the window (tmux capture-pane -pt <callsign>) before killing or resuming\n' "$deadline"
    ring "log-watch NEVER-STARTED: $log" \
         "No recognized runner marker within ${deadline}s of arming. The spawn may not have started, or it is an interactive session that does not print these markers. Read the window before killing or resuming."
    finish 3
  fi
  started=1   # any output at all means the process is alive; only total silence is NEVER-STARTED
  if [[ "$line" =~ $ENDED ]]; then
    printf 'ENDED | %s\n' "$line"
    ring "log-watch ENDED: $log" "The run ended. Marker: $line"
    finish 2
  elif [[ "$line" =~ $ACTIVITY ]]; then
    printf 'ACTIVITY | %s\n' "$line"
  fi
done < "$fifo"

# Reaching here means the pipe closed without an ending marker: the tail died, the log was
# removed, or something killed the child. Exiting 0 would report a clean finish for a watch
# that simply stopped watching.
# `|| tail_rc=$?`, never a bare `wait`: under `set -e` a child killed by a signal makes
# `wait` nonzero and would abort the script here before WATCH-LOST is printed.
tail_rc=0
wait "$tail_pid" 2>/dev/null || tail_rc=$?
tail_pid=""
printf 'WATCH-LOST | the log stream ended with no run-ended marker (tail rc=%s) — supervision has STOPPED; re-arm now and check the executor yourself\n' "$tail_rc" >&2
ring "log-watch WATCH-LOST: $log" \
     "The log stream ended with no run-ended marker (tail rc=$tail_rc). Supervision has stopped. Re-arm and inspect the executor."
finish 4
