#!/usr/bin/env bash
# spawn-exec.sh — launch one executor agent in its own tmux session (the supported way
# for a PL to start an executor).
#
# Needs: Linux, tmux, systemd user session (systemd-run, systemctl --user), flock, jq,
# git, the `sno` CLI, and the chosen runtime CLI (codex, claude, hermes or openclaw).
#
# A separate systemd service enforces the wall budget T: SIGTERM at T, then SIGKILL at
# 1.5T. A relaunch needs a fresh spawn; a relaunch after the wall needs the owner
# (whoever owns the work) to approve it.
#
# BEGIN SPAWN-EXEC USAGE
# Usage:
#   spawn-exec.sh --journey <j-id> --repo <path> --budget-h <hours>
#                 --dispatch <file> --class closure|build|operate
#                 --addr <executor Reach address> [--lane <name>]
#                 [--fence <file>] [--callsign <name>] [--kind executor]
#                 [--resume <session-id>] [--log <path>]
#                 [--runtime codex|claude|hermes|openclaw] [--window]
#   spawn-exec.sh -h|--help
#
# Required: --journey, --repo, --budget-h, --dispatch, --addr.
# Values: --class closure|build|operate (default build);
#         --runtime codex|claude|hermes|openclaw (default codex; pass --runtime claude when
#         the executor should be a Claude session). hermes (the Hermes Agent CLI) and openclaw
#         (the OpenClaw CLI) are further supported agent CLIs; they cannot resume a session.
# --resume <session-id> relaunches an existing codex or claude session; other runtimes refuse it.
# --window is accepted and ignored: tmux is the only seat channel.
# Exit: 0 spawned; 2 usage; 3 live-session conflict;
#       6 missing dependency; 7 startup proof failed.
# END SPAWN-EXEC USAGE
#
# Behavior:
#   1. Claims a callsign if not provided (callsign.sh claim).
#   2. Appends the enforced DEADLINE BLOCK to the dispatch text
#      (absolute clock times — agents cannot feel time; they must read it).
#   3. Launches the executor INSIDE A TMUX SESSION NAMED BY ITS CALLSIGN
#      with the runtime in a dedicated systemd user scope. One external controller
#      sends SIGTERM at T and cgroup-wide
#      SIGKILL at 1.5T, then records whether every owned container is empty.
#      Attach: `tmux attach -t <callsign>` for observation.
#      Mid-run instructions travel through the executor's Reach address. The runtime
#      runs without its own sandbox or approval prompts (codex --dangerously-bypass-
#      approvals-and-sandbox, claude --dangerously-skip-permissions): the guardrails are
#      the wall and fence-check.sh instead, so use it only in a repo and on a
#      machine where an unattended agent may act freely.
#   4. Records the spawn (pid, callsign, deadlines) in
#      ~/.local/state/agent-spawns.jsonl and prints a summary line.
set -euo pipefail

scripts_dir="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"

SPAWNS="$HOME/.local/state/agent-spawns.jsonl"
CALLSIGN_SH="$(dirname "$0")/callsign.sh"
LANE_RESOLVE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lane-resolve.sh"
WALL_CONTROLLER="$(dirname "$0")/executor-wall.sh"

journey="" repo="" lane="" budget_h="" dispatch="" callsign="" kind="executor" resume="" log="" jclass="" fence=""
# The runtime is selectable per spawn, Codex by default. The adapter
# owns exactly two things: how to launch and how to resume.
runtime="codex"
# The Reach address this executor answers to. It is passed at launch and never inferred.
addr=""
usage() {
  sed -n '/^# BEGIN SPAWN-EXEC USAGE$/,/^# END SPAWN-EXEC USAGE$/p' "$0" |
    sed '1d;$d;s/^# \{0,1\}//'
}
while [ $# -gt 0 ]; do
  case "$1" in
    --journey)  journey="$2"; shift 2 ;;
    --repo)     repo="$2"; shift 2 ;;
    --lane)     lane="$2"; shift 2 ;;
    --budget-h) budget_h="$2"; shift 2 ;;
    --dispatch) dispatch="$2"; shift 2 ;;
    --class)    jclass="$2"; shift 2 ;;
    --fence)    fence="$2"; shift 2 ;;
    --callsign) callsign="$2"; shift 2 ;;
    --kind)     kind="$2"; shift 2 ;;
    --resume)   resume="$2"; shift 2 ;;
    --log)      log="$2"; shift 2 ;;
    --runtime)  runtime="$2"; shift 2 ;;
    --window)   shift ;;   # accepted and ignored: tmux is the only seat channel
    --addr)     addr="$2"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "spawn-exec: unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -n "$journey" ] && [ -n "$repo" ] && [ -n "$budget_h" ] && [ -n "$dispatch" ] || {
  echo "spawn-exec: need --journey --repo --budget-h --dispatch" >&2; exit 2; }
# An executor that cannot be talked to, woken, or tracked is not started: a missing or
# malformed address is refused before the runtime starts.
case "$runtime" in codex|claude|hermes|openclaw) : ;; *) echo "spawn-exec: unsupported runtime: $runtime" >&2; exit 2 ;; esac
if [ -n "$resume" ]; then
  case "$runtime" in codex|claude) : ;; *)
    echo "spawn-exec: --resume is not supported for runtime $runtime (only codex and claude sessions can be resumed); nothing was started" >&2; exit 2 ;; esac
