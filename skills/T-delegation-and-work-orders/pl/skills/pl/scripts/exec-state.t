#!/usr/bin/env bash
# Contract under test: the instrument answers "what is it doing NOW", not just "is it up".
#
# Every row is a case whose answer is already known before the instrument runs — that is
# the whole bar for a liveness instrument that could match its own process.
#
#   working         a real child command is running, and its argv is reported
#   reasoning       no child, a turn open, the session file still moving
#   stalled         no child, a turn open, the session file frozen past the threshold
#   idle            no child, no turn open
#   dead            the window is gone but a terminal state file is beside it
#   unknown         the window is gone and nothing says why — NOT a finish
#   record-missing  no spawn record
#   record-stale    the record names a pane that no longer exists
#
# Both runtimes are covered for the turn-state rows, because the record that closes a turn
# differs between them and an instrument that only knows one calls the other's working
# agent idle.
#
# Real dependencies: real tmux sessions, real files. The session store is a real JSONL file
# in each runtime's real shape; nothing about the instrument is mocked.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${TARGET:-$SCRIPT_DIR/exec-state.sh}"

root="$(mktemp -d)"
sessions=()
units=()
cleanup() {
    local s unit discovered=()
    while read -r s; do
        [[ -n "$s" ]] && discovered+=("$s")
    done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null |
        awk -v suffix="-$$" 'index($0, "walk-state-") == 1 &&
            substr($0, length($0) - length(suffix) + 1) == suffix')
    sessions+=("${discovered[@]}")
    for s in "${sessions[@]:-}"; do [[ -z "$s" ]] || tmux kill-session -t "$s" 2>/dev/null || true; done
    for unit in "${units[@]:-}"; do
        [[ -z "$unit" ]] || systemctl --user kill --kill-whom=all --signal=KILL "$unit" 2>/dev/null || true
        [[ -z "$unit" ]] || systemctl --user stop "$unit" 2>/dev/null || true
        [[ -z "$unit" ]] || systemctl --user reset-failed "$unit" 2>/dev/null || true
    done
    rm -rf -- "$root"
}
trap cleanup EXIT

export AGENT_SPAWNS="$root/agent-spawns.jsonl"
: > "$AGENT_SPAWNS"

n=0
fail=0
check() { # label expected actual
    n=$((n + 1))
    if [[ "$3" == "$2" ]]; then printf 'ok %d - %s\n' "$n" "$1"
    else printf 'not ok %d - %s\n' "$n" "$1"; printf '#   wanted %s, got %s\n' "$2" "$3"
        fail=$((fail + 1)); fi
}

state_of() { bash "$TARGET" --callsign "$1" "${@:2}" 2>/dev/null | sed -n 's/^state=//p'; }

record() { # callsign pane runtime session_file state_file [spawn_id]
    printf '{"ts":"now","pid":1,"callsign":"%s","pane":"%s","runtime":"%s","session_file":"%s","state_file":"%s","spawn_id":"%s"}\n' \
        "$1" "$2" "$3" "$4" "$5" "${6:-s1}" >> "$AGENT_SPAWNS"
}

printf 'TAP version 13\n'

# --- record-missing ---------------------------------------------------------------
check 'no spawn record is reported as such, not as dead' record-missing "$(state_of never-spawned)"

# --- working: a real child command --------------------------------------------------
cs_work="walk-state-work-$$"; sessions+=("$cs_work")
tmux new-session -d -s "$cs_work" -x 100 -y 30 "bash -c 'sleep 400; :'"
sleep 1
pane_work="$(tmux list-panes -t "$cs_work" -F '#{pane_id}' | head -1)"
record "$cs_work" "$pane_work" codex "$root/work.jsonl" "$root/work.state"
check 'a running child command is reported working' working "$(state_of "$cs_work")"
check 'the running command itself is reported, not just that something runs' pass \
    "$(bash "$TARGET" --callsign "$cs_work" 2>/dev/null | grep -q 'running=.*sleep 400' && echo pass || echo fail)"

# --- reasoning vs stalled vs idle, on a session with NO child ----------------------
cs_turn="walk-state-turn-$$"; sessions+=("$cs_turn")
tmux new-session -d -s "$cs_turn" -x 100 -y 30 "cat"
sleep 1
pane_turn="$(tmux list-panes -t "$cs_turn" -F '#{pane_id}' | head -1)"

