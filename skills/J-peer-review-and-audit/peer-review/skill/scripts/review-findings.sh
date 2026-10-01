#!/usr/bin/env bash
# review-findings.sh — the durable home for what reviews actually found.
#
#   review-findings.sh record <report.md> [--run <id>] [--scope <id>] [--kind <k>]
#   review-findings.sh list [--status <s>] [--file <substr>] [--severity <s>] [--limit <n>]
#   review-findings.sh set <id-prefix> <accepted|rejected|superseded|undecided> [note]
#   review-findings.sh prior <file> [<file>...]
#
# Why this exists. The invocation ledger counts findings but does not retain their
# text or prior decisions. A repeated review can raise a settled finding again.
#
# The invocation ledger (codex-review-stats.jsonl) answers "did this review
# run?". This file answers "what did it find, and what did we decide?" — a
# different grain, keyed by reviewed file, so it is a separate ledger rather
# than more columns on that one.
#
# A finding's identity is its file plus its normalized title, so the same
# problem raised in round 3 updates the round-1 row instead of appearing again.
# `status` is the user's column: nothing here sets it to anything but
# `undecided`.
set -Eeuo pipefail

FINDINGS_FILE="${FINDINGS_FILE:-$HOME/.local/state/codex-reviews/findings.jsonl}"
mkdir -p "$(dirname "$FINDINGS_FILE")" 2>/dev/null || true
touch "$FINDINGS_FILE" 2>/dev/null || true

[ $# -ge 1 ] || { sed -n '2,20p' "$0"; exit 2; }
cmd="$1"; shift

case "$cmd" in
    record|list|set|prior) ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "review-findings: unknown command '$cmd'" >&2; exit 2 ;;
esac

python3 - "$FINDINGS_FILE" "$cmd" "$@" <<'PY'
import hashlib, json, os, re, sys, datetime

store, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3:]

def load():
    rows = []
    if os.path.exists(store):
        for line in open(store, encoding="utf-8", errors="replace"):
            line = line.strip()
            if line:
                try:
                    rows.append(json.loads(line))
                except Exception:
                    pass          # one torn line must not hide the rest
    return rows

def save(rows):
    # `.tmp` is per-process: two reviewers finishing together would otherwise
    # write the same temp file and one would rename the other's half.
    tmp = f"{store}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    os.replace(tmp, store)        # rewritten atomically; never a half file

class Lock:
    """Whole-file read-modify-write, so concurrent reviews cannot lose findings.

    Up to MAX_PARALLEL reviews run at once and each rewrites this ledger whole;
    without the lock the later writer's copy — loaded before the earlier one
    saved — silently drops the earlier review's findings entirely."""
    def __init__(self, path):
        self.path = path + ".lock"
        self.fh = None
    def __enter__(self):
        try:
            import fcntl
            self.fh = open(self.path, "w")
            fcntl.flock(self.fh, fcntl.LOCK_EX)
        except Exception:
            self.fh = None        # no flock available: proceed rather than fail
        return self
    def __exit__(self, *a):
        if self.fh:
            try:
                import fcntl
                fcntl.flock(self.fh, fcntl.LOCK_UN)
            finally:
                self.fh.close()
        return False

def opt(name, default=None):
    return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else default

# A finding line, per the prompts' output contract:
#   code:  - [high] [fix-now] title (path:12-20, confidence 0.85)
#   plan:  - [high] title (path:12-20, confidence 0.85)
HEAD = re.compile(r'^-\s+\[(critical|high|medium|low)\]\s*(?:\[(fix-now|debt|out-of-context)\]\s*)?(.*)$',
                  re.IGNORECASE)
CONF = re.compile(r'^(.*?),\s*confidence\s*([0-9.]+)\s*$', re.IGNORECASE | re.DOTALL)

