#!/usr/bin/env bash
# convergence-watch.sh — supervise distance-to-close, not liveness.
# Activity alone is not health. A run whose remaining-work count stops shrinking is
# DIVERGING even if files are moving. The verdict is computed, not felt.
# Needs bash, python3 and flock.
#
# usage:
#   convergence-watch.sh record  --journey <id> --remaining <N> [--note "<txt>"]
#                                [--class closure|build|review] [--cycle <k>]
#       N = red tests + open blocking review findings + unchecked charter checklist
#       items. Use the same formula for every sample of one journey; known non-blocking
#       debt is excluded because it is tracked separately.
#       --class is fixed by the FIRST record; a later mismatch is an error. The default is
#       closure: the weaker build rule must be chosen explicitly in the dispatch.
#         closure = finish/verify/close/revert work; remaining may only decrease, so ANY
#                   increase is DIVERGING immediately.
#         build   = discovery may legitimately grow remaining; two consecutive growth
#                   steps are DIVERGING.
#         review  = a reviewer's findings count; advisory only, never DIVERGING.
#       --cycle coalesces samples: the same cycle id overwrites the previous sample (one
#       fix-verify cycle = one sample, so a report and a test batch over the same
#       unchanged slice are not counted as two flat steps).
#   convergence-watch.sh verdict --journey <id>
#       exit 0 CONVERGING    — last < previous
#       exit 4 WARNING       — one flat step (closure), or one flat/up step (build)
#       exit 3 DIVERGING     — closure: ANY increase, or two flat steps;
#                              build: two consecutive growth steps
#                              -> stop adding work now and close with what is done
#       exit 2 INSUFFICIENT  — fewer than 2 samples
#       exit 5 CLOSED        — last remaining == 0
# State: ~/.local/state/convergence/<journey>.jsonl (append-only; the verdict uses the
# last sample per cycle).
set -euo pipefail

case "${1:-}" in
  -h|--help) sed -n '2,/^# last sample per cycle/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

DIR="$HOME/.local/state/convergence"
mkdir -p "$DIR"

cmd="${1:-}"; shift || true
journey="" remaining="" note="" class="" cycle=""
while [ $# -gt 0 ]; do
  case "$1" in
    --journey)   journey="$2"; shift 2 ;;
    --remaining) remaining="$2"; shift 2 ;;
    --note)      note="$2"; shift 2 ;;
    --class)     class="$2"; shift 2 ;;
    --cycle)     cycle="$2"; shift 2 ;;
    *) echo "convergence-watch: unknown arg $1" >&2; exit 64 ;;
  esac
done
[ -n "$journey" ] || { echo "convergence-watch: --journey required" >&2; exit 64; }
# Reject (never normalize) unsafe journey ids: normalizing would let two
# distinct ids (deploy/blue vs deployblue) share one state file and swap
# verdicts between independent journeys.
case "$journey" in
  *[!a-zA-Z0-9_.-]*) echo "convergence-watch: journey id may only contain [a-zA-Z0-9_.-]: '$journey'" >&2; exit 64 ;;
esac
file="$DIR/$journey.jsonl"

_lock() { # per-journey lock: class lookup + append must be atomic (race:
  # two concurrent first-records could otherwise both win and split the class)
  command -v flock >/dev/null 2>&1 || { echo "convergence-watch: missing dependency: flock" >&2; exit 7; }
  exec 9>"$file.lock"
  flock -w 5 9 || { echo "convergence-watch: lock busy for $journey" >&2; exit 8; }
}

_stored_class() { # class from the FIRST VALID json line (never text-grep:
  # a malformed interrupted write must not be able to set the sticky class)
  [ -f "$file" ] || { printf ''; return; }
  python3 - "$file" <<'EOF'
import json, sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    try: o = json.loads(line)
    except ValueError: continue
    c = o.get("class")
    if c in ("closure", "build", "review"):
        print(c); break
EOF
}