# codex shape: an open turn is one with no task_complete at the tail
printf '{"type":"session_meta"}\n{"type":"response_item"}\n' > "$root/codex-open.jsonl"
record "$cs_turn" "$pane_turn" codex "$root/codex-open.jsonl" "$root/turn.state"
check 'codex: an open turn with a fresh file is reasoning, not idle' reasoning "$(state_of "$cs_turn")"
touch -d '-10 minutes' "$root/codex-open.jsonl"
check 'codex: the same open turn gone quiet is stalled' stalled "$(state_of "$cs_turn")"
touch "$root/codex-open.jsonl"

printf '{"type":"response_item"}\n{"type":"event_msg","payload":{"type":"task_complete"}}\n' \
    > "$root/codex-done.jsonl"
cs_idle="walk-state-idle-$$"; sessions+=("$cs_idle")
tmux new-session -d -s "$cs_idle" -x 100 -y 30 "cat"; sleep 1
pane_idle="$(tmux list-panes -t "$cs_idle" -F '#{pane_id}' | head -1)"
record "$cs_idle" "$pane_idle" codex "$root/codex-done.jsonl" "$root/idle.state"
check 'codex: a closed turn is idle' idle "$(state_of "$cs_idle")"

printf '%s\n' \
    '{"type":"response_item","payload":{"type":"message","role":"user"}}' \
    '{"type":"event_msg","payload":{"type":"task_complete"}}' \
    '{"type":"response_item","payload":{"type":"message","role":"user"}}' \
    > "$root/codex-reopened.jsonl"
cs_codex_reopen="walk-state-codex-reopen-$$"; sessions+=("$cs_codex_reopen")
tmux new-session -d -s "$cs_codex_reopen" -x 100 -y 30 "cat"; sleep 1
pane_codex_reopen="$(tmux list-panes -t "$cs_codex_reopen" -F '#{pane_id}' | head -1)"
record "$cs_codex_reopen" "$pane_codex_reopen" codex \
    "$root/codex-reopened.jsonl" "$root/codex-reopened.state"
check 'codex: a new user message after task_complete reopens the turn' \
    reasoning "$(state_of "$cs_codex_reopen")"

# --- claude: structural work and turn boundaries ----------------------------------
# The executable name is deliberately useless here. Same-group children model persistent MCP
# and language-server helpers; a different-group child models a tool command. Real Claude
# transcripts use terminal assistant stop reasons rather than the file's final record as the
# turn boundary.
ln -s /bin/bash "$root/claude"

claude_chain() { # label child-mode session-file -> callsign
    local label="$1" child_mode="$2" session="$3"
    local cs="walk-state-claude-$label-$$" runner="$root/claude-$label.sh"
    if [[ "$child_mode" == same-group ]]; then
        child_line='sleep 400 &'
    else
        child_line='setsid sleep 400 &'
    fi
    printf '#!/usr/bin/env bash\nset -o pipefail\ntimeout --foreground --signal=TERM --kill-after=5 300s %q -c %q\nsleep 86400\n' \
        "$root/claude" "$child_line wait" > "$runner"
    sessions+=("$cs")
    tmux new-session -d -s "$cs" -x 100 -y 30 "bash $runner"
    sleep 2
    record "$cs" "$(tmux list-panes -t "$cs" -F '#{pane_id}' | head -1)" \
        claude "$session" "$root/$label.state"
    printf '%s\n' "$cs"
}

printf '%s\n' \
    '{"type":"user","isSidechain":false,"message":{"content":[{"type":"text"}]}}' \
    '{"type":"assistant","isSidechain":false,"message":{"stop_reason":"tool_use","content":[{"type":"tool_use"}]}}' \
    '{"type":"user","isSidechain":false,"message":{"content":[{"type":"tool_result"}]}}' \
    '{"type":"assistant","isSidechain":false,"message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}' \
    '{"type":"system","subtype":"turn_duration"}' \
    '{"type":"last-prompt"}' > "$root/claude-closed.jsonl"
cs_c_idle="$(claude_chain idle same-group "$root/claude-closed.jsonl")"
check 'claude: persistent same-group helpers do not make an idle executor working' \
    idle "$(state_of "$cs_c_idle")"
