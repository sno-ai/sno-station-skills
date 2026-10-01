#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(mktemp -d)"
trap 'rm -r -- "$root"' EXIT

# lane-resolve.sh reclaims expired leases through cos-claim.sh, which lives in the
# sibling cos skill. HOME here is an empty fixture, so point the resolver at the real
# script: repo shape first, deployed shape second.
cos_claim=""
for d in "$script_dir/../../../../cos/skills/cos/scripts" "$script_dir/../../cos/scripts"; do
  [[ -f "$d/cos-claim.sh" ]] && { cos_claim="$d/cos-claim.sh"; break; }
done
[[ -n "$cos_claim" ]] || { echo 'SKIP: cos skill not installed'; exit 0; }

home="$root/home"
repo="$root/multi"
fixture="$root/fixture"
mkdir -p "$home" "$repo/ai-doc/ACTIVE/PL" "$fixture"
ln -s "$script_dir/spawn-exec.sh" "$fixture/spawn-exec.sh"
ln -s "$script_dir/lane-resolve.sh" "$fixture/lane-resolve.sh"
ln -s "$script_dir/executor-wall.sh" "$fixture/executor-wall.sh"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name='Lane Test' -c user.email='lane@invalid' \
    commit -q --allow-empty -m fixture

registry="$root/registry.tsv"
SNO_PL_REGISTRY="$registry" SNO_REACH_ROOT="$root/reach" "$cos_claim" open setup >/dev/null
sed -i '2,$d' "$registry"
{
    printf 'multi\talpha\tpl.alpha@host1\tmulti\tcodex\tcos/sno-alpha\tRUN\t-\n'
    printf 'multi\tbeta\tpl.beta@host1\tmulti\tcodex\tcos/example-repo\tRUN\t-\n'
    printf 'multi\tomega\tpl.omega@host1\tmulti\tcodex\tcos/sno-omega\tRUN\t-\n'
} >>"$registry"
dispatch="$root/dispatch.md"
cat >"$dispatch" <<'DISPATCH'
mission: lane-test · operation: open · success-test: lane resolves · evidence: launcher stderr · owner: pending · parent: none · predecessor: none
$deliver charter.md
DISPATCH

run_spawn() {
    local name="$1" env_lane="$2"
    shift 2
    set +e
    HOME="$home" SNO_REACH_ROOT="$root/reach" PL_REGISTRY="$registry" \
        PL_LANE="$env_lane" PL_COS_CLAIM="$cos_claim" \
        bash "$fixture/spawn-exec.sh" --journey "j-$name" --repo "$repo" \
        --budget-h 0.1 --dispatch "$dispatch" --class closure \
        --addr "executor.$name@host1" "$@" >"$root/$name.out" 2>"$root/$name.err"
    run_rc=$?
    set -e
    run_err="$root/$name.err"
}

tests=0
failures=0
check() {
    local label="$1"
    shift
    tests=$((tests + 1))
    if "$@"; then printf 'ok %d - %s\n' "$tests" "$label"
    else printf 'not ok %d - %s\n' "$tests" "$label"; cat "$run_err"; failures=$((failures + 1)); fi
}

printf 'TAP version 13\n'

run_spawn env-lane beta
check 'PL_LANE resolves the launcher past lane selection' \
    bash -c 'test "$1" -eq 127 && grep -Fq callsign.sh "$2"' _ "$run_rc" "$run_err"

# Make the explicitly selected row observably distinct from the environment-selected row.
# If the launcher ignores --lane, alpha remains valid and reaches callsign.sh instead.
sed -i 's/pl\.beta@host1/not-a-pl-address/' "$registry"
run_spawn explicit-lane alpha --lane beta
check '--lane overrides PL_LANE and selects the explicit row' \
    bash -c 'test "$1" -eq 2 && grep -Fq "lane beta has no strict PL address (not-a-pl-address)" "$2"' \
        _ "$run_rc" "$run_err"

run_spawn ambiguous ''
check 'an ambiguous repository is refused by the canonical resolver' test "$run_rc" -eq 2
check 'the refusal names all lanes and the selector' \
    bash -c 'grep -Fq "  alpha" "$1" && grep -Fq "  beta" "$1" && grep -Fq "  omega" "$1" && grep -Fq -- "--lane or \$PL_LANE" "$1"' \
        _ "$run_err"

printf '1..%d\n' "$tests"
[[ "$failures" -eq 0 ]]
