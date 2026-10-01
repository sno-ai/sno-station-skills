#!/usr/bin/env bash
# todo.sh — THE write path for a repo's TODO.md board.
#
# This is the only writer of rows in TODO.md (the PL and COS do not edit rows by hand).
# It enforces: one list, one line per row, closed rows leave immediately, no second open
# list, no narrative on the board.
# Needs python3 and flock; close records into <repo>/ai-doc/JOURNAL/routing-ledger.jsonl.
#
# Reading needs no command — the file is already in the shape an agent wants.
#
# Two constraints come from cos-roster.sh (in the cos skill), which a supervisor runs
# at boot and at every tick:
#   1. Under the OPEN heading it accepts list items and blank lines. ANY other
#      non-empty line makes it report the whole board UNPARSED. So the renderer
#      emits `- ` lines and nothing else there; the checksum comment goes ABOVE
#      the heading, where explanation already lives.
#   2. It prints only the first 150 characters of each item. So the renderer
#      fixes field ORDER — name, state, id first — rather than letting the
#      author choose one that pushes the state out of view.
#
# Staleness is deliberately NOT rendered into the file. It is a function of the
# clock, and a file that changes because a day passed cannot be checksummed.
# `verified:` is stored; `check` computes the age.
set -Eeuo pipefail

readonly ROW_CAP=25
readonly STALE_DAYS="${TODO_STALE_DAYS:-15}"
readonly LOCK_WAIT=10

die() {
    local code="$1"
    shift
    printf 'todo: %s\n' "$*" >&2
    exit "$code"
}

usage() {
    cat <<'USAGE'
usage: todo.sh <command> [--repo <dir>] ...

  init   [--north-star <text>]                          create the board; never overwrites
  add    --name <text> --prd <path|none> --state <state> --decision high|low
         [--why-now <text>] [--journey <id>] [--callsign <name>] [--budget <text>]
         [--awaiting <text>] [--held-because <text>] [--command <what you ran>]
  set    <id> [--name|--prd|--state|--decision|--why-now|--journey|--callsign
         |--budget|--awaiting|--held-because <value>] ...   (never --verified, never --id)
  move   <id> (--before <id> | --after <id> | --top yes | --bottom yes)   priority order
  verify <id> --command <what you actually ran>
  note   <id> (--text <text> | --file <path>)
  close  <id> --outcome <text> [--evidence <path>]
  check
  archive-tail [--confirm-no-owed-work yes]   refuses while the tail holds list items

states: running queued ranked-next not-started blocked-on-owner owner-fyi

exit: 0 ok · 64 usage · 65 board invalid or check found violations
      66 target missing (repo, board, id) · 69 unavailable (python3, lock)
USAGE
}

# The verb is the first bare word and --repo may sit on either side of it: both
# orders get typed, and a positional rule that only one works is a trap rather
# than a contract. --repo is consumed here so the lock is taken before python
# opens anything.
verb=''
repo="$PWD"
args=()
while (($# > 0)); do
    case "$1" in
        -h | --help | help)
            usage
            exit 0
            ;;
        --repo)
            (($# >= 2)) || die 64 '--repo needs a directory'
            repo="$2"
            shift 2
            ;;
        -*)
            args+=("$1")
            shift
            ;;
        *)
            if [[ -z "$verb" ]]; then
                verb="$1"
            else
                args+=("$1")
            fi
            shift
            ;;
    esac
done

case "$verb" in
    init | add | set | move | verify | note | close | check | archive-tail) ;;
    '')
        usage >&2
        exit 64
        ;;
    *)
        usage >&2
        die 64 "unknown command '$verb'"
        ;;
esac