fi
[ -n "$addr" ] || { echo "spawn-exec: --addr <executor Reach address> is required; an executor that cannot be addressed cannot be woken" >&2; exit 2; }
[[ "$addr" =~ ^[a-z][a-z0-9-]{0,31}\.[a-z0-9][a-z0-9-]{0,63}@[a-z0-9][a-z0-9.-]{0,252}$ ]] || { echo "spawn-exec: invalid Reach address: $addr" >&2; exit 2; }
jclass="${jclass:-build}"
[ -f "$dispatch" ] || { echo "spawn-exec: dispatch file not found: $dispatch" >&2; exit 2; }
if [ "$jclass" = operate ]; then
  for field in command working-directory artifact; do
    grep -qE "^${field}:[[:space:]]*[^[:space:]]" "$dispatch" || {
      echo "spawn-exec: operate dispatch missing $field field" >&2; exit 2;
    }
  done
fi

mkdir -p "$HOME/.local/state"; touch "$SPAWNS"
[ -z "$fence" ] || [ -f "$fence" ] || { echo "spawn-exec: fence file not found: $fence" >&2; exit 2; }
[ -d "$repo" ] || { echo "spawn-exec: repo dir not found: $repo" >&2; exit 2; }
repo="$(cd -- "$repo" && pwd -P)"
main_root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$repo")"
# Check every prerequisite before any resource is claimed, and report all that are missing in one message.
missing_deps=()
for dep in "$runtime" tmux sno flock systemd-run systemctl jq; do
  command -v "$dep" >/dev/null || missing_deps+=("$dep")
done
if [ "${#missing_deps[@]}" -gt 0 ]; then
  echo "spawn-exec: missing dependency: ${missing_deps[*]} (needs Linux with tmux, a systemd user session, flock, jq, the sno CLI and the runtime CLI on PATH; nothing was started)" >&2
  exit 6
fi
[ -x "$WALL_CONTROLLER" ] || { echo "spawn-exec: missing dependency: executable executor-wall.sh beside this script" >&2; exit 6; }
[ -f "$LANE_RESOLVE" ] || { echo "spawn-exec: missing dependency: lane-resolve.sh beside this script" >&2; exit 6; }
# Workspace layout: control files live under <repo>/ai-doc/ACTIVE/PL; created on first use.
mb_base="$main_root/ai-doc"
mkdir -p "$mb_base/ACTIVE/PL/exec-logs" || {
  echo "spawn-exec: cannot create $mb_base/ACTIVE/PL/exec-logs" >&2; exit 2; }
# Mission registry: every charter carries one machine-readable mission header line;
# this script is the only writer of missions.jsonl.
missions="$mb_base/ACTIVE/PL/missions.jsonl"
touch "$missions" || {
  echo "spawn-exec: cannot initialize mission registry: $missions" >&2
  exit 2
}
mhdr="$(grep -m1 -E '^mission:' "$dispatch" 2>/dev/null || true)"
mfield() { { printf '%s\n' "$mhdr" | grep -oE "$1[[:space:]]*:[[:space:]]*[^·]+" | head -1 | sed -E "s/^$1[[:space:]]*:[[:space:]]*//; s/[[:space:]]+$//"; } || true; }
m_id="$(mfield mission)"; m_op="$(mfield operation)"; m_test="$(mfield success-test)"
m_evid="$(mfield evidence)"; m_owner="$(mfield owner)"; m_parent="$(mfield parent)"; m_pred="$(mfield predecessor)"
m_pred_spawn="$(mfield predecessor-spawn-id)"
m_id="${m_id:-$journey}"; m_op="${m_op:-open}"; m_test="${m_test:-unspecified}"
m_evid="${m_evid:-unspecified}"; m_owner="${m_owner:-unspecified}"

case "$budget_h" in ''|*[!0-9.]*|.|*.*.*) echo "spawn-exec: --budget-h must be a positive number" >&2; exit 2 ;; esac

# JSON-ledger fields are written by naive printf — strip anything that could
# break a JSON string or forge records (quotes, backslashes, control bytes).
sane() { printf '%s' "${1:-}" | tr '[:cntrl:]' ' ' | tr -d '\\"'; }
journey="$(sane "$journey")"; kind="$(sane "$kind")"; resume="$(sane "$resume")"
runtime="$(sane "$runtime")"; addr="$(sane "$addr")"
callsign="$(sane "$callsign")"; repo="$(sane "$repo")"; log="$(sane "$log")"

# budget arithmetic (awk — no bc dependency); grace = 1.5 * budget.
# One external controller sends TERM at T and KILL exactly at the 1.5T wall.
budget_s=$(awk -v h="$budget_h" 'BEGIN{printf "%d", h*3600}')
grace_s=$(awk -v h="$budget_h" 'BEGIN{printf "%d", h*3600*1.5}')
[ "$budget_s" -gt 0 ] || { echo "spawn-exec: --budget-h must be > 0" >&2; exit 2; }
# Two distinct deadlines require at least one second between TERM and KILL.
[ "$grace_s" -ge 2 ] || { echo "spawn-exec: budget too small — 1.5x grace must be >= 2s (got ${grace_s}s)" >&2; exit 2; }
wall_epoch="$(date +%s)"
t_budget="$(date -d "@$((wall_epoch + budget_s))" '+%Y-%m-%d %H:%M %Z')"
t_grace="$(date -d "@$((wall_epoch + grace_s))" '+%Y-%m-%d %H:%M %Z')"
# comms deadlines (persisted ISO — roster.sh is the timer owner and needs
# machine-comparable values; the roster owns the alarm)
t_ack="$(date -d '+15 minutes' -Is)"
t_conv="$(date -d '+90 minutes' -Is)"