check 'claude: persistent helper argv is not reported as running work' pass \
    "$(bash "$TARGET" --callsign "$cs_c_idle" 2>/dev/null | grep -q '^running=' && echo fail || echo pass)"

printf '%s\n' \
    '{"type":"user","isSidechain":false,"message":{"content":[{"type":"text"}]}}' \
    '{"type":"assistant","isSidechain":false,"message":{"stop_reason":"tool_use","content":[{"type":"thinking"}]}}' \
    > "$root/claude-open.jsonl"
cs_c_open="$(claude_chain open same-group "$root/claude-open.jsonl")"
check 'claude: a fresh open turn with only helpers is reasoning' reasoning "$(state_of "$cs_c_open")"
touch -d '-10 minutes' "$root/claude-open.jsonl"
check 'claude: the same open turn gone quiet is stalled' stalled "$(state_of "$cs_c_open")"

printf '%s\n' \
    '{"type":"user","isSidechain":false,"message":{"content":[{"type":"text"}]}}' \
    '{"type":"assistant","isSidechain":false,"message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}' \
    '{"type":"last-prompt"}' \
    '{"type":"user","isSidechain":false,"message":{"content":[{"type":"text"}]}}' \
    > "$root/claude-reopened.jsonl"
cs_c_reopen="$(claude_chain reopen same-group "$root/claude-reopened.jsonl")"
check 'claude: a new prompt after a terminal record reopens the turn' \
    reasoning "$(state_of "$cs_c_reopen")"

printf '%s\n' \
    '{"type":"user","isSidechain":false,"message":{"content":[{"type":"text"}]}}' \
    '{"type":"assistant","isSidechain":false,"message":{"stop_reason":"stop_sequence","content":[{"type":"text"}]}}' \
    '{"type":"last-prompt"}' > "$root/claude-interrupted.jsonl"
cs_c_interrupt="$(claude_chain interrupt same-group "$root/claude-interrupted.jsonl")"
check 'claude: a stop-sequence terminal record closes an interrupted turn' \
    idle "$(state_of "$cs_c_interrupt")"

cs_c_work="$(claude_chain work different-group "$root/claude-closed.jsonl")"
check 'claude: a different-group direct child is working' working "$(state_of "$cs_c_work")"
check 'claude: the different-group child argv is reported' pass \
    "$(bash "$TARGET" --callsign "$cs_c_work" 2>/dev/null | grep -q 'running=.*sleep 400' && echo pass || echo fail)"


# --- stopped, and the identity rule that has to hold for it to mean anything -------
# A STOPPED PROCESS IS NOT AN IDLE ONE. A background runtime can take SIGTTIN on
# its first terminal read and remain in state T.
#
# The chains below are built the way the launcher builds them: the pane runs `bash <runner>`,
# the runner wraps a terminal-reading program in the wall. That shape is what makes the runtime
# the wall's child, which is how it is identified — by POSITION. It cannot be identified by
# name: an executor's tree can contain helper processes named after other tools.
chain() { # name wall-flag command -> callsign
    local cs="walk-state-$1-$$" runner="$root/$1.sh"
    printf '#!/usr/bin/env bash\nset -o pipefail\ntimeout %s--signal=TERM --kill-after=5 300s %s\nsleep 86400\n' \
        "$2" "$3" > "$runner"
    sessions+=("$cs")
    tmux new-session -d -s "$cs" -x 100 -y 30 "bash $runner"
    sleep 2
    printf '%s\n' "$cs"
}

cs_stop="$(chain stopped '' cat)"
record "$cs_stop" "$(tmux list-panes -t "$cs_stop" -F '#{pane_id}' | head -1)" cat "$root/s.jsonl" "$root/s.state"
check 'a STOPPED runtime is reported stopped, not idle' stopped "$(state_of "$cs_stop")"
check 'the answer says it will not resume on its own and points at the wall wrapper' pass \
    "$(bash "$TARGET" --callsign "$cs_stop" 2>/dev/null | grep -qi 'foreground' && echo pass || echo fail)" \
    "detail was: $(bash "$TARGET" --callsign "$cs_stop" 2>/dev/null | sed -n 's/^detail=//p')"

