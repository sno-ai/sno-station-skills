#!/usr/bin/env bash
# exec-state.sh — say what an executor is doing right now, from disk, without asking it.
#
# A supervisor should be able to say that an agent is alive and what it is doing; "alive"
# alone does not distinguish work from a stall. Needs Linux with tmux, ps (procps), jq,
# awk and find (checked at start).
#
# Two instruments, because neither answers alone:
#
#   1. The process tree. The children of the executor's pane process, with their argv, say
#      what is running. It needs no cooperation from the agent, so it survives a stall.
#   2. The runtime session store. Both runtimes append typed records to a per-session file
#      for the whole turn, so the tail of that file says whether a turn is open, and its
#      growth says whether the turn is moving. The process tree cannot see either: an
#      agent thinking hard and an agent hung look identical from outside.
#
# A runtime-specific signal is reported as runtime-specific and never generalised. Codex
# excludes its idle inhibitor. Claude's helpers stay in the runtime process group, while tool
# commands are direct children in a different group; executable names are not classifications.
#
# usage: exec-state.sh --callsign <name> [--runtime codex|claude] [--session-file <path>]
#                      [--stale-seconds <n>] [--json]
#        exec-state.sh --pid <runtime-pid> [--runtime codex|claude] [--checkout <dir>]
#                      [--session-file <path>] [--stale-seconds <n>] [--json]
#   --pid names the runtime process directly (a seat that joined by hand has no spawn
#   record or tmux window); --runtime defaults to its process name and --checkout to its
#   current directory. The spawn-record and window states below are unreachable in this mode.
# States, exactly one, on stdout:
#   stopped           the runtime process is SIGSTOPped; it will not resume on its own
#   runtime-mismatch  the record and the process at the runtime position disagree
#   ambiguous-runtime more than one process under this pane carries the recorded runtime name
#   working          a child process is running; its argv is reported
#   reasoning        no child, a turn is open, and the session file is still growing
#   stalled          no child, a turn is open, and the session file has not moved
#   idle             no child and no turn open
#   dead             no tmux session for this callsign
#   record-missing   no spawn record for this callsign
#   record-stale     the spawn record names a pane that no longer exists
#   unknown          the session is gone and nothing says why
# exit 0 always when a state could be determined; 64 usage; 65 no spawn record file;
# 69 a required tool is missing.
set -Eeuo pipefail

SPAWNS="${AGENT_SPAWNS:-$HOME/.local/state/agent-spawns.jsonl}"
# A turn whose file has not grown for this long is not thinking, it is stuck. The number
# is fixed here so that "has it been long enough" is not re-judged every time.
STALE_SECONDS_DEFAULT=180
# The launcher's runner parks on this exact command after the runtime returns, so the pane
# always has a child. It is not work.
readonly RUNNER_IDLE_TRAILER='sleep 86400'

