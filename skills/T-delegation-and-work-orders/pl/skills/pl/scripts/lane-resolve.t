#!/usr/bin/env bash
# lane-resolve.sh — one row, or a refusal. Never a guess.
#
# Row 4: on a repository with three lanes whose owning COS differ, a repository-only lookup
# would return lane A's supervisor to lane B, silently. Row 5 proves the same for the
# Reach address, which is worse — two supervisors on one seat.
set -Eeuo pipefail

RESOLVE="${RESOLVE:-$(dirname "$0")/lane-resolve.sh}"
script_dir="$(cd -- "$(dirname -- "$RESOLVE")" && pwd)"
if [[ -z "${CLAIM:-}" ]]; then
  for d in "$script_dir/../../../../cos/skills/cos/scripts" "$script_dir/../../cos/scripts"; do
    [[ -f "$d/cos-claim.sh" ]] && { CLAIM="$d/cos-claim.sh"; break; }
  done
fi
[[ -n "${CLAIM:-}" ]] || { echo 'SKIP: cos skill not installed'; exit 0; }

root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
host="$(hostname)"
export SNO_OWNER_ADDR="owner.primary@$host"
export SNO_REACH_ROOT="$root/reach"

tests=0
failures=0
check() { # $1 label, rest: command
  local label="$1"; shift
  tests=$((tests + 1))
  if "$@"; then printf 'ok %d - %s\n' "$tests" "$label"
  else printf 'not ok %d - %s\n' "$tests" "$label"; failures=$((failures + 1)); fi
}

# A registry shaped like the real one: one single-lane repo, one three-lane repo whose lanes
# have DIFFERENT owning COS (reachable today via `cos-claim.sh open-lane`), one retired lane,
# and one row with a placeholder address.
reg="$root/pl-registry.tsv"
SNO_PL_REGISTRY="$reg" "$CLAIM" open setup >/dev/null
sed -i '2,$d' "$reg"
{
  printf 'solo\tall\tpl.solo@host1\tsolo\tcodex\tcos/solo\tRUN\t-\n'
  printf 'multi\ta\tpl.multi@host1\tmulti\tcodex\tcos/first\tRUN\t-\n'
  printf 'multi\tb\tpl.multi-b@host1\tmulti\tcodex\tcos/second\tRUN\t-\n'
  printf 'multi\t-\tcos.multi@host1\tmulti-cos\tclaw\tcos/first\tRUN\tCOS identity\n'
  printf 'multi\told\tpl.multi-old@host1\tmulti\tcodex\tcos/first\tRETIRED\t-\n'
  printf 'prefixed\tall\tpl.prefixed@host1\tprefixed\tcodex\tcos/sno-prefixed\tRUN\t-\n'
  printf 'unclaimed\tall\tpl.unclaimed@host1\tunclaimed\tcodex\tunclaimed\tRUN\t-\n'
  printf 'broken\tall\tTBD\tbroken\tcodex\tcos/x\tRUN\t-\n'
  printf 'sweep\told\tpl.sweep-old@host1\tsweep\tclaw\tcos/other\tRUN\tOld lane.\n'
  printf 'sweep\tcurrent\tpl.sweep-current@host1\tsweep\tclaude\tcos/sweep\tRUN\tCurrent lane.\n'
} >> "$reg"
sed -i "s/@host1/@$host/g" "$reg"
export PL_REGISTRY="$reg"

lease_now="$(date +%s)"
lease_old=$((lease_now - 86401))
lease_fresh=$((lease_now - 60))
sno reach init --as "pl.sweep-old@$host" --name Old >/dev/null
sno reach init --as "pl.sweep-current@$host" --name Current >/dev/null
jq --arg updated "$(date -u -d "@$lease_old" +%Y-%m-%dT%H:%M:%SZ)" \
  '.updated=$updated' "$SNO_REACH_ROOT/pl.sweep-old@$host/seat.json" \
  >"$root/old-seat.json"
mv "$root/old-seat.json" "$SNO_REACH_ROOT/pl.sweep-old@$host/seat.json"
mkdir -p "$SNO_REACH_ROOT/pl.sweep-old@$host/new"
printf '%s\n' 'preserve this task' >"$SNO_REACH_ROOT/pl.sweep-old@$host/new/task.eml"
export PL_COS_CLAIM="$CLAIM"
export SNO_COS_CLAIM_NOW="$lease_now"

r() { bash "$RESOLVE" "$@" 2>/dev/null; }