missing=()
for tool in python3 flock; do command -v "$tool" >/dev/null 2>&1 || missing+=("$tool"); done
((${#missing[@]} == 0)) || die 69 "missing dependency: ${missing[*]} (needs Linux with python3 and flock)"

[[ -d "$repo" ]] || die 66 "no such repo directory: $repo"
repo="$(cd -- "$repo" && pwd)"
board="$repo/TODO.md"

# The lock is the board's, held across read-validate-write. It is a separate
# stable path on purpose: the write finishes with a rename, so a lock held on
# TODO.md's own inode would be a lock on a file that no longer has that name.
lock="$board.lock"
exec 9>>"$lock" || die 69 "cannot open the board lock: $lock"
flock -w "$LOCK_WAIT" 9 || die 69 "another writer holds the board lock after ${LOCK_WAIT}s: $lock"

now="${TODO_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

python3 - "$verb" "$repo" "$board" "$now" "$ROW_CAP" "$STALE_DAYS" "${args[@]+"${args[@]}"}" <<'PY'
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

VERB, REPO, BOARD, NOW, ROW_CAP, STALE_DAYS = (
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]), int(sys.argv[6]))
ARGS = sys.argv[7:]
LEDGER = os.path.join(REPO, "ai-doc", "JOURNAL", "routing-ledger.jsonl")
DETAIL_DIR = os.path.join("ai-doc", "ACTIVE", "PL", "board")

E_USAGE, E_DATA, E_MISSING = 64, 65, 66
SEP = " · "
OPEN_HEADING = re.compile(r"^(#+)\s*OPEN\s*#*\s*$", re.IGNORECASE)
HEADING = re.compile(r"^(#+)\s")
CHECKSUM = re.compile(r"^<!-- board-checksum: ")
ID_RE = re.compile(r"^b-(\d{4,})$")
STATES = ("running", "queued", "ranked-next", "not-started", "blocked-on-owner", "owner-fyi")
DECISIONS = ("high", "low")
UNVERIFIED = "never"
# `running` decays faster than every other state, so it gets its own, shorter staleness
# window than STALE_DAYS. One day, not zero: the field is a date, so "today only" would
# fail a row verified last night that is still working.
RUNNING_STALE_DAYS = 1

# Rendered in this order, always. `verified` is stamped only by `verify`.
FIELDS = ("state", "id", "prd", "decision", "verified",
          "journey", "callsign", "budget", "why-now", "held-because", "awaiting", "detail")
REQUIRED = ("state", "id", "prd", "decision", "verified")
SETTABLE = ("name", "prd", "state", "decision", "why-now",
            "journey", "callsign", "budget", "awaiting", "held-because")
# Caps keep name+state+id inside the 150 characters cos-roster.sh displays, and
# push anything longer into the detail file, which is where narrative belongs.
LIMITS = {"name": 80, "prd": 200, "why-now": 160, "awaiting": 200, "held-because": 160,
          "journey": 60, "callsign": 40, "budget": 60, "outcome": 200, "evidence": 200,
          "command": 300, "text": 4000}


def die(code, message):
    sys.stderr.write("todo: %s\n" % message)
    raise SystemExit(code)


def flags(spec):
    """Parse --key value pairs. Unknown or repeated flags are a usage error."""
    out = {}
    rest = []
    i = 0
    while i < len(ARGS):
        a = ARGS[i]
        if a.startswith("--"):
            key = a[2:]
            if key not in spec:
                die(E_USAGE, "unknown flag --%s for '%s'" % (key, VERB))
            if key in out:
                die(E_USAGE, "--%s given twice" % key)
            if i + 1 >= len(ARGS):
                die(E_USAGE, "--%s needs a value" % key)
            out[key] = ARGS[i + 1]
            i += 2
        else:
            rest.append(a)
            i += 1
    return out, rest


def clean(key, value):
    """A field value is one line, free of the separator, within its cap."""
    if value != value.strip():
        die(E_DATA, "%s has leading or trailing whitespace" % key)
    if not value:
        die(E_DATA, "%s is empty" % key)
    if "\n" in value or "\t" in value:
        die(E_DATA, "%s must be a single line" % key)
    if "·" in value:
        die(E_DATA, "%s must not contain the field separator '·'" % key)
    if "**" in value:
        die(E_DATA, "%s must not contain '**'" % key)
    cap = LIMITS.get(key, 200)
    if len(value) > cap:
        die(E_DATA, "%s is %d characters, over the %d cap — put the detail in the "
                    "detail file with: todo.sh note <id> --text '...'" % (key, len(value), cap))
    return value


def today():
    return NOW[:10]


def parse_row(line):
    """A row is exactly one line. None means this line is not a legal row."""
    if not line.startswith("- **"):
        return None
    end = line.find("**" + SEP, 4)
    if end < 0:
        return None
    row = {"name": line[4:end]}
    if not row["name"] or "**" in row["name"]:
        return None
    for seg in line[end + 2 + len(SEP):].split(SEP):
        key, sep, value = seg.partition(": ")
        if not sep or key not in FIELDS or key in row or not value:
            return None
        row[key] = value
    for key in REQUIRED:
        if key not in row:
            return None
    if row["state"] not in STATES or row["decision"] not in DECISIONS:
        return None
    if not ID_RE.match(row["id"]):
        return None
    return row


def render_row(row):
    parts = ["- **%s**" % row["name"]]
    parts += ["%s: %s" % (k, row[k]) for k in FIELDS if row.get(k)]
    return SEP.join(parts)


def read_board():
    """(header, rows, raw_rows, tail, blank_lines_seen). Splits at the OPEN heading."""
    if not os.path.exists(BOARD):
        return None
    try:
        with open(BOARD, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
    except OSError as exc:
        die(E_MISSING, "cannot read the board: %s" % exc)
    if lines and lines[-1] == "":
        lines.pop()

    header, body, tail, depth = [], [], [], None
    for line in lines:
        if depth is None:
            m = OPEN_HEADING.match(line)
            if m:
                depth = len(m.group(1))
                header.append(line)
            elif not CHECKSUM.match(line):
                header.append(line)
            continue
        if tail:
            tail.append(line)
            continue
        h = HEADING.match(line)
        if h and len(h.group(1)) <= depth:
            tail.append(line)
            continue
        body.append(line)
    if depth is None:
        die(E_DATA, "TODO.md has no heading named OPEN, so there is no board to write to. "
                    "Every supervisor's roll call reports this repo as NO-OPEN-SECTION.")
    while body and not body[-1].strip():
        body.pop()
    return {"header": header, "body": body, "tail": tail}


def rows_of(board):
    """Parsed rows plus the lines that could not be parsed as rows."""
    rows, bad = [], []
    for line in board["body"]:
        if not line.strip():
            continue
        row = parse_row(line)
        if row is None:
            bad.append(line)
        else:
            rows.append(row)
    return rows, bad


def checksum(rows):
    blob = "\n".join(render_row(r) for r in rows)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:16]


def stored_stamp():
    """(checksum, [ids]) from the comment above OPEN. (None, None) if never written."""
    try:
        with open(BOARD, encoding="utf-8") as fh:
            for line in fh:
                if CHECKSUM.match(line):
                    digest = re.search(r"sha256:([0-9a-f]+)", line)
                    ids = re.search(r"ids: ([b0-9,\-]+)", line)
                    listed = [] if not ids or ids.group(1) == "-" else ids.group(1).split(",")
                    return (digest.group(1) if digest else None, listed)
    except OSError:
        return (None, None)
    return (None, None)


def write_board(board, rows):
    """Atomic whole-file render. The only place this file is produced.

    Row ORDER is preserved exactly as given, never sorted. The order IS the
    priority — "the top row that is not running or blocked is the default next
    block" — so sorting by id would silently make creation order decide what gets
    worked next, and no command could express a priority at all.
    """
    seen = set()
    for row in rows:
        if row["id"] in seen:
            die(E_DATA, "duplicate row id %s" % row["id"])
        seen.add(row["id"])
        for key in REQUIRED:
            if not row.get(key):
                die(E_DATA, "row %s is missing %s" % (row["id"], key))

    # The id list is what makes a hand DELETION detectable. A checksum alone says
    # "something changed"; it cannot tell an edited row from a removed one, and the
    # removed one is the failure that matters.
    stamp = ("<!-- board-checksum: sha256:%s · rows: %d · ids: %s · written by todo.sh; "
             "rows are not hand-edited -->"
             % (checksum(rows), len(rows), ",".join(r["id"] for r in rows) or "-"))
    header = [l for l in board["header"] if not CHECKSUM.match(l)]
    above = header[:-1]
    while above and not above[-1].strip():
        above.pop()
    out = above + ["", stamp] + header[-1:]
    out += [""] + [render_row(r) for r in rows]
    if board["tail"]:
        out += [""] + board["tail"]

    directory = os.path.dirname(BOARD) or "."
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".TODO.md.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write("\n".join(out).rstrip("\n") + "\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, BOARD)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def load_for_write():
    """Read, and decide what to do about a hand edit.

    The rule is asymmetric on purpose, and it is the same asymmetry as everywhere
    else in this tool: **recording work is never refused, losing it always is.**

      added or modified by hand, still parses -> adopted and re-stamped, loudly
      a row that does not parse              -> write stops, file untouched
      a row that has DISAPPEARED             -> write stops, the id is named

    The last case is why the stamp carries the id list. Without it a hand deletion
    and a hand edit look identical — one warning line on stderr — and the next
    ordinary write would make the deletion permanent with every later `check`
    passing.
    """
    board = read_board()
    if board is None:
        die(E_MISSING, "no TODO.md in %s — write the board first with: todo.sh init" % REPO)
    rows, bad = rows_of(board)
    if bad:
        sys.stderr.write("todo: these lines under OPEN are not legal rows:\n")
        for line in bad[:5]:
            sys.stderr.write("  %s\n" % line[:150])
        die(E_DATA, "fix or delete them, then rerun. A row is one line:\n"
                    "  - **<name>**%sstate: <state>%sid: b-0001%sprd: <path>%s"
                    "decision: high%sverified: YYYY-MM-DD" % (SEP, SEP, SEP, SEP, SEP))

    stored, listed = stored_stamp()
    present = {r["id"] for r in rows}
    if stored is None:
        if rows:
            sys.stderr.write("todo: this board carries no checksum yet, so it was last "
                             "written by hand; its %d rows parse and are adopted.\n" % len(rows))
        return board, rows
    missing = [i for i in listed if i not in present]
    if missing:
        die(E_DATA, "these rows were on the board at the last write and are gone now: %s. "
                    "A row leaves only through `close`. Read the old line with `git show "
                    "HEAD:TODO.md` and put it back with `todo.sh add` — do NOT `git "
                    "checkout` the whole file, which would discard every other row written "
                    "since the last commit. Nothing was written." % ", ".join(missing))
    if stored != checksum(rows):
        sys.stderr.write("todo: the board was hand-edited since the last write — no row was "
                         "lost, so the %d rows are adopted and re-stamped.\n" % len(rows))
    return board, rows


