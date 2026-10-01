#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cos_claim=""
for d in "$script_dir/../../../../cos/skills/cos/scripts" "$script_dir/../../cos/scripts"; do
  [[ -f "$d/cos-claim.sh" ]] && { cos_claim="$d/cos-claim.sh"; break; }
done
[[ -n "$cos_claim" ]] || { echo 'SKIP: cos skill not installed'; exit 0; }
root="$(mktemp -d)"
trap 'rm -r -- "$root"' EXIT
host="$(hostname)"
export HOME="$root/home" SNO_REACH_ROOT="$root/reach"
export PL_REGISTRY="$root/registry.tsv"
export SNO_PL_REGISTRY="$PL_REGISTRY"
mkdir -p "$HOME" "$root/repo/ai-doc" "$root/bin"
"$cos_claim" open repo >"$root/open.out"
printf 'mission: no-fence · operation: open · success-test: card rendered · evidence: card · owner: pending · parent: none · predecessor: none\n' >"$root/dispatch.md"
printf '#!/usr/bin/env bash\nexit 1\n' >"$root/bin/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' >"$root/bin/codex"
chmod +x "$root/bin/tmux" "$root/bin/codex"

rc=0
PATH="$root/bin:$PATH" bash "$script_dir/spawn-exec.sh" \
    --journey j-no-fence --repo "$root/repo" --budget-h 0.1 \
    --dispatch "$root/dispatch.md" --class closure \
    --callsign proof --addr "executor.no-fence@$host" \
    --log "$root/executor.log" >"$root/spawn.out" 2>"$root/spawn.err" || rc=$?
[[ "$rc" == 1 ]]
sno reach lint "$root/executor.log.on-station.eml" >/dev/null
grep -Fxq 'X-Work: j-no-fence' "$root/executor.log.on-station.eml"
grep -Fq 'measured-at-spawn: fence-exists=no fence-bytes=0 fence-sha256=none' \
    "$root/executor.log.on-station.eml"
grep -Fq 'observed-by-executor: sent separately' "$root/executor.log.on-station.eml"
printf 'ok - absent fence is reported as absent in the generated Reach card\n'
