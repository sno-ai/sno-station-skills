#!/usr/bin/env bash
# Tests for attempt-gate.sh — the circuit breaker's deterministic pre-send check.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
gate="$script_dir/attempt-gate.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

failures=0
test_no=0

pass() {
    test_no=$((test_no + 1))
    printf 'ok %d - %s\n' "$test_no" "$1"
}

fail() {
    test_no=$((test_no + 1))
    failures=$((failures + 1))
    printf 'not ok %d - %s\n' "$test_no" "$1"
    [[ -z "${2:-}" ]] || printf '#   %s\n' "$2"
}

# run <expected-exit> <label> -- <args...>; captures stdout into $out, stderr into $err
run() {
    local want="$1" label="$2"; shift 3
    local rc=0
    out="$(bash "$gate" "$@" 2>"$tmp/err")" || rc=$?
    err="$(cat "$tmp/err")"
    if [[ "$rc" == "$want" ]]; then
        pass "$label"
    else
        fail "$label" "exit=$rc want=$want stdout=$out stderr=$err"
    fi
}

expect_out() {
    local label="$1" needle="$2"
    if [[ "$out" == *"$needle"* ]]; then
        pass "$label"
    else
        fail "$label" "stdout=$out (wanted: $needle)"
    fi
}

printf 'TAP version 13\n'

# A realistic Maildir-shaped tree: cards are RFC-5322-ish files under new/ and cur/.
maildir="$tmp/mailbox"
mkdir -p "$maildir/new" "$maildir/cur"

# Fresh slug: nothing recorded anywhere.
run 0 'count on a fresh slug is 0' -- count --slug fix-x --scan "$maildir"
expect_out 'fresh count prints attempts=0' 'attempts=0'
run 0 'check on a fresh slug allows attempt 1' -- check --slug fix-x --scan "$maildir"
expect_out 'fresh check prints next-attempt=1' 'ok next-attempt=1'

# One recorded attempt.
cat >"$maildir/cur/1755300000.card1" <<'EOF'
From: cos.primary@host1
Subject: stall in lane b — attempt: fix-x #1 — success check: git log -1 -- src/
RECOMMENDATION — you decide; these are the facts and the rule they touch.
attempt: fix-x #1 — success check: git log -1 -- src/
EOF
run 0 'one tag counts 1' -- count --slug fix-x --scan "$maildir"
expect_out 'one tag prints attempts=1' 'attempts=1'
run 0 'check after one attempt allows attempt 2' -- check --slug fix-x --scan "$maildir"
expect_out 'check prints next-attempt=2' 'ok next-attempt=2'

# Second attempt recorded -> the third is refused.
cat >"$maildir/new/1755310000.card2" <<'EOF'
Subject: same stall, reworded — attempt: fix-x #2 — success check: git log -1 -- src/
attempt: fix-x #2 — success check: git log -1 -- src/
EOF
run 3 'two attempts refuse the third (exit 3)' -- check --slug fix-x --scan "$maildir"
expect_out 'refusal prints REFUSED attempts=2 slug=fix-x' 'REFUSED attempts=2 slug=fix-x'
if [[ "$err" == *'attempt: fix-x #1'* && "$err" == *'attempt: fix-x #2'* ]]; then
    pass 'refusal lists the matched tag lines on stderr'
else
    fail 'refusal lists the matched tag lines on stderr' "stderr=$err"
fi

# A reply QUOTING attempt #1 must not raise the count (distinct-N, quote-proof).
cat >"$maildir/cur/1755320000.reply" <<'EOF'
Subject: re: stall in lane b
> attempt: fix-x #1 — success check: git log -1 -- src/
Your first attempt did not resolve it.
EOF
run 0 'a quoted old tag does not raise the count' -- count --slug fix-x --scan "$maildir"
expect_out 'count stays attempts=2 despite the quote' 'attempts=2'

# A different slug's tags are invisible to this slug.
run 0 'a different slug is not counted' -- count --slug other-problem --scan "$maildir"
expect_out 'other slug prints attempts=0' 'attempts=0'

# A slug containing a dot is matched literally, not as a regex wildcard.
cat >"$maildir/cur/1755330000.dotted" <<'EOF'
attempt: fixXy #9 — success check: true
EOF
run 0 'dotted slug does not regex-match fixXy' -- count --slug 'fix.y' --scan "$maildir"
expect_out 'dotted slug prints attempts=0' 'attempts=0'

# Missing scan path is exit 65, never a silent zero (a missing path must not read as zero attempts).
run 65 'missing scan path exits 65' -- count --slug fix-x --scan "$tmp/does-not-exist"

# Usage errors are loud.
run 64 'missing --slug exits 64' -- check --scan "$maildir"
run 64 'missing --scan exits 64' -- check --slug fix-x
run 64 'unknown subcommand exits 64' -- frobnicate --slug fix-x --scan "$maildir"

# Directory recursion: a thread export two levels down still counts.
mkdir -p "$tmp/threads/j-42"
printf 'ruling: attempt: deep-slug #1 — success check: ls out/\n' >"$tmp/threads/j-42/thread.md"
run 0 'recursive directory scan finds nested tags' -- count --slug deep-slug --scan "$tmp/threads"
expect_out 'nested tag prints attempts=1' 'attempts=1'

printf '1..%d\n' "$test_no"
if [[ "$failures" -eq 0 ]]; then
    printf '# attempt-gate tests passed\n'
else
    printf '# attempt-gate tests FAILED (%d)\n' "$failures"
    exit 1
fi
