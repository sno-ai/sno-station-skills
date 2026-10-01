#!/usr/bin/env bash
# spawn-exec-interactive-e2e.sh — the launcher starts an interactive agent, refuses a
# spawn it could not reach, and proves completion by an artifact rather than an exit code.
#
# LIVE TEST: it starts real codex and claude sessions (spending real agent quota) and
# kills leftover processes whose command line carries this run's id (pkill -f). It
# therefore skips (exit 0) unless SNO_PL_E2E_LIVE=1 is set.
#
# What this pins down, and why each row exists:
#
#   1. `codex exec` appears nowhere in the launcher (it starts the interactive program).
#   2. The runtime's stdout is never piped: a pipe destroys the terminal an interactive
#      program needs. The transcript is tapped with `tmux pipe-pane` instead.
#   3. A spawn with no address, or a malformed one, is refused before the runtime starts
#      and before any resource is claimed: an executor nobody can address cannot be woken.
#   4. An unsupported `--runtime` is refused the same way.
#   5. The generated runner registers the seat before the runtime starts, and a failed
#      registration refuses instead of leaving an unreachable agent running.
#   6. The runner places the runtime in a dedicated foreground systemd scope; the wall
#      controller is external, so it can verify the cgroup-wide kill it initiated.
#   7. The runner writes a terminal-state file stamped with the spawn id.
#   8. The runtime really runs in that scope (foreground process group) and answers a
#      real prompt.
#
# Rows 1-4 run the real CLI. Rows 5-7 read the runner the launcher generates, which is the
# artifact that actually runs; they do not restate it from memory.
set -Eeuo pipefail

if [[ "${SNO_PL_E2E_LIVE:-}" != 1 ]]; then
    printf 'SKIP: spawn-exec-interactive-e2e.sh starts real codex/claude sessions (uses agent quota) and runs pkill -f; set SNO_PL_E2E_LIVE=1 to run it\n'
    exit 0
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/spawn-exec.sh"
[ -f "$TARGET" ] || { echo "FAIL: spawn-exec.sh not found beside this test" >&2; exit 2; }

root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT

n=0
fail=0
check() { # label result [detail]
    n=$((n + 1))
    if [[ "$2" == pass ]]; then printf 'ok %d - %s\n' "$n" "$1"
    else printf 'not ok %d - %s\n' "$n" "$1"; [[ -z "${3:-}" ]] || printf '#   %s\n' "$3"
        fail=$((fail + 1)); fi
}

printf 'TAP version 13\n'

# --- rows 1-2: the mode and the pipe ---------------------------------------------
check 'the launcher no longer runs codex exec anywhere' \
    "$([[ "$(grep -c 'codex exec' "$TARGET")" -eq 0 ]] && echo pass || echo fail)" \
    "occurrences: $(grep -c 'codex exec' "$TARGET")"

# The runtime invocation must not be followed by a pipe. Look at the generated-runner
# lines that name the runtime and assert none of them pipes into tee.
check 'the runtime is never piped, so the interactive terminal survives' \
    "$(grep -nE "printf '  (codex|claude)" "$TARGET" | grep -q 'tee' && echo fail || echo pass)" \
    "$(grep -nE "printf '  (codex|claude)" "$TARGET" | head -3)"

check 'the transcript is tapped with tmux pipe-pane instead' \
    "$(grep -q 'tmux pipe-pane' "$TARGET" && echo pass || echo fail)"

# --- rows 3-4: the gate refuses what it cannot reach ------------------------------
printf 'do nothing\n' > "$root/dispatch.md"
gate() { # extra args -> "rc|stderr-first-line"
    local out rc
    set +e
    out="$(bash "$TARGET" --journey j-e2e-interactive --repo "$root" --budget-h 1 \
        --dispatch "$root/dispatch.md" --class closure "$@" 2>&1)"
    rc=$?
    set -e
    printf '%s|%s\n' "$rc" "$(head -1 <<<"$out")"
}