def ledger_ids():
    """Ids already spent, including on rows that have closed and left the file.

    The ledger may carry more than one event shape, written by other tools. This reads
    only its own `board_closed` events
    and skips everything else, including lines it cannot parse — a foreign or
    corrupt line must not be able to stop a board write.
    """
    if not os.path.exists(LEDGER):
        return set()
    out = set()
    try:
        with open(LEDGER, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or '"board_closed"' not in line:
                    continue
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if event.get("event") == "board_closed" and isinstance(event.get("id"), str):
                    out.add(event["id"])
    except OSError as exc:
        # Fail closed: without the ledger a fresh id cannot be proven fresh, and a
        # reused id silently re-points every close that ever quoted the old one.
        die(E_MISSING, "cannot read the routing ledger, so no id can be proven unused: %s" % exc)
    return out


def next_id(rows):
    used = {r["id"] for r in rows} | ledger_ids()
    highest = max((int(ID_RE.match(i).group(1)) for i in used if ID_RE.match(i)), default=0)
    return "b-%04d" % (highest + 1)


def find(rows, row_id):
    for row in rows:
        if row["id"] == row_id:
            return row
    die(E_MISSING, "no row with id %s on the board" % row_id)


def detail_path(row_id):
    return os.path.join(DETAIL_DIR, "%s.md" % row_id)


def append_detail(row, text):
    path = os.path.join(REPO, detail_path(row["id"]))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    new = not os.path.exists(path)
    with open(path, "a", encoding="utf-8") as fh:
        if new:
            fh.write("# %s — %s\n\n"
                     "Detail for one TODO.md row. The board carries one line; everything\n"
                     "that would not fit is here, newest entry last.\n" % (row["id"], row["name"]))
        fh.write("\n## %s\n\n%s\n" % (NOW, text.strip()))
    row["detail"] = detail_path(row["id"])


def one_id(rest):
    if len(rest) != 1:
        die(E_USAGE, "'%s' takes exactly one row id" % VERB)
    if not ID_RE.match(rest[0]):
        die(E_USAGE, "'%s' is not a row id (expected b-0001)" % rest[0])
    return rest[0]


def cmd_add():
    opts, rest = flags(("name", "prd", "state", "decision", "why-now", "command",
                        "journey", "callsign", "budget", "awaiting", "held-because"))
    if rest:
        die(E_USAGE, "add takes flags only, got: %s" % " ".join(rest))
    for key in ("name", "prd", "state", "decision"):
        if key not in opts:
            die(E_USAGE, "add needs --%s" % key)
    if opts["state"] not in STATES:
        die(E_USAGE, "state must be one of: %s" % " ".join(STATES))
    if opts["decision"] not in DECISIONS:
        die(E_USAGE, "decision must be high or low")

    board, rows = load_for_write()
    proof = opts.pop("command", None)
    row = {k: clean(k, v) for k, v in opts.items()}
    row["id"] = next_id(rows)
    # A new row is somebody's assertion, not a disk check, so `add` claims nothing.
    # Adding a row and having the freshness gate pass for 15 days on the strength of
    # that is how an unverified claim governs scheduling. `--command` is the same
    # bargain `verify` offers: stamp the date, carry what produced it.
    row["verified"] = today() if proof else UNVERIFIED
    rows.append(row)
    if proof:
        append_detail(row, "verified against disk with: %s" % clean("command", proof))
    write_board(board, rows)
    # Over the cap the row is still recorded. Refusing to record real work is how
    # work becomes invisible, which is the failure the cap exists to warn about.
    if len(rows) > ROW_CAP:
        sys.stderr.write("todo: %d rows, over the %d the roll call displays — run "
                         "`todo.sh check` and close or split something.\n" % (len(rows), ROW_CAP))
    print(row["id"])


def cmd_set():
    opts, rest = flags(SETTABLE + ("verified", "id"))
    row_id = one_id(rest)
    for banned in ("verified", "id"):
        if banned in opts:
            die(E_USAGE, "--%s cannot be set by hand. `verify` stamps the date, and only "
                         "after you name the command you ran." % banned)
    if not opts:
        die(E_USAGE, "set needs at least one field to change")
    if "state" in opts and opts["state"] not in STATES:
        die(E_USAGE, "state must be one of: %s" % " ".join(STATES))
    if "decision" in opts and opts["decision"] not in DECISIONS:
        die(E_USAGE, "decision must be high or low")

    board, rows = load_for_write()
    row = find(rows, row_id)
    for key, value in opts.items():
        row[key] = clean(key, value)
    # A state TRANSITION is refused where recording a row never is, and the
    # difference is what refusing costs: refusing to record loses work, refusing a
    # transition only leaves the row where it was, still visible. So the states that
    # make a claim about the world must carry what backs the claim.
    if row["state"] == "running" and not (row.get("journey") and row.get("callsign")):
        die(E_DATA, "%s cannot go running without --journey and --callsign: a running row "
                    "is the traceability from block to charter to journey, and without them "
                    "nothing can find the work it claims is under way." % row_id)
    if row["state"] == "blocked-on-owner" and not row.get("awaiting"):
        die(E_DATA, "%s cannot go blocked-on-owner without --awaiting '<the exact decision, "
                    "written out>'. A block with no named decision never gets asked." % row_id)
    write_board(board, rows)


def cmd_move():
    """Priority order is what this file's order MEANS, so it needs a real operation.

    Without it the only way to promote a row is to hand-edit the board, which the
    same rules forbid — and a rule with no permitted way to obey it gets broken.
    """
    opts, rest = flags(("before", "after", "top", "bottom"))
    row_id = one_id(rest)
    given = [k for k in ("before", "after", "top", "bottom") if k in opts]
    if len(given) != 1:
        die(E_USAGE, "move takes exactly one of --before <id>, --after <id>, "
                     "--top yes, --bottom yes")
    board, rows = load_for_write()
    row = find(rows, row_id)
    rows = [r for r in rows if r["id"] != row_id]
    where = given[0]
    if where == "top":
        rows.insert(0, row)
    elif where == "bottom":
        rows.append(row)
    else:
        target = opts[where]
        if not ID_RE.match(target):
            die(E_USAGE, "--%s takes a row id (expected b-0001)" % where)
        if target == row_id:
            die(E_USAGE, "a row cannot be moved relative to itself")
        index = next((i for i, r in enumerate(rows) if r["id"] == target), None)
        if index is None:
            die(E_MISSING, "no row with id %s to move %s" % (target, where))
        rows.insert(index if where == "before" else index + 1, row)
    write_board(board, rows)
    print(" ".join(r["id"] for r in rows))


def cmd_verify():
    opts, rest = flags(("command",))
    row_id = one_id(rest)
    if "command" not in opts:
        die(E_USAGE, "verify needs --command '<what you actually ran>'. The date means "
                     "the row was checked against disk, so it carries the check.")
    board, rows = load_for_write()
    row = find(rows, row_id)
    row["verified"] = today()
    append_detail(row, "verified against disk with: %s" % clean("command", opts["command"]))
    write_board(board, rows)


def cmd_note():
    opts, rest = flags(("text", "file"))
    row_id = one_id(rest)
    if ("text" in opts) == ("file" in opts):
        die(E_USAGE, "note takes exactly one of --text or --file")
    if "file" in opts:
        try:
            with open(opts["file"], encoding="utf-8") as fh:
                text = fh.read()
        except OSError as exc:
            die(E_MISSING, "cannot read %s: %s" % (opts["file"], exc))
    else:
        text = opts["text"]
    if not text.strip():
        die(E_USAGE, "note text is empty")
    if len(text) > LIMITS["text"]:
        die(E_DATA, "note is %d characters, over the %d cap" % (len(text), LIMITS["text"]))

    board, rows = load_for_write()
    row = find(rows, row_id)
    append_detail(row, text)
    write_board(board, rows)


def cmd_close():
    opts, rest = flags(("evidence", "outcome"))
    row_id = one_id(rest)
    if "outcome" not in opts:
        die(E_USAGE, "close needs --outcome")
    evidence = clean("evidence", opts["evidence"]) if "evidence" in opts else ""
    outcome = clean("outcome", opts["outcome"])
    if evidence:
        candidate = evidence if os.path.isabs(evidence) else os.path.join(REPO, evidence)
        if not os.path.exists(candidate):
            sys.stderr.write("todo: close evidence path unavailable: %s; recording the "
                             "outcome and continuing\n" % evidence)

    board, rows = load_for_write()
    row = find(rows, row_id)
    # The ledger is written BEFORE the row leaves: the reverse order can lose the
    # record of a closed row entirely, while this order can only leave a closed row
    # still visible, which `check` reports and a retry finishes. That retry is why
    # the append is skipped when this row already has a close event — otherwise
    # every interrupted close leaves a duplicate behind it.
    already = row_id in ledger_ids()
    if already:
        sys.stderr.write("todo: %s already has a close event in the ledger — finishing the "
                         "interrupted close, not recording a second one.\n" % row_id)
    else:
        event = {"schema": 1, "ts": NOW, "event": "board_closed",
                 "repo": os.path.basename(REPO), "id": row["id"], "name": row["name"],
                 "prd": row["prd"], "outcome": outcome, "evidence": evidence}
        os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
        try:
            with open(LEDGER, "a", encoding="utf-8") as fh:
                fh.write(json.dumps(event, ensure_ascii=False) + "\n")
                fh.flush()
                os.fsync(fh.fileno())
        except OSError as exc:
            die(E_MISSING, "cannot append the close to the routing ledger: %s" % exc)

    rows = [r for r in rows if r["id"] != row_id]
    write_board(board, rows)
    print("closed %s — recorded in ai-doc/JOURNAL/routing-ledger.jsonl" % row_id)


# A row's `prd:` is its address, and an address nobody can open is worse than none:
# it reads as sourced work while pointing at nothing.
#
# A row may legitimately cite work on an unmerged branch, so `<ref>:<path>` is a
# resolvable address and is looked up with git rather than on disk. Anything else is
# resolved in the working tree, because that is the only tree a reader of this board has.
def prd_resolves(spec):
    """(ok, detail). detail names what was looked up when it did not resolve.

    The working tree is tried first and settles almost every row. Git is consulted only
    for a `<ref>:<path>` address, and the ref is never pattern-matched — branch names
    carry slashes (`feat/my-change`) and any shape rule invented here would reject
    exactly the branches this address exists to name. Ask git; it owns the answer.
    """
    if os.path.exists(os.path.join(REPO, spec)):
        return True, None
    if ":" in spec:
        proc = subprocess.run(["git", "-C", REPO, "cat-file", "-e", spec],
                              capture_output=True)
        if proc.returncode == 0:
            return True, None
        ref, _, path = spec.partition(":")
        return False, "neither the working tree nor %s holds %s" % (ref, path)
    return False, "no such path in the working tree"


def cmd_check():
    board = read_board()
    if board is None:
        die(E_MISSING, "no TODO.md in %s" % REPO)
    rows, bad = rows_of(board)
    problems = []

    for line in bad:
        problems.append("not a legal row: %s" % line[:120])
    seen = set()
    for row in rows:
        if row["id"] in seen:
            problems.append("duplicate row id %s" % row["id"])
        seen.add(row["id"])
    if len(rows) > ROW_CAP:
        problems.append("%d rows, over the %d the roll call displays — the rest are "
                        "invisible at roll call" % (len(rows), ROW_CAP))
    stored, listed = stored_stamp()
    if not bad and stored is None and rows:
        problems.append("no checksum, so these rows were written by hand; the next "
                        "todo.sh write adopts and stamps them")
    elif not bad and stored is not None:
        gone = [i for i in (listed or []) if i not in {r["id"] for r in rows}]
        if gone:
            problems.append("rows deleted by hand since the last write: %s — a row leaves "
                            "only through `close`; restore them from git" % ", ".join(gone))
        elif stored != checksum(rows):
            problems.append("hand-edited since the last write (checksum does not match); the "
                            "next todo.sh write adopts and re-stamps it")

    closed_already = ledger_ids()
    limit = datetime.date.fromisoformat(today()) - datetime.timedelta(days=STALE_DAYS)
    running_high = 0
    for row in rows:
        if row["id"] in closed_already:
            problems.append("%s has a close event in the routing ledger but is still on the "
                            "board — an interrupted close; rerun `close %s`"
                            % (row["id"], row["id"]))
        if row["state"] == "running" and row["decision"] == "high":
            running_high += 1
        # Each row is checked for every violation it has, so one finding cannot hide
        # another on the same row.
        if row["verified"] == UNVERIFIED:
            problems.append("%s has never been verified against disk — run `verify %s "
                            "--command '<what you ran>'`" % (row["id"], row["id"]))
        else:
            try:
                stamped = datetime.date.fromisoformat(row["verified"])
                if stamped < limit:
                    problems.append("%s last verified %s, over %d days ago — re-verify it "
                                    "or restate it" % (row["id"], row["verified"], STALE_DAYS))
            except ValueError:
                problems.append("%s has an unreadable verified date: %s"
                                % (row["id"], row["verified"]))
        if row["prd"] == "none":
            problems.append("%s names no source artifact; its first slice is writing the "
                            "one-page charter" % row["id"])
        else:
            resolved, detail = prd_resolves(row["prd"])
            if not resolved:
                problems.append("%s cites %s, which cannot be opened (%s) — correct the "
                                "path, or address it as <branch>:<path> if the artifact "
                                "lives on an unmerged branch"
                                % (row["id"], row["prd"], detail))
        if row["state"] == "running" and not (row.get("journey") and row.get("callsign")):
            problems.append("%s is running with no journey and callsign" % row["id"])
        # `running` is the one state that decays on its own: the executor dies, the
        # session goes, and the row keeps claiming a live agent. Nothing on the board
        # notices, because a row is only ever touched by whoever closes it. A running
        # row states a fact about right now and is
        # re-verified daily; anything older is a claim nobody has checked.
        if row["state"] == "running" and row["verified"] != UNVERIFIED:
            try:
                stamped = datetime.date.fromisoformat(row["verified"])
            except ValueError:
                stamped = None
            if stamped is not None and stamped < datetime.date.fromisoformat(today()) - \
                    datetime.timedelta(days=RUNNING_STALE_DAYS):
                problems.append("%s claims running on a %s verification — re-verify that "
                                "its executor is alive, or set the state it is really in"
                                % (row["id"], row["verified"]))
        if row["state"] == "blocked-on-owner" and not row.get("awaiting"):
            problems.append("%s is blocked on the owner with no --awaiting decision "
                            "written out" % row["id"])

    if running_high > 1:
        problems.append("%d high-decision rows are running at once; the capacity rule is "
                        "one at a time, solo" % running_high)
    if board["tail"]:
        problems.append("%d lines below the OPEN section — everything owed belongs in "
                        "OPEN and everything else belongs in ai-doc/JOURNAL/; move it "
                        "with `todo.sh archive-tail`" % len(board["tail"]))

    if problems:
        for problem in problems:
            print("FAIL %s" % problem)
        raise SystemExit(E_DATA)
    print("ok %d rows, none stale, nothing below OPEN" % len(rows))


def cmd_archive_tail():
    opts, rest = flags(("confirm-no-owed-work",))
    if rest:
        die(E_USAGE, "archive-tail takes no positional arguments")
    board, rows = load_for_write()
    if not board["tail"]:
        print("nothing below the OPEN section")
        return

    # Moving a second list of work out silently and then passing `check` would hide
    # owed work. No rule can tell "- Feature A" (owed) from "- Work completed"
    # (history). So the operator is shown every list item and has
    # to say, in the command, that none of them is owed.
    bullets = [l for l in board["tail"] if re.match(r"^\s*(?:[-*+]|\d+[.)])\s+\S", l)]
    if bullets and "confirm-no-owed-work" not in opts:
        sys.stderr.write("todo: the tail holds %d list items. Any of them that is still "
                         "owed must become a row FIRST (`todo.sh add …`) — archiving it "
                         "makes it invisible while `check` passes.\n" % len(bullets))
        for line in bullets[:15]:
            sys.stderr.write("  %s\n" % line.strip()[:120])
        if len(bullets) > 15:
            sys.stderr.write("  … %d more\n" % (len(bullets) - 15))
        die(E_DATA, "when every one of them is history, rerun with "
                    "--confirm-no-owed-work yes")
    dest_rel = os.path.join("ai-doc", "JOURNAL", "board-tail-%s.md" % today())
    dest = os.path.join(REPO, dest_rel)
    if os.path.exists(dest):
        die(E_DATA, "%s already exists; move it aside first — this command never "
                    "appends to or overwrites an archive" % dest_rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "w", encoding="utf-8") as fh:
        fh.write("# Board tail archived %s\n\n"
                 "Everything that sat below TODO.md's OPEN section, moved here whole by\n"
                 "todo.sh archive-tail. Nothing was summarised, edited or dropped.\n\n"
                 % NOW)
        fh.write("\n".join(board["tail"]).strip("\n") + "\n")
    moved = len(board["tail"])
    board["tail"] = []
    write_board(board, rows)
    print("moved %d lines to %s" % (moved, dest_rel))


def cmd_init():
    """Create the board. Exists so no instruction anywhere says 'hand-write the header'."""
    opts, rest = flags(("north-star",))
    if rest:
        die(E_USAGE, "init takes flags only, got: %s" % " ".join(rest))
    if os.path.exists(BOARD):
        die(E_DATA, "%s already exists; init never overwrites a board" % BOARD)
    north = clean("north-star", opts.get("north-star", "set the north star with a charter"))
    header = [
        "# TODO — %s (written by todo.sh, owner-reviewed)" % os.path.basename(REPO),
        "",
        "> North star: %s" % north,
        "",
        "Everything still owed by this repository is the one list below, in priority",
        "order. There is no second list: running, queued, ranked-but-unstarted,",
        "blocked-on-the-owner and owner-FYI are `state:` values on a row. Closed work",
        "leaves for `ai-doc/JOURNAL/routing-ledger.jsonl` and never comes back.",
        "",
        "Rows are written by `todo.sh`, never by hand.",
        "",
        "## OPEN",
    ]
    write_board({"header": header, "body": [], "tail": []}, [])
    print(BOARD)


{
    "init": cmd_init,
    "add": cmd_add,
    "set": cmd_set,
    "move": cmd_move,
    "verify": cmd_verify,
    "note": cmd_note,
    "close": cmd_close,
    "check": cmd_check,
    "archive-tail": cmd_archive_tail,
}[VERB]()
PY
