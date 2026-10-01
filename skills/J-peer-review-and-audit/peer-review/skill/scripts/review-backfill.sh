#!/usr/bin/env bash
# review-backfill.sh — recover past Codex-reviewer reports from Codex's own session logs.
#
#   review-backfill.sh [--since <YYYY-MM-DD>] [--dry-run]
#
# If report files were lost, the findings can still be recovered — every Codex
# review's final message is in ~/.codex/sessions, which is where this reads them
# from. Recovery is a scan, not a reconstruction.
#
# What it does: finds every rollout whose prompt is one of the adversarial-review
# templates, writes its final report into the archive under the date it actually
# ran, then hands the lot to review-findings.sh in one call. Re-running is safe —
# findings are keyed by file plus title, so a second pass updates rows instead of
# duplicating them, and an already-written report file is not rewritten.
set -Eeuo pipefail

SESSIONS="${CODEX_SESSIONS_DIR:-$HOME/.codex/sessions}"
ARCHIVE="${REVIEW_ARCHIVE_DIR:-$HOME/.local/state/codex-reviews}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
since=""
dry=0

while [ $# -gt 0 ]; do
    case "$1" in
        --since)   [ $# -ge 2 ] || { echo "review-backfill: --since needs a date" >&2; exit 2; }
                   since="$2"; shift 2 ;;
        --dry-run) dry=1; shift ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "review-backfill: unknown arg $1" >&2; exit 2 ;;
    esac
done
[ -d "$SESSIONS" ] || { echo "review-backfill: no session logs at $SESSIONS" >&2; exit 1; }
[ -n "$since" ] || since="$(date -d '30 days ago' +%F 2>/dev/null || date -v-30d +%F)"

echo "[review-backfill] scanning $SESSIONS for reviews since $since" >&2

manifest="$(mktemp)"
trap 'rm -f -- "$manifest"' EXIT

python3 - "$SESSIONS" "$ARCHIVE" "$since" "$dry" "$manifest" <<'PY'
import json, os, sys, glob, time

sessions, archive, since, dry, manifest = sys.argv[1:6]
dry = dry == "1"

paths = sorted(glob.glob(os.path.join(sessions, "*", "*", "*", "*.jsonl")))
print(f"[review-backfill] {len(paths)} session file(s) to scan", file=sys.stderr)

t0 = time.time()
written = skipped = scanned = 0
out_paths = []
for i, p in enumerate(paths):
    if i and i % 1000 == 0:
        el = time.time() - t0
        print(f"[review-backfill]   {i}/{len(paths)}  {el:.0f}s  {written} recovered",
              file=sys.stderr, flush=True)
    base = os.path.basename(p)
    # rollout-<timestamp>-<uuid>.jsonl — cheap date filter before reading
    day = base[8:18] if base.startswith("rollout-") else ""
    if day and day < since:
        continue
    scanned += 1
    is_review = False
    last = None
    ts = day
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if '"user_message"' in line and not is_review:
                    try:
                        msg = json.loads(line)["payload"].get("message", "")
                    except Exception:
                        continue
                    head = msg[:400].lower()
                    if "adversarial" in head and "review" in head:
                        is_review = True
                elif '"agent_message"' in line:
                    try:
                        rec = json.loads(line)
                        last = rec["payload"].get("message", "")
                        ts = rec.get("timestamp", ts)[:10] or ts
                    except Exception:
                        pass
    except OSError:
        continue
    if not is_review or not last:
        continue
    sid = base.rsplit("-", 5)[-1].replace(".jsonl", "") if "-" in base else base
    dest_dir = os.path.join(archive, ts or "unknown-date")
    dest = os.path.join(dest_dir, f"backfill-{sid}.md")
    out_paths.append(dest)
    if os.path.exists(dest):
        skipped += 1
        continue
    if dry:
        written += 1
        continue
    os.makedirs(dest_dir, exist_ok=True)
    with open(dest, "w", encoding="utf-8") as f:
        f.write(last)
    written += 1

with open(manifest, "w") as f:
    for p_ in out_paths:
        f.write(p_ + "\n")
print(f"[review-backfill] scanned {scanned} session(s) in window: "
      f"{written} report(s) {'would be ' if dry else ''}recovered, {skipped} already present",
      file=sys.stderr)
PY

if [ "$dry" = 1 ]; then
    echo "[review-backfill] dry run — nothing written, no findings recorded" >&2
    exit 0
fi

count="$(wc -l < "$manifest" | tr -d ' ')"
if [ "$count" = 0 ]; then
    echo "[review-backfill] no reports in the window; nothing to record" >&2
    exit 0
fi

# One call, not one per report: the ledger is rewritten whole on each save.
# shellcheck disable=SC2046 # the manifest holds one path per line, no spaces
xargs -a "$manifest" -d '\n' bash "$HERE/review-findings.sh" record --kind recovered
