#!/usr/bin/env bash
# roster.sh — how many agents are running and what state is each in.
# Needs python3 and the sno CLI (git for --git), checked at start; without tmux or ps the
# liveness columns degrade to HEADED?.
# The roster joins the on-disk sources:
#   ~/.local/state/agent-callsigns.jsonl   who is active (claim/release)
#   ~/.local/state/agent-states.jsonl      last self-reported state (run/wait/done/stuck)
#   ~/.local/state/agent-spawns.jsonl      spawn records (pid, deadlines, log)
#   tmux sessions                          live panes named by callsign
#   ~/.local/state/convergence/<j>.jsonl   distance-to-close samples
#
#   roster.sh [--repo <substring>] [--git <repo-path>]... [--git-only]
#       one line per ACTIVE callsign + anomaly lines, then one fixed-shape
#       git block per --git repo (see "git block" below). --git-only drops the
#       callsign table so stdout is byte-stable and two sweeps can be diffed.
#
# Computed STATE per agent (evidence beats self-report):
#   DEAD    had a process (tmux/spawn pid) and it is gone, no done/seal state
#   STOPPED the runtime process is SIGSTOPped -- alive to a liveness ping, doing nothing,
#           and it will not resume on its own; outranks RUN/SILENT and every self-report
#   RUN     process alive (or headed) AND artifact movement within 45 min
#   SILENT  process alive but nothing moved for >45 min  -> go look
#   WAIT    self-reported wait (blocked on a card/ruling), process alive
#   DONE    self-reported done (executor finished, audit-pending) or conv CLOSED
#   STUCK   self-reported stuck, or DIVERGING convergence
#   HEADED? no tmux, no spawn record — a window the user opened by hand; liveness is
#           unverifiable from here, judge by artifact movement only
# Anomalies printed after the table:
#   GHOST session   tmux session whose name is NOT an active callsign
#   UNREGISTERED    (detection limited to tmux/spawn sources)
# Exit: 0 always when readable (the roster is a report, not a gate); 2 usage; 69 a
# required tool is missing.
set -euo pipefail

case "${1:-}" in
  -h|--help) sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
esac

STATE_DIR="$HOME/.local/state"
repo_filter=""
git_repos=()
git_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo_filter="$2"; shift 2 ;;
    --git)
      [ $# -ge 2 ] || { echo "roster: --git needs a repo path" >&2; exit 2; }
      [ -d "$2" ] || { echo "roster: --git path is not a directory: $2" >&2; exit 2; }
      git_repos+=("$(cd -- "$2" && pwd)"); shift 2 ;;
    --git-only) git_only=1; shift ;;
    *) echo "roster: unknown arg $1" >&2; exit 2 ;;
  esac
done
if [ "$git_only" = 1 ] && [ "${#git_repos[@]}" -eq 0 ]; then
  echo "roster: --git-only needs at least one --git <repo-path>" >&2; exit 2
fi
missing=()
if [ "$git_only" = 0 ]; then
  for t in python3 sno; do command -v "$t" >/dev/null || missing+=("$t"); done
fi
if [ "${#git_repos[@]}" -gt 0 ]; then command -v git >/dev/null || missing+=(git); fi
if [ "${#missing[@]}" -gt 0 ]; then
  echo "roster: missing dependency: ${missing[*]} (needs python3 and the sno CLI; tmux and ps improve liveness; git for --git)" >&2; exit 69
fi

# The fleet table carries RELATIVE ages ("moved=3h22m"), so it changes on every
# run by design — useful to read, useless to diff. --git-only suppresses it so
# the git blocks below are the whole of stdout and two sweeps differ only when
# the repo actually moved. (Body left unindented: it feeds a python heredoc
# where leading whitespace is syntax.)
if [ "$git_only" = 0 ]; then
# tmux snapshot: "name pane_pid" per session (empty if no server)
tmux_snap="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | while read -r s; do
  printf '%s %s\n' "$s" "$(tmux list-panes -t "$s" -F '#{pane_pid}' 2>/dev/null | head -1)"
done || true)"

now_epoch=$(date +%s)

# One process snapshot for the whole roster. A stopped executor still looks alive to a
# liveness ping (its pane shell keeps answering), so the process status is read here.
ps_snap="$(ps -eo pid=,ppid=,stat=,comm= 2>/dev/null || true)"

