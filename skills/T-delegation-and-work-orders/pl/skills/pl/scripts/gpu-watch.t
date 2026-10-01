#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
export SNO_SCRATCH="$root/state" GPU_WATCH_SMI="$root/smi"
mkdir -p "$root/repo/ai-doc/ACTIVE/PL"
git -C "$root/repo" init -q
cat > "$root/smi" <<'SMI'
#!/usr/bin/env bash
cat "$GPU_WATCH_SAMPLE"
SMI
chmod +x "$root/smi"
cd "$root/repo"
tick() {
  local rc=0
  bash "$script_dir/gpu-watch.sh" --journey "$1" --tick-secs 60 --grace-mins 2 --stall-mins 1 --max-hours "$2" > "$root/out" || rc=$?
  [[ "$rc" -eq "$3" ]] || { printf 'wrong exit: %s (wanted %s)\n' "$rc" "$3" >&2; exit 1; }
  [[ -f $(sed -n '1p' "$root/out") ]]
}
export GPU_WATCH_SAMPLE="$root/sample"
printf '0, 30, 1024\n' > "$root/sample"
tick active 8 0
printf '0, 0, 1024\n' > "$root/sample"
tick active 8 3
grep -Fq 'GPU-WATCH: STALL' "$root/out"
tick never 8 0
tick never 8 0
tick never 8 4
grep -Fq 'GPU-WATCH: NEVER-STARTED' "$root/out"
printf '0, 30, 1024\n' > "$root/sample"
tick elapsed 0 0
grep -Fq 'GPU-WATCH: WINDOW-ELAPSED' "$root/out"
jq -e 'select(.journey == "active" and .event == "STALL")' ai-doc/ACTIVE/PL/gpu-watch.jsonl >/dev/null
jq -e 'select(.journey == "never" and .event == "NEVER-STARTED")' ai-doc/ACTIVE/PL/gpu-watch.jsonl >/dev/null
jq -e 'select(.journey == "elapsed" and .event == "WINDOW-ELAPSED")' ai-doc/ACTIVE/PL/gpu-watch.jsonl >/dev/null
[[ $(jq -c 'select(.max_util != null)' ai-doc/ACTIVE/PL/gpu-watch.jsonl | wc -l) -eq 6 ]]
printf 'ok - GPU ticks, exit codes, and audit trail\n'
