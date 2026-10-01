#!/usr/bin/env bash
# cos-since.sh — "has anything moved since <time>?" in one command.
#
# Read mailbox and executor movement from their actual sources so a watcher
# cannot mistake a read-only process or filename order for lane progress.
#
# Usage:
#   cos-since.sh <utc-stamp> [repo-dir]
#     <utc-stamp>  compact UTC (YYYYMMDDTHHMMSSZ); prefixes work.
#     [repo-dir]   defaults to $PWD.
#
# Exit codes:  0 something moved · 1 nothing moved · 2 bad usage/paths.

set -uo pipefail

SINCE="${1:-}"
REPO="${2:-$PWD}"

if [ -z "$SINCE" ]; then
	echo "usage: cos-since.sh <utc-stamp YYYYMMDDTHHMMSSZ> [repo-dir]" >&2
	exit 2
fi

: "${PL_SKILL_DIR:?set PL_SKILL_DIR to the installed pl skill directory}"
for tool in sno python3; do
	command -v "$tool" >/dev/null 2>&1 || { echo "cos-since: $tool is required but not installed" >&2; exit 2; }
done

REGISTRY="${SNO_PL_REGISTRY:-$HOME/.local/state/pl-registry.tsv}"
repo_base="$(basename "$REPO")"
# One resolver, never a repository-only first-row lookup: on a multi-lane repository that
# addresses the wrong PL silently. It refuses rather than guesses.
SEAT="$(bash "$PL_SKILL_DIR/scripts/lane-resolve.sh" \
	--repo "$repo_base" --field addr)" || exit 64
if [ ! -d "$REPO" ] || [ ! -f "$REGISTRY" ]; then
	echo "cos-since: repo or registry is unavailable" >&2
	exit 2
fi
case "$SEAT" in
	pl.*@"$(hostname)") ;;
	*) echo "cos-since: registry has no strict PL address for $repo_base" >&2; exit 2 ;;
esac

moved=0
now_local=$(date '+%H:%M:%S %Z')

echo "=== since $SINCE  (now $now_local) ==="

# 1. Mailbox movement. Read the strict repository seat through the public log,
#    then restore the compact timestamp prefix consumed by this script.
if ! log=$(sno reach log --as "$SEAT" 2>/dev/null |
	python3 -c '
import datetime
import sys

since = sys.argv[1].rstrip("Z")
for line in sys.stdin:
    fields = line.rstrip("\n").split("\t", 4)
    if len(fields) != 5:
        raise SystemExit(2)
    try:
        stamp = datetime.datetime.strptime(
            fields[2], "%Y-%m-%d %H:%M:%S"
        ).strftime("%Y%m%dT%H%M%SZ")
    except ValueError:
        raise SystemExit(2)
    if stamp.rstrip("Z") >= since:
        print(f"{stamp} {fields[3].strip()} {fields[4].strip()} ({fields[0]})")
' "$SINCE"); then
	echo "cos-since: Reach log failed for $SEAT" >&2
	exit 2
fi

if [ -n "$log" ]; then
	moved=1
	echo "--- mailbox: $(printf '%s\n' "$log" | wc -l) event(s) ---"
	printf '%s\n' "$log" | cut -c1-170
	echo "--- of those, FROM the lane (not our own cards) ---"
	printf '%s\n' "$log" | grep -Ei '^[0-9]+T[0-9]+Z (pl|executor)' | cut -c1-170 ||
		echo "    (none — every event since then is ours; the lane has not answered)"
else
	echo "--- mailbox: no events ---"
fi

# 2. Product executors. Argument POSITION, never a substring: a substring search
#    matches its own command line, and a dispatch file that quotes the launch
#    command makes a parked executor advertise a runner that does not exist.
#    `--sandbox read-only` is an adversarial review, never a product executor.
echo "--- product executors ---"
execs=$(ps -eo pid=,etime=,args= 2>/dev/null |
	awk '(($3 ~ /codex$/ && $4 == "exec") || ($3 ~ /claude$/ && $0 ~ / (-p|--print)( |$)/)) && $0 !~ /sandbox read-only/')
if [ -n "$execs" ]; then
	moved=1
	printf '%s\n' "$execs" | cut -c1-150
else
	echo "    none running"
fi

# 3. Turn lock. This only indicates work in progress; Reach registration
#    determines whether a card can land.
locks=$(ps -eo args= 2>/dev/null | grep -c "[C]odex is running an active turn")
echo "--- turn lock: $locks (Codex turns only; 0 = no observed Codex turn) ---"

if [ "$moved" -eq 1 ]; then exit 0; fi
echo "NOTHING MOVED since $SINCE."
exit 1