cs_run="$(chain running '--foreground ' cat)"
record "$cs_run" "$(tmux list-panes -t "$cs_run" -F '#{pane_id}' | head -1)" cat "$root/r.jsonl" "$root/r.state"
check 'CONTROL: the same chain running is never reported stopped' pass \
    "$([[ "$(state_of "$cs_run")" != stopped ]] && echo pass || echo fail)" \
    "state was $(state_of "$cs_run")"

# A tool the agent started can be stopped while the turn carries on. That is not the executor
# being stopped, and reporting it as such would take a working agent off the board.
cs_child="$(chain childstop '--foreground ' 'bash -c "sleep 400 & kill -STOP \$!; sleep 500"')"
record "$cs_child" "$(tmux list-panes -t "$cs_child" -F '#{pane_id}' | head -1)" bash "$root/cc.jsonl" "$root/cc.state"
check 'CONTROL: a stopped NON-runtime child does not make the executor stopped' pass \
    "$([[ "$(state_of "$cs_child")" != stopped ]] && echo pass || echo fail)" \
    "state was $(state_of "$cs_child")"

# The record names a runtime; the process at the runtime position is something else. That is a
# stale or wrong record, and guessing which of the two to believe is how a healthy executor gets
# reported dead. It is reported as the disagreement it is.
cs_mis="$(chain mismatch '--foreground ' cat)"
record "$cs_mis" "$(tmux list-panes -t "$cs_mis" -F '#{pane_id}' | head -1)" codex "$root/m.jsonl" "$root/m.state"
check 'a record whose runtime is not the process at that position is runtime-mismatch' \
    runtime-mismatch "$(state_of "$cs_mis")"

# ...but a stopped process outranks the record. A stopped process under a wrong record is still a
# stopped executor, and burying that in detail text nobody must act on is how it stays hidden.
cs_mis_stop="$(chain mismatchstopped '' cat)"
record "$cs_mis_stop" "$(tmux list-panes -t "$cs_mis_stop" -F '#{pane_id}' | head -1)" codex "$root/ms.jsonl" "$root/ms.state"
check 'a STOPPED process under a wrong record is still reported stopped' stopped "$(state_of "$cs_mis_stop")"
check 'and the record disagreement rides along in the detail' pass \
    "$(bash "$TARGET" --callsign "$cs_mis_stop" 2>/dev/null | grep -qi 'record' && echo pass || echo fail)" \
    "detail was: $(bash "$TARGET" --callsign "$cs_mis_stop" 2>/dev/null | sed -n 's/^detail=//p')"

# No wall wrapper: fall back to matching the recorded name inside THIS pane's tree. Two matches
# is not a coin toss.
cs_amb="walk-state-ambiguous-$$"; sessions+=("$cs_amb")
printf '#!/usr/bin/env bash\nset -o pipefail\ntail -f /dev/null & tail -f /dev/null & sleep 86400\n' > "$root/amb.sh"
tmux new-session -d -s "$cs_amb" -x 100 -y 30 "bash $root/amb.sh"; sleep 2
record "$cs_amb" "$(tmux list-panes -t "$cs_amb" -F '#{pane_id}' | head -1)" tail "$root/a.jsonl" "$root/a.state"
check 'two candidates with the recorded name is ambiguous-runtime, never a guess' \
    ambiguous-runtime "$(state_of "$cs_amb")"

# The pane tree is the only place looked at, so a same-named process elsewhere on this machine —
# including a recycled pid — cannot reach the answer. This row runs one deliberately.
sleep 900 &
foreign=$!
cs_foreign="$(chain foreign '--foreground ' cat)"
record "$cs_foreign" "$(tmux list-panes -t "$cs_foreign" -F '#{pane_id}' | head -1)" sleep "$root/f.jsonl" "$root/f.state"
check 'CONTROL: a same-named process outside the pane tree is unreachable' pass \
    "$([[ "$(state_of "$cs_foreign")" != stopped ]] && echo pass || echo fail)" \
    "a `sleep` is running outside the pane and the recorded runtime is `sleep`; state was $(state_of "$cs_foreign")"
kill "$foreign" 2>/dev/null || true

# --- dead vs unknown: the distinction that keeps being lost ------------------------
cs_dead="walk-state-dead-$$"
tmux new-session -d -s "$cs_dead" -x 100 -y 30 "cat"; sleep 1
pane_dead="$(tmux list-panes -t "$cs_dead" -F '#{pane_id}' | head -1)"
printf 'spawn-id=s1\nstate=done\n' > "$root/dead.state"
record "$cs_dead" "$pane_dead" codex "$root/dead.jsonl" "$root/dead.state"
tmux kill-session -t "$cs_dead"
check 'a gone window WITH a terminal state file is dead' dead "$(state_of "$cs_dead")"

