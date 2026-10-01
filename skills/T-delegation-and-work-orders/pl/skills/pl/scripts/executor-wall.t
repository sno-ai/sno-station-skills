#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
wall="$script_dir/executor-wall.sh"
launcher="$script_dir/spawn-exec.sh"

printf 'TAP version 13\n'

case_number=0
fail=0
check() {
    local description="$1" result="$2" detail="${3:-}"
    case_number=$((case_number + 1))
    if [[ "$result" == pass ]]; then
        printf 'ok %d - %s\n' "$case_number" "$description"
    else
        printf 'not ok %d - %s\n' "$case_number" "$description"
        [[ -z "$detail" ]] || printf '# %s\n' "$detail"
        fail=1
    fi
}

check 'the external wall controller exists' \
    "$([[ -x "$wall" ]] && echo pass || echo fail)" \
    "$wall is missing or not executable"

if [[ ! -x "$wall" ]]; then
    printf '1..%d\n' "$case_number"
    exit "$fail"
fi

# This matches the generated source text, not a test variable.
# shellcheck disable=SC2016
runner_end='^} > "$runner"'
check 'the pane runner carries no timeout wall' \
    "$(! sed -n "/^state_file=/,/$runner_end/p" "$launcher" | grep -q 'timeout --foreground' && echo pass || echo fail)"
check 'the launcher uses a dedicated runtime scope' \
    "$(grep -q 'systemd-run --user --scope' "$launcher" && echo pass || echo fail)"
check 'the launcher arms an external wall service' \
    "$(grep -q 'executor-wall.sh' "$launcher" && grep -q 'wall_unit' "$launcher" && echo pass || echo fail)"
check 'the launcher injects the ownership marker at the runtime scope, not the tmux pane' \
    "$(! grep -q 'tmux new-session.*SNO_EXEC_SPAWN_ID\|^[[:space:]]*-e "SNO_EXEC_SPAWN_ID' "$launcher" &&
       ! grep -q 'SNO_EXEC_SPAWN_ID=.*systemd-run --user --scope' "$launcher" &&
       grep -q 'systemd-run --user --scope.*env SNO_EXEC_SPAWN_ID=' "$launcher" && echo pass || echo fail)"

root="$(mktemp -d)"
run_id="sno-wall-test-$$"
session="$run_id"
main_unit="$run_id-main.scope"
nested_unit="$run_id-nested.scope"
cleared_unit="$run_id-cleared.scope"
unsafe_unit="$run_id-unsafe.scope"
cleanup_main_unit="$run_id-cleanup-main.scope"
cleanup_nested_unit="$run_id-cleanup-nested.scope"
marker="$run_id-marker"
cleanup_marker="$run_id-cleanup-marker"
cleared_launcher_pid=''
events="$root/events.jsonl"
unsafe_events="$root/unsafe-events.jsonl"
body="$root/runtime-body.sh"
cleanup_body="$root/cleanup-body.sh"

# Invoked through trap.
# shellcheck disable=SC2317
cleanup() {
    if tmux has-session -t "$session" 2>/dev/null; then
        tmux kill-session -t "$session" || true
    fi
    systemctl --user kill --kill-whom=all --signal=KILL \
        "$main_unit" "$nested_unit" "$cleared_unit" "$unsafe_unit" \
        "$cleanup_main_unit" "$cleanup_nested_unit" >/dev/null 2>&1 || true
    systemctl --user stop "$main_unit" "$nested_unit" "$cleared_unit" "$unsafe_unit" \
        "$cleanup_main_unit" "$cleanup_nested_unit" >/dev/null 2>&1 || true
    systemctl --user reset-failed \
        "$main_unit" "$nested_unit" "$cleared_unit" "$unsafe_unit" \
        "$cleanup_main_unit" "$cleanup_nested_unit" >/dev/null 2>&1 || true
    [[ -z "$cleared_launcher_pid" ]] || wait "$cleared_launcher_pid" 2>/dev/null || true
    rm -r -- "$root"
}
trap cleanup EXIT INT TERM

cat >"$body" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
nested_unit="$1"
trap '' TERM
setsid bash -c 'trap "" TERM; exec sleep 30' &
systemd-run --user --scope --quiet --unit="$nested_unit" \
    bash -c 'trap "" TERM; exec sleep 30' &
wait
EOF
chmod +x "$body"

env -u SNO_EXEC_SPAWN_ID systemd-run --user --scope --quiet --unit="$cleared_unit" \
    bash -c 'trap "" TERM; exec sleep 30' &
cleared_launcher_pid=$!
tmux new-session -d -s "$session" \
    "systemd-run --user --scope --quiet --unit=$main_unit env SNO_EXEC_SPAWN_ID=$marker bash $body $nested_unit"

for _ in {1..50}; do
    if systemctl --user is-active --quiet "$main_unit" &&
       systemctl --user is-active --quiet "$nested_unit" &&
       systemctl --user is-active --quiet "$cleared_unit"; then
        break
    fi
    sleep 0.1
done

check 'the dedicated runtime, inherited nested scope, and unrelated scope started' \
    "$(systemctl --user is-active --quiet "$main_unit" &&
       systemctl --user is-active --quiet "$nested_unit" &&
       systemctl --user is-active --quiet "$cleared_unit" && echo pass || echo fail)"