no_addr="$(gate)"
check 'a spawn with no address is refused' \
    "$([[ "${no_addr%%|*}" == 2 ]] && echo pass || echo fail)" "$no_addr"
check 'the refusal says why an unaddressable executor is refused' \
    "$([[ "$no_addr" == *"cannot be woken"* ]] && echo pass || echo fail)" "$no_addr"

bad_addr="$(gate --addr 'not-an-address')"
check 'a malformed address is refused' \
    "$([[ "${bad_addr%%|*}" == 2 ]] && echo pass || echo fail)" "$bad_addr"

bad_runtime="$(gate --addr executor.e2e@host1 --runtime perl)"
check 'an unsupported runtime is refused' \
    "$([[ "${bad_runtime%%|*}" == 2 ]] && echo pass || echo fail)" "$bad_runtime"

# --- rows 5-7: what the generated runner actually does ----------------------------
# The runner is built by a here-doc block in the launcher. Read that block rather than a
# restatement of it: the block is what runs.
runner_block="$(sed -n '/^state_file=/,/^} > "\$runner"/p' "$TARGET")"

check 'the runner registers the seat before starting the runtime' \
    "$(awk '/register --as/{r=NR} /systemd-run --user --scope/{s=NR} END{exit !(r && s && r < s)}' <<<"$runner_block" && echo pass || echo fail)" \
    'registration must precede the dedicated runtime scope'

check 'a failed registration refuses instead of running unreachable' \
    "$(grep -q 'REFUSING' <<<"$runner_block" && grep -q 'write_startup_receipt refused' <<<"$runner_block" && echo pass || echo fail)"

check 'the runner places the runtime in a dedicated user scope without an in-pane timer' \
    "$(awk '/systemd-run --user --scope/{s=NR} /(codex|claude) --dangerously/{c=NR} END{exit !(s && c && s < c)}' <<<"$runner_block" &&
       ! grep -q 'timeout --foreground' <<<"$runner_block" && echo pass || echo fail)" \
    'systemd-run --scope must immediately precede the runtime and timeout must be absent'

check 'the runner writes a terminal-state file carrying the spawn id' \
    "$(grep -q 'spawn-id=' <<<"$runner_block" && grep -q 'state_file' <<<"$runner_block" && echo pass || echo fail)"

check 'the runner says an exit code is not the completion signal' \
    "$(grep -q 'NOT the completion signal' <<<"$runner_block" && echo pass || echo fail)"

# --- row 8: the runtime must actually run ----------------------------------------
# Every row below builds its chain from lines read out of the launcher; a row that hardcodes
# the wall line would keep passing while the launcher changed. A wall wrapper can put the
# runtime in a background process group, where it is stopped on its first read of the
# terminal (state T) while the pane's command still looks alive.
#
# Ownership: everything started here carries RUN_ID in its argv or its script path, so the
# reaper can find it without touching anyone else's sessions.
RUN_ID="sxe2e-$$-$(date +%s)"
started_sessions=()
started_units=()
session_manifest="$root/$RUN_ID.sessions"
unit_manifest="$root/$RUN_ID.units"
: >"$session_manifest"
: >"$unit_manifest"
reap() {
    local s unit
    for s in "${started_sessions[@]:-}"; do
        [[ -z "$s" ]] || tmux kill-session -t "$s" 2>/dev/null || true
    done
    for unit in "${started_units[@]:-}"; do
        [[ -z "$unit" ]] || systemctl --user kill --kill-whom=all --signal=KILL "$unit" 2>/dev/null || true
        [[ -z "$unit" ]] || systemctl --user stop "$unit" 2>/dev/null || true
    done
    while IFS= read -r s; do
        [[ -z "$s" ]] || tmux kill-session -t "$s" 2>/dev/null || true
    done <"$session_manifest"
    while IFS= read -r unit; do
        [[ -z "$unit" ]] || systemctl --user kill --kill-whom=all --signal=KILL "$unit" 2>/dev/null || true
        [[ -z "$unit" ]] || systemctl --user stop "$unit" 2>/dev/null || true
    done <"$unit_manifest"
    pkill -f -- "$RUN_ID" 2>/dev/null || true
}
trap 'reap; rm -rf -- "$root"' EXIT

