#!/usr/bin/env bash
# cos-roster.sh — THE answer to "how many PLs do I own, what state is each in,
# what is unread, which boards are stale".
#
# Computes PL liveness so a supervisor does not infer it from a partial process
# listing (the pl skill's roster.sh is the counterpart for the executor layer).
# Needs Linux (/proc, ps), python3 and the sno command.
#
#   cos-roster.sh [--cos <id>] [--all] [--json]
#
#   --cos <id>   which COS to report for (default: cos/<current repo basename>)
#   --all        every registry row regardless of owner
#   --json       one JSON object on stdout, nothing else
#   SNO_OWNER_ADDR  owner's current Reach seat address; unset means no owner cards are read
#
# PRIMARY SIGNAL — the turn lock, not the heartbeat:
# a Codex agent holds a systemd idle-inhibitor for the whole of every turn, whose
# reason field reads "Codex is running an active turn". A heartbeat alone
# cannot prove whether a PL is currently executing.
#
# STATE per PL — evidence beats the registry's cached column:
#   RUN         an interactive window is mid-turn (turn lock held)
#   UNREACHABLE a window exists but its Reach seat is not registered
#   CHECK       something is live but this tool cannot attribute it to this lane
#               (multi-lane repo, or a Claude agent that leaves no lock)
#   DEAD        no interactive window, and the heartbeat is recent enough that one
#               was running here within the last 12h — a death to act on
#   WAIT-OWNER  alive and its only open cards are addressed to the owner
#   NONE        no PL here now: no window, and either no heartbeat at all or one
#               older than 12h. Not an alarm — a repo simply without a supervisor
#   UNKNOWN     process observation FAILED. No verdict is offered and none may be
#               inferred: do not reopen anything off an UNKNOWN row
#
# FAIL CLOSED. Missing evidence is never read as absence of a process — that
# inversion turns one failed `ps` into "every PL is dead" and invites reopening
# on top of live ones. Any observation gap yields UNKNOWN and exit 3.
#
# ROLE from argv, positively identified: the binary basename must be exactly
# `codex` or `claude`. For Codex the token right after it decides — `exec` is an
# executor a PL spawned, a service subcommand (mcp-server, app-server,
# remote-control …) is not an agent and is dropped, anything else is an
# interactive window. For Claude, `-p`/`--print` is a one-shot headless run and
# anything else is a window. Windows are counted across known agent runtimes.
# The registry runtime label is informational; it never decides identity,
# authority, or whether a lane may open. A PL window and one the owner opened
# remain indistinguishable, and that limit is printed rather than
# guessed away. Service processes and unrelated Claude sessions must not turn a
# dead lane into a merely unreachable one.
#
# DELIVERABILITY comes from a live Reach registration. A turn lock proves work,
# not whether a card can be delivered.
#
# Sensor gaps can still produce `CHECK`; they never make a runtime label authoritative.
#
# EXIT: 0 report complete · 2 usage or a missing/corrupt registry · 3 report
# published but observation was incomplete (some verdicts are UNKNOWN).
set -euo pipefail

REGISTRY="${SNO_PL_REGISTRY:-$HOME/.local/state/pl-registry.tsv}"
STATE_DIR="$HOME/.local/state/pl-heartbeat"

usage() {
  # The header block IS the help text; print it up to the first non-comment line
  # so the two can never drift apart.
  awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
}

die() { printf 'cos-roster: %s\n' "$*" >&2; exit 2; }

cos_id=""
show_all=0
as_json=0
while [ $# -gt 0 ]; do
  case "$1" in
    --cos)  [ $# -ge 2 ] || die "--cos needs a value"; cos_id="$2"; shift 2 ;;
    --all)  show_all=1; shift ;;
    --json) as_json=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg $1 (try --help)" ;;
  esac
done

[ "$(uname -s)" = Linux ] || die "requires Linux (reads /proc and ps)"
[ -r "$REGISTRY" ] || die "registry not readable: $REGISTRY"
command -v sno >/dev/null 2>&1 || die "sno command is unavailable"

top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$cos_id" ]; then
  if [ -n "$top" ]; then
    cos_id="cos/$(basename -- "$top")"
  else
    cos_id="cos/unknown"
  fi
fi

command -v python3 >/dev/null 2>&1 || die "python3 is required"

set +e
python3 - "$REGISTRY" "$STATE_DIR" "$cos_id" "$show_all" "$as_json" "$(date +%s)" "${top:-$PWD}" "$(hostname)" <<'PY'
import json, os, re, sys, subprocess, datetime
from email.parser import BytesParser
from email.policy import default as email_policy
from email.utils import getaddresses

registry, state_dir, cos_id, show_all, as_json, now = sys.argv[1:7]
host = sys.argv[8]
show_all, as_json, now = show_all == "1", as_json == "1", int(now)