case "$cmd" in
  record)
    case "$remaining" in ''|*[!0-9]*) echo "convergence-watch: --remaining must be a non-negative integer" >&2; exit 64 ;; esac
    remaining=$((10#$remaining))   # force base-10: "08" must be 8, never octal-invalid -> 0
    if [ -n "$cycle" ]; then
      case "$cycle" in *[!0-9]*) echo "convergence-watch: --cycle must be a non-negative integer" >&2; exit 64 ;; esac
      cycle=$((10#$cycle))
    fi
    case "$class" in ''|closure|build|review) : ;; *) echo "convergence-watch: --class must be closure|build|review" >&2; exit 64 ;; esac
    _lock
    stored="$(_stored_class)"
    if [ -z "$stored" ]; then
      # first record fixes the class; DEFAULT closure (fail-strict) — the
      # weaker build rule is never obtained by omission
      class="${class:-closure}"
    else
      if [ -n "$class" ] && [ "$class" != "$stored" ]; then
        echo "convergence-watch: class mismatch — '$journey' was registered as '$stored' (changing class requires a new journey + escalation)" >&2
        exit 6
      fi
      class="$stored"
    fi
    note="$(printf '%s' "$note" | tr '[:cntrl:]' ' ' | tr -d '\\"')"
    printf '{"ts":"%s","remaining":%d,"class":"%s","cycle":%s,"note":"%s"}\n' \
      "$(date -Is)" "$remaining" "$class" "${cycle:-null}" "$note" >> "$file"
    echo "recorded $journey remaining=$remaining class=$class${cycle:+ cycle=$cycle}"
    ;;
  verdict)
    [ -f "$file" ] || { echo "INSUFFICIENT (no samples)"; exit 2; }
    class="$(_stored_class)"; class="${class:-closure}"
    # effective series = latest sample per non-null cycle AT ITS ORIGINAL
    # POSITION (replacement works even when other samples intervene); null
    # cycles are each their own entry. Closure journeys additionally scan the
    # full effective history: any increase anywhere is a violation of the closure rule;
    # a later decrease (or even reaching 0) must not hide it.
    verdict_out="$(python3 - "$file" "$class" <<'EOF'
import json, sys
path, klass = sys.argv[1], sys.argv[2]
rows = []
for line in open(path):
    line = line.strip()
    if not line: continue
    try: o = json.loads(line)
    except ValueError: continue
    rows.append((o.get("cycle"), o.get("remaining")))
eff, pos = [], {}
for cyc, rem in rows:
    if cyc is not None and cyc in pos:
        eff[pos[cyc]] = rem          # replace in place, even non-adjacent
    else:
        if cyc is not None: pos[cyc] = len(eff)
        eff.append(rem)
n = len(eff)
if n == 0: print("2|INSUFFICIENT (no samples)"); sys.exit()
last = eff[-1]
# review = a reviewer's find-count series, not a journey distance-to-close. Findings
# legitimately grow across rounds (a plan review finds 0, a code review finds 2), so it
# never emits DIVERGING; it is advisory only. An executor stops only on its own
# closure|build series.
if klass == "review":
    if last == 0: print("5|CLOSED (review find-count 0 — clean)"); sys.exit()
    if n < 2: print(f"0|REVIEW ({last} findings; advisory, NOT a journey stop signal)"); sys.exit()
    prev = eff[-2]
    trend = "shrinking" if last < prev else ("flat" if last == prev else "still surfacing")
    print(f"0|REVIEW ({prev} -> {last}, {trend}; advisory find-count, NOT a journey stop signal)")
    sys.exit()
grew = next(((a, b) for a, b in zip(eff, eff[1:]) if b > a), None)
if klass == "closure" and grew:
    print(f"3|DIVERGING (remaining grew {grew[0]} -> {grew[1]} on a closure journey"
          + ("; series later reached 0 — record the violation in the close audit" if last == 0 else "")
          + ") — stop adding work now and close with what is done"); sys.exit()
if last == 0: print("5|CLOSED (remaining=0)"); sys.exit()
if n < 2: print(f"2|INSUFFICIENT (1 sample, remaining={last})"); sys.exit()
prev = eff[-2]
if last < prev: print(f"0|CONVERGING ({prev} -> {last})"); sys.exit()
if klass == "build":
    # build plateaus are LEGAL (working a hard item holds the count flat);
    # build diverges only on GROWTH two steps in a row.
    if n >= 3 and eff[-3] < prev < last:
        print(f"3|DIVERGING ({eff[-3]} -> {prev} -> {last}; two consecutive growth steps on a build journey) — stop now"); sys.exit()
    if last > prev:
        print(f"4|WARNING ({prev} -> {last} grew on build; one more growth step = DIVERGING)"); sys.exit()
    print(f"0|HOLDING ({prev} -> {last} build plateau — legal; judge progress by artifact movement, not this series)"); sys.exit()
if n >= 3 and prev >= eff[-3]:
    print(f"3|DIVERGING ({eff[-3]} -> {prev} -> {last}; two non-shrinking steps) — stop now"); sys.exit()
print(f"4|WARNING ({prev} -> {last} not shrinking; one more non-shrinking step = DIVERGING)")
EOF
)"
    rc="${verdict_out%%|*}"; msg="${verdict_out#*|}"
    echo "$msg"; exit "$rc"
    ;;
  *) sed -n '2,/^# last sample per cycle/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64 ;;
esac
