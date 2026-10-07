#!/bin/bash
# exec-sentinel.sh — turns an executor's silence into a card to its supervisors.
#
# A silent executor generates no signal of its own. Each tick compares the executor's log
# size and the commit count with the previous tick; when neither has moved for the stall
# window it sends a card to the PL and COS Reach addresses.
#
# Run one tick per heartbeat; its interval must equal --tick-secs, for example:
# sno heartbeat --interval 1m --label sentinel-<callsign> -- bash "${PL_SKILL_DIR}/scripts/exec-sentinel.sh" --log <spawn-log> --repo <worktree> --pl "$PL_ADDR" --cos "$COS_ADDR" --tick-secs 60
#
# It watches a branch, not a journey: the commit counter is `git rev-list --count HEAD`
# on the worktree, so any executor committing to that branch resets the stall, even if the
# watched executor is idle. Use one watch per executor and retire it when its journey
# closes; a watch that outlives its journey produces false stalls.
#
# usage: exec-sentinel.sh --log <path> --repo <worktree> --pl <addr> --cos <addr>
#                         [--journey <id>] [--stall-min N] [--from <addr>] [--tick-secs N]
set -euo pipefail
case "${1:-}" in
  -h|--help) sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
esac
LOG=""; REPO=""; PL=""; COS=""; JOURNEY="unknown"; STALL_MIN=8; FROM=""; TICK=60
while [ $# -gt 0 ]; do
  case "$1" in
    --log) LOG="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    --pl) PL="$2"; shift 2;;
    --cos) COS="$2"; shift 2;;
    --journey) JOURNEY="$2"; shift 2;;
    --stall-min) STALL_MIN="$2"; shift 2;;
    --tick-secs) TICK="$2"; shift 2;;
    --from) FROM="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 64;;
  esac
done
[ -n "$LOG" ] && [ -n "$REPO" ] && [ -n "$PL" ] && [ -n "$COS" ] || {
  echo "usage: --log <path> --repo <worktree> --pl <addr> --cos <addr>" >&2; exit 64; }
[ -n "$FROM" ] || FROM="$COS"

[[ "$STALL_MIN" =~ ^[0-9]+$ && "$TICK" =~ ^[0-9]+$ && "$TICK" -gt 0 ]] || { printf 'stall-min and tick-secs must be nonnegative integers; tick-secs must be positive\n' >&2; exit 64; }
TICKS_TO_STALL=$(( (STALL_MIN * 60 + TICK - 1) / TICK ))
[[ "$TICKS_TO_STALL" -gt 0 ]] || TICKS_TO_STALL=1
SCRATCH="${SNO_SCRATCH:-${TMPDIR:-/tmp}}"
mkdir -p -- "$SCRATCH"
KEY=$(printf '%s\0' "pl" "$LOG" "$REPO" "$PL" "$COS" "$JOURNEY" "$FROM" | sha256sum)
STATE="$SCRATCH/exec-sentinel-${KEY%% *}.state"
printf '%s\n' "$STATE"
logsz=$(stat -c%s -- "$LOG" 2>/dev/null || printf '0')
commits=$(git -C "$REPO" rev-list --count HEAD 2>/dev/null || printf '0')
if [[ -f "$STATE" ]]; then
  read -r prev_log prev_commits stall alerts < "$STATE"
  for value in "$prev_log" "$prev_commits" "$stall" "$alerts"; do
    [[ "$value" =~ ^[0-9]+$ ]] || { printf 'invalid sentinel state: %s\n' "$STATE" >&2; exit 2; }
  done
else
  tmp=$(mktemp "$STATE.XXXXXX")
  printf '%s %s 0 0\n' "$logsz" "$commits" > "$tmp"
  mv -f -- "$tmp" "$STATE"
  printf '%s log+0B commits=%s(+0) stall=0/%s\n' "$(date -u '+%H:%M:%SZ')" "$commits" "$TICKS_TO_STALL"
  exit 0
fi

ring() {
  local subject="$1" body="$2" to status
  for to in "$PL" "$COS"; do
    if printf 'From: SENTINEL <%s>\nTo: watcher <%s>\nSubject: %s\nDate: %s\nMessage-ID: <sentinel-%s-%s-%s@%s>\nX-Work: %s\nX-Type: decision\nX-Name: sentinel\n\n%s\n' \
      "$FROM" "$to" "$subject" "$(date -u '+%a, %d %b %Y %H:%M:%S +0000')" \
      "$(date -u '+%Y%m%dT%H%M%SZ')" "$RANDOM" "${to%%@*}" "$(hostname)" "$JOURNEY" "$body" \
      | timeout 30 sno reach send --no-ring --as "$FROM" >/dev/null; then
      # The card is stored. Ringing waits for the receiver to answer, so it runs detached and
      # never holds this tick; a ring nobody answers leaves the stored card in place.
      ( timeout 120 sno reach ring "$to" >/dev/null 2>&1 & )
      continue
    else
      status=$?
      printf 'exec-sentinel: could not send card to %s (exit %s); inspect Reach outbox\n' "$to" "$status" >&2
    fi
  done
}

  grew=$(( logsz - prev_log )); dc=$(( commits - prev_commits ))

  # The stall test uses deltas only. An absolute count (for example "commits == 0")
  # would stay false after the first commit and switch the alarm off for good.
  if [ "$grew" -le 0 ] && [ "$dc" -le 0 ]; then stall=$(( stall + 1 )); else
    if [ "$stall" -ge "$TICKS_TO_STALL" ]; then
      ring "[DECISION] SENTINEL: $JOURNEY is MOVING again after $(( stall * TICK / 60 ))m of silence" \
"Recovered on its own. Log grew ${grew}B, commits ${commits} (+${dc}).
No action needed; this closes the stall alert above it."
    fi
    stall=0; alerts=0
  fi

  if [ "$stall" -ge "$TICKS_TO_STALL" ]; then
    mins=$(( stall * TICK / 60 ))
    # Ring at the threshold, then re-ring on a widening backoff so it can never be
    # noticed once and forgotten: 8m, 16m, 32m, 64m ...
    if [ "$alerts" -eq 0 ] || [ "$mins" -ge $(( STALL_MIN * (1 << alerts) )) ]; then
      alerts=$(( alerts + 1 ))
      ring "[DECISION] SENTINEL STALL: $JOURNEY silent ${mins}m - executor produced nothing" \
"Log $LOG has not grown and no commit has landed in ${mins} minutes.
Worktree: $REPO   commits on HEAD: ${commits}

A silent executor is the one failure that generates no signal of its own, which is
why this card exists. Go look at the log NOW and either restart it or report why it
is legitimately quiet.

Default working rule: an executor does not wait on a missing input. It states the
assumption it is proceeding under, records it in the commit message and the status file,
and keeps building. A genuinely blocked executor should be escalated promptly.

This card repeats on a widening interval until the executor moves again."
    fi
  fi
tmp=$(mktemp "$STATE.XXXXXX")
printf '%s %s %s %s\n' "$logsz" "$commits" "$stall" "$alerts" > "$tmp"
mv -f -- "$tmp" "$STATE"
printf '%s log+%sB commits=%s(+%s) stall=%s/%s\n' "$(date -u '+%H:%M:%SZ')" "$grew" "$commits" "$dc" "$stall" "$TICKS_TO_STALL"