# The scope command's own words, minus the generated unit value.
scope_head="$(sed -n "s/^  printf '\(systemd-run --user --scope --quiet\) --unit=.*/\1/p" "$TARGET" | head -1)"
runtime_invocation() { # codex|claude -> the launcher's own invocation for that runtime
    sed -n "s/^[[:space:]]*$1)[[:space:]]*printf '  \($1 [^%]*\)%s.*/\1/p" "$TARGET" | head -1
}

# A chain shaped exactly like the launcher. `cat` stands in for the runtime because reading the
# terminal is the property that distinguishes a foreground scope from a background one.
chain_stat() { # control|scope arm-name command -> the STAT of the runtime
    local mode="$1" arm="$2" cmd="$3"
    local sess="${RUN_ID}-${arm}" unit="${RUN_ID}-${arm}.scope"
    local wrap="$root/${RUN_ID}-${arm}.sh" pane_pid parent_pid rt_pid
    if [[ "$mode" == control ]]; then
        printf '#!/usr/bin/env bash\nset -o pipefail\ntimeout --signal=TERM --kill-after=5 300s %s\nsleep 86400\n' \
            "$cmd" > "$wrap"
    else
        printf '#!/usr/bin/env bash\nset -o pipefail\n%s --unit=%q %s\nsleep 86400\n' \
            "$scope_head" "$unit" "$cmd" > "$wrap"
        started_units+=("$unit")
        printf '%s\n' "$unit" >>"$unit_manifest"
    fi
    started_sessions+=("$sess")
    printf '%s\n' "$sess" >>"$session_manifest"
    tmux new-session -d -s "$sess" -x 120 -y 40 "bash $wrap" 2>/dev/null || { printf 'no-session\n'; return 0; }
    sleep 3
    pane_pid="$(tmux list-panes -t "$sess" -F '#{pane_pid}' 2>/dev/null | head -1)"
    parent_pid="$(pgrep -P "${pane_pid:-0}" 2>/dev/null | head -1)"
    if [[ "$mode" == control ]]; then
        rt_pid="$(pgrep -P "${parent_pid:-0}" 2>/dev/null | head -1)"
    else
        rt_pid="$parent_pid"
    fi
    [[ -n "$rt_pid" ]] || { printf 'no-runtime\n'; return 0; }
    ps -o stat= -p "$rt_pid" 2>/dev/null | tr -d ' '
}

bare_stat="$(chain_stat control bare cat)"
check 'CONTROL: a wall without --foreground leaves a terminal-reading runtime STOPPED' \
    "$([[ "$bare_stat" == T* ]] && echo pass || echo fail)" \
    "control arm STAT was '$bare_stat'; T is a state that ordinary liveness checks do not notice"

live_stat="$(chain_stat scope live cat)"
check "the launcher's OWN scope line runs the runtime in the pane's foreground group" \
    "$([[ "$live_stat" == S*+* ]] && echo pass || echo fail)" \
    "the launcher's scope head is '$scope_head' and the runtime STAT was '$live_stat'; wanted a sleeping process carrying the foreground marker +"

# The stand-in reports a bare `T`; a real runtime reports `Tl`. A check that compares the
# whole status field to `T` would pass every fixture here and catch neither supported
# runtime, so compare the first character.
real_stopped="$(chain_stat control realstop "$(runtime_invocation codex)")"
check 'CONTROL: a stopped REAL runtime does not report the stand-in status' \
    "$([[ "${real_stopped:0:1}" == T && "$real_stopped" != T ]] && echo pass || echo fail)" \
    "real runtime STAT was '$real_stopped' against the stand-in's '$bare_stat' — compare the FIRST CHARACTER, never the field"

