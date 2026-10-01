#!/usr/bin/env bash
# review-receipt.sh — what the dispatched reviews actually covered.
#
#   review-receipt.sh [--since <YYYY-MM-DD|today|all>] [--journey <id>] [--check]
#
# Reads the review ledger and prints one row per invocation, then lists every
# run that did NOT produce a review. Reporting only: exit is 0 whatever it finds,
# unless --check is given, which exits 1 when anything is uncovered.
#
# Why this is a script and not an instruction to the reviewing agent: the agent
# cannot see per-wave outcomes, only whatever reached its stdout, and an agent
# asked to report its own coverage reports what it believes. The wrapper is the
# only thing that knows, and it already writes the ledger this reads.
#
# "Uncovered" is any of:
#   - a start line with no matching end line (the run was killed)
#   - an end line whose outcome is not success
#   - a refused line (cap reached, contract unmet, no concurrency slot)
set -Eeuo pipefail

STATS_FILE="${STATS_FILE:-$HOME/.local/state/codex-review-stats.jsonl}"
since="today"
journey=""
check=0

while [ $# -gt 0 ]; do
    case "$1" in
        --since)   [ $# -ge 2 ] || { echo "review-receipt: --since needs a value" >&2; exit 2; }
                   since="$2"; shift 2 ;;
        --journey) [ $# -ge 2 ] || { echo "review-receipt: --journey needs a value" >&2; exit 2; }
                   journey="$2"; shift 2 ;;
        --check)   check=1; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "review-receipt: unknown arg $1" >&2; exit 2 ;;
    esac
done

if [ ! -r "$STATS_FILE" ]; then
    echo "review-receipt: no ledger at $STATS_FILE — no reviews have run" >&2
    exit 0
fi

case "$since" in
    today) since_date="$(date +%F)" ;;
    all)   since_date="0000-00-00" ;;
    *)     since_date="$since" ;;
esac

python3 - "$STATS_FILE" "$since_date" "$journey" "$check" <<'PY'
import json, os, sys

path, since, journey, check = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"

rows = []
for line in open(path, encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        r = json.loads(line)
    except Exception:
        continue                      # a torn line must not hide the rest
    if r.get("ts", "")[:10] < since:
        continue
    if journey and r.get("journey") != journey:
        continue
    rows.append(r)

starts, ends, refused = {}, {}, []
for r in rows:
    ev = r.get("event")
    if ev == "start":
        starts[r["run"]] = r
    elif ev == "end":
        ends[r["run"]] = r
    elif ev == "refused":
        refused.append(r)

def names(r):
    t = r.get("targets") or []
    if not t:
        return f"({r.get('files', '?')} file(s), paths not recorded)"
    base = [os.path.basename(x) for x in t]
    shown = " ".join(base[:3])
    return shown + (f" +{len(base)-3}" if len(base) > 3 else "")

entries = []      # (sort_ts, status, round, cap, verdict, high, kind, targets, note)
uncovered = []

for run, s in starts.items():
    e = ends.get(run)
    rd, cap = s.get("round", 0), s.get("cap", 0)
    if e is None:
        entries.append((s["ts"], "KILLED", rd, cap, "-", "-", s.get("kind", "?"), names(s),
                        "started, never finished — no end line"))
        uncovered.append((names(s), "the run was killed before it finished; nothing was reviewed"))
    elif e.get("outcome") == "success":
        # A plan review with no probe file checked the document against itself
        # only. It ran, so it is covered — but not against reality, and the row
        # has to say so or the receipt overstates what was actually established.
        note = "" if (e.get("probe") is not False or e.get("kind") == "code") \
               else "no evidence file — claims unverified, not refuted"
        entries.append((s["ts"], "done", rd, cap, e.get("verdict", "?"),
                        e.get("high", "-"), e.get("kind", "?"), names(s), note))
    else:
        why = e.get("failure") or e.get("outcome", "failed")
        entries.append((s["ts"], "FAILED", rd, cap, "-", "-", e.get("kind", "?"), names(s), why))
        uncovered.append((names(s), f"the review failed: {why}"))

for r in refused:
    entries.append((r["ts"], "REFUSED", r.get("round", 0), r.get("cap", 0), "-", "-",
                    r.get("kind", "?"), names(r), f"{r.get('reason')}: {r.get('detail')}"))
    uncovered.append((names(r), f"nothing ran — {r.get('reason')}: {r.get('detail')}"))

entries.sort(key=lambda x: x[0])

print(f"=== REVIEW RECEIPT — {len(entries)} run(s) since {since if since != '0000-00-00' else 'the beginning'}"
      + (f", journey {journey}" if journey else "") + " ===")
if not entries:
    print("  (no reviews in this window)")
else:
    print(f"{'STATUS':8s} {'ROUND':6s} {'VERDICT':16s} {'HIGH':>4s}  {'KIND':5s} TARGETS")
    for ts, status, rd, cap, verdict, high, kind, tgt, note in entries:
        print(f"{status:8s} {f'{rd}/{cap}':6s} {str(verdict)[:16]:16s} {str(high):>4s}  {kind:5s} {tgt}"
              + (f"   ({note})" if note else ""))

print()
if uncovered:
    print(f"NOT ACTUALLY COVERED ({len(uncovered)}) — these must not be counted as reviewed:")
    for tgt, why in uncovered:
        print(f"  {tgt}: {why}")
else:
    print("NOT ACTUALLY COVERED (0) — every dispatched review produced a report.")

if check and uncovered:
    sys.exit(1)
PY