# Every descendant of a pid, breadth-first, as "pid comm args". The pane process is the
# runner script, so what the agent is doing is never inferred from the pane process itself.
# The runner's child is the dedicated-scope runtime, whose children are the commands the
# agent actually runs.
descendants() { # pid
    local queue=("$1") pid kid kcomm kargs
    while ((${#queue[@]} > 0)); do
        pid="${queue[0]}"; queue=("${queue[@]:1}")
        while read -r kid kcomm kargs; do
            [[ -n "$kid" ]] || continue
            printf '%s %s %s\n' "$kid" "$kcomm" "$kargs"
            queue+=("$kid")
        done < <(ps --ppid "$pid" -o pid=,comm=,args= 2>/dev/null || true)
    done
}

# Where the runtime keeps the record of the turn in progress. The spawn record cannot name
# it: the file does not exist until the runtime has started and chosen its own name.
discover_session_file() { # runtime checkout since-epoch
    local runtime="$1" checkout="$2" since="$3" slug dir f
    case "$runtime" in
        claude)
            # The runtime encodes the working directory in the path, so this is exact.
            slug="$(printf '%s' "$checkout" | tr '/.' '--')"
            dir="$HOME/.claude/projects/$slug"
            [[ -d "$dir" ]] || return 1
            find "$dir" -maxdepth 1 -name '*.jsonl' -newermt "@$since" -printf '%T@ %p\n' 2>/dev/null |
                sort -rn | head -1 | cut -d' ' -f2-
            ;;
        codex)
            # The path carries only a date, so the working directory is read from the file's
            # own opening record — matching by time alone would pick up another lane's run.
            while read -r f; do
                [[ -n "$f" ]] || continue
                if head -1 "$f" 2>/dev/null | jq -e --arg c "$checkout" \
                    'select((.cwd // .payload.cwd) == $c)' >/dev/null 2>&1; then
                    printf '%s\n' "$f"
                    return 0
                fi
            done < <(find "$HOME/.codex/sessions" -name 'rollout-*.jsonl' -newermt "@$since" \
                        -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
            return 1
            ;;
        *) return 1 ;;
    esac
}

callsign='' runtime='' session_file='' stale_seconds="$STALE_SECONDS_DEFAULT" as_json=no
pid_arg='' checkout_arg=''
while (($# > 0)); do
    case "$1" in
        --callsign)       callsign="${2:-}"; shift 2 ;;
        --pid)            pid_arg="${2:-}"; shift 2 ;;
        --checkout)       checkout_arg="${2:-}"; shift 2 ;;
        --runtime)        runtime="${2:-}"; shift 2 ;;
        --session-file)   session_file="${2:-}"; shift 2 ;;
        --stale-seconds)  stale_seconds="${2:-}"; shift 2 ;;
        --json)           as_json=yes; shift ;;
        -h|--help)        sed -n '/^# usage:/,/^# 69 a required/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'exec-state: unsupported option: %s\n' "$1" >&2; exit 64 ;;
    esac
done
if [[ -n "$pid_arg" ]]; then
    [[ "$pid_arg" =~ ^[1-9][0-9]*$ ]] ||
        { printf 'exec-state: --pid must be a process id\n' >&2; exit 64; }
    [[ -z "$callsign" ]] || { printf 'exec-state: --pid and --callsign are exclusive\n' >&2; exit 64; }
    callsign="pid:$pid_arg"
