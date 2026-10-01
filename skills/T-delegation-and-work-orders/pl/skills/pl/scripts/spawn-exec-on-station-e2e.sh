#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cos_claim=""
for d in "$script_dir/../../../../cos/skills/cos/scripts" "$script_dir/../../cos/scripts"; do
  [[ -f "$d/cos-claim.sh" ]] && { cos_claim="$d/cos-claim.sh"; break; }
done
[[ -n "$cos_claim" ]] || { echo 'SKIP: cos skill not installed'; exit 0; }
root="$(mktemp -d)"
host="$(hostname)"
session="a1-on-station-$$"
cleanup() {
    tmux kill-session -t "$session" 2>/dev/null || true
    rm -r -- "$root"
}
trap cleanup EXIT

export HOME="$root/home" SNO_REACH_ROOT="$root/reach"
mkdir -p "$HOME" "$root/repo/ai-doc" "$root/bin"
export PL_REGISTRY="$root/registry.tsv"
export SNO_PL_REGISTRY="$PL_REGISTRY"
"$cos_claim" open repo >"$root/open.out"
tmux new-session -d -s "$session" 'bash --noprofile --norc'
sno reach register --as "pl.repo@$host" --channel tmux \
    --handle "$(tmux list-panes -t "$session" -F '#{pane_id}')" >/dev/null

printf 'mission: proof · operation: open · success-test: card delivered · evidence: inbox · owner: pending · parent: none · predecessor: none\n' >"$root/dispatch.md"
printf 'allow\n' >"$root/fence.txt"
printf '#!/usr/bin/env bash\nexit 1\n' >"$root/bin/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' >"$root/bin/codex"
chmod +x "$root/bin/tmux" "$root/bin/codex"
rc=0
PATH="$root/bin:$PATH" bash "$script_dir/spawn-exec.sh" \
    --journey j-on-station --repo "$root/repo" --budget-h 0.1 \
    --dispatch "$root/dispatch.md" --fence "$root/fence.txt" \
    --callsign proof --addr "executor.proof@$host" --log "$root/executor.log" \
    >"$root/spawn.out" 2>"$root/spawn.err" || rc=$?
[[ "$rc" == 1 ]]
[[ -f "$root/executor.log.on-station.eml" ]]
sno reach lint "$root/executor.log.on-station.eml" >/dev/null
sno reach send --no-ring --as "executor.proof@$host" <"$root/executor.log.on-station.eml" >/dev/null
card="$(sno reach inbox --as "pl.repo@$host" | awk -F '\t' 'NR == 1 {print $1}')"
[[ -f "$card" ]]
grep -Fxq 'X-Work: j-on-station' "$card"
grep -Fxq 'Subject: [STATUS] on-station: proof' "$card"
grep -Fq 'measured-at-spawn: fence-exists=yes fence-bytes=6' "$card"
grep -Fq 'sno reach send --as executor.proof@' "$root/executor.log.dispatch"
printf 'ok - generated on-station card delivered and read through Reach\n'