main_group="$(systemctl --user show "$main_unit" -p ControlGroup --value)"
main_pids="$(<"/sys/fs/cgroup$main_group/cgroup.procs")"
detached=fail
while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    pid_sid="$(ps -o sid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    pid_ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    [[ "$pid_sid" == "$pid" && "$pid_ppid" != 1 ]] && detached=pass
done <<<"$main_pids"
check 'a setsid descendant remains in the dedicated runtime scope' "$detached"

set +e
bash "$wall" --spawn-id "$marker" --term-after 1 --kill-after 2 --events "$events"
wall_rc=$?
set -e
check 'the external controller survives and completes' \
    "$([[ "$wall_rc" -eq 0 ]] && echo pass || echo fail)" "controller rc=$wall_rc"

event_names="$(jq -rs 'map(.event) | join(",")' "$events" 2>/dev/null || true)"
check 'expiry intent is durable before kill confirmation' \
    "$([[ "$event_names" == expiry-intent,kill-confirmed ]] && echo pass || echo fail)" \
    "events were '$event_names'"
check 'the intent and confirmation carry the exact spawn id' \
    "$(jq -e --arg sid "$marker" 'select(.spawn_id == $sid)' "$events" >/dev/null 2>&1 &&
       [[ "$(jq -r --arg sid "$marker" 'select(.spawn_id == $sid) | .spawn_id' "$events" | wc -l)" -eq 2 ]] && echo pass || echo fail)"

owned_active=0
systemctl --user is-active --quiet "$main_unit" && owned_active=1
systemctl --user is-active --quiet "$nested_unit" && owned_active=1
check 'cgroup-wide enforcement empties the runtime and marked nested scopes' \
    "$([[ "$owned_active" -eq 0 ]] && echo pass || echo fail)"
cleared_group="$(systemctl --user show "$cleared_unit" -p ControlGroup --value 2>/dev/null || true)"
check 'an unrelated unmarked scope is neither claimed nor killed' \
    "$(! jq -e --arg group "$cleared_group" '.scopes[] == $group' "$events" >/dev/null 2>&1 &&
       systemctl --user is-active --quiet "$cleared_unit" && echo pass || echo fail)"
check 'kill confirmation contains no termination-failed event' \
    "$(! jq -e 'select(.event == "termination-failed")' "$events" >/dev/null 2>&1 && echo pass || echo fail)"

cat >"$cleanup_body" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
nested_unit="$1"
trap '' TERM
systemd-run --user --scope --quiet --unit="$nested_unit" \
    bash -c 'trap "" TERM; exec sleep 30' &
wait
EOF
chmod +x "$cleanup_body"

for _ in {1..50}; do
    ! tmux has-session -t "$session" 2>/dev/null && break
    sleep 0.1
done
tmux new-session -d -s "$session" \
    "systemd-run --user --scope --quiet --unit=$cleanup_main_unit env SNO_EXEC_SPAWN_ID=$cleanup_marker bash $cleanup_body $cleanup_nested_unit"
for _ in {1..50}; do
    if systemctl --user is-active --quiet "$cleanup_main_unit" &&
       systemctl --user is-active --quiet "$cleanup_nested_unit"; then
        break
    fi
    sleep 0.1
done
check 'the startup-cleanup fixture owns an outer and inherited nested scope' \
    "$(systemctl --user is-active --quiet "$cleanup_main_unit" &&
       systemctl --user is-active --quiet "$cleanup_nested_unit" && echo pass || echo fail)"

set +e
bash "$wall" --spawn-id "$cleanup_marker" --cleanup-now
cleanup_rc=$?
set -e
check 'startup cleanup proves both marked scopes empty' \
    "$([[ "$cleanup_rc" -eq 0 ]] &&
       ! systemctl --user is-active --quiet "$cleanup_main_unit" &&
       ! systemctl --user is-active --quiet "$cleanup_nested_unit" && echo pass || echo fail)" \
    "controller rc=$cleanup_rc"

unsafe_marker="$run_id-unsafe-marker"
# The single-quoted script expands inside the delegated scope, not in this test shell.
# shellcheck disable=SC2016
SNO_EXEC_SPAWN_ID="$unsafe_marker" setsid -f \
    systemd-run --user --scope --quiet --property=Delegate=yes --unit="$unsafe_unit" \
    bash -c 'group=$(awk -F: '\''$1 == "0" { print $3; exit }'\'' /proc/self/cgroup); child="/sys/fs/cgroup${group}/unsafe-child"; mkdir "$child"; echo $$ >"$child/cgroup.procs"; exec sleep 30'
for _ in {1..50}; do
    unsafe_group="$(systemctl --user show "$unsafe_unit" -p ControlGroup --value 2>/dev/null || true)"
    [[ -r "/sys/fs/cgroup$unsafe_group/unsafe-child/cgroup.procs" ]] && break
    sleep 0.1
done

set +e
bash "$wall" --spawn-id "$unsafe_marker" --term-after 1 --kill-after 2 --events "$unsafe_events"
unsafe_rc=$?
set -e
check 'a marked process in a non-unit cgroup fails closed' \
    "$([[ "$unsafe_rc" -eq 1 ]] && echo pass || echo fail)" "controller rc=$unsafe_rc"
check 'unsafe ownership writes termination-failed and never kill-confirmed' \
    "$(jq -e 'select(.event == "termination-failed")' "$unsafe_events" >/dev/null 2>&1 &&
       ! jq -e 'select(.event == "kill-confirmed")' "$unsafe_events" >/dev/null 2>&1 && echo pass || echo fail)"

printf '1..%d\n' "$case_number"
exit "$fail"