ROSTER_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" \
python3 - "$STATE_DIR" "$repo_filter" "$now_epoch" "${git_repos[@]}" <<'EOF' 3<<<"$tmux_snap" 4<<<"$ps_snap"
import json, os, subprocess, sys, glob, datetime, mailbox, tempfile, email.utils

state_dir, repo_filter, now_epoch = sys.argv[1], sys.argv[2], int(sys.argv[3])
SILENT_MIN = 45

def read_jsonl(path):
    rows = []
    try:
        # errors="replace": one torn non-UTF8 append must not blind the whole
        # roster during a partial append
        with open(path, errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line: continue
                try: rows.append(json.loads(line))
                except ValueError: continue
    except OSError: pass
    return rows

def ts_epoch(ts):
    if not ts or not isinstance(ts, str): return None   # a numeric ts must not crash the supervisor
    try: return int(datetime.datetime.fromisoformat(ts).timestamp())
    except (ValueError, TypeError): pass
    try: return int(email.utils.parsedate_to_datetime(ts).timestamp())
    except (ValueError, TypeError): return None

def age_str(ep):
    if ep is None: return "?"
    m = max(0, (now_epoch - ep)) // 60
    return f"{m//60}h{m%60:02d}m" if m >= 60 else f"{m}m"

def pid_alive(pid):
    try: os.kill(int(pid), 0); return True
    except (OSError, ValueError, TypeError): return False

work_cache, read_failures = {}, []
def work_messages(journey):
    if journey not in work_cache:
        with tempfile.TemporaryDirectory() as directory:
            output = os.path.join(directory, "work.mbox")
            result = subprocess.run(["sno", "reach", "export", "--work", journey,
                                     "--output", output], capture_output=True, text=True)
            if result.returncode:
                read_failures.append(f"REACH-READ-FAILED: {journey}: {result.stderr.strip()}")
                work_cache[journey] = None
            elif os.path.isfile(output):
                work_cache[journey] = list(mailbox.mbox(output))
            else:
                work_cache[journey] = []
    return work_cache[journey]

def _ack_seen(callsign, journey):
    messages = work_messages(journey)
    if messages is None: return None
    return any(str(msg.get("Subject", "")) == f"[STATUS] on-station: {callsign}"
               for msg in messages)

def _close_stalled(journey):
    # A close-audit was requested for this journey but no SEAL/PASS reply exists.
    # Returns the epoch of the latest unsealed close-request, else None.
    # Append position, not timestamps, decides the order of events.
    def close_events():
        out = []
        for msg in work_messages(journey) or []:
            t = str(msg.get("Subject", ""))
            if "close-audit requested" in t: out.append(("req", ts_epoch(msg.get("Date"))))
            elif "SEALED" in t or "CLOSE-AUDIT PASS" in t: out.append(("seal", None))
        return out
    events = close_events()
    if not events: return None
    last_is_req, last_req_ep = False, None
    for k, e in events:
        if k == "req": last_is_req = True; last_req_ep = e or last_req_ep
        else: last_is_req = False
    return last_req_ep if last_is_req else None

# --- sources ---
calls = read_jsonl(os.path.join(state_dir, "agent-callsigns.jsonl"))
last = {}
for r in calls:
    if r.get("event") in ("claim", "release") and r.get("name"):
        last[r["name"]] = r
active = {n: r for n, r in last.items() if r.get("event") == "claim"}

states = {}
for r in read_jsonl(os.path.join(state_dir, "agent-states.jsonl")):
    if r.get("name"): states[r["name"]] = r

spawns = {}
for r in read_jsonl(os.path.join(state_dir, "agent-spawns.jsonl")):
    if r.get("callsign"): spawns[r["callsign"]] = r   # latest wins

tmux = {}
with open(3) as f3:                     # fd 3 = tmux snapshot from the shell
    for line in f3:
        parts = line.split()
        if parts: tmux[parts[0]] = parts[1] if len(parts) > 1 else ""

procs = {}                              # pid -> (ppid, stat, comm)
children = {}                           # ppid -> [pid]
with open(4) as f4:                     # fd 4 = one process snapshot for every agent
    for line in f4:
        parts = line.split(None, 3)
        if len(parts) < 4: continue
        pid, ppid, stat, comm = parts[0], parts[1], parts[2], parts[3].strip()
        procs[pid] = (ppid, stat, comm)
        children.setdefault(ppid, []).append(pid)

def stopped_runtime(pane_pid, runtime):
    """The runtime process if it is STOPPED, else None.

    Identified by POSITION, not by name: the pane runs the runner, whose child is the wall
    (`timeout`), whose child is the runtime. Name alone is unsafe — an executor's tree can
    contain helper processes named after other tools. Falls back to a unique name match inside this pane's
    own tree when there is no wall wrapper; two matches is not a coin toss and answers nothing.
    A first status character of uppercase `T` is stopped by a job-control signal; real runtimes
    report `Tl`, so the FIELD is never compared whole. Lowercase `t` is a debugger stop and is
    left alone — someone is attached and meant it."""
    if not pane_pid or pane_pid not in procs: return None
    cand = None
    walls = [k for k in children.get(pane_pid, []) if procs[k][2] == "timeout"]
    if walls:
        kids = children.get(walls[0], [])
        if len(kids) == 1: cand = kids[0]
    if cand is None:
        seen, stack, matches = set(), list(children.get(pane_pid, [])), []
        while stack:
            pid = stack.pop()
            if pid in seen: continue
            seen.add(pid)
            if procs.get(pid, ("", "", ""))[2] == runtime: matches.append(pid)
            stack.extend(children.get(pid, []))
        if len(matches) == 1: cand = matches[0]
    if cand is None: return None
    stat = procs[cand][1]
    return cand if stat[:1] == "T" else None

def conv_info(journey):
    path = os.path.join(state_dir, "convergence", f"{journey}.jsonl")
    rows = read_jsonl(path)
    if not rows: return None, None, None
    lastr = rows[-1]
    # verdict comes from convergence-watch.sh (never reimplement its rules):
    # rc 0 CONVERGING / 2 INSUFFICIENT / 3 DIVERGING / 4 WARNING / 5 CLOSED
    verdict = None
    cw = os.path.join(os.environ.get("ROSTER_SCRIPT_DIR", "."), "convergence-watch.sh")
    if os.path.isfile(cw):
        try:
            rc = subprocess.run(["bash", cw, "verdict", "--journey", journey],
                                capture_output=True, timeout=15).returncode
            verdict = {0: "CONVERGING", 3: "DIVERGING", 4: "WARNING", 5: "CLOSED"}.get(rc)
        except (subprocess.TimeoutExpired, OSError): pass
    return lastr.get("remaining"), ts_epoch(lastr.get("ts")), verdict

# --- join ---
rows_out, anomalies = [], []
for name, claim in sorted(active.items()):
    repo = claim.get("repo", "")
    if repo_filter and repo_filter not in repo: continue
    journey = claim.get("journey", "?")
    claim_epoch = ts_epoch(claim.get("ts"))
    st = states.get(name, {})
    # A state event counts ONLY if it names this exact journey — no legacy
    # window: unauthenticated events are never persisted (callsign.sh) and
    # never trusted here.
    if st.get("journey") != journey: st = {}
    st_epoch = ts_epoch(st.get("ts"))
    self_state = st.get("state")
    sp = spawns.get(name)
    in_tmux = name in tmux
    proc_alive = None
    if in_tmux:
        proc_alive = pid_alive(tmux.get(name))
    elif sp and sp.get("journey") == journey:
        proc_alive = pid_alive(sp.get("pid"))

    remaining, conv_epoch, verdict = conv_info(journey)
    # artifact movement = WORK evidence only; a self-reported title is a claim,
    # not progress, and must not suppress the stall signal
    move_epochs = [e for e in (conv_epoch,) if e]
    if sp and sp.get("log"):
        try: move_epochs.append(int(os.stat(sp["log"]).st_mtime))
        except OSError: pass
    last_move = max(move_epochs) if move_epochs else None
    quiet = last_move is None or (now_epoch - last_move) > SILENT_MIN * 60

    stopped_pid = None
    if in_tmux and sp:
        stopped_pid = stopped_runtime(tmux.get(name), sp.get("runtime") or "codex")

    if proc_alive is False and self_state not in ("done",):
        state = "DEAD"
    elif stopped_pid:
        # Outranks every self-report and every movement heuristic: the process is stopped by
        # the kernel and will not resume on its own, whatever the agent last claimed.
        state = "STOPPED"
    elif verdict == "DIVERGING":
        state = "STUCK(diverging)"      # judged, outranks any self-report
    elif self_state == "done" or verdict == "CLOSED":
        state = "DONE(audit-pending)"
    elif self_state == "stuck":
        state = "STUCK"
    elif self_state == "wait" and proc_alive is not False:
        state = "WAIT"
    elif proc_alive is None:
        state = "HEADED?" + ("-quiet" if quiet else "-moving")
    elif quiet:
        state = "SILENT"
    else:
        state = "RUN"

    ev = []
    ev.append("tmux" if in_tmux else ("spawn-pid" if sp and sp.get("journey") == journey else "no-proc-source"))
    if stopped_pid: ev.append(f"runtime-stopped(pid {stopped_pid})")
    if proc_alive is True: ev.append("alive")
    if proc_alive is False: ev.append("proc-gone")
    ev.append(f"conv={remaining if remaining is not None else '-'}"
              + (f"/{verdict}" if verdict else "") + f"({age_str(conv_epoch)})")
    if self_state: ev.append(f"self={self_state}({age_str(st_epoch)})")
    ev.append(f"moved={age_str(last_move)}")

    # deadline alarms — the roster is what notices a card that never arrives (a watcher
    # only reacts to cards that do); these fire on every sweep that runs the roster
    if sp and sp.get("journey") == journey:
        ack_due = ts_epoch(sp.get("ack_due"))
        if ack_due and now_epoch > ack_due and _ack_seen(name, journey) is False:
            anomalies.append(f"NO-ACK: {name} past ack deadline ({age_str(ack_due)} overdue) — treat dispatch as NEVER DELIVERED: ping once, then re-dispatch")
        conv_due = ts_epoch(sp.get("conv_due"))
        if conv_due and now_epoch > conv_due and conv_epoch is None:
            anomalies.append(f"NO-CONVERGENCE: {name}/{journey} past first-sample deadline ({age_str(conv_due)} overdue) — stalled or ignoring the contract: go look")
    # CLOSE-STALLED backstop: a close-audit requested but not sealed after 30 min means
    # the work is waiting on a verdict nobody delivered. Fires for any active agent
    # (spawned or hand-opened), so a parked executor cannot idle to the wall unnoticed.
    cs_ep = _close_stalled(journey)
    if cs_ep is not None and (now_epoch - cs_ep) > 30 * 60:
        anomalies.append(f"CLOSE-STALLED: {name}/{journey} close-audit requested {age_str(cs_ep)} ago, still unsealed — run the close audit and seal it now (otherwise the executor may reach its wall with the close unfinished)")
    rows_out.append((name, journey, os.path.basename(repo) or repo, state, " ".join(ev)))

for sess in tmux:
    if sess not in active:
        anomalies.append(f"GHOST session: tmux '{sess}' is not an active callsign — leftover session or unregistered agent")

# PL heartbeats: touched at the start of every PL turn (boot, card, and user reply).
# A fresh heartbeat proves recent activity; a stale one proves nothing about awake versus
# asleep (a PL mid-conversation with the user leaves no heartbeat), so it is a prompt to
# verify, never a sleep/death verdict.
hb_dir = os.path.join(state_dir, "pl-heartbeat")
heartbeats = []
for hb in sorted(glob.glob(os.path.join(hb_dir, "*"))):
    name = os.path.basename(hb)
    if repo_filter and repo_filter not in name: continue
    try: ep = int(os.stat(hb).st_mtime)
    except OSError: continue
    heartbeats.append(f"PL {name}: last heartbeat {age_str(ep)} ago")
    # Stale = UNKNOWN, not dead: a PL handling another task can leave this quiet.
    if now_epoch - ep > 30 * 60:
        anomalies.append(f"PL-heartbeat quiet {age_str(ep)}: {name} — NOT a sleep/death signal (a PL talking to the user touches no heartbeat); confirm via the user or the live window, never report it as 'not awake'")

print(f"{'NAME':<8} {'JOURNEY':<38} {'REPO':<18} {'STATE':<18} EVIDENCE")
for r in rows_out:
    print(f"{r[0]:<8} {r[1]:<38} {r[2]:<18} {r[3]:<18} {r[4]}")
if not rows_out:
    print("(no active callsigns" + (f" matching '{repo_filter}'" if repo_filter else "") + ")")
for h in heartbeats:
    print(h)
for a in anomalies:
    print(f"!! {a}")
for error in read_failures:
    print(f"!! {error}")
EOF
fi   # end of the fleet table (skipped under --git-only)

# --- git block (--git <repo-path>, repeatable) -------------------------------
# The repo half of the wake sweep is byte-stable for unchanged repo state — no
# clock, no relative dates, no "-3 vs -4" drift, no ad-hoc path list.
#
# WHICH paths are watched is repo knowledge, not roster knowledge, so it lives
# in <repo>/.pl/watch.paths (whitespace-separated; paths containing spaces are
# not supported). Unknown keys and #comments are ignored:
#     src:       apps packages tests
#     protected: evals/baselines.json docs/spec.md
# No file / no key: src falls back to the whole tree, and the protected
# sections say so rather than silently reporting the whole tree as protected.
#
# Sections, always emitted, always in this order:
#   BRANCH   current branch
#   LOG      last 5 commits, absolute committer date
#   DIRTY    uncommitted paths inside src
#   PROT     uncommitted paths inside protected
#   PROTLOG  commits inside the last 5 that touched protected
# Exit stays 0: like the rest of the roster this is a report, not a gate.
GIT_LOG_N=5

watch_key() { # $1 repo, $2 key -> value line on stdout; 1 if the key is absent
  local conf="$1/.pl/watch.paths" key="$2" line k
  [ -f "$conf" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    case "$line" in *:*) ;; *) continue ;; esac
    k="${line%%:*}"
    k="${k//[[:space:]]/}"
    [ "$k" = "$key" ] || continue
    printf '%s\n' "${line#*:}"
    return 0
  done < "$conf"
  return 1
}

