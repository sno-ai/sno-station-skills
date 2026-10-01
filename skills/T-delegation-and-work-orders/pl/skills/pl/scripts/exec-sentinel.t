#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
root=$(mktemp -d)
session="sentinel-pl-$$"
trap 'tmux kill-session -t "$session" 2>/dev/null || true; rm -rf -- "$root"' EXIT
export SNO_REACH_ROOT="$root/reach" SNO_SCRATCH="$root/state"
host=$(hostname)
pl="pl.sentinel@$host"; cos="cos.sentinel@$host"
mkdir -p "$root/repo"
git -C "$root/repo" init -q
git -C "$root/repo" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m start
: > "$root/executor.log"
sno reach init --as "$pl" --name Lead >/dev/null
sno reach init --as "$cos" --name Chief >/dev/null
cat > "$root/receiver.sh" <<'RECEIVER'
#!/usr/bin/env bash
while IFS= read -r line; do
  if [[ "$line" =~ ([0-9a-f]{8})\ typed\ by\ the\ mail\ transport ]]; then
    printf 'ACK-%s\n' "${BASH_REMATCH[1]}"
  fi
done
RECEIVER
tmux new-session -d -s "$session" "bash $(printf '%q' "$root/receiver.sh")"
tmux new-window -t "$session" "bash $(printf '%q' "$root/receiver.sh")"
mapfile -t panes < <(tmux list-panes -a -t "$session" -F '#{pane_id}')
sno reach register --as "$pl" --channel tmux --handle "${panes[0]}" >/dev/null
sno reach register --as "$cos" --channel tmux --handle "${panes[1]}" >/dev/null
tick() { bash "$script_dir/exec-sentinel.sh" --log "$root/executor.log" --repo "$root/repo" --pl "$pl" --cos "$cos" --from "$cos" --journey example-work --stall-min 2 --tick-secs 60 > "$root/out"; }
cards() { find "$SNO_REACH_ROOT/$1/new" -type f -print0 | xargs -0 -r grep -lF "$2" | wc -l; }
assert_cards() {
  local addr
  for addr in "$pl" "$cos"; do
    [[ $(cards "$addr" "$1") -eq "$2" ]] || { printf 'wrong cards for %s: %s (wanted %s)\n' "$addr" "$1" "$2" >&2; exit 1; }
  done
}
tick
state=$(sed -n '1p' "$root/out")
[[ -f "$state" ]] && [[ $(wc -l < "$root/out") -eq 2 ]]
assert_cards '[DECISION] SENTINEL STALL:' 0
tick
assert_cards '[DECISION] SENTINEL STALL:' 0
tick
assert_cards '[DECISION] SENTINEL STALL:' 1
tick
assert_cards '[DECISION] SENTINEL STALL:' 1
tick
assert_cards '[DECISION] SENTINEL STALL:' 2
git -C "$root/repo" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m resumed
tick
assert_cards 'MOVING again' 1
tick
assert_cards '[DECISION] SENTINEL STALL:' 2
tick
assert_cards '[DECISION] SENTINEL STALL:' 3
printf 'progress\n' >> "$root/executor.log"
tick
assert_cards 'MOVING again' 2
[[ $(sed -n '1p' "$root/out") == "$state" ]]
printf 'ok - sentinel ticks, backoff, commit delta, and recovery\n'
