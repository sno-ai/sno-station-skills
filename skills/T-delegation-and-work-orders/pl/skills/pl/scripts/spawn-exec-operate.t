#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
launcher="$script_dir/spawn-exec.sh"
# lane-resolve.sh reclaims expired leases through cos-claim.sh, which lives in the
# sibling cos skill. HOME here is an empty fixture, so point the resolver at the real
# script: repo shape first, deployed shape second.
cos_claim=""
for d in "$script_dir/../../../../cos/skills/cos/scripts" "$script_dir/../../cos/scripts"; do
  [[ -f "$d/cos-claim.sh" ]] && { cos_claim="$d/cos-claim.sh"; break; }
done
[[ -n "$cos_claim" ]] || { echo 'SKIP: cos skill not installed'; exit 0; }
restricted_path=/usr/bin:/bin
real_path="$PATH"
root="$(mktemp -d)"
host="$(hostname)"
failure_nested_unit="operate-wall-failure-nested-$$.scope"
cleanup() {
    [[ ! -d "$root/tmux" ]] || TMUX_TMPDIR="$root/tmux" tmux kill-server 2>/dev/null || true
    systemctl --user kill --kill-whom=all --signal=KILL "$failure_nested_unit" >/dev/null 2>&1 || true
    systemctl --user stop "$failure_nested_unit" >/dev/null 2>&1 || true
    systemctl --user reset-failed "$failure_nested_unit" >/dev/null 2>&1 || true
    rm -r -- "$root"
}
trap cleanup EXIT

home="$root/home"
repo="$root/repo"
mkdir -p "$home" "$repo/ai-doc/ACTIVE/PL"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name='Operate Test' -c user.email='operate@invalid' \
    commit -q --allow-empty -m fixture

mission='mission: operate-test · operation: open · success-test: command completes · evidence: result file · owner: pending · parent: none · predecessor: none'
tests=0
failures=0

check() {
    local label="$1"
    shift
    tests=$((tests + 1))
    if "$@"; then
        printf 'ok %d - %s\n' "$tests" "$label"
    else
        printf 'not ok %d - %s\n' "$tests" "$label"
        failures=$((failures + 1))
    fi
}

run_charter() {
    local name="$1" body="$2"
    local dispatch="$root/$name.md"
    printf '%s\n%s\n' "$mission" "$body" >"$dispatch"
    set +e
    HOME="$home" PATH="$restricted_path" bash "$launcher" \
        --journey j-operate-test --repo "$repo" --budget-h 0.1 \
        --dispatch "$dispatch" --class operate --runtime codex \
        --addr "executor.operate-test@$host" >"$root/$name.out" 2>"$root/$name.err"
    run_rc=$?
    set -e
    run_err="$root/$name.err"
}

printf 'TAP version 13\n'

run_charter valid $'command: ./run-existing.sh\nworking-directory: /srv/job\nartifact: /srv/job/result.json'
check 'operate accepts command, working directory, and artifact without a deliver line' \
    test "$run_rc" -eq 6
check 'operate reaches downstream dependency checks' \
    grep -Fq 'spawn-exec: missing dependency: codex' "$run_err"
check 'operate does not run the deliver gate' \
    bash -c '! grep -qi deliver "$1"' _ "$run_err"

for missing in command working-directory artifact; do
    case "$missing" in
        command) body=$'working-directory: /srv/job\nartifact: /srv/job/result.json' ;;
        working-directory) body=$'command: ./run-existing.sh\nartifact: /srv/job/result.json' ;;
        artifact) body=$'command: ./run-existing.sh\nworking-directory: /srv/job' ;;
    esac
    run_charter "missing-$missing" "$body"
    check "operate rejects a missing $missing field" \
        bash -c 'test "$1" -eq 2 && grep -Fq "$2" "$3"' \
            _ "$run_rc" "$missing" "$run_err"
done