cs_old_state="walk-state-old-state-$$"
tmux new-session -d -s "$cs_old_state" -x 100 -y 30 "cat"; sleep 1
pane_old_state="$(tmux list-panes -t "$cs_old_state" -F '#{pane_id}' | head -1)"
printf 'spawn-id=old-generation\nstate=done\n' > "$root/old-generation.state"
record "$cs_old_state" "$pane_old_state" codex "$root/old-generation.jsonl" \
    "$root/old-generation.state" new-generation
tmux kill-session -t "$cs_old_state"
check 'a gone current generation cannot borrow an old terminal-state artifact' \
    unknown "$(state_of "$cs_old_state")"

cs_unk="walk-state-unknown-$$"
tmux new-session -d -s "$cs_unk" -x 100 -y 30 "cat"; sleep 1
pane_unk="$(tmux list-panes -t "$cs_unk" -F '#{pane_id}' | head -1)"
record "$cs_unk" "$pane_unk" codex "$root/unk.jsonl" "$root/never-written.state"
tmux kill-session -t "$cs_unk"
check 'a gone window with NOTHING beside it is unknown, never a finish' unknown "$(state_of "$cs_unk")"

# --- record-stale ------------------------------------------------------------------
cs_stale="walk-state-stale-$$"; sessions+=("$cs_stale")
tmux new-session -d -s "$cs_stale" -x 100 -y 30 "cat"; sleep 1
record "$cs_stale" '%999999' codex "$root/stale.jsonl" "$root/stale.state"
check 'a record naming a pane that no longer exists is record-stale' record-stale "$(state_of "$cs_stale")"

# --- the instrument must never find ITSELF -----------------------------------------
# This asserts that the liveness instrument does not match its own process.
check 'the instrument does not report its own process as the executor work' pass \
    "$(bash "$TARGET" --callsign "$cs_work" 2>/dev/null | grep -q 'running=.*exec-state' && echo fail || echo pass)"

# --- the degenerate shape: the pane's OWN process is the command -------------------
# `tmux new-session -d -s x "sleep 1800"` answers `idle`, not `working`.
#
# The launcher never produces this shape — its pane runs a bash runner with the runtime as a
# child, which is why the production path answers `working` with the real command. Where the
# pane process IS the agent, the child instrument has nothing to look at by construction, and
# the right answer comes from the turn state instead: an agent with an open turn is reasoning,
# one with no turn open is idle. Treating any non-shell pane process as work was tried and
# reverted: it makes every agent look busy the instant it starts, which is the same
# alive-therefore-fine answer this instrument was built to replace.
cs_own="walk-state-own-$$"; sessions+=("$cs_own")
tmux new-session -d -s "$cs_own" -x 100 -y 30 "sleep 900"
sleep 1
pane_own="$(tmux list-panes -t "$cs_own" -F '#{pane_id}' | head -1)"
record "$cs_own" "$pane_own" codex "$root/own.jsonl" "$root/own.state"
check 'a pane with no child and no session file is idle, and that is deliberate' idle \
    "$(state_of "$cs_own")"

# --- THE SHAPE THE LAUNCHER ACTUALLY PRODUCES -------------------------------------------
# The fixture above differs from the launcher's actual pane shape:
#   pane = the runner script -> dedicated systemd scope -> the runtime -> the agent's commands
# so the pane ALWAYS has a child, the instrument returned `working` immediately every time,
# and `reasoning`, `stalled` and `idle` were unreachable for every real executor. A hung
# agent looked healthy indefinitely, which is the single thing this instrument exists to stop.
runtime_stub="$root/codex"
cp /bin/sleep "$runtime_stub"
cs_real="walk-state-real-$$"; sessions+=("$cs_real")
real_unit="walk-state-real-$$.scope"; units+=("$real_unit")
real_runner="$root/real-runner.sh"
printf '#!/usr/bin/env bash\nset -o pipefail\nsystemd-run --user --scope --quiet --unit=%q env SNO_EXEC_SPAWN_ID=%q %q 3000\nsleep 86400\n' \
    "$real_unit" "walk-state-real-$$" "$runtime_stub" >"$real_runner"