# 1-3. the ordinary single-lane case resolves every field from the one row
check "single-lane repo resolves its address" test "$(r --repo solo --field addr)" = "pl.solo@$host"
check "single-lane repo derives its COS address" \
  test "$(r --repo solo --field cos_addr)" = "cos.solo@$host"
check "a COS token keeps its full text in the derived COS address" \
  test "$(r --repo prefixed --field cos_addr)" = "cos.sno-prefixed@$host"
check "prints all five fields on one tab-separated line" \
  test "$(r --repo solo | awk -F'\t' '{print NF}')" -eq 5

# 4-5. Lane b must get lane b's supervisor and lane b's Reach address — never lane a's,
#      which is exactly what a repository-only first-row lookup returns.
check "lane b gets its OWN owning COS, not the first row's" \
  test "$(r --repo multi --lane b --field cos_token)" = "cos/second"
check "lane b gets its OWN Reach address, not the first row's" \
  test "$(r --repo multi --lane b --field addr)" = "pl.multi-b@$host"
check "lane a still resolves to lane a" \
  test "$(r --repo multi --lane a --field cos_token)" = "cos/first"

# 6-8. fail closed rather than guess
check "a multi-lane repo with no lane named is REFUSED, not guessed" \
  bash -c 'bash "$1" --repo multi >/dev/null 2>&1; test $? -eq 64' _ "$RESOLVE"
check "the refusal lists the lanes to choose from" \
  bash -c 'out="$(bash "$1" --repo multi 2>&1 >/dev/null)";
           grep -q "  a" <<<"$out" && ! grep -qx "  -" <<<"$out"' _ "$RESOLVE"
check "an unknown repository is refused" \
  bash -c 'bash "$1" --repo nosuch >/dev/null 2>&1; test $? -eq 64' _ "$RESOLVE"

# 9. a retired lane is not a candidate — a closed lane must never resolve as the live one
check "a RETIRED lane is never resolved" \
  bash -c 'bash "$1" --repo multi --lane old >/dev/null 2>&1; test $? -eq 64' _ "$RESOLVE"

# 10. a placeholder address is caught here, not at the moment something tries to send
check "a row with a placeholder address is refused" \
  bash -c 'bash "$1" --repo broken >/dev/null 2>&1; test $? -eq 64' _ "$RESOLVE"

# 11. an unclaimed lane is not an error: the owner supervises it until a COS claims it
check "an unclaimed lane reports to the owner" \
  test "$(r --repo unclaimed --field cos_addr)" = "owner.primary@$host"

# 12. $PL_LANE is honoured, so a session started on a lane needs no flag
check "PL_LANE selects the lane without a flag" \
  bash -c 'PL_LANE=b bash "$1" --repo multi --field addr 2>/dev/null | grep -qx "$2"' _ "$RESOLVE" "pl.multi-b@$host"

# 13-15. The ordinary resolver entry reaps every expired lane in this repository before
# resolving. Ownership by another COS does not keep a lost seat alive.
check "resolver reaps stale lanes before deciding whether the repository is ambiguous" \
  test "$(r --repo sweep --field addr)" = "pl.sweep-current@$host"
check "resolver records the stale foreign-owner lane as retired" \
  awk -F '\t' '$1 == "sweep" && $2 == "old" && $6 == "cos/other" &&
                   $7 == "RETIRED" {found=1} END {exit !found}' "$reg"
check "resolver reclaim preserves the retired lane task" \
  test -f "$SNO_REACH_ROOT/pl.sweep-old@$host/new/task.eml"

# 16-18. argument and environment contract
check "an unknown flag exits 64" \
  bash -c 'bash "$1" --repo solo --nope >/dev/null 2>&1; test $? -eq 64' _ "$RESOLVE"
check "an unknown --field exits 64" \
  bash -c 'bash "$1" --repo solo --field nope >/dev/null 2>&1; test $? -eq 64' _ "$RESOLVE"
check "a missing registry exits 65, distinct from a bad lookup" \
  bash -c 'PL_REGISTRY=/nonexistent bash "$1" --repo solo >/dev/null 2>&1; test $? -eq 65' _ "$RESOLVE"

# 19. the COS identity row (lane "-") is never a PL lane
check "the COS identity row cannot resolve as a PL lane" \
  bash -c 'bash "$1" --repo multi --lane - >/dev/null 2>&1; test $? -eq 64' _ "$RESOLVE"

printf '1..%d\n' "$tests"
[[ "$failures" -eq 0 ]] || { printf '%d failure(s)\n' "$failures" >&2; exit 1; }