mkdir -p "$root/bin" "$root/tmux" "$root/tmp" "$home/.mblaze"
chmod 700 "$root/tmux"
printf 'FQDN: operate-test.invalid\n' >"$home/.mblaze/profile"
cat >"$root/bin/codex" <<'RUNTIME'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ -t 0 && -t 1 ]]
printf 'operational artifact\n' >"$TEST_ARTIFACT"
trap 'exit 0' HUP INT TERM
while IFS= read -r _; do :; done
RUNTIME
chmod 700 "$root/bin/codex"
registry="$root/registry.tsv"
HOME="$home" SNO_REACH_ROOT="$root/reach" SNO_PL_REGISTRY="$registry" \
    "$cos_claim" open repo beta >"$root/lane-open.out"

set +e
env -u TMUX -u TMUX_PANE HOME="$home" PATH="$root/bin:$real_path" \
    TMPDIR="$root/tmp" TMUX_TMPDIR="$root/tmux" SNO_REACH_ROOT="$root/reach" \
    PL_REGISTRY="$registry" \
    SNO_PL_REGISTRY="$registry" PL_LANE=beta PL_COS_CLAIM="$cos_claim" \
    TEST_ARTIFACT="$root/result.json" timeout 20 bash "$launcher" \
        --journey j-operate-e2e --repo "$repo" --budget-h 0.001 \
        --dispatch "$root/valid.md" --class operate \
        --addr "executor.operate-e2e@$host" --log "$root/operate.log" \
        >"$root/e2e.out" 2>"$root/e2e.err"
e2e_rc=$?
set -e

check 'operate completes the real launcher boundary' test "$e2e_rc" -eq 0
check 'operate records the spawn' \
    bash -c 'jq -e '\''select(.journey == "j-operate-e2e" and .class == "operate")'\'' "$1" >/dev/null' \
        _ "$home/.local/state/agent-spawns.jsonl"
check 'the operational runtime produces its named artifact' test -s "$root/result.json"
check 'operate uses closure convergence semantics' \
    grep -Fq 'convergence-watch.sh" record --journey j-operate-e2e --class closure' \
        "$root/operate.log.dispatch"

for _ in $(seq 1 100); do
    if [[ -f "$root/operate.log.wall.jsonl" ]] &&
       jq -e 'select(.event == "kill-confirmed")' "$root/operate.log.wall.jsonl" >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done
check 'the external wall stops the operational runtime' \
    bash -c 'jq -e '\''select(.event == "kill-confirmed")'\'' "$1" >/dev/null' \
        _ "$root/operate.log.wall.jsonl"
operate_callsign="$(jq -r 'select(.journey == "j-operate-e2e") | .callsign' \
    "$home/.local/state/agent-spawns.jsonl")"
for _ in $(seq 1 20); do
    TMUX_TMPDIR="$root/tmux" tmux has-session -t "$operate_callsign" 2>/dev/null || break
    sleep 0.1
done
check 'the executor session ends after its runtime stops' \
    bash -c '! TMUX_TMPDIR="$1" tmux has-session -t "$2" 2>/dev/null' \
        _ "$root/tmux" "$operate_callsign"
if ! jq -e 'select(.event == "kill-confirmed")' "$root/operate.log.wall.jsonl" >/dev/null 2>&1; then
    sed 's/^/# wall: /' "$root/operate.log.wall.jsonl"
fi

real_systemd_run="$(command -v systemd-run)"
cat >"$root/bin/systemd-run" <<WRAPPER
#!/usr/bin/env bash
set -Eeuo pipefail
unit=''
collect=0
for arg in "\$@"; do
    if [[ "\$arg" == --unit=* ]]; then
        unit="\${arg#--unit=}"
    fi
    if [[ "\$arg" == --collect ]]; then
        collect=1
    fi
done
if [[ "\$unit" == sno-exec-*.scope ]]; then
    printf '%s\n' "\$unit" >"$root/failing-runtime-unit"