chmod +x "$real_runner"
tmux new-session -d -s "$cs_real" -x 100 -y 30 "bash $real_runner"
sleep 1
pane_real="$(tmux list-panes -t "$cs_real" -F '#{pane_id}' | head -1)"
printf '{"type":"response_item"}\n{"type":"event_msg","payload":{"type":"task_complete"}}\n' \
    > "$root/real-closed.jsonl"
record "$cs_real" "$pane_real" codex "$root/real-closed.jsonl" "$root/real.state"
check 'the current systemd-scope runner shape with a closed turn is idle, not working' \
    idle "$(state_of "$cs_real")"

printf '{"type":"session_meta"}\n{"type":"response_item"}\n' > "$root/real-open.jsonl"
: > "$AGENT_SPAWNS"
record "$cs_real" "$pane_real" codex "$root/real-open.jsonl" "$root/real.state"
check 'the same shape with an OPEN turn is reasoning — the turn signal is reachable at last' \
    reasoning "$(state_of "$cs_real")"
touch -d '-10 minutes' "$root/real-open.jsonl"
check 'and when that open turn stops moving it is stalled, which was unreachable before' \
    stalled "$(state_of "$cs_real")"

# The runner parks on this exact command once the runtime returns, so the pane still has a
# child. Counting it made a finished executor look busy forever.
cs_park="walk-state-park-$$"; sessions+=("$cs_park")
tmux new-session -d -s "$cs_park" -x 100 -y 30 "bash -c 'sleep 86400'"
sleep 1
pane_park="$(tmux list-panes -t "$cs_park" -F '#{pane_id}' | head -1)"
record "$cs_park" "$pane_park" codex "$root/real-closed.jsonl" "$root/park.state"
check 'the runner parked after the runtime returned is not work' idle "$(state_of "$cs_park")"

# --- the session store is FOUND, not required to be handed over -------------------------
# The spawn record cannot name this file: it does not exist until the runtime has started and
# chosen its own name. Nothing ever filled that field, so the turn instrument never ran.
home="$root/home"
co="$root/checkout"; mkdir -p "$co"
slug="$(printf '%s' "$co" | tr '/.' '--')"
mkdir -p "$home/.claude/projects/$slug" "$home/.codex/sessions/2000/01/01"
printf '{"type":"user"}\n' > "$home/.claude/projects/$slug/aaaa.jsonl"
printf '{"type":"session_meta","cwd":"%s"}\n{"type":"response_item"}\n' "$co" \
    > "$home/.codex/sessions/2000/01/01/rollout-2000-01-01T12-00-00-mine.jsonl"
printf '{"type":"session_meta","cwd":"/somewhere/else"}\n' \
    > "$home/.codex/sessions/2000/01/01/rollout-2000-01-01T13-00-00-theirs.jsonl"
for rt in codex; do
    cs_d="walk-state-disc-$rt-$$"; sessions+=("$cs_d")
    tmux new-session -d -s "$cs_d" -x 80 -y 24 "cat"; sleep 1
    pane_d="$(tmux list-panes -t "$cs_d" -F '#{pane_id}' | head -1)"
    printf '{"ts":"2000-01-01T00:00:00+00:00","pid":1,"callsign":"%s","pane":"%s","runtime":"%s","repo":"%s","state_file":"%s"}\n' \
        "$cs_d" "$pane_d" "$rt" "$co" "$root/d.state" >> "$AGENT_SPAWNS"
    check "$rt: with NO session file in the record, the open turn is still found" reasoning \
        "$(HOME="$home" bash "$TARGET" --callsign "$cs_d" 2>/dev/null | sed -n 's/^state=//p')"
done
# The newest codex session belongs to another checkout; picking by time alone reads another
# lane's turn state and reports it as this executor's.
check 'codex: a newer session from a DIFFERENT checkout is not mistaken for this one' pass \
    "$(HOME="$home" bash "$TARGET" --callsign "walk-state-disc-codex-$$" --json 2>/dev/null |
       jq -e '.turn == "open"' >/dev/null 2>&1 && echo pass || echo fail)"

printf '1..%d\n' "$n"
((fail == 0)) || { printf '# %d of %d failed\n' "$fail" "$n" >&2; exit 1; }
