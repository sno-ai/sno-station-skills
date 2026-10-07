#!/bin/bash
# exec-sentinel.sh — converts an executor's SILENCE into a doorbell.
#
# THE PROBLEM IT SOLVES: neither a PL nor COS is a process that wakes itself.
# Between turns they are stopped. They only resume when something rings their
# window. So when an executor goes quiet, the event needing attention
# produces no signal.
#
# Run one tick per heartbeat; its interval must equal --tick-secs.
# sno heartbeat --interval 1m --label sentinel-<executor> -- bash <skill-dir>/scripts/exec-sentinel.sh --log L --repo R --pl A --cos B --tick-secs 60
#
# IT WATCHES A BRANCH, NOT ONE WORK ITEM, AND THAT IS A REAL LIMIT. The commit counter is
# `git rev-list --count HEAD` on the worktree, so ANY executor committing to that branch
# resets the stall even if that executor belongs to another lane.
#
# So: ONE WATCH PER EXECUTOR, and RETIRE IT WHEN ITS WORK CLOSES. A watch outliving its
# work produces false stalls and false recoveries, and both teach a supervisor to
# discount it.
#
# A branch-wide counter cannot prove which executor made progress.
#
# usage: exec-sentinel.sh --log <path> --repo <worktree> --pl <addr> --cos <addr>
#                         [--work <id>] [--stall-min N] [--from <addr>] [--tick-secs N]
set -euo pipefail
case "${1:-}" in
  -h|--help) sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
esac
LOG=""; REPO=""; PL=""; COS=""; WORK="unknown"; STALL_MIN=8; FROM=""; TICK=60
while [ $# -gt 0 ]; do
  case "$1" in
    --log) LOG="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    --pl) PL="$2"; shift 2;;
    --cos) COS="$2"; shift 2;;
    --work) WORK="$2"; shift 2;;
    --stall-min) STALL_MIN="$2"; shift 2;;
    --tick-secs) TICK="$2"; shift 2;;
    --from) FROM="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 64;;
  esac
done
[ -n "$LOG" ] && [ -n "$REPO" ] && [ -n "$PL" ] && [ -n "$COS" ] || {
  echo "usage: --log <path> --repo <worktree> --pl <addr> --cos <addr>" >&2; exit 64; }
for tool in git sno sha256sum timeout; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'exec-sentinel: %s is required but not installed\n' "$tool" >&2; exit 69; }
done
[ -n "$FROM" ] || FROM="$COS"
[[ "$STALL_MIN" =~ ^[0-9]+$ && "$TICK" =~ ^[0-9]+$ && "$TICK" -gt 0 ]] || { printf 'stall-min and tick-secs must be nonnegative integers; tick-secs must be positive\n' >&2; exit 64; }
TICKS_TO_STALL=$(( (STALL_MIN * 60 + TICK - 1) / TICK ))
[[ "$TICKS_TO_STALL" -gt 0 ]] || TICKS_TO_STALL=1
SCRATCH="${SNO_SCRATCH:-${TMPDIR:-/tmp}}"
mkdir -p -- "$SCRATCH"
KEY=$(printf '%s\0' "cos" "$LOG" "$REPO" "$PL" "$COS" "$WORK" "$FROM" | sha256sum)
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
      "$(date -u '+%Y%m%dT%H%M%SZ')" "$RANDOM" "${to%%@*}" "$(hostname)" "$WORK" "$body" \
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

  # THE STALL TEST IS DELTA-ONLY, DELIBERATELY.
  # An absolute commit count would disable the alarm after the first commit.
  # Only movement since the previous tick belongs in this condition.
  if [ "$grew" -le 0 ] && [ "$dc" -le 0 ]; then stall=$(( stall + 1 )); else
    if [ "$stall" -ge "$TICKS_TO_STALL" ]; then
      ring "[DECISION] SENTINEL: $WORK is MOVING again after $(( stall * TICK / 60 ))m of silence" \
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
      ring "[DECISION] SENTINEL STALL: $WORK silent ${mins}m - executor produced nothing" \
"Log $LOG has not grown and no commit has landed in ${mins} minutes.
Worktree: $REPO   commits on HEAD: ${commits}

A silent executor is the one failure that generates no signal of its own, which is
why this card exists. Go look at the log NOW and either restart it or report why it
is legitimately quiet.

Default: an executor does not block on a missing input. It states the assumption it is
proceeding under, records it in the commit message and the status file, and keeps
building; a genuinely blocked executor should be escalated within 10 minutes.

This card repeats on a widening interval until the executor moves again."
    fi
  fi
tmp=$(mktemp "$STATE.XXXXXX")
printf '%s %s %s %s\n' "$logsz" "$commits" "$stall" "$alerts" > "$tmp"
mv -f -- "$tmp" "$STATE"
printf '%s log+%sB commits=%s(+%s) stall=%s/%s\n' "$(date -u '+%H:%M:%SZ')" "$grew" "$commits" "$dc" "$stall" "$TICKS_TO_STALL"