# Lane resolution keys on the REPOSITORY name.
repo_base="$(basename "$main_root")"
resolve_args=(--repo "$repo_base" --field addr)
[ -z "$lane" ] || resolve_args+=(--lane "$lane")
if ! pl_address="$(PL_REGISTRY="${PL_REGISTRY:-${SNO_PL_REGISTRY:-}}" \
    bash "$LANE_RESOLVE" "${resolve_args[@]}")"; then
  exit 2
fi

claimed_here=0
if [ -z "$callsign" ]; then
  callsign="$("$CALLSIGN_SH" claim --journey "$journey" --repo "$main_root" --kind "$kind" \
      --label "spawned $(date '+%H:%M')")" || exit $?
  claimed_here=1
fi
# The executor that actually holds a primary open/transfer is the lifecycle
# owner. Auto-claim cannot know that identity when the dispatch is authored,
# so normalize only after the atomic claim; delegates retain the primary owner.
case "$m_op" in
  open|transfer) m_owner="$callsign" ;;
esac
# ANY post-claim failure — cd, mktemp, disk-full, tmux — must not strand the
# claim (`set -e` skips inline cleanup): EXIT trap releases
# what WE claimed unless the spawn reached success.
spawn_ok=0 mission_registered=0 abort_runner="" session_started=0
wall_started=0 wall_unit="" runtime_started=0 runtime_unit=""
seat_lock_fd="" startup_pane=""
seat_dir="" startup_file="" reach_root=""
mission_lock="${missions}.lock"
cleanup_reach_startup() {
  local runtime_group="" runtime_deadline
  if [ "$session_started" = 1 ] && tmux has-session -t "$callsign" 2>/dev/null; then
    tmux kill-session -t "$callsign" 2>/dev/null || true
  fi
  if [ "$wall_started" = 1 ] && [ -n "$wall_unit" ]; then
    systemctl --user stop "$wall_unit" >/dev/null 2>&1 || true
  fi
  if [ "$runtime_started" = 1 ] && [ -n "$runtime_unit" ]; then
    if ! bash "$WALL_CONTROLLER" --spawn-id "$mission_spawn_id" --cleanup-now; then
      echo "spawn-exec: CRITICAL — failed startup left marked executor work alive; preserving mission and callsign for recovery" >&2
      return 1
    fi
    systemctl --user kill --kill-whom=all --signal=KILL "$runtime_unit" >/dev/null 2>&1 || true
    systemctl --user stop --no-block "$runtime_unit" >/dev/null 2>&1 || true
    runtime_deadline=$(( SECONDS + 5 ))
    while [ "$SECONDS" -lt "$runtime_deadline" ]; do
      runtime_group="$(systemctl --user show "$runtime_unit" -p ControlGroup --value 2>/dev/null || true)"
      if [ -z "$runtime_group" ] || [ ! -r "/sys/fs/cgroup$runtime_group/cgroup.procs" ] ||
         [ ! -s "/sys/fs/cgroup$runtime_group/cgroup.procs" ]; then
        runtime_started=0
        break
      fi
      sleep 0.1
    done
    if [ "$runtime_started" = 1 ]; then
      echo "spawn-exec: CRITICAL — failed startup left runtime unit $runtime_unit non-empty; preserving mission and callsign for recovery" >&2
      return 1
    fi
  fi
  if [ -n "$startup_pane" ] && [ -f "$seat_dir/reachable.json" ] &&
     jq -e --arg pane "$startup_pane" '.identity == {kind:"tmux-pane",value:$pane}'        "$seat_dir/reachable.json" >/dev/null 2>&1; then
    sno reach unregister --as "$addr" >/dev/null ||
      echo "spawn-exec: could not unregister failed Reach seat $addr" >&2
  fi
  if [ -n "$seat_lock_fd" ]; then
    flock -u "$seat_lock_fd" 2>/dev/null || true
    exec {seat_lock_fd}>&-
    seat_lock_fd=""
  fi
}
release_on_fail() {
  [ "$spawn_ok" = 1 ] && return 0
  if ! cleanup_reach_startup; then
    return 1
  fi
  if [ "$mission_registered" = 1 ]; then
    if ! bash "$abort_runner" launch 1; then
      echo "spawn-exec: CRITICAL — launch failed and mission abort could not be recorded in $missions" >&2
      "$CALLSIGN_SH" release "$callsign" --journey "$journey" 2>/dev/null || true
    fi
    mission_registered=0
    claimed_here=0
  fi
  [ "$claimed_here" = 1 ] && "$CALLSIGN_SH" release "$callsign" --journey "$journey" 2>/dev/null || true
}
trap release_on_fail EXIT

[ -n "$log" ] || {
  mkdir -p "$mb_base/ACTIVE/PL/exec-logs" 2>/dev/null || true
  log="$mb_base/ACTIVE/PL/exec-logs/${journey}-${callsign}.log"
  touch "$log" 2>/dev/null || log="$HOME/.local/state/${journey}-${callsign}.log"
}
[ -e "$log" ] || touch "$log" || {
  echo "spawn-exec: cannot create explicit log path: $log" >&2
  exit 2
}

