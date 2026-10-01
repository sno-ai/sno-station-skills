#!/usr/bin/env bash
# Exercise the public commands with a different home and scratch directory.
set -Eeuo pipefail

scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(mktemp -d)"
trap 'rm -r -- "$root"' EXIT
mkdir -p "$root/home with spaces" "$root/repo/ai-doc" "$root/scratch with spaces"
printf 'fixture dispatch\n' >"$root/dispatch.md"

rc=0
HOME="$root/home with spaces" PATH=/usr/bin:/bin bash "$scripts_dir/spawn-exec.sh" \
    --journey portable --repo "$root/repo" --budget-h invalid \
    --dispatch "$root/dispatch.md" --addr executor.portable@host1 \
    >"$root/spawn.out" 2>"$root/spawn.err" || rc=$?
[[ "$rc" == 6 ]]
grep -Fq 'spawn-exec: missing dependency: codex' "$root/spawn.err"
[[ ! -s "$root/home with spaces/.local/state/agent-spawns.jsonl" ]]
printf 'ok 1 - launcher checks the requested home before starting an executor\n'

rc=0
SNO_SCRATCH="$root/scratch with spaces" bash "$scripts_dir/general-env-doctor.sh" workspace \
    >"$root/workspace.out" 2>"$root/workspace.err" || rc=$?
[[ "$rc" == 0 ]]
grep -Fxq "[PASS] workspace: scratch directory writable: $root/scratch with spaces" "$root/workspace.out"
printf 'ok 2 - a writable scratch directory does not require a mount\n'

rc=0
SNO_SCRATCH="$root/missing" bash "$scripts_dir/general-env-doctor.sh" workspace \
    >"$root/missing.out" 2>"$root/missing.err" || rc=$?
[[ "$rc" == 3 ]]
grep -Fq "[FAIL] workspace: scratch directory is missing or not writable: $root/missing" "$root/missing.out"
printf 'ok 3 - missing scratch is refused\n1..3\n'