STALE_MIN = 90          # heartbeat older than this is not, by itself, death
MOVEMENT_MIN = 90       # mailbox movement window that counts as life
ABANDONED_MIN = 12 * 60 # beyond this a heartbeat is a fossil, not a recent death
# A live Reach registration does not prove that a card was handled. Past this
# age, an unread card needs direct inspection.
UNDELIVERED_ACT_MIN = 30
# The mirror of UNDELIVERED: a live Reach registration does not prove that a
# quiet lane started its next task after a seal.
# 45m allows a normal gap between a seal and the next dispatch.
IDLE_LANE_MIN = 45
COLS = ("home_repo", "lane", "reach_address", "heartbeat_name",
        "runtime", "owning_cos", "state", "note")


def die(msg):
    print(f"cos-roster: {msg}", file=sys.stderr)
    sys.exit(2)


def rows():
    """A malformed row FAILS THE RUN. Skipping it would delete a PL from the
    only supervisory roll call while still printing 'no anomalies' — a silent
    disappearance is worse than a loud refusal, and the header already promised
    exit 2 for a corrupt registry."""
    out = []
    with open(registry, errors="replace") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if parts[0] == "home_repo":                       # header
                continue
            if len(parts) < len(COLS) - 1:                    # note is optional
                die(f"registry line {n}: expected {len(COLS)-1} tab-separated "
                    f"fields, got {len(parts)}: {line[:70]}")
            parts += [""] * (len(COLS) - len(parts))
            row = dict(zip(COLS, parts))
            if row["lane"] == "-" or row["state"].upper() == "RETIRED":
                continue
            for required in ("home_repo", "lane", "reach_address", "owning_cos"):
                if not row[required].strip():
                    die(f"registry line {n}: empty required field '{required}'")
            if not (row["reach_address"].startswith("pl.")
                    and row["reach_address"].endswith("@" + host)):
                die(f"registry line {n}: reach_address must be one strict "
                    "PL repository-seat address")
            out.append(row)
    if not out:
        die("registry contains no PL rows")

    # Ownership must be unambiguous. Capacity never suppresses a read-only roster.
    seen = {}
    for r in out:
        key = (r["home_repo"], r["lane"])
        if key in seen:
            die(f"registry: lane {key[0]}/{key[1]} appears twice (owners "
                f"'{seen[key]}' and '{r['owning_cos']}'). A PL has exactly one "
                f"owning COS — two claimants whipsaw the executor. Fix the file.")
        seen[key] = r["owning_cos"]

    return out


def age_min(epoch):
    return None if epoch is None else max(0, (now - epoch)) // 60


def age_str(epoch):
    m = age_min(epoch)
    if m is None:
        return "never"
    return f"{m // 60}h{m % 60:02d}m" if m >= 60 else f"{m}m"


def mtime(path):
    try:
        return int(os.stat(path).st_mtime)
    except OSError:
        return None


