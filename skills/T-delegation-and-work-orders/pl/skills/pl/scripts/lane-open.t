#!/usr/bin/env bash
# Observe the public commands, registry bytes and real Reach seat.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
root="$(mktemp -d)"
trap 'rm -r -- "$root"' EXIT
host="$(hostname)"
export PL_REGISTRY="$root/registry.tsv"
export SNO_REACH_ROOT="$root/reach"
export SNO_OWNER_ADDR="owner.primary@$(hostname)"
export PL_COS_CLAIM="$root/noop-claim.sh"
unset PL_LANE
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$PL_COS_CLAIM"
chmod +x "$PL_COS_CLAIM"
printf '%s\n' $'home_repo\tlane\treach_address\theartbeat_name\truntime\towning_cos\tstate\tnote' >"$PL_REGISTRY"

tests=0
failures=0
check() {
  local label="$1"; shift
  tests=$((tests + 1))
  if "$@"; then printf 'ok %d - %s\n' "$tests" "$label"
  else printf 'not ok %d - %s\n' "$tests" "$label"; failures=$((failures + 1)); fi
}
open_lane() {
  status=0
  bash "$script_dir/lane-open.sh" "$@" >"$root/out" 2>"$root/err" || status=$?
}

open_lane --repo '/tmp/parent with spaces/solo/'
check 'opens successfully' test "$status" -eq 0
check 'prints the exact default row' test "$(cat "$root/out")" = \
  $'solo\tall\tpl.solo@'"$host"$'\tsolo\tclaude\tunclaimed\tRUN\tLane opened by a standalone PL.'
check 'appends exactly one row' test "$(wc -l <"$PL_REGISTRY")" -eq 2
check 'stored row equals stdout' cmp -s "$root/out" <(tail -n 1 "$PL_REGISTRY")
resolved="$(bash "$script_dir/lane-resolve.sh" --repo solo 2>/dev/null)" || true
check 'resolver returns the owner and unclaimed ownership' test "$resolved" = \
  $'all\tpl.solo@'"$host"$'\tunclaimed\towner.primary@'"$host"$'\tRUN'
check 'creates the real PL seat' jq -e --arg host "$host" \
  '.address == "pl.solo@\($host)" and .role == "pl" and .runtime == "unbound"' \
  "$SNO_REACH_ROOT/pl.solo@$host/seat.json"
check 'creates no COS seat' test ! -e "$SNO_REACH_ROOT/cos.solo@$host"

cp -- "$PL_REGISTRY" "$root/before"
open_lane --repo solo --runtime codex
check 'second open exits 64' test "$status" -eq 64
check 'refusal prints no row' test ! -s "$root/out"
check 'refusal preserves all registry bytes' cmp -s "$PL_REGISTRY" "$root/before"

printf '%s\n' $'multi\tbuild\tpl.multi-build@'"$host"$'\tmulti-build\tcodex\tcos/multi\tRETIRED\tRetired lane.' >>"$PL_REGISTRY"
cp -- "$PL_REGISTRY" "$root/before"
open_lane --repo multi --lane build --runtime codex
check 'retired row permits opening the same lane' test "$status" -eq 0
check 'named lane uses the exact address and heartbeat' test "$(cat "$root/out")" = \
  $'multi\tbuild\tpl.multi-build@'"$host"$'\tmulti-build\tcodex\tunclaimed\tRUN\tLane opened by a standalone PL.'
check 'opening preserves retired and unrelated rows' cmp -s "$root/before" <(head -n -1 "$PL_REGISTRY")
resolved="$(bash "$script_dir/lane-resolve.sh" --repo multi --lane build 2>/dev/null)" || true
check 'resolver selects the new row over the retired row' test "$resolved" = \
  $'build\tpl.multi-build@'"$host"$'\tunclaimed\towner.primary@'"$host"$'\tRUN'

cp -- "$PL_REGISTRY" "$root/before"
open_lane --repo invalid --runtime invalid
check 'invalid runtime exits 64 without writing' test "$status" -eq 64
check 'invalid input preserves registry bytes' cmp -s "$root/before" "$PL_REGISTRY"
open_lane --repo
check 'missing argument exits 64' test "$status" -eq 64

export PL_REGISTRY="$root/fresh/state/registry.tsv"
open_lane --repo sno-fresh-repo
check 'a fresh machine with no registry opens its first lane' test "$status" -eq 0
check 'a repository name keeps its full text in the address' \
  test "$(tail -n 1 "$PL_REGISTRY" | cut -f3)" = "pl.sno-fresh-repo@$host"
check 'the new registry holds the header and exactly one row' test "$(wc -l <"$PL_REGISTRY")" -eq 2
check 'the new registry header names the reach_address column' test "$(head -n 1 "$PL_REGISTRY")" = \
  $'home_repo\tlane\treach_address\theartbeat_name\truntime\towning_cos\tstate\tnote'

printf '1..%d\n' "$tests"
[[ "$failures" -eq 0 ]] || { printf '%d failure(s)\n' "$failures" >&2; exit 1; }