fi
[[ -n "$callsign" ]] || { printf 'exec-state: --callsign or --pid is required\n' >&2; exit 64; }
missing=()
for _tool in ps jq awk find; do command -v "$_tool" >/dev/null || missing+=("$_tool"); done
if [[ -z "$pid_arg" ]]; then command -v tmux >/dev/null || missing+=(tmux); fi
if ((${#missing[@]} > 0)); then
    printf 'exec-state: missing dependency: %s (needs Linux with tmux, ps, jq, awk and find)\n' "${missing[*]}" >&2
    exit 69
fi
[[ "$stale_seconds" =~ ^[0-9]+$ ]] ||
    { printf 'exec-state: --stale-seconds must be a whole number\n' >&2; exit 64; }

state='' detail='' argv='' pane='' turn=''

emit_state() {
    if [[ "$as_json" == yes ]]; then
        jq -nc --arg cs "$callsign" --arg st "$state" --arg d "$detail" \
            --arg a "$argv" --arg p "$pane" --arg rt "$runtime" --arg turn "$turn" \
            '{callsign:$cs,state:$st,detail:$d,running:$a,pane:$p,runtime:$rt,turn:$turn}'
    else
        printf 'state=%s\n' "$state"
        [[ -z "$argv" ]] || printf 'running=%s\n' "$argv"
        [[ -z "$detail" ]] || printf 'detail=%s\n' "$detail"
    fi
    exit 0
}

# --- the spawn record -------------------------------------------------------------
record='' spawn_id='' pane_pid='' runtime_pid='' candidate_pid='' identity='' identity_detail='' tree=''
if [[ -n "$pid_arg" ]]; then
    # A named runtime process: no spawn record, no window. The process is the whole identity.
    if ! ps -p "$pid_arg" >/dev/null 2>&1; then
        state=dead
        detail="no process with pid $pid_arg"
        emit_state
    fi
    [[ -n "$runtime" ]] || runtime="$(ps -o comm= -p "$pid_arg" 2>/dev/null | tr -d ' ' || true)"
    pane_pid="$pid_arg"
    runtime_pid="$pid_arg"
    candidate_pid="$pid_arg"
else
[[ -f "$SPAWNS" ]] || { printf 'exec-state: no spawn record file at %s\n' "$SPAWNS" >&2; exit 65; }
record="$(grep -F "\"callsign\":\"$callsign\"" "$SPAWNS" 2>/dev/null | tail -1 || true)"
if [[ -z "$record" ]]; then
    state=record-missing
    detail="no spawn record for $callsign in $SPAWNS"
    emit_state
fi
pane="$(jq -r '.pane // ""' <<<"$record" 2>/dev/null || true)"
spawn_id="$(jq -r '.spawn_id // ""' <<<"$record" 2>/dev/null || true)"
[[ -n "$runtime" ]] || runtime="$(jq -r '.runtime // "codex"' <<<"$record" 2>/dev/null || echo codex)"
[[ -n "$session_file" ]] || session_file="$(jq -r '.session_file // ""' <<<"$record" 2>/dev/null || true)"

# --- is the window there at all? --------------------------------------------------
if ! tmux has-session -t "$callsign" 2>/dev/null; then
    # A window that is gone with a terminal-state artifact beside it ended; one with
    # nothing beside it is not proof of a clean finish.
    state_file="$(jq -r '.state_file // ""' <<<"$record" 2>/dev/null || true)"
    state_spawn_id=''
    if [[ -n "$state_file" && -f "$state_file" ]]; then
        state_spawn_id="$(sed -n 's/^spawn-id=//p' "$state_file" 2>/dev/null | head -1 || true)"
    fi
    if [[ -n "$spawn_id" && "$state_spawn_id" == "$spawn_id" ]]; then
        state=dead
        detail="the window is gone and its terminal state file matches spawn $spawn_id: $state_file"
    else
        state=unknown
        detail="the window for $callsign is gone and no terminal state matches current spawn ${spawn_id:-<missing>} — this is NOT a finish"
    fi
    emit_state
fi

if [[ -n "$pane" ]] && ! tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$pane"; then
    state=record-stale
    detail="the spawn record names pane $pane, which no longer exists"
    emit_state
fi

# --- which process IS the runtime: position, verified by name ----------------------
# Not name alone. An executor's tree can contain helper processes named after other tools (for example an
# MCP server), so "the process called <runtime>" picks the wrong one or calls a healthy executor
# ambiguous. The launcher puts the dedicated-scope runtime directly below the runner; a
# runtime started under a `timeout` wall wrapper is identified by position; otherwise
# there must be exactly one name match inside this pane's tree.
# The tree is walked from the live pane, which puts a recycled pid or a same-named process
# elsewhere on the machine out of reach.
# Use the recorded pane, not the session's first one: a session can hold more than one pane,
# and reading a neighbour's pane would answer about the wrong agent.
pane_pid=''
if [[ -n "$pane" ]]; then
    pane_pid="$(tmux list-panes -a -F '#{pane_id} #{pane_pid}' 2>/dev/null |
        awk -v want="$pane" '$1 == want { print $2; exit }' || true)"
fi
[[ -n "$pane_pid" ]] ||
    pane_pid="$(tmux list-panes -t "$callsign" -F '#{pane_pid}' 2>/dev/null | head -1 || true)"
if [[ -n "$pane_pid" ]]; then
    tree="$(descendants "$pane_pid")"
    wall_pid="$(ps --ppid "$pane_pid" -o pid=,comm= 2>/dev/null |
        awk '$2 == "timeout" { print $1; exit }' || true)"
    wall_kids=''
    [[ -z "$wall_pid" ]] || wall_kids="$(ps --ppid "$wall_pid" -o pid=,comm= 2>/dev/null || true)"
    if [[ -n "$wall_kids" ]] && (( $(grep -c . <<<"$wall_kids") == 1 )); then
        candidate_pid="$(awk '{ print $1 }' <<<"$wall_kids")"
        candidate_comm="$(awk '{ print $2 }' <<<"$wall_kids")"
        if [[ "$candidate_comm" == "$runtime" ]]; then
            runtime_pid="$candidate_pid"
        else
            identity=runtime-mismatch
            identity_detail="the spawn record says the runtime is '$runtime'; the process the wall is running is '$candidate_comm' (pid $candidate_pid). The record is stale, or this pane is not the executor it names."
        fi
    elif [[ -n "$tree" ]]; then
        # Dedicated-scope runner, or an agent started by hand. Fall back to the recorded
        # name inside this pane's tree only; two matches cannot be decided.
        name_matches="$(awk -v rt="$runtime" '$2 == rt { print $1 }' <<<"$tree")"
        if [[ -n "$name_matches" ]]; then
            if (( $(grep -c . <<<"$name_matches") == 1 )); then
                runtime_pid="$name_matches"
                candidate_pid="$runtime_pid"
            else
                identity=ambiguous-runtime
                identity_detail="more than one process under this pane is named '$runtime' (pids $(tr '\n' ' ' <<<"$name_matches")); which one is the executor cannot be decided from here"
            fi
        fi
    fi