# Render and lint the exact bytes the executor will send before any tmux session starts.
# This proves message validity only; the on-station acknowledgement still proves Reach
# readiness.
#
# The card carries the launcher's own measurement of the fence file (exists, bytes,
# sha256); the executor sends its own reading separately, so the two can be compared.
fence_exists_at_spawn=no
fence_bytes_at_spawn=0
fence_sha_at_spawn=none
if [ -n "$fence" ] && [ -f "$fence" ]; then
  fence_exists_at_spawn=yes
  fence_bytes_at_spawn="$(wc -c <"$fence" | tr -d ' ')"
  fence_sha_at_spawn="$(sha256sum -- "$fence" | cut -d' ' -f1)"
fi
on_station_message="$log.on-station.eml"
{
  printf 'From: %s <%s>\n' "$callsign" "$addr"
  printf 'To: PL <%s>\n' "$pl_address"
  printf 'Subject: [STATUS] on-station: %s\n' "$callsign"
  printf 'Date: %s\n' "$(date -R)"
  printf 'Message-ID: <on-station-%s-%s@%s>\n' "$(date +%s%N)" "$$" "$(hostname)"
  printf 'X-Work: %s\n' "$journey"
  printf 'X-Type: status\n\n'
  printf 'on station; charter=%s.dispatch read; fence=%s\n' "$log" "${fence:-NONE}"
  printf 'measured-at-spawn: fence-exists=%s fence-bytes=%s fence-sha256=%s\n' \
    "$fence_exists_at_spawn" "$fence_bytes_at_spawn" "$fence_sha_at_spawn"
  printf 'observed-by-executor: sent separately; a disagreement with the line above is a finding\n'
} >"$on_station_message"
if ! sno reach lint "$on_station_message"; then
  echo "spawn-exec: generated on-station message failed canonical lint; no executor was started" >&2
  exit 7
fi

# Serialize launches for one address while Reach initializes its persistent seat.
reach_root="${SNO_REACH_ROOT:-$HOME/.local/state/sno-reach}"
mkdir -p -- "$reach_root"
exec {seat_lock_fd}>"$reach_root/.spawn-$addr.lock"
flock -x "$seat_lock_fd"
seat_dir="$reach_root/$addr"
if [ -f "$seat_dir/reachable.json" ]; then
  old_pane="$(jq -er 'select(.channel == "tmux" and .identity.kind == "tmux-pane") | .identity.value'     "$seat_dir/reachable.json" 2>/dev/null || true)"
  if [ -n "$old_pane" ] && tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$old_pane"; then
    echo "spawn-exec: Reach address $addr is already registered to live pane $old_pane" >&2
    exit 3
  fi
  sno reach unregister --as "$addr" >/dev/null || {
    echo "spawn-exec: could not clear stale Reach registration for $addr" >&2; exit 7;
  }
fi
sno reach init --as "$addr" --name "${addr%@*}" >/dev/null || {
  echo "spawn-exec: could not initialize Reach seat $addr" >&2; exit 7;
}
startup_file="$log.startup"
rm -f -- "$startup_file"

# Deadline block — appended to the dispatch, absolute times only.
convergence_class="$jclass"
[ "$convergence_class" != operate ] || convergence_class=closure
merged="$(mktemp)"
cat "$dispatch" > "$merged"
cat >> "$merged" <<EOF

=== DEADLINE (enforced by the launcher) ===
Your callsign: ${callsign}. Budget: ${budget_h}h.
T  (budget)     = ${t_budget}: from this moment, STOP all feature/fix-forward
   work; smallest completion path ONLY (commit verified work via explicit
   paths, write the close report, send the close card).
1.5T (hard wall) = ${t_grace}: SIGTERM is sent at T and SIGKILL at this
   time — trapping/ignoring TERM buys you nothing.
   Anything uncommitted may be lost. There is no extension — no card, no
   apology, no reason changes this.
