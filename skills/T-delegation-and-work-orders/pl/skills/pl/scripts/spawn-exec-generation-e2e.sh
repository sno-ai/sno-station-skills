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
printf 'mission: mission-generation · operation: open · success-test: generation recorded · evidence: registry · owner: pending · parent: none · predecessor: none\n' >"$root/dispatch.md"
printf '#!/usr/bin/env bash\nexit 1\n' >"$root/bin/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' >"$root/bin/codex"
chmod +x "$root/bin/tmux" "$root/bin/codex"

for name in first second; do
    rc=0
    PATH="$root/bin:$PATH" bash "$script_dir/spawn-exec.sh" \
        --journey "j-$name" --repo "$root/repo" --budget-h 0.1 \
        --dispatch "$root/dispatch.md" --class closure \
        --callsign "$name" --addr "executor.$name@$host" \
        --log "$root/$name.log" >"$root/$name.out" 2>"$root/$name.err" || rc=$?
    [[ "$rc" == 1 ]]
    [[ -f "$SNO_REACH_ROOT/executor.$name@$host/seat.json" ]]
done
jq -es '
    [.[] | select(.mission == "mission-generation")] as $rows |
    ($rows | length) == 4 and
    $rows[0].event == "open" and $rows[1].event == "abort" and
    $rows[2].event == "open" and $rows[3].event == "abort" and
    $rows[0].spawn_id == $rows[1].spawn_id and
    $rows[2].spawn_id == $rows[3].spawn_id and
    $rows[0].spawn_id != $rows[2].spawn_id
' "$root/repo/ai-doc/ACTIVE/PL/missions.jsonl" >/dev/null
printf 'ok - two failed launches retain distinct matching lifecycle generations\n'