fi

# --- a stopped process outranks every other signal ----------------------------------
# A stopped process is not an idle one. A runtime in a background process group can take
# SIGTTIN on its first terminal read and remain in state T.
#
# Compare the first character of the status field, uppercase: a real runtime reports `Tl`,
# so comparing the whole field would miss it. Lowercase `t` is a debugger stop — someone is
# attached and meant it — and is deliberately not reported.
fi
if [[ -n "$candidate_pid" ]]; then
    cand_stat="$(ps -o stat= -p "$candidate_pid" 2>/dev/null | tr -d ' ' || true)"
    if [[ "${cand_stat:0:1}" == T ]]; then
        state=stopped
        argv="$(ps -o comm= -p "$candidate_pid" 2>/dev/null || true)"
        detail="the runtime ($argv, pid $candidate_pid) is STOPPED (status $cand_stat). It is not idle and it will not resume on its own: a runtime in a background process group takes SIGTTIN on its first read of the terminal, so check that the runtime runs in the pane's foreground process group."
        [[ -z "$identity_detail" ]] ||
            detail="$detail The spawn record also disagrees with the process tree: $identity_detail"
        emit_state
    fi
fi
if [[ -n "$identity" ]]; then
    state="$identity"
    detail="$identity_detail"
    emit_state
fi