fi
if ((collect == 1)); then
    for _ in {1..50}; do
        if systemctl --user is-active --quiet "$failure_nested_unit"; then
            touch "$root/failure-nested-was-active"
            break
        fi
        sleep 0.1
    done
    exit 1
fi
exec "$real_systemd_run" "\$@"
WRAPPER
chmod 700 "$root/bin/systemd-run"
cat >"$root/bin/codex" <<RUNTIME
#!/usr/bin/env bash
set -Eeuo pipefail
[[ -t 0 && -t 1 ]]
systemd-run --user --scope --quiet --unit="$failure_nested_unit" \
    bash -c 'trap "" TERM; exec sleep 30' &
trap 'exit 0' HUP INT TERM
wait
RUNTIME
chmod 700 "$root/bin/codex"
cat >"$root/wall-failure.md" <<'FAILURE_DISPATCH'
mission: operate-wall-failure · operation: open · success-test: launcher refuses · evidence: runtime scope empty · owner: pending · parent: none · predecessor: none · why-not-incumbent: different test mission
command: ./run-existing.sh
working-directory: /srv/job
artifact: /srv/job/result.json
FAILURE_DISPATCH

set +e
env -u TMUX -u TMUX_PANE HOME="$home" PATH="$root/bin:$real_path" \
    TMPDIR="$root/tmp" TMUX_TMPDIR="$root/tmux" SNO_REACH_ROOT="$root/reach" \
    PL_REGISTRY="$registry" \
    SNO_PL_REGISTRY="$registry" PL_LANE=beta PL_COS_CLAIM="$cos_claim" \
    TEST_ARTIFACT="$root/failure-result.json" timeout 20 bash "$launcher" \
        --journey j-operate-wall-failure --repo "$repo" --budget-h 0.01 \
        --dispatch "$root/wall-failure.md" --class operate \
        --addr "executor.operate-wall-failure@$host" --log "$root/wall-failure.log" \
        >"$root/wall-failure.out" 2>"$root/wall-failure.err"
wall_failure_rc=$?
set -e

failed_runtime_unit=''
[[ ! -f "$root/failing-runtime-unit" ]] || failed_runtime_unit="$(<"$root/failing-runtime-unit")"
failed_runtime_group="$(systemctl --user show "$failed_runtime_unit" -p ControlGroup --value 2>/dev/null || true)"
failed_runtime_procs=''
if [[ -n "$failed_runtime_group" && -r "/sys/fs/cgroup$failed_runtime_group/cgroup.procs" ]]; then
    failed_runtime_procs="$(<"/sys/fs/cgroup$failed_runtime_group/cgroup.procs")"
fi
nested_runtime_group="$(systemctl --user show "$failure_nested_unit" -p ControlGroup --value 2>/dev/null || true)"
nested_runtime_procs=''
if [[ -n "$nested_runtime_group" && -r "/sys/fs/cgroup$nested_runtime_group/cgroup.procs" ]]; then
    nested_runtime_procs="$(<"/sys/fs/cgroup$nested_runtime_group/cgroup.procs")"
fi
check 'a wall-arm failure refuses the spawn' test "$wall_failure_rc" -eq 7
check 'the injected failure reached systemd-run after the runtime unit was named' \
    test -n "$failed_runtime_unit"
check 'the failure fixture started the inherited nested scope before rollback' \
    test -f "$root/failure-nested-was-active"
check 'wall-arm failure rollback leaves the runtime scope empty' \
    test -z "$failed_runtime_procs"
check 'wall-arm failure rollback also empties an inherited nested scope' \
    test -z "$nested_runtime_procs"
if [[ -z "$failed_runtime_unit" ]]; then
    sed 's/^/# wall-failure stderr: /' "$root/wall-failure.err"
fi

printf '1..%d\n' "$tests"
[[ "$failures" -eq 0 ]]