# A real turn, through the launcher's own scope line and its own runtime invocation. The
# expected answer is a TRANSFORMATION of the challenge, so it appears nowhere in the prompt and
# the terminal's echo of that prompt cannot satisfy the row.
CHALLENGE='Reply with ONLY the reverse of this string, nothing else: q7M2z9K4'
ANSWER='4K9z2M7q'
real_turn() { # codex|claude -> done|<diagnosis>
    local rt="$1" invocation sess unit wrap i
    invocation="$(runtime_invocation "$rt")"
    [[ -n "$invocation" ]] || { printf 'no-invocation-in-launcher\n'; return 0; }
    command -v "$rt" >/dev/null || { printf 'binary-absent\n'; return 0; }
    sess="${RUN_ID}-turn-${rt}"; unit="${RUN_ID}-turn-${rt}.scope"
    wrap="$root/${RUN_ID}-turn-${rt}.sh"
    printf '#!/usr/bin/env bash\nset -o pipefail\n%s --unit=%q %s\nsleep 86400\n' \
        "$scope_head" "$unit" "$invocation" > "$wrap"
    started_sessions+=("$sess")
    started_units+=("$unit")
    printf '%s\n' "$sess" >>"$session_manifest"
    printf '%s\n' "$unit" >>"$unit_manifest"
    tmux new-session -d -s "$sess" -x 120 -y 40 -c "$root" "bash $wrap" 2>/dev/null || { printf 'no-session\n'; return 0; }
    sleep 18
    tmux send-keys -t "$sess" "$CHALLENGE" 2>/dev/null || { printf 'send-failed\n'; return 0; }
    sleep 0.3
    tmux send-keys -t "$sess" Enter 2>/dev/null || { printf 'send-failed\n'; return 0; }
    for i in $(seq 1 40); do
        sleep 1.5
        if ((i % 10 == 0)); then
            printf '# real %s turn: %d/40 polls complete\n' "$rt" "$i" >&2
        fi
        if tmux capture-pane -p -t "$sess" -S -200 2>/dev/null | grep -qF "$ANSWER"; then
            printf 'done\n'; return 0
        fi
    done
    printf 'no-answer-within-60s\n'
}

for rt in codex claude; do
    turn="$(real_turn "$rt")"
    check "a real $rt executor completes a turn through the generated-runner shape" \
        "$([[ "$turn" == "done" ]] && echo pass || echo fail)" \
        "outcome '$turn'; a missing binary is a wrong environment and fails here rather than skipping"
done

# Ownership check: this suite must leave nothing behind. Anything still carrying RUN_ID after
# the reaper has run is a leak.
reap
sleep 1
leaked="$(pgrep -fa -- "$RUN_ID" 2>/dev/null || true)"
leaked="$(grep -c . <<<"${leaked:-}" || true)"
[[ -n "$(pgrep -f -- "$RUN_ID" 2>/dev/null || true)" ]] || leaked=0
leaked_sessions="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -c -- "$RUN_ID" || true)"
leaked_units=0
while IFS= read -r unit; do
    if [[ -n "$unit" ]] && systemctl --user is-active --quiet "$unit"; then
        leaked_units=$((leaked_units + 1))
    fi
done <"$unit_manifest"
check 'the suite leaves no session, scope, or process of its own behind' \
    "$([[ "$leaked" -eq 0 && "$leaked_sessions" -eq 0 && "$leaked_units" -eq 0 ]] && echo pass || echo fail)" \
    "processes still carrying this run's marker: $leaked; sessions: $leaked_sessions; scopes: $leaked_units"


printf '1..%d\n' "$n"
((fail == 0)) || { printf '# %d of %d failed\n' "$fail" "$n" >&2; exit 1; }