# --- instrument 1: what is running ------------------------------------------------
if [[ -n "$pane_pid" ]]; then
    if [[ -n "$runtime_pid" ]]; then
        # The agent is the runtime, so work means a command the runtime started. The runtime
        # itself running is not work — it is the executor existing.
        if [[ "$runtime" == claude ]]; then
            # Persistent Claude helpers remain in Claude's process group. Tool commands are
            # direct children in a different process group. Names cannot distinguish them: an
            # idle Claude can carry several such helper children, possibly named after other tools.
            runtime_pgid="$(ps -o pgid= -p "$runtime_pid" 2>/dev/null | tr -d ' ' || true)"
            if [[ -n "$runtime_pgid" ]]; then
                argv="$(ps --ppid "$runtime_pid" -o pgid=,args= 2>/dev/null |
                    awk -v own="$runtime_pgid" '
                        $1 != own {
                            $1 = ""; sub(/^ +/, "")
                            if ($0 !~ /^\[/) { print; exit }
                        }
                    ' || true)"
            fi
        else
            # The idle-inhibitor child and codex-code-mode-host are session-long Codex
            # bookkeeping, not work; counting them would make every idle Codex read as working.
            argv="$(ps --ppid "$runtime_pid" -o args= 2>/dev/null |
                grep -v 'systemd-inhibit' | grep -v 'codex-code-mode-host' | grep -v '^\[' | head -1 || true)"
        fi
    else
        # No runtime in the tree: either an agent started by hand, or the runner parked after
        # the runtime returned. Never count the park itself.
        argv="$(awk -v trailer="$RUNNER_IDLE_TRAILER" '
            $2 == "timeout" || $2 == "systemd-inhibit" || $2 == "codex-code-mode" { next }
            { line = $0; sub(/^[0-9]+ [^ ]+ /, "", line)
              if (line != trailer && line !~ /^\[/) { print line; exit } }
        ' <<<"$tree")"
    fi
fi
if [[ -n "$argv" ]]; then
    state=working
    emit_state
fi

# --- instrument 2: is a turn open, and is it moving? -------------------------------
# Without this the answer stops at "alive, no child", which cannot tell an agent thinking
# from an agent hung.
if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    if [[ -n "$pid_arg" ]]; then
        spawn_epoch="$(date -d "$(ps -o lstart= -p "$pid_arg" 2>/dev/null || true)" +%s 2>/dev/null || echo 0)"
        checkout="${checkout_arg:-$(readlink "/proc/$pid_arg/cwd" 2>/dev/null || true)}"
    else
        spawn_epoch="$(date -d "$(jq -r '.ts // ""' <<<"$record" 2>/dev/null || true)" +%s 2>/dev/null || echo 0)"
        checkout="$(jq -r '.repo // ""' <<<"$record" 2>/dev/null || true)"
    fi
    if [[ -n "$checkout" ]]; then
        session_file="$(discover_session_file "$runtime" "$checkout" "$spawn_epoch" 2>/dev/null || true)"
    fi
fi
if [[ -z "$session_file" || ! -f "$session_file" ]]; then
    state=idle
    turn=unknown
    detail="no child process, and no session file could be found for this executor, so turn state is unavailable — an open turn would be invisible here"
    emit_state
fi

case "$runtime" in
    codex)  # The last exact user/task boundary wins. A substring can belong to an older turn
            # or message content and must not close a later user prompt.
            if boundary_stream="$(jq -r '
                if (.type == "response_item" and .payload.type == "message" and
                    .payload.role == "user") or
                   (.type == "event_msg" and .payload.type == "user_message") then
                    "open"
                elif .type == "event_msg" and .payload.type == "task_complete" then
                    "closed"
                else empty end
            ' "$session_file" 2>/dev/null)"; then
                turn="$(tail -1 <<<"$boundary_stream")"
                [[ -n "$turn" ]] || turn=open
            else
                turn=open
            fi ;;
    claude) # The last RELEVANT boundary wins. Tool results and trailing bookkeeping do not
            # open a turn; a new non-tool user prompt does. Claude emits `tool_use` on every
            # non-terminal assistant fragment and a different, non-empty reason at termination.
            if boundary_stream="$(jq -r '
                if (.type == "user" and (.isSidechain != true) and
                    ((.message.content | type) == "array") and
                    any(.message.content[]?; .type != "tool_result")) then
                    "open"
                elif (.type == "assistant" and (.isSidechain != true) and
                      ((.message.stop_reason // "") != "") and
                      (.message.stop_reason != "tool_use")) then
                    "closed"
                else empty end
            ' "$session_file" 2>/dev/null)"; then
                turn="$(tail -1 <<<"$boundary_stream")"
                [[ -n "$turn" ]] || turn=open
            else
                # A malformed tail must not fabricate an idle executor.
                turn=open
            fi ;;
    *)      turn=unknown ;;
esac

if [[ "$turn" == closed ]]; then
    state=idle
    detail='no child process and no turn open'
    emit_state
fi

now="$(date +%s)"
mtime="$(stat -c %Y "$session_file" 2>/dev/null || echo 0)"
age=$((now - mtime))
if ((age <= stale_seconds)); then
    state=reasoning
    detail="a turn is open and its session file moved ${age}s ago"
else
    state=stalled
    detail="a turn is open but its session file has not moved for ${age}s (threshold ${stale_seconds}s)"
fi
emit_state