def split_location(rest):
    """Peel the trailing (location[, confidence]) off a finding line.

    A plain regex for the tail loses every finding whose path contains brackets of
    its own — Next.js route groups like app/[lang]/(shop)/x.tsx — and would
    mis-split any title that contains parentheses. Walking back from the final
    ')' to its balanced '(' handles both."""
    rest = rest.strip()
    if not rest.endswith(")"):
        return rest, ""
    depth = 0
    for i in range(len(rest) - 1, -1, -1):
        if rest[i] == ")":
            depth += 1
        elif rest[i] == "(":
            depth -= 1
            if depth == 0:
                return rest[:i].strip(), rest[i + 1:-1].strip()
    return rest, ""

def norm(title):
    return re.sub(r'[^a-z0-9 ]', '', title.lower()).strip()

def parse(report_path):
    out = []
    try:
        text = open(report_path, encoding="utf-8", errors="replace").read()
    except OSError:
        return out
    for line in text.splitlines():
        m = HEAD.match(line.strip())
        if not m:
            continue
        sev, binn, rest = m.groups()
        title, inner = split_location(rest)
        conf = 0.0
        cm = CONF.match(inner)
        if cm:
            inner, conf = cm.group(1).strip(), float(cm.group(2))
        if not title or not inner:
            continue                       # a bullet with no location is prose
        # the first location wins as the owning file; the rest stay in `loc`
        path = inner.split(",")[0].split(";")[0].split(":")[0].strip().strip("`")
        out.append({
            "severity": sev.lower(),
            "class": (binn or "").lower(),
            "title": title.strip(),
            "file": path,
            "loc": inner,
            "confidence": conf,
        })
    return out

if cmd == "record":
    # Several reports in one call: the backfill has thousands of them, and one
    # process per report would reload and rewrite the whole ledger each time.
    flagged = set()
    for name in ("--run", "--scope", "--kind", "--date"):
        if name in args:
            i = args.index(name)
            flagged.add(i); flagged.add(i + 1)
    reports = [a for i, a in enumerate(args) if i not in flagged and not a.startswith("--")]
    if not reports:
        print("review-findings record: needs at least one report file", file=sys.stderr); sys.exit(2)
    run, scope, kind = opt("--run", ""), opt("--scope", ""), opt("--kind", "")
    default_date = opt("--date") or datetime.date.today().isoformat()
    lock = Lock(store); lock.__enter__()
    rows = load()
    by_id = {r["id"]: r for r in rows}
    order = {"low": 0, "medium": 1, "high": 2, "critical": 3}
    added = updated = 0
    for report in reports:
        # A backfilled report is dated by its own archive folder, not by today,
        # or every recovered finding would claim it was first seen at recovery.
        day = default_date
        parent = os.path.basename(os.path.dirname(os.path.abspath(report)))
        if re.fullmatch(r'\d{4}-\d{2}-\d{2}', parent):
            day = parent
        for f in parse(report):
            fid = hashlib.sha1(f"{f['file']}|{norm(f['title'])}".encode()).hexdigest()[:12]
            if fid in by_id:
                r = by_id[fid]
                r["times_seen"] = r.get("times_seen", 1) + 1
                r["last_seen"] = max(r.get("last_seen", day), day)
                r["first_seen"] = min(r.get("first_seen", day), day)
                if run:
                    r["last_run"] = run
                # severity can be re-judged upward between rounds; keep the worst
                if order.get(f["severity"], 0) > order.get(r.get("severity", "low"), 0):
                    r["severity"] = f["severity"]
                updated += 1
            else:
                r = {
                    "id": fid, "first_seen": day, "last_seen": day, "times_seen": 1,
                    "file": f["file"], "loc": f["loc"], "severity": f["severity"],
                    "class": f["class"], "title": f["title"], "confidence": f["confidence"],
                    "status": "undecided", "note": "",
                    "scope": scope, "kind": kind, "first_run": run, "last_run": run,
                    "report": os.path.abspath(report),
                }
                rows.append(r); by_id[fid] = r
                added += 1
    save(rows)
    lock.__exit__()
    print(f"[review-findings] {len(reports)} report(s): {added} new, {updated} already known "
          f"({len(rows)} findings on record)", file=sys.stderr)