Past T, do not add any out-of-charter work. Within budget, extra in-scope
quality is welcome.
You cannot feel time. Run \`date\` at every phase boundary and compare
against the two timestamps above. Plan backward from T, not forward.

=== COMMS CONTRACT (acknowledgment required) ===
Read accumulated work at each task boundary and after long commands:
  sno reach inbox --as ${addr}
Read each exact card path printed by inbox. Handle decisions and questions before
continuing interrupted work. A ring is a prompt to read the inbox, not a card.

FIRST act, before any work — READ the charter and fence, then send the on-station
card. The prepared card records the spawner's fence measurement; send your own
measurement separately if it differs:
  charter: ${log}.dispatch
  fence:   ${fence:-<none declared>}
  sno reach send --as ${addr} < '${on_station_message}'
ACK deadline ${t_ack} (15 min): no card by then = the PL treats this
dispatch as never delivered and re-dispatches.
STATE to disk on every transition:
  \`bash "${scripts_dir}/callsign.sh" title run|wait|done ${callsign} --journey ${journey} "<label>"\`.
CONVERGENCE every fix-verify cycle:
  \`bash "${scripts_dir}/convergence-watch.sh" record --journey ${journey} --class ${convergence_class} --remaining <N> --cycle <k>\`
First sample due by ${t_conv}; a series silent for 90 min is treated as a stalled run.
For a work card, accept before doing the work:
  printf '%s\n' 'Accepted.' | sno reach reply --as ${addr} --card "<exact card path>" --state accepted
Then report the result with the same card path:
  printf '%s\n' '<result and evidence>' | sno reach reply --as ${addr} --card "<exact card path>" --state completed
Use --state failed if the work failed. A question asking for information takes
reply without --state. Do not dismiss an actionable question or decision.
For later supervision, arm a heartbeat that rings your own seat, then end the turn:
  heartbeat --interval 10m --label pl-${callsign} -- sno reach ring ${addr}
If Reach reports a delivered card with wake exit 5 or 6, inspect the recipient
seat; do not resend the card.
EOF

cd "$repo"
# Read the merged dispatch in the PARENT before backgrounding: bash performs a
# background command's expansions in the forked child, so an early rm of the
# temp file would race the child's $(cat …) and hand the executor an EMPTY
# dispatch.
dispatch_text="$(command cat "$merged")"
rm -f "$merged"

# Every executor runs inside a tmux session NAMED BY ITS CALLSIGN:
#   - persistent PTY: the session lives on its own — no resume pumping and no
#     double-spawn; mid-run instructions accumulate in the executor Reach
#   - attachable window: `tmux attach -t <callsign>` any time; scrollback and
#     titles stay visible
#   - no runtime sandbox: the codex workspace-write sandbox mounts .git read-only, so
#     commits would fail. The guardrails here are the wall, fence-check on every
#     commit, and explicit-path discipline.
# The runtime receives the spawn marker and runs in a dedicated systemd user scope.
# The wall is a separate user service, so it survives every scope it signals.
# Callsign grammar check: a callsign is interpolated into tmux and shell commands, so it
# must be provably inert.
case "$callsign" in *[!a-z]*|'') echo "spawn-exec: callsign must be lowercase letters only: '$callsign'" >&2; exit 2 ;; esac
if tmux has-session -t "$callsign" 2>/dev/null; then
  echo "spawn-exec: tmux session '$callsign' already exists — refusing double-spawn" >&2
  exit 3
fi
printf '%s' "$dispatch_text" > "$log.dispatch"   # BEFORE the session starts (race)

# Never build a shell program by interpolating caller values (an apostrophe in
# --log/--resume would execute as the tmux user). All values are embedded via
# printf %q into a per-spawn runner file.
runner="$log.runner"
abort_runner="$log.abort"
mission_spawn_id="$(date -u +%Y%m%dT%H%M%S)-$$-$callsign"
runtime_unit="sno-exec-${mission_spawn_id}.scope"
wall_unit="sno-exec-wall-${mission_spawn_id}.service"
wall_events="$log.wall.jsonl"
rm -f -- "$wall_events" "$wall_events.lock"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'missions=%q\nmission_lock=%q\nspawn_id=%q\n' \
    "$missions" "$mission_lock" "$mission_spawn_id"
  printf 'release_launch_claim=%q\n' "$claimed_here"
  printf 'callsign_sh=%q\ncallsign=%q\njourney=%q\n' \
    "$CALLSIGN_SH" "$callsign" "$journey"
  printf 'mission=%q\noperation=%q\nowner=%q\nsuccess_test=%q\nevidence=%q\nparent=%q\n' \
    "$m_id" "$m_op" "$m_owner" "$m_test" "$m_evid" "${m_parent:-none}"
  # A delegate is bound to the PRIMARY generation it was admitted under, never to
  # whichever delegate happens to be newest. Empty for a primary; the runner refuses
  # rather than guesses if a delegate ever reaches it unset.
  printf 'bound_primary_spawn=%q\n' "${m_pred_spawn:-}"
  cat <<'EOF'
mode="${1:-runtime}"
exit_rc="${2:-1}"
exec {lock_fd}>>"$mission_lock"
flock -x "$lock_fd"
# A delegate spawn must not supersede the primary's generation. A primary reads
# its generation from primary lifecycle events; delegates still count delegate events.
if [ "$operation" = "delegate" ] && [ -z "${bound_primary_spawn:-}" ]; then
  echo "spawn-exec: CRITICAL — delegate $spawn_id has no bound primary generation; refusing to" >&2
  echo "spawn-exec:   guess whether its terminal row belongs in $missions. Record it by hand." >&2
  exit 1
fi
current="$(
  jq -rs --arg m "$mission" --arg sid "$spawn_id" --arg op "$operation" \
     --arg bps "${bound_primary_spawn:-}" '
    [.[] | select(
      .mission == $m and
      (.event == "open" or .event == "transfer" or
       .event == "close" or .event == "abort")
    )][-1]
    | if $op == "delegate" then
        # A delegate is current while the primary generation it was admitted under is
        # still the live one. Two delegates under one primary therefore BOTH record a
        # terminal row — they are not each other'"'"'s successors. A transfer moves the
        # spawn id and a close or abort changes the event, so either suppresses it.
        (if (.event == "open" or .event == "transfer") and .spawn_id == $bps
         then "current" else "stale" end)
      else
        (if .spawn_id == $sid then "current" else "stale" end)
      end
  ' "$missions"
)"
if [ "$current" = "current" ]; then
  if [ "$mode" = "runtime" ] && [ "$operation" != "delegate" ]; then
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg m "$mission" \
      --arg o "$owner" --arg sid "$spawn_id" --arg cs "$callsign" \
      --arg journey "$journey" --argjson rc "$exit_rc" \
      '{ts:$ts,mission:$m,event:"correction",owner:$o,outcome:"executor_stopped",callsign:$cs,corrects_spawn_id:$sid,journey:$journey,exit_rc:$rc,exit_rc_is:"the status returned by the dedicated runtime scope client. It proves only that the interactive runtime stopped, not that the task completed and not that the external wall fired. Task completion still requires the terminal artifact plus close card; wall enforcement is proven only by this spawn id in its wall event file.",reason:"executor process exited; mission and callsign remain reserved for exact-session continuation"}' \
      >> "$missions"
  elif [ "$operation" = "delegate" ]; then
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg m "$mission" \
      --arg o "$owner" --arg sid "$spawn_id" --arg cs "$callsign" \
      --argjson rc "$exit_rc" \
      '{ts:$ts,mission:$m,event:"correction",owner:$o,corrects_spawn_id:$sid,delegate:$cs,outcome:(if $rc == 0 then "delegate_stopped" elif $rc >= 128 then "delegate_outcome_unknown" else "delegate_failed" end),exit_rc:$rc,exit_rc_is:"the status returned by the dedicated runtime scope client. It proves only that the interactive runtime stopped, not that the delegated task completed and not that the external wall fired. Task completion still requires an explicit result; wall enforcement is proven only by this spawn id in its wall event file. Treat delegate_outcome_unknown as neither done nor failed.",reason:"delegated executor exited; mission ownership and live state remain with the primary owner"}' \
      >> "$missions"
  else
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg m "$mission" \
      --arg o "$owner" --arg st "$success_test" --arg ev "$evidence" \
      --arg pa "$parent" --arg pr "$callsign" --arg sid "$spawn_id" \
      '{ts:$ts,mission:$m,event:"abort",owner:$o,success_test:$st,evidence_form:$ev,parent:$pa,predecessor:$pr,spawn_id:$sid,reason:"spawn-exec executor exited nonzero after lifecycle admission; no executor remains live"}' \
      >> "$missions"
  fi
else
  # This branch writes nothing to the registry, so it says so explicitly.
  echo "spawn-exec: NO stop record written for spawn $spawn_id (operation=$operation)." >&2
  echo "spawn-exec:   The mission's own lifecycle already advanced past this spawn, so this" >&2
  echo "spawn-exec:   exit is not the current generation and its stop is not recorded." >&2
  echo "spawn-exec:   The callsign is NOT released by this path. If you expected a stop" >&2
  echo "spawn-exec:   record, read $missions and find which later event superseded it." >&2
fi
flock -u "$lock_fd"
exec {lock_fd}>&-
if { [ "$mode" = "launch" ] && [ "$release_launch_claim" = 1 ]; } ||
   [ "$operation" = "delegate" ]; then
  if ! "$callsign_sh" release "$callsign" --journey "$journey"; then
    echo "spawn-exec: CRITICAL — stopped executor callsign release failed: $callsign" >&2
    exit 1
  fi
fi
EOF
} > "$abort_runner"
chmod +x "$abort_runner"

# The runtime adapter owns exactly two things: how to launch, and how to resume. Every
# other part of the lifecycle — registration, wake, liveness, close, archive — is written
# once and never branches on this value.
resume_line=""
case "$runtime" in
  codex)  [ -n "$resume" ] && resume_line="resume $(printf '%q' "$resume")" ;;
  claude) [ -n "$resume" ] && resume_line="--resume $(printf '%q' "$resume")" ;;
esac
state_file="$log.state"
rm -f -- "$state_file"
{
  printf '#!/usr/bin/env bash\nset -o pipefail\n'
  printf 'exec %d>&-\n' "$seat_lock_fd"
  printf 'export SNO_REACH_ROOT=%q\n' "$reach_root"
  printf 'export SNO_REACH_ADDR=%q\n' "$addr"
  printf 'startup_file=%q\nstartup_spawn_id=%q\n' "$startup_file" "$mission_spawn_id"
  cat <<'EOF'
write_startup_receipt() {
  local state="$1" reason="${2:-}" tmp="${startup_file}.tmp.$$"
  jq -nc --arg sid "$startup_spawn_id" --arg state "$state" --arg reason "$reason" \
    '{spawn_id:$sid,state:$state,reason:$reason}' >"$tmp" || return 1
  mv -f -- "$tmp" "$startup_file"
}
EOF
  # The executor registers its Reach seat before it starts working; a failed registration
  # is a failed spawn rather than an executor nobody can reach.
  printf "sno reach register --as %q --channel tmux --handle \"\$(tmux display-message -p '#{pane_id}')\"\n" "$addr"
  printf 'register_rc=$?\n'
  printf 'if [ "$register_rc" -ne 0 ]; then\n'
  printf '  echo "[spawn-exec] REFUSING: %s could not register its Reach seat; an unreachable executor is not started"\n' "$addr"
  printf '  write_startup_receipt refused "registration-failed:$register_rc" || true\n'
  printf '  exit "$register_rc"\n'
  printf 'fi\n'
  printf 'write_startup_receipt registered || exit 74\n'
  # systemd-run --scope stays in the pane's foreground process group and moves the runtime plus
  # ordinary and setsid descendants into one dedicated cgroup. A separately armed service owns
  # the timer and discovers any normally inherited nested scope by this spawn's marker.
  printf 'systemd-run --user --scope --quiet --unit=%q env SNO_EXEC_SPAWN_ID=%q \\\n' \
    "$runtime_unit" "$mission_spawn_id"
  case "$runtime" in
    codex)  printf '  codex --dangerously-bypass-approvals-and-sandbox %s \\\n' "$resume_line" ;;
    claude) printf '  claude --dangerously-skip-permissions %s \\\n' "$resume_line" ;;
    hermes) printf '  hermes chat --yolo --query \\\n' ;;
    openclaw) printf '  openclaw tui --message \\\n' ;;
  esac
  # No pipe: an interactive terminal program dies when its stdout becomes a pipe
  # (`codex ... | tee log` ends the session). The transcript is captured by tapping the
  # pane from outside instead (tmux pipe-pane, set at launch).
  printf '  "$(cat %q)"\n' "$log.dispatch"
  printf 'ec=$?\necho\n'
  # Completion is an ARTIFACT, not an exit code. An interactive session returns to a
  # prompt rather than exiting, so the number below cannot mean what it meant before; the
  # supervisor reads the state file and the close card, and this file carries the spawn id
  # so a stale one from a previous generation can never be mistaken for this run's.
  printf 'printf %%s "spawn-id=%s\\nruntime=%s\\nexit=$ec\\nended-at=$(date -Is)\\n" > %q\n' \
    "$mission_spawn_id" "$runtime" "$state_file"
  printf 'bash %q runtime "$ec" || echo "[spawn-exec] CRITICAL: runtime stop bookkeeping failed"\n' "$abort_runner"
  printf 'echo "[spawn-exec] the runtime returned rc=$ec."\n'
  printf 'echo "[spawn-exec]   This is NOT the completion signal. An interactive session"\n'
  printf 'echo "[spawn-exec]   returns to its prompt instead of exiting, so a return code"\n'
  printf 'echo "[spawn-exec]   here means the runtime stopped, not that the work finished."\n'
  printf 'echo "[spawn-exec]   COMPLETION IS PROVEN BY TWO THINGS TOGETHER: the terminal"\n'
  printf 'echo "[spawn-exec]   state file %s carrying THIS spawn id, and the close card."\n' "$state_file"
  printf 'echo "[spawn-exec]   Either alone is a claim, not a proof."\n'
} > "$runner"
chmod +x "$runner"

# The registry append is serialized under the mission lock. Every fallible artifact
# preparation happens before the append. If the final tmux launch still fails, the EXIT
# trap appends a terminal abort event.
mission_event="$(
  jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg m "$m_id" --arg e "$m_op" \
    --arg o "$m_owner" --arg st "$m_test" --arg ev "$m_evid" \
    --arg pa "${m_parent:-none}" --arg pr "${m_pred:-none}" --arg sid "$mission_spawn_id" \
    '{ts:$ts,mission:$m,event:$e,owner:$o,success_test:$st,evidence_form:$ev,parent:$pa,predecessor:$pr,spawn_id:$sid}'
)"
session_binding_event=""
if [ -n "$resume" ]; then
  session_binding_event="$(
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg m "$m_id" \
      --arg o "$m_owner" --arg cs "$callsign" --arg sid "$mission_spawn_id" \
      --arg session "$resume" --arg journey "$journey" \
      '{ts:$ts,mission:$m,event:"correction",owner:$o,outcome:"session_bound",callsign:$cs,binds_spawn_id:$sid,session:$session,journey:$journey}'
  )"
fi
exec {mission_lock_fd}>>"$mission_lock"
flock -x "$mission_lock_fd"
printf '%s\n' "$mission_event" >> "$missions"
[ -z "$session_binding_event" ] || printf '%s\n' "$session_binding_event" >> "$missions"
mission_registered=1
flock -u "$mission_lock_fd"
exec {mission_lock_fd}>&-

tmux new-session -d -s "$callsign" -c "$repo" "bash $(printf '%q' "$runner")"
session_started=1
runtime_started=1
pid="$(tmux list-panes -t "$callsign" -F '#{pane_pid}' | head -1)" || {
  echo "spawn-exec: session '$callsign' started but its PID cannot be resolved; refusing startup" >&2
  exit 7
}
exec_pane="$(tmux list-panes -t "$callsign" -F '#{pane_id}' | head -1)" || {
  echo "spawn-exec: session '$callsign' started but its pane cannot be resolved; refusing startup" >&2
  exit 7
}
if [ -z "$pid" ] || [ -z "$exec_pane" ]; then
  echo "spawn-exec: session '$callsign' returned an empty PID or pane; refusing startup" >&2
  exit 7
fi
startup_pane="$exec_pane"

# Tap the pane instead of piping the runtime. This is the only way to keep a transcript of
# an interactive terminal program: a shell pipe on its stdout destroys the terminal it
# needs and the session dies at once.
tmux pipe-pane -t "$callsign" -o "cat >> $(printf '%q' "$log")" 2>/dev/null || {
  echo "spawn-exec: WARNING — transcript tap failed for '$callsign'; the executor is live but unlogged" >&2; }

# A detached tmux client returning only proves that a pane was created. The spawn becomes
# successful only after this exact generation publishes an atomic registration receipt and
# the canonical seat points at this exact pane. Without both checks, a rejected child looks
# identical to a live executor at the caller boundary.
startup_state="" startup_reason="" startup_deadline=$(( SECONDS + 10 ))
while [ "$SECONDS" -lt "$startup_deadline" ]; do
  if [ -f "$startup_file" ] && [ ! -L "$startup_file" ]; then
    if jq -e --arg sid "$mission_spawn_id" \
        '.spawn_id == $sid and (.state == "registered" or .state == "refused") and
         (.reason | type == "string")' "$startup_file" >/dev/null 2>&1; then
      startup_state="$(jq -r '.state' "$startup_file")"
      startup_reason="$(jq -r '.reason' "$startup_file")"
      break
    fi
    startup_reason="invalid-or-uncorrelated-startup-receipt"
    break
  fi
  if ! tmux has-session -t "$callsign" 2>/dev/null; then
    startup_reason="session-ended-before-registration"
    break
  fi
  sleep 0.1
done
if [ -z "$startup_state" ] && [ -z "$startup_reason" ]; then
  startup_reason="startup-receipt-timeout"
fi

if [ "$startup_state" != registered ]; then
  echo "spawn-exec: executor '$callsign' refused before Reach registration completed: $startup_reason" >&2
  exit 7
fi
if ! tmux has-session -t "$callsign" 2>/dev/null ||
   ! jq -e --arg addr "$addr" --arg pane "$exec_pane" \
      '.address == $addr and .channel == "tmux" and
       .identity == {kind:"tmux-pane", value:$pane}' \
      "$seat_dir/reachable.json" >/dev/null 2>&1; then
  echo "spawn-exec: executor '$callsign' registered without exact live-pane reachability; refusing startup" >&2
  exit 7
fi
runtime_scope=""
runtime_scope_deadline=$(( SECONDS + 5 ))
while [ "$SECONDS" -lt "$runtime_scope_deadline" ]; do
  runtime_scope="$(systemctl --user show "$runtime_unit" -p ControlGroup --value 2>/dev/null || true)"
  [ -n "$runtime_scope" ] && break
  sleep 0.1
done
if [ -z "$runtime_scope" ]; then
  echo "spawn-exec: executor '$callsign' registered but its dedicated runtime scope was not created; refusing startup" >&2
  exit 7
fi

now_epoch="$(date +%s)"
term_remaining=$(( wall_epoch + budget_s - now_epoch ))
kill_remaining=$(( wall_epoch + grace_s - now_epoch ))
if [ "$term_remaining" -lt 1 ] || [ "$kill_remaining" -le "$term_remaining" ]; then
  echo "spawn-exec: startup consumed the executor wall budget before the controller could be armed; refusing startup" >&2
  exit 7
fi
if ! systemd-run --user --quiet --collect --unit="$wall_unit" \
    bash "$WALL_CONTROLLER" --spawn-id "$mission_spawn_id" \
      --term-after "$term_remaining" --kill-after "$kill_remaining" \
      --events "$wall_events"; then
  echo "spawn-exec: could not arm the external wall controller; refusing startup" >&2
  exit 7
fi
wall_started=1
if ! systemctl --user is-active --quiet "$wall_unit"; then
  echo "spawn-exec: external wall controller did not remain active; refusing startup" >&2
  exit 7
fi

# Registration is now externally visible and correlated to this pane. Transfer ownership
# of the seat and session to the running executor before recording or announcing success.
flock -u "$seat_lock_fd"
exec {seat_lock_fd}>&-
seat_lock_fd=""
session_started=0
wall_started=0
runtime_started=0
spawn_ok=1

# The initial owned scopes are evidence, not the controller's discovery boundary. The exact
# spawn marker lets the controller find normally inherited nested scopes again at TERM and KILL.
pane_scope=""
[ -z "$exec_pane" ] || pane_scope=$(sed 's|^0::||' "/proc/$pid/cgroup" 2>/dev/null | head -1 || true)

printf '{"ts":"%s","pid":%d,"callsign":"%s","journey":"%s","repo":"%s","budget_h":%s,"class":"%s","t_budget":"%s","t_grace":"%s","ack_due":"%s","conv_due":"%s","fence":"%s","log":"%s","resume":"%s","runtime":"%s","addr":"%s","pane":"%s","state_file":"%s","spawn_id":"%s","pane_scope":"%s","runtime_scope":"%s","runtime_unit":"%s","wall_unit":"%s","wall_events":"%s"}\n' \
  "$(date -Is)" "$pid" "$callsign" "$journey" "$repo" "$budget_h" "$jclass" \
  "$t_budget" "$t_grace" "$t_ack" "$t_conv" "$(sane "$fence")" "$log" "$resume" \
  "$runtime" "$addr" "$(sane "$exec_pane")" "$log.state" "$mission_spawn_id" \
  "$(sane "$pane_scope")" "$(sane "$runtime_scope")" "$runtime_unit" "$wall_unit" \
  "$(sane "$wall_events")" >> "$SPAWNS"

echo "spawned callsign=$callsign pid=$pid runtime=$runtime addr=$addr pane=$exec_pane budget=${budget_h}h T='$t_budget' WALL='$t_grace' log=$log state=$log.state"
