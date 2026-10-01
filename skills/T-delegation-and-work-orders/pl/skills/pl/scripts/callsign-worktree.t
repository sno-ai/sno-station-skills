#!/usr/bin/env bash
set -Eeuo pipefail

callsign="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/callsign.sh"
root="$(mktemp -d)"
trap 'rm -r -- "$root"' EXIT

home="$root/home"
main="$root/main-repo"
linked="$root/linked-worktree"
mkdir -p "$home" "$main"
git -C "$main" init -q -b main
git -C "$main" -c user.name='Callsign Test' -c user.email='callsign@invalid' \
    commit -q --allow-empty -m fixture
git -C "$main" worktree add -q -b linked "$linked"
mkdir -p "$main/subdir" "$linked/subdir"
canonical_main="$(cd -- "$main" && pwd -P)"

HOME="$home" "$callsign" claim --journey j-main --repo "$main" --kind executor >/dev/null
HOME="$home" "$callsign" claim --journey j-main-sub --repo "$main/subdir" --kind executor >/dev/null
HOME="$home" "$callsign" claim --journey j-linked --repo "$linked" --kind executor >/dev/null
HOME="$home" "$callsign" claim --journey j-linked-sub --repo "$linked/subdir" --kind executor >/dev/null

ledger="$home/.local/state/agent-callsigns.jsonl"
tests=0
failures=0
check() {
    local label="$1"
    shift
    tests=$((tests + 1))
    if "$@"; then printf 'ok %d - %s\n' "$tests" "$label"
    else printf 'not ok %d - %s\n' "$tests" "$label"; failures=$((failures + 1)); fi
}

printf 'TAP version 13\n'
for journey in j-main j-main-sub j-linked j-linked-sub; do
    actual="$(jq -rs --arg journey "$journey" \
        '[.[] | select(.event == "claim" and .journey == $journey)][-1].repo' "$ledger")"
    check "$journey records the main checkout" test "$actual" = "$canonical_main"
done
unique_repos="$(jq -rs '[.[] | select(.event == "claim") | .repo] | unique | length' "$ledger")"
check 'all four claims use one repository identity' \
    test "$unique_repos" -eq 1

printf '1..%d\n' "$tests"
[[ "$failures" -eq 0 ]]