elif cmd == "list":
    rows = load()
    st, fl, sv = opt("--status"), opt("--file"), opt("--severity")
    limit = int(opt("--limit", "0") or 0)
    if st: rows = [r for r in rows if r.get("status") == st]
    if fl: rows = [r for r in rows if fl in r.get("file", "")]
    if sv: rows = [r for r in rows if r.get("severity") == sv]
    order = {"critical": 0, "high": 1, "medium": 2, "low": 3}
    rows.sort(key=lambda r: (order.get(r.get("severity"), 9), -r.get("times_seen", 1)))
    if limit: rows = rows[:limit]
    if not rows:
        print("(no findings on record match)"); sys.exit(0)
    print(f"{'ID':12s} {'SEVERITY':9s} {'STATUS':11s} {'SEEN':>4s}  {'FILE':38s} TITLE")
    for r in rows:
        print(f"{r['id']:12s} {r.get('severity',''):9s} {r.get('status',''):11s} "
              f"{r.get('times_seen',1):>4d}  {r.get('file','')[:38]:38s} {r.get('title','')[:70]}")
    undecided = sum(1 for r in load() if r.get("status") == "undecided")
    print(f"\n{undecided} finding(s) still undecided — `review-findings.sh set <id> <accepted|rejected|superseded>`")

elif cmd == "set":
    if len(args) < 2:
        print("review-findings set: needs <id-prefix> <status> [note]", file=sys.stderr); sys.exit(2)
    prefix, status = args[0], args[1]
    note = " ".join(args[2:])
    if status not in ("accepted", "rejected", "superseded", "undecided"):
        print(f"review-findings set: bad status '{status}'", file=sys.stderr); sys.exit(2)
    lock = Lock(store); lock.__enter__()
    rows = load()
    hit = [r for r in rows if r["id"].startswith(prefix)]
    if not hit:
        print(f"review-findings set: no finding starts with '{prefix}'", file=sys.stderr); sys.exit(1)
    if len(hit) > 1:
        print(f"review-findings set: '{prefix}' matches {len(hit)} findings", file=sys.stderr); sys.exit(1)
    hit[0]["status"] = status
    if note:
        hit[0]["note"] = note
    hit[0]["decided_on"] = datetime.date.today().isoformat()
    save(rows)
    lock.__exit__()
    print(f"{hit[0]['id']} -> {status}: {hit[0]['title'][:70]}", file=sys.stderr)

elif cmd == "prior":
    # Bounded on purpose. Payload size is the one live correlate of a review
    # coming back empty, so settled history is capped rather than replayed whole, and
    # only rulings a reviewer should not re-litigate are worth the bytes.
    MAX_ROWS, MAX_CHARS = 40, 4000
    want = [a for a in args if not a.startswith("--")]
    rows = [r for r in load()
            if r.get("status") in ("rejected", "superseded")
            and any(r.get("file", "") == w or os.path.basename(r.get("file", "")) == os.path.basename(w)
                    for w in want)]
    order = {"critical": 0, "high": 1, "medium": 2, "low": 3}
    rows.sort(key=lambda r: order.get(r.get("severity"), 9))
    if not rows:
        sys.exit(0)
    out, n = [], 0
    for r in rows[:MAX_ROWS]:
        line = (f"- [{r['severity']}] {r['title']} ({r['loc']}) — previously "
                f"{r['status']}{': ' + r['note'] if r.get('note') else ''}")
        if n + len(line) > MAX_CHARS:
            out.append(f"- ... {len(rows) - len(out)} further settled findings omitted (size cap)")
            break
        out.append(line); n += len(line)
    print("<prior_rulings>")
    print("These were raised by an earlier review of the same files and ruled on. "
          "Do not report them again as new; raise one only with new evidence, and say what changed.")
    print("\n".join(out))
    print("</prior_rulings>")
PY