def read_jsonl(path):
    """Returns (rows, torn). `torn` counts records that could not be parsed —
    reported rather than swallowed, so a partial read can never masquerade as a
    complete mailbox view."""
    out, torn = [], 0
    try:
        with open(path, errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    out.append(json.loads(line))
                except ValueError:
                    torn += 1
    except OSError:
        pass
    return out, torn


def ts_epoch(ts):
    if not isinstance(ts, str) or not ts:
        return None
    try:                                     # mailbox index: YYYYMMDDTHHMMSSZ
        return int(datetime.datetime.strptime(ts, "%Y%m%dT%H%M%SZ")
                   .replace(tzinfo=datetime.timezone.utc).timestamp())
    except ValueError:
        pass
    try:
        return int(datetime.datetime.fromisoformat(ts).timestamp())
    except (ValueError, TypeError):
        return None


def repo_root(home_repo):
    # Relative registry entries name sibling checkouts of the current repository.
    return os.path.join(os.path.dirname(sys.argv[7]), os.path.expanduser(home_repo))


def mailbox_command(address, verb):
    try:
        result = subprocess.run(
            ["sno", "reach", verb, "--as", address],
            capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    return [line for line in result.stdout.splitlines() if line]


def action_paths(queued):
    paths = []
    for line in queued:
        path, separator, subject = line.partition("\t")
        if not separator or not subject or not os.path.isabs(path) or not os.path.isfile(path):
            return None
        paths.append(path)
    return paths


def reach_seats():
    try:
        result = subprocess.run(["sno", "reach", "seats", "--json"],
                                capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    try:
        return {row["address"] for row in map(json.loads, result.stdout.splitlines())
                if row["state"] == "live"}
    except (ValueError, KeyError, TypeError):
        return None


def mailbox_facts(address):
    """Public strict-address action paths, last activity, and observation status."""
    queued = mailbox_command(address, "inbox")
    log = mailbox_command(address, "log")
    if queued is None or log is None:
        return {}, 0, None, 0, False
    queued = action_paths(queued)
    if queued is None:
        return {}, 0, None, 0, False

    by_path, last = {}, None
    for line in log:
        fields = line.split("\t", 4)
        if len(fields) != 5:
            return {}, 0, None, 0, False
        try:
            epoch = int(datetime.datetime.strptime(
                fields[2], "%Y-%m-%d %H:%M:%S"
            ).replace(tzinfo=datetime.timezone.utc).timestamp())
        except ValueError:
            return {}, 0, None, 0, False
        by_path[fields[0]] = epoch
        last = epoch if last is None else max(last, epoch)

    cards = []
    for path in queued:
        epoch = by_path.get(path)
        cards.append({
            "file": path,
            "ts_utc": (
                datetime.datetime.fromtimestamp(
                    epoch, datetime.timezone.utc
                ).strftime("%Y%m%dT%H%M%SZ")
                if epoch is not None else None
            ),
        })
    return ({address: cards} if cards else {}), 0, last, 0, True


def owner_cards_by_sender(address):
    if not address:
        return {}, True
    queued = mailbox_command(address, "inbox")
    if queued is None:
        return {}, False
    paths = action_paths(queued)
    if paths is None:
        return {}, False
    cards = {}
    for path in paths:
        try:
            with open(path, "rb") as source:
                message = BytesParser(policy=email_policy).parse(source, headersonly=True)
        except OSError:
            return {}, False
        senders = [value for _, value in getaddresses(message.get_all("from", []))]
        if len(senders) != 1 or not STRICT_ADDRESS.fullmatch(senders[0]):
            return {}, False
        cards.setdefault(senders[0], []).append({"file": path, "ts_utc": None})
    return cards, True


# Both boards: the optional owner-facing `TOP-TODO` and the PL-maintained `TODO.md`
# go stale independently, so each is compared with the routing ledger.
BOARDS = ("TOP-TODO", "TODO.md")


def board_stale(root):
    """Names the boards older than the routing ledger's newest event, or None."""
    if not root:
        return None
    newest = None
    recs, _ = read_jsonl(os.path.join(root, "ai-doc", "JOURNAL", "routing-ledger.jsonl"))
    for rec in recs:
        e = ts_epoch(rec.get("ts") or rec.get("ts_utc"))
        if e is not None and (newest is None or e > newest):
            newest = e
    if newest is None:
        return None
    stale = [b for b in BOARDS
             if (m := mtime(os.path.join(root, b))) is not None and newest > m]
    return stale or None


# The open board, and why the roll call prints it rather than pointing at it.
#
# Printing TODO.md here makes open work visible at each roll call instead of
# relying on the supervisor to remember a separate file.
#
# ONE convention, deliberately: work that is still owed lives under a heading
# named OPEN. Everything outside that heading is context or history. No line
# schema, no per-item owner, no date stamp, no linter — five conventions would
# reproduce the complexity that causes the forgetting. The section ends at the
# next heading of the same or shallower depth.
# EXACTLY `OPEN`, with nothing after it but optional closing hashes. A heading with a
# suffix (for example `## OPEN: restore the failed lane`) is not the open heading, so
# such a file reports NO-OPEN-SECTION: loud, and repairable, never zero items.
OPEN_HEADING = re.compile(r"^(#+)\s*OPEN\s*#*\s*$", re.IGNORECASE)
# Every list syntax Markdown allows, because the board convention deliberately
# specifies no line schema. A parser narrower than the convention it reads turns
# a legal board into a silent zero, which reads as "this repo is clear".
# Any indent, because a nested subtask is a separate owed item, not a wrapped
# continuation of its parent. Folding it into the parent halves the count, and the
# count is what the close is matched against — one merged line is one silently
# undisposed task.
OPEN_ITEM = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+(.*)")
OPEN_ITEM_CAP = 25
OPEN_ITEM_WIDTH = 150
# The OPEN section holds list items and nothing else, so anything else under it is
# reported rather than skipped. Explanatory prose belongs ABOVE the heading, where
# it is still read and cannot be mistaken for — or hide — an owed item.
# Bounds exist because this script runs at every boot and every tick for every
# supervisor: a pathological board must degrade to a named status, never to a
# process that dies and blinds the roll call entirely.
MAX_BOARD_BYTES = 4 * 1024 * 1024
MAX_BOARD_LINES = 20000


def open_board(root):
    """(items, path, status). OK | MISSING | NO-OPEN-SECTION | UNREADABLE | UNPARSED.

    Never returns an empty list with an OK status by guessing: a board it cannot
    parse reports its failure by name. Reporting "nothing open" because the file
    moved, the heading was renamed, or the items were written in a list syntax
    this function does not recognise is the one output that would make this
    change worse than no change at all — it would retire a real backlog silently.
    UNPARSED is that last case: an OPEN section with content but no item this
    parser could read. It is never OK, and a genuinely finished board is
    distinguishable from it because a finished board's section is EMPTY.
    """
    if not root:
        return [], None, "MISSING"
    path = os.path.join(root, "TODO.md")
    try:
        if os.path.getsize(path) > MAX_BOARD_BYTES:
            return [], path, "TOO-LARGE"
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = []
            for n, line in enumerate(fh):
                if n >= MAX_BOARD_LINES:
                    return [], path, "TOO-LARGE"
                lines.append(line.rstrip("\n"))
    except FileNotFoundError:
        return [], path, "MISSING"
    except OSError:
        return [], path, "UNREADABLE"

    depth, body = None, []
    for line in lines:
        if depth is None:
            m = OPEN_HEADING.match(line)
            if m:
                depth = len(m.group(1))
            continue
        h = re.match(r"^(#+)\s", line)
        if h and len(h.group(1)) <= depth:
            break
        body.append(line)
    if depth is None:
        return [], path, "NO-OPEN-SECTION"

    items, unclaimed = [], 0
    for line in body:
        m = OPEN_ITEM.match(line)
        if m:
            items.append(" ".join(m.group(1).split()))
        elif items and line.startswith((" ", "\t")) and line.strip():
            # A wrapped continuation of the item above — indented, and NOT itself a
            # list marker, which the branch above already claimed. Fold it back so an
            # item's state survives the wrap a fixed-width editor introduced.
            items[-1] = f"{items[-1]} {' '.join(line.split())}"
        elif line.strip():
            # Content under OPEN that is neither an item nor a continuation. It is
            # counted, never skipped: one owed thing written as a paragraph while
            # other lines parse cleanly would otherwise leave the count looking
            # complete, which is the failure the whole status set exists to prevent.
            unclaimed += 1
    if unclaimed:
        return items, path, "UNPARSED"
    return items, path, "OK"


TURN_LOCK_MARKER = "Codex is running an active turn"
# Codex subcommands that are background services, not agents. Counting them as PL windows reports a
# dead lane as merely unreachable and sends the supervisor to type into a pipe.
CODEX_SERVICES = {"mcp", "mcp-server", "app-server", "proto", "remote-control",
                  "login", "logout", "completion", "apply", "debug"}


def proc_cwd(pid):
    """Returns (path, ok). ok=False means the process exists but its directory
    could not be read — an observation gap, never evidence of absence."""
    try:
        return os.readlink(f"/proc/{pid}/cwd"), True
    except FileNotFoundError:
        return None, True          # process exited between listing and reading
    except OSError:
        return None, False         # permission or kernel error: we are blind


# A window's working directory is wherever the agent last did `cd`, often a
# subdirectory. Keying the process table by that raw path would put a live PL in a
# slot no registry row looks up, so it would read DEAD or NONE and invite a second
# supervisor on the lane. Paths are therefore folded onto the registered repo root.
# The address shape the mailbox itself enforces. Anything else on a `--as` is a
# launcher, an unexpanded variable, or a malformed invocation — never a seat.
STRICT_ADDRESS = re.compile(
    r"^[a-z][a-z0-9-]{0,31}\.[a-z0-9][a-z0-9-]{0,63}@[a-z0-9][a-z0-9.-]{0,252}$")


def root_normaliser(known_roots):
    """Map any path to the longest registered repo root containing it."""
    roots = []
    for r in known_roots:
        if not r:
            continue
        try:
            roots.append(os.path.realpath(r))
        except OSError:
            continue
    roots.sort(key=len, reverse=True)          # longest match wins: nested repos

    def normalise(path):
        if not path:
            return path
        try:
            real = os.path.realpath(path)
        except OSError:
            real = path
        for r in roots:
            if real == r or real.startswith(r + os.sep):
                return r
        return real
    return normalise


def agent_role(args):
    """None (not an agent) | 'executor' | 'window'. Positive identification: the
    binary basename must be exactly `codex` or `claude` — which excludes helper
    binaries such as codex-code-mode-host — and for Codex only the token
    IMMEDIATELY after it may be a subcommand, so a flag value can never be
    mistaken for one.

    Claude is scanned too even though it takes no turn lock: without this, a live
    Claude PL has zero windows, falls through to NONE, and the supervisor opens a
    second one on top of it."""
    toks = args.split()
    if not toks:
        return None
    # `timeout` FORKS the command it wraps, so the spawner's kernel-wall wrapper and the
    # agent itself are two processes carrying the same `codex exec` text. Counting both
    # doubles the EXEC column, which a supervisor reads against the per-PL executor cap.
    # Skip the wrapper; its child is the real process and is scanned on its own.
    if os.path.basename(toks[0]) == "timeout":
        return None
    idx = next((i for i, t in enumerate(toks)
                if os.path.basename(t) in ("codex", "claude")), None)
    if idx is None:
        return None
    binary = os.path.basename(toks[idx])
    sub = toks[idx + 1] if idx + 1 < len(toks) else None

    if binary == "claude":
        # `-p` / `--print` is a one-shot headless run: an executor, not a window.
        rest = toks[idx + 1:]
        return "executor" if ("-p" in rest or "--print" in rest) else "window"

    if sub is None or sub.startswith("-"):
        return "window"
    if sub in CODEX_SERVICES:
        return None
    return "executor" if sub == "exec" else "window"


def scan_processes(normalise=lambda p: p):
    """Returns (repos, ok). ok=False means observation was incomplete and every
    verdict derived from it must be UNKNOWN — missing evidence is not absence.

    repos: {root: {windows, executors, window_turn, executor_turn, watchers}}
    Reach registration, rather than a listener process, establishes deliverability."""
    try:
        proc = subprocess.run(["ps", "-eo", "pid,ppid,args", "--no-headers"],
                              capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return {}, False
    if proc.returncode != 0 or not proc.stdout.strip():
        return {}, False

    ok = True
    procs, turn_parents = {}, set()
    for line in proc.stdout.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) < 3:
            continue
        pid, ppid, args = parts
        procs[pid] = args
        if "systemd-inhibit" in args and TURN_LOCK_MARKER in args:
            turn_parents.add(ppid)

    repos = {}
    mine = {str(os.getpid()), str(os.getppid())}

    def slot(root):
        return repos.setdefault(root, {"windows": {"codex": 0, "claude": 0},
                                       "executors": {"codex": 0, "claude": 0},
                                       "window_turn": False,
                                       "executor_turn": False, "watchers": {}})

    for pid, args in procs.items():
        if pid in mine or "cos-roster" in args:
            continue

        if "systemd-inhibit" in args:
            continue
        role = agent_role(args)
        if role is None:
            continue
        binary = "claude" if any(os.path.basename(t) == "claude"
                                 for t in args.split()) else "codex"
        root, read_ok = proc_cwd(pid)
        ok = ok and read_ok
        root = normalise(root)
        if not root:
            continue
        s = slot(root)
        s["executors" if role == "executor" else "windows"][binary] += 1
        if pid in turn_parents:
            s["executor_turn" if role == "executor" else "window_turn"] = True
    return repos, ok


def classify(hb_epoch, proc, open_cards, shared_repo, observed, registered):
    """Process state leads; the heartbeat is auxiliary and never decisive.

    Attribution honesty: processes and the mailbox are REPO-wide. In a multi-lane
    repo only the heartbeat is lane-attributable, so a repo-level signal may
    never rescue a stale lane heartbeat — that is how a long-dead lane gets
    reported as merely quiet because a sibling lane is busy. And the heartbeat
    namespace is `<repo-basename>`, written by COS and PL alike, so a fresh one
    does not prove WHICH role is alive."""
    if not observed:
        return "UNKNOWN"

    # A PL seat is independent of the agent runtime that currently occupies it.
    windows = sum(proc.get("windows", {}).values())
    turn = proc.get("window_turn", False)
    hb_age = age_min(hb_epoch)
    hb_fresh = hb_age is not None and hb_age < STALE_MIN

    def wait_or_run():
        if open_cards.get("owner") and not open_cards.get("pl"):
            return "WAIT-OWNER"
        return "RUN"

    if windows == 0:
        if registered:
            return "CHECK"
        # DEAD must mean "it was running and is now gone" — something to act on.
        # A heartbeat file from days ago is a fossil of a PL that once ran here;
        # reporting that as DEAD forever makes every long-quiet repo a standing
        # alarm, and a standing alarm is the one iron rule 5 exists to prevent.
        if hb_epoch is None or (age_min(hb_epoch) or 0) > ABANDONED_MIN:
            return "NONE"
        return "DEAD"
    if not registered:
        return "UNREACHABLE"
    if shared_repo and not hb_fresh:
        return "CHECK"
    if turn:
        return wait_or_run()
    return "CHECK"


NEXT = {
    "DEAD":    "no interactive window at all; confirm, then reopen per cos-watch (cap 3) and hand over a written state summary",
    "UNREACHABLE": "window exists without a live Reach registration; register its seat or inspect the window",
    "CHECK":   "something is live but this tool cannot attribute it to this lane; go look at the window yourself",
    "UNKNOWN": "PROCESS OBSERVATION FAILED — no verdict. Do NOT reopen anything off this row; re-run, and if it persists inspect the window by hand",
    "WAIT-OWNER": "queue it into the return report with the literal line the owner must type",
    "NONE":    "no PL here; open one only if a charter in the queue needs this repo",
    "RUN":     "",
}
UNDELIVERABLE = ("UNREACHABLE", "DEAD", "NONE", "UNKNOWN")

report, anomalies = [], []
boards = {}
live_owned = 0
degraded = False

all_rows = rows()
owner_open, owner_observed = owner_cards_by_sender(os.environ.get("SNO_OWNER_ADDR"))
# A repo carrying more than one row shares its mailbox and process list across
# lanes; classify() must know so it does not credit one lane with another's life.
lanes_per_repo = {}
for r in all_rows:
    lanes_per_repo[r["home_repo"]] = lanes_per_repo.get(r["home_repo"], 0) + 1

# The registry's own repo roots are the only paths a row can look up, so they are
# what a process cwd is folded onto.
procs_by_repo, observed = scan_processes(
    root_normaliser({repo_root(r["home_repo"]) for r in all_rows}))
if not observed:
    degraded = True
    anomalies.append(
        "OBSERVATION FAILED  the process scan could not complete  ->  every state "
        "below is UNKNOWN; do NOT reopen or declare anything dead from this run")

seats = reach_seats()
for row in all_rows:
    if not show_all and row["owning_cos"] != cos_id:
        continue

    root = repo_root(row["home_repo"])
    hb = mtime(os.path.join(state_dir, row["heartbeat_name"])) if row["heartbeat_name"] else None
    proc = procs_by_repo.get(root or "", {})
    open_to, backlog, last_mail, torn, mailbox_observed = mailbox_facts(
        row["reach_address"])
    owner_cards = owner_open.get(row["reach_address"], [])
    classification_cards = {
        "pl": open_to.get(row["reach_address"], []),
        "owner": owner_cards,
    }
    if owner_cards:
        open_to["owner"] = owner_cards
    mailbox_observed = mailbox_observed and owner_observed and seats is not None
    address = row["reach_address"]
    registered = seats is not None and address in seats
    state = classify(hb, proc, classification_cards,
                     lanes_per_repo[row["home_repo"]] > 1,
                     observed and mailbox_observed, registered)
    if not mailbox_observed:
        degraded = True
        anomalies.append(
            f"MAILBOX OBSERVATION FAILED  {row['reach_address']}  ->  "
            "state is UNKNOWN; do not reopen or declare anything dead")
    stale = board_stale(root)
    board_items, board_path, board_status = open_board(root)
    # TODO.md is the board, always. A repo may also hold TOP-TODO, a hand-written
    # summary for the owner to read: not a competing authority. Only its modification
    # time is compared (board_stale); its content is never read.
    boards.setdefault(row["home_repo"], (board_items, board_path, board_status))
    watchers = {address: 1} if registered else {}
    pl_watched = watchers.get(address, 0) > 0
    open_for_me = open_to.get(address)

    # The cap belongs to THIS COS. --all widens the view, never the accounting:
    # counting another supervisor's PLs against your own cap is a false alarm,
    # and a roll call that cries wolf is a roll call that stops being read.
    if state in ("RUN", "UNREACHABLE", "CHECK", "WAIT-OWNER") and row["owning_cos"] == cos_id:
        live_owned += 1

    report.append({
        "home_repo": row["home_repo"], "lane": row["lane"],
        "owning_cos": row["owning_cos"], "runtime": row["runtime"],
        "state": state,
        "windows": sum(proc.get("windows", {}).values()),
        "in_turn": bool(proc.get("window_turn", False)),
        # Summed across ALL runtimes, deliberately. An executor's runtime is
        # independent of the PL's runtime. Otherwise a Claude PL running Codex
        # executors would appear idle while its executors are working.
        "executors": sum(proc.get("executors", {}).values()),
        "address": address,
        "watchers": watchers,
        "heartbeat_age": age_str(hb),
        "last_mailbox_activity": age_str(last_mail),
        "open_cards": {k: len(v) for k, v in sorted(open_to.items())},
        "executor_backlog": backlog,
        "mailbox_torn_records": torn,
        "mailbox_observation_complete": mailbox_observed,
        "board_stale": stale,
        # Bounded on the same cap as the printed report. An unbounded list here
        # would let one large board produce arbitrarily large JSON and block or
        # starve a piped consumer — costing the supervisor the whole liveness
        # report, not just the board.
        "open_board": {"path": board_path, "status": board_status,
                       "open_count": len(board_items),
                       "items": board_items[:OPEN_ITEM_CAP],
                       "items_truncated": len(board_items) > OPEN_ITEM_CAP},
        "registry_state": row["state"],
        "next": NEXT[state],
    })

    where = f"{row['home_repo']}/{row['lane']}"
    if state in ("DEAD", "UNREACHABLE", "CHECK", "UNKNOWN"):
        anomalies.append(f"{state}  {where}  ->  {NEXT[state]}")
    # A RUN row with an open card and no Reach registration needs attention.
    if open_for_me and (state in UNDELIVERABLE or not pl_watched):
        why = state if state in UNDELIVERABLE else "in a turn but without a Reach registration"
        # The AGE is the whole point: a fresh COS session has no memory of when it first
        # saw a card, so the age comes from the mailbox log, not from counting ticks.
        # "It will land when the turn ends" is a prediction, not an observation.
        ages = [a for a in (age_min(ts_epoch(c.get("ts_utc") or c.get("ts")))
                            for c in open_for_me) if a is not None]
        oldest = max(ages) if ages else None
        stamp = f", oldest {age_str(now - oldest * 60)} old" if oldest is not None else \
                ", age UNKNOWN (unparsable timestamp — treat as old)"
        if (state in UNDELIVERABLE or not pl_watched or oldest is None or
                oldest >= UNDELIVERED_ACT_MIN):
            todo = ("ACT NOW: inspect the Reach registration and the card in its "
                    "window; restore the seat or escalate if the agent cannot act")
        else:
            todo = (f"the seat is registered, but the card is still unread. Under "
                    f"{UNDELIVERED_ACT_MIN}m, re-check on the next scheduled turn; "
                    "if it remains unread, act")
        anomalies.append(
            f"UNDELIVERED  {len(open_for_me)} card(s) to {address} in {where}{stamp}, "
            f"while it is {why}  ->  {todo}")
    # IDLE LANE. Everything below is observable; whether the lane SHOULD be producing is
    # not, so the tool states the facts and hands that judgment back rather than guessing
    # from a board it cannot parse. Restricted to single-lane repos on purpose: the
    # executor count is per repo, so in a multi-lane repo a busy sibling would mask this
    # lane's silence and the alarm would be a lie.
    # An owner gate suppresses it, and the test is an OPEN DECISION CARD TO THE OWNER,
    # never the board's prose. A lane whose remaining work is waiting on a human is
    # correctly quiet for hours, and alarming on it every tick would train the supervisor
    # to skip the row, creating a blind spot that looks like normal work.
    # Using the card rather than the board also makes the silence conditional on the
    # gate being VISIBLE to the owner: a gate the owner was never carded about is a
    # defect in its own right, and this keeps alarming until it is sent.
    idle_age = age_min(last_mail)
    if (lanes_per_repo[row["home_repo"]] == 1
            and state in ("RUN", "UNREACHABLE", "CHECK")
            and not sum(proc.get("executors", {}).values())
            and not open_for_me
            and not open_to.get("owner")
            and idle_age is not None and idle_age >= IDLE_LANE_MIN):
        anomalies.append(
            f"IDLE LANE  {where} has been alive with no executor running and an empty inbox "
            f"for {age_str(last_mail)}{', Reach seat registered' if pl_watched else ''}  ->  "
            f"Reach rings on new mail, but the PL must start its next task after a seal. "
            f"Open its board: if runnable work is "
            f"sitting there, this is a stall and it will not end on its own; if the lane is "
            f"genuinely finished or deliberately held, say so in the log and move on")
    if torn:
        degraded = True
        anomalies.append(
            f"MAILBOX INCOMPLETE  {torn} unparsable record(s) in {where}  ->  the unread-card "
            f"count above may be short; re-run the commands")
    if stale:
        anomalies.append(
            f"STALE BOARD  {row['home_repo']} {' and '.join(stale)} older than the routing "
            f"ledger  ->  fix the document now; a stale board silently makes a correct PL wrong")
    # A board this tool cannot read is reported as unreadable, never as empty. The
    # failure mode being closed here is a supervisor seeing no open items because
    # the file moved or the heading was renamed, and concluding the repo is clear.
    if board_status != "OK":
        why = {
            "MISSING": "there is no TODO.md in this repo, so no close in it can be "
                       "disposed against a board",
            "NO-OPEN-SECTION": "TODO.md exists but has no heading named OPEN, so what "
                               "is still owed cannot be told from what is history",
            "UNREADABLE": "TODO.md exists but could not be read",
            "UNPARSED": "TODO.md's OPEN section holds content that is neither a list "
                        "item nor a wrapped continuation, so the count above is not the "
                        "whole of what is open. Move explanatory prose ABOVE the OPEN "
                        "heading and make every owed thing a list item",
            "TOO-LARGE": "TODO.md is past this tool's read bound, so it was not parsed "
                         "at all. Split or prune it — a board too large to read is a "
                         "board nobody reads either",
        }[board_status]
        anomalies.append(
            f"BOARD {board_status}  {row['home_repo']}  ->  {why}. Create or repair it "
            f"BEFORE declaring anything closed here; 'no open items' is not claimed and "
            f"must not be inferred from this run")
    if row["state"] != state and state != "UNKNOWN":
        anomalies.append(
            f"REGISTRY DRIFT  {where} row says {row['state']}, disk says {state}"
            f"  ->  update ~/.local/state/pl-registry.tsv under flock")

# A repo-wide finding (a stale board) is reached once per lane. Printing it twice
# is the tool committing iron rule 5's error on the supervisor's behalf.
anomalies = list(dict.fromkeys(anomalies))

# An empty report is the most dangerous output this tool can produce: a supervisor
# reading "0 rows, no anomalies" concludes all is well when in fact nothing was
# looked at. The usual cause is running from the wrong directory, since the COS id
# defaults to the current repo's name. Refuse instead of reporting silence.
if not report and not show_all:
    known = sorted({r["owning_cos"] for r in all_rows})
    die(f"no registry row is owned by '{cos_id}'. This would have printed an empty, "
        f"clean-looking report. Known owners: {', '.join(known)}. Run from the repo "
        f"you supervise, or pass --cos explicitly.")

cap = {"live_owned": live_owned, "cap": 3,
       "verdict": ("over cap — forbidden" if live_owned > 3 else
                   "at cap — a third needs a written reason in the registry" if live_owned == 3 else
                   "ok")}

if as_json:
    json.dump({"ok": not degraded, "operation": "cos-roster", "cos": cos_id,
               "observation_complete": not degraded, "capacity": cap,
               "pls": report, "anomalies": anomalies},
              sys.stdout, indent=2)
    sys.stdout.write("\n")
    sys.exit(3 if degraded else 0)

print(f"COS {cos_id} — {len(report)} row(s) shown, {live_owned} live and owned by you, "
      f"cap 3 ({cap['verdict']})")
if not observed:
    print("!! PROCESS OBSERVATION FAILED — every state below is UNKNOWN and no verdict is offered")

# The open board prints FIRST, above the liveness table, because the top of a
# report is the part that is actually read. It is here rather than behind a
# pointer for the reason in open_board()'s comment: a path that must be
# remembered is a path that gets skipped at hour six.
print()
for repo, (items, path, status) in sorted(boards.items()):
    if status != "OK":
        print(f"OPEN BOARD  {repo}  !! {status} — {path or 'no path'}; open items are "
              f"NOT known and must not be assumed to be none")
        continue
    if not items:
        print(f"OPEN BOARD  {repo}  0 open items ({path})")
        continue
    print(f"OPEN BOARD  {repo}  {len(items)} open ({path})")
    for item in items[:OPEN_ITEM_CAP]:
        text = item if len(item) <= OPEN_ITEM_WIDTH else item[:OPEN_ITEM_WIDTH - 1] + "…"
        print(f"  · {text}")
    if len(items) > OPEN_ITEM_CAP:
        print(f"  · … {len(items) - OPEN_ITEM_CAP} more — open {path}")
print()
print("Every close accounts for EVERY line above, count-matched: the one you hand the baton\n"
      "to is quoted verbatim, and each other line is carried, blocked on a NAMED person or\n"
      "lane, or closed — and closed means the row left TODO.md in the commit you name.\n"
      "Dropping work is the owner's call, never a supervisor's. The close also states\n"
      "board_before: <commit of the TODO.md you just read>, because a closed row leaves\n"
      "OPEN and without it nobody can tell later which list you disposed of.\n"
      "No quoted line, or fewer lines than counted above = not a close (COS iron rule 12).")
print()
print(f"{'REPO/LANE':<30} {'STATE':<11} {'TURN':<9} {'WIN':>3} {'EXEC':>4} {'WATCH':<7} "
      f"{'HEARTBEAT':<10} {'MAILBOX':<10} {'BKLG':>4}  OPEN CARDS")
for e in report:
    cards = ", ".join(f"{k}:{v}" for k, v in e["open_cards"].items()) or "-"
    turn = "in-turn" if e["in_turn"] else ("idle" if e["windows"] else "-")
    watch = ",".join(sorted(e["watchers"])) or "none"
    print(f"{e['home_repo'] + '/' + e['lane']:<30} {e['state']:<11} {turn:<9} "
          f"{e['windows']:>3} {e['executors']:>4} {watch:<7} "
          f"{e['heartbeat_age']:<10} {e['last_mailbox_activity']:<10} "
          f"{e['executor_backlog']:>4}  {cards}")
print()
print("WATCH lists Reach seats with a live registration; no listener process is needed.\n"
      "HEARTBEAT is auxiliary and never decisive.\n"
      "TURN, WIN, EXEC and MAILBOX are repository-wide; HEARTBEAT is lane-specific.\n"
      "BKLG counts unanswered executor cards in the PL inbox.")

if anomalies:
    print()
    print("ANOMALIES — each line ends with the next command")
    for a in anomalies:
        print(f"  {a}")
elif degraded:
    print()
    print("report is INCOMPLETE — see the warnings above; 'no anomalies' is not claimed")
else:
    print()
    print("no anomalies")

sys.exit(3 if degraded else 0)
PY
rc=$?
set -e
exit "$rc"
