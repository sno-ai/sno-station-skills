#!/usr/bin/env bash
# gpu-watch.sh — one GPU-liveness sample per heartbeat tick.
# heartbeat --interval 4m --label gpu-<journey> -- bash "${PL_SKILL_DIR}/scripts/gpu-watch.sh" --journey <id> --tick-secs 240
# Needs nvidia-smi and jq.
# The heartbeat interval must equal --tick-secs; delete the printed state file when the phase closes.
# Exit: 0 healthy/window elapsed; 3 active then stalled; 4 never active; 2 usage/probe error.
# Samples and verdicts append to ai-doc/ACTIVE/PL/gpu-watch.jsonl.
set -euo pipefail
ACTIVE_PCT="${GPU_WATCH_ACTIVE_PCT:-10}"
SMI="${GPU_WATCH_SMI:-nvidia-smi}"
die() { printf 'gpu-watch: %s\n' "$*" >&2; exit 2; }
case "${1:-}" in
  -h|--help) sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
esac
JOURNEY="-"; GRACE_MINS=45; STALL_MINS=20; MAX_HOURS=8; GPUS="all"; TICK=240
while [[ $# -gt 0 ]]; do
  case "$1" in
    --journey) JOURNEY="${2:?}"; shift 2 ;;
    --grace-mins) GRACE_MINS="${2:?}"; shift 2 ;;
    --stall-mins) STALL_MINS="${2:?}"; shift 2 ;;
    --max-hours) MAX_HOURS="${2:?}"; shift 2 ;;
    --gpus) GPUS="${2:?}"; shift 2 ;;
    --tick-secs) TICK="${2:?}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
for value in "$GRACE_MINS" "$STALL_MINS" "$MAX_HOURS" "$TICK" "$ACTIVE_PCT"; do
  [[ "$value" =~ ^[0-9]+$ ]] || die "numeric arguments only"
done
[[ "$TICK" -gt 0 ]] || die 'tick-secs must be positive'
command -v "$SMI" >/dev/null || die "nvidia-smi not available"
command -v jq >/dev/null || die "jq not available"
GRACE_SECS="${GPU_WATCH_GRACE_SECS:-$((GRACE_MINS*60))}"
STALL_SECS="${GPU_WATCH_STALL_SECS:-$((STALL_MINS*60))}"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || printf '.')
LOGDIR="$ROOT/ai-doc/ACTIVE/PL"
LOGFILE="$LOGDIR/gpu-watch.jsonl"
SCRATCH="${SNO_SCRATCH:-${TMPDIR:-/tmp}}"
mkdir -p -- "$SCRATCH"
KEY=$(printf '%s\0' "$ROOT" "$JOURNEY" "$GPUS" | sha256sum)
STATE="$SCRATCH/gpu-watch-${KEY%% *}.state"
printf '%s\n' "$STATE"
if [[ -f "$STATE" ]]; then
  read -r ELAPSED SEEN_ACTIVE LAST_ACTIVE ACTIVE_STREAK N < "$STATE"
  for value in "$ELAPSED" "$SEEN_ACTIVE" "$LAST_ACTIVE" "$ACTIVE_STREAK" "$N"; do
    [[ "$value" =~ ^[0-9]+$ ]] || die "invalid state: $STATE"
  done
  ELAPSED=$((ELAPSED + TICK))
else
  ELAPSED=0; SEEN_ACTIVE=0; LAST_ACTIVE=0; ACTIVE_STREAK=0; N=0
fi
sample() {
  local out filtered max
  out=$("$SMI" --query-gpu=index,utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null) || return 1
  [[ -n "$out" ]] || return 1
  filtered="$out"
  if [[ "$GPUS" != all ]]; then
    filtered=$(printf '%s\n' "$out" | awk -F', ' -v want=",$GPUS," 'index(want, ","$1",")')
    [[ -n "$filtered" ]] || return 1
  fi
  max=$(printf '%s\n' "$filtered" | awk -F', ' 'BEGIN{m=0} {if ($2+0>m) m=$2+0} END{print m}')
  printf '%s|%s' "$max" "$(printf '%s' "$filtered" | tr '\n' ';')"
}
finish() {
  printf 'GPU-WATCH: %s\njourney: %s  gpus: %s  elapsed: %smin  samples: %s\n  - %s\n' \
    "$2" "$JOURNEY" "$GPUS" "$((ELAPSED/60))" "$N" "$3"
  if [[ -d "$LOGDIR" ]]; then
    jq -cn --arg t "$(date -u +%Y%m%dT%H%M%SZ)" --arg j "$JOURNEY" --arg v "$2" --arg d "$3" \
      '{ts:$t,journey:$j,event:$v,detail:$d}' >> "$LOGFILE"
  fi
  exit "$1"
}
if ! S=$(sample); then finish 2 PROBE-FAILED "nvidia-smi query failed or GPU filter '$GPUS' matched nothing"; fi
MAXU="${S%%|*}"; DETAIL="${S#*|}"; N=$((N+1))
if [[ -d "$LOGDIR" ]]; then
  jq -cn --arg t "$(date -u +%Y%m%dT%H%M%SZ)" --arg j "$JOURNEY" --argjson u "$MAXU" --arg g "$DETAIL" \
    '{ts:$t,journey:$j,max_util:$u,gpus:$g}' >> "$LOGFILE"
fi
if [[ "$MAXU" -ge "$ACTIVE_PCT" ]]; then
  SEEN_ACTIVE=1; LAST_ACTIVE=$ELAPSED; ACTIVE_STREAK=$((ACTIVE_STREAK+1))
else
  ACTIVE_STREAK=0
  if [[ "$SEEN_ACTIVE" -eq 1 && $((ELAPSED-LAST_ACTIVE)) -ge "$STALL_SECS" ]]; then
    finish 3 STALL "GPU was active, now silent $(((ELAPSED-LAST_ACTIVE)/60))min (>= $((STALL_SECS/60))min) — inspect the executor transcript and Reach inbox NOW"
  elif [[ "$SEEN_ACTIVE" -eq 0 && "$ELAPSED" -ge "$GRACE_SECS" ]]; then
    finish 4 NEVER-STARTED "no GPU activity within $((GRACE_SECS/60))min grace — is the phase still preparing, or pointed the wrong way?"
  fi
fi
tmp=$(mktemp "$STATE.XXXXXX")
printf '%s %s %s %s %s\n' "$ELAPSED" "$SEEN_ACTIVE" "$LAST_ACTIVE" "$ACTIVE_STREAK" "$N" > "$tmp"
mv -f -- "$tmp" "$STATE"
if [[ "$ELAPSED" -ge $((MAX_HOURS*3600)) ]]; then
  finish 0 WINDOW-ELAPSED "max window reached with healthy activity (seen_active=$SEEN_ACTIVE) — re-arm if the GPU phase continues"
fi
printf 'GPU-WATCH: healthy journey=%s gpus=%s elapsed=%smin samples=%s active-streak=%s\n' \
  "$JOURNEY" "$GPUS" "$((ELAPSED/60))" "$N" "$ACTIVE_STREAK"
