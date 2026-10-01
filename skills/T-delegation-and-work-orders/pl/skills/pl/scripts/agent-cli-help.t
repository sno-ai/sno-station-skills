#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(mktemp -d)"
trap 'rm -r -- "$root"' EXIT

scripts=(
    convergence-watch.sh
    exec-sentinel.sh
    fence-check.sh
    general-env-doctor.sh
    gpu-watch.sh
    roster.sh
)
tests=0
failures=0

printf 'TAP version 13\n'
for script in "${scripts[@]}"; do
    set +e
    HOME="$root/home" timeout 5 bash "$script_dir/$script" --help \
        >"$root/$script.out" 2>"$root/$script.err"
    rc=$?
    set -e
    tests=$((tests + 1))
    if [[ "$rc" -eq 0 ]] && [[ -s "$root/$script.out" ]] && \
       grep -Fqi "${script%.sh}" "$root/$script.out" && \
       { [[ "$script" != exec-sentinel.sh && "$script" != roster.sh ]] ||
         ! grep -Eq '^(set -|case )' "$root/$script.out"; } && \
       [[ ! -s "$root/$script.err" ]]; then
        printf 'ok %d - %s exposes help without running\n' "$tests" "$script"
    else
        printf 'not ok %d - %s must expose help without running\n' "$tests" "$script"
        printf '# rc=%s stdout=%s stderr=%s\n' "$rc" \
            "$(tr '\n' ' ' <"$root/$script.out")" \
            "$(tr '\n' ' ' <"$root/$script.err")"
        failures=$((failures + 1))
    fi
done

printf '1..%d\n' "$tests"
[[ "$failures" -eq 0 ]]