emit() { # $1 label, stdin -> "<label> <line>" per line, or "<label> (none)"
  local label="$1" line seen=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%-7s %s\n' "$label" "$line"
    seen=1
  done
  [ "$seen" = 1 ] || printf '%-7s %s\n' "$label" "(none)"
}

git_block() { # $1 repo path
  local repo="$1" src_raw prot_raw has_src=0 has_prot=0
  local -a src=() prot=()

  printf '=== GIT %s %s\n' "$(basename -- "$repo")" "$repo"
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'BRANCH  (not a git repository)\n'
    printf '!! GIT %s: --git was given a path that is not a git repository — fix the caller, this repo was NOT checked\n' "$repo" >&2
    return 0
  fi

  printf 'BRANCH  %s\n' "$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '(detached)')"
  # every git call is `|| true`-guarded: an unreadable repo must degrade to an
  # empty section, never abort the roster the rest of the fleet depends on
  { git -C "$repo" log --format='%h %cI %s' -"$GIT_LOG_N" 2>/dev/null || true; } | emit LOG

  src_raw="$(watch_key "$repo" src)" && has_src=1
  prot_raw="$(watch_key "$repo" protected)" && has_prot=1
  # word splitting is the documented config format (whitespace-separated paths)
  [ "$has_src" = 1 ] && read -ra src <<<"$src_raw"
  [ "$has_prot" = 1 ] && read -ra prot <<<"$prot_raw"

  { git -C "$repo" status --porcelain=v1 -- "${src[@]}" 2>/dev/null || true; } \
    | LC_ALL=C sort | emit DIRTY

  if [ "$has_prot" = 1 ] && [ "${#prot[@]}" -gt 0 ]; then
    { git -C "$repo" status --porcelain=v1 -- "${prot[@]}" 2>/dev/null || true; } \
      | LC_ALL=C sort | emit PROT
    { git -C "$repo" log --format='%h %cI %s' -"$GIT_LOG_N" -- "${prot[@]}" 2>/dev/null || true; } \
      | emit PROTLOG
  else
    printf '%-7s %s\n' PROT "(undefined — no 'protected:' in $repo/.pl/watch.paths)"
    printf '%-7s %s\n' PROTLOG "(undefined — no 'protected:' in $repo/.pl/watch.paths)"
  fi
}

for gr in "${git_repos[@]}"; do
  git_block "$gr"
done
