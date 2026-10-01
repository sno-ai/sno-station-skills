---
name: cos-watch
description: "Supervise active PLs, including wake cadence, liveness, recovery, large-run launches, and cross-journey order. Loaded ONLY by the cos core via its routing table; NEVER auto-load from context or invoke directly."
requires:
  programs: []
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
    - {slot: 4.background-processes, need: required}
---

# COS — live supervision

Apply the COS core's finite development budget and affected-test scope. Estimate setup,
execution, and reporting from available prior runtimes; do not add estimation machinery
or preflight. Full suites and new security checks need the owner's specific approval,
never COS approval. Missing auxiliary records do not stop functional work.

Before running these commands, set `COS_SKILL_DIR` and `PL_SKILL_DIR` to the absolute directories of the installed `cos` and `pl` skills, in the same Bash call.

Prerequisites are listed in the `cos` core (§Prerequisites and terms): Linux, tmux, flock, jq, python3, pstree and pgrep, and the `pl` skill.

Loaded whenever anything is in flight: a journey running, a night shift open, a wake
tick firing, a PL gone quiet, a big run launching.

**Exclusive authority of this overlay:** reopening a dead PL (within the cap of three),
and editing a stale board document mid-flight. Everything else still leaves as a card.

## The wake cycle

COS schedules its own wakeups. During a night shift the owner types nothing.

**The intervals live in ONE table — the core's Iron rule 0 — and are not
restated here.** On a declared night shift the number is 10 minutes and is never reasoned
upward. A second copy of that table is how a supervisor ends up picking 20–60 minutes on
the one shift where the law says 10 minutes.

Every tick, in order:

1. `sno reach inbox --as <your address>`, then `"${COS_SKILL_DIR}/scripts/cos-roster.sh"` — the roll call.
2. Re-read `LEARNING.md`'s index. It is at most 64 lines and effectively free, and re-reading is
   what stops a long session from running on a cached picture.
3. Check each owned PL against the six reasons to act (core, §Decision discipline).
4. **Flush the buffer if anything carded in.** An executor or PL that sent a card is
   stopped and waiting — that reply carries every buffered item for free (core skill,
   §Card timing). Buffered items that nobody has given you a free ride for stay buffered.
5. Append **one line** to the watch log: time (UTC by default), each PL's state, what moved, and how
   many items are still buffered — a buffer nobody reports is a buffer that gets forgotten.
6. **Stay silent unless a trigger fires.** A tick that finds nothing produces no message
   to the owner and no card.

### How to actually schedule it

**One mechanism, and nothing blocks.** A COS that ends its turn without a heartbeat armed
has become the unwatched inbox its own core law describes — the failure it exists to
prevent, committed by the supervisor. End the turn; a heartbeat rings your own seat to
start the next one. The same on every runtime, with no waiting command and no polling
loop:

```bash
# Register first, or a PL's card cannot ring this window between ticks.
# register prints `cos-claim: registered address=<addr> owner=<token>`; keep the address.
COS_ADDR=$(bash "${COS_SKILL_DIR}/scripts/cos-claim.sh" register [<seat-letter>] \
  | sed -n 's/^cos-claim: registered address=\([^ ]*\).*/\1/p')
[[ -n "$COS_ADDR" ]] || exit 64
heartbeat --interval <interval> --label cos-<name> -- sno reach ring "$COS_ADDR"
```

`<interval>` comes from the core's table (`10m` on a night shift). `heartbeat --list` shows
whether it is still armed (yours is marked); it stops by itself after 24 hours, so re-arm
then, and `heartbeat --stop cos-<name>` before re-arming with a new interval. The next
wake is armed before the turn ends, every time — including the tick that found nothing.

**THE RING IS A HINT. YOUR INBOX IS THE QUEUE.** Begin every tick with
`sno reach inbox --as <your-address>` and never treat "a ring arrived" as the same event as
"a card arrived". Cards whose wake failed sit in the inbox for hours, questions included.
Every send that fails to wake returns exit 5 or 6 to its sender, and reading the inbox on
your own schedule is the independent check that the queue itself is being drained.

**The tell:** send exit 5 or 6 means the card
exists but the wake did not land. Check the recipient's inbox immediately and restore its
registration. Do not resend the card and do not create a second wake path with a direct
terminal command.

## Liveness — the turn lock leads; the heartbeat is never decisive

Run `"${COS_SKILL_DIR}/scripts/cos-roster.sh"`. Never assemble this by hand — that is
the exact action it was built to abolish.

| Source | Proves | Does NOT prove |
|---|---|---|
| **Turn lock + heartbeat-ring, read as ONE pair** — the idle-inhibitor reading `Codex is running an active turn` (it exists only for Codex on Linux with systemd; on any other setup judge liveness from the seat and `sno reach seats` instead), together with whether that lane's heartbeat-ring is armed (`heartbeat --list`) | the pair, and only the pair: **lock = a turn is executing**; **no lock + heartbeat-ring armed = healthy between ticks** (reachable, NOT working); **no lock and no heartbeat-ring = not reachable on schedule**, a compliance failure | **the lock alone anything**: a turn stuck on one command holds it too. Also: Claude-runtime agents take no lock at all |
| Role from arguments — `codex exec …` vs plain `codex …` | executor versus interactive window | **which** window. A PL's window and one the owner opened are indistinguishable — say so rather than guessing |
| Heartbeat file age | recent activity when fresh | **nothing when stale.** A PL deep in an owner conversation leaves no other disk trace |
| Inbox and artifact movement | work is landing | quiet may mean thinking, waiting, or dead. Repo-wide, so it cannot tell two lanes apart |

The state that matters most is not DEAD, it is **UNREACHABLE**: a session exists, no
turn is executing, no heartbeat-ring is armed, and the ring does not start a turn. That
agent is alive, will answer if typed into, and **cannot receive a card**. It is the shape
of the multi-hour stall and it looks fine in every window screenshot. **The predicate is
the ring outcome plus what the seat then does, never the lock** — on Codex a missing lock
means nothing is running, so send and judge by whether the ring started a turn. A Claude
agent takes no lock and must have its heartbeat found in `heartbeat --list` or be treated
as unreachable. An armed heartbeat is reachability evidence, never proof of progress.

**Never reopen off a stale heartbeat alone.** A stale heartbeat is routine on a PL that
is mid-turn and about to dispatch. Reopening over a working supervisor is a bigger failure
than the stall it prevents.

## Decision rules live in the core

The six reasons to act, the restraint list, the two staffing questions for opening a
new agent, and the circuit breaker are in the `cos` core, §Decision discipline. Check
them there on every tick; this file keeps only the mechanics around them — the wake
cycle, liveness, reopening, big-run posture, sequencing.

## Reopening a dead PL

The one non-document action COS takes alone.

1. **Confirm death**: no window process at all. A tmux husk is not proof, and a stale
   heartbeat is not proof. **UNREACHABLE is not death** — that agent is alive and will answer
   if typed into; reopening on top of it creates a second claimant to the same lane.
2. **Claim under the lock.** Take `flock "${SNO_PL_REGISTRY:-$HOME/.local/state/pl-registry.tsv}.lock"`, then inside
   it re-read the registry, re-check ownership and the count, and write the claim before
   releasing. Counting outside the lock lets two COS both see room for one more and
   produce four supervisors. Replacing a dead one is free; one → two is fine; two → three
   needs a written justification in the row. **A fourth is forbidden**, and
   `cos-roster.sh` still reports every lane when capacity is exceeded. Reconcile workload
   through authorized scheduling or transfer while continuing supervision; capacity is
   not permission to lose visibility or park the assigned work.
3. **Reopen** with the same runtime the dead one used, per its registry row; record the
   new session, the reopen reason and the time (UTC by default) in that row — under the same lock.
4. **Hand over a written state summary** — never let a fresh PL reconstruct the lane
   from scratch. It must contain: what is sealed and must not be redone (with commits),
   what is stopped and why, the current charter queue in order, **this lane's strict registered
   PL seat address**, and the reciprocal turn-exit heartbeat-ring block from the core with
   that address already substituted in. **The charter queue is quoted from the repo's
   `TODO.md` `OPEN` section, not rebuilt from what the dying lane was last seen doing** —
   a replacement handed a queue assembled from a supervisor's recollection inherits that
   supervisor's blind spots, which is how a ranked item survives a reopen without anyone
   deciding to drop it.
5. **Log it.** Reopens are the metric that tells whether the layer below is healthy.

## Big-run posture — the launch window

**The opening minutes of a large run are the densest friction window** — environment
decay, missing bindings, stale virtual environments, orphan processes. The reactive
posture (arm a watch, wait for a card) is wrong there.

- When a big run starts, **read the startup output yourself** at a minutes-level cadence
  until it is cruising (a background `"${PL_SKILL_DIR}/scripts/log-watch.sh" --ring`, plus at most one bounded
  `sno reach watch <seat> --timeout 5`; never a long watch). Waiting is the cheap posture for the steady state, never for the
  launch.
- **First confirmed red: go in and root-cause now.** Fix and relaunch, or authorise a
  *capped* evidence-continue. An uncapped "let it finish for forensics" is illegal — the
  remaining phases' results are predetermined and carry zero information.
- **Corrupting-class reds invert this**: continuing writes destroys the scene. Stop and
  snapshot.
- **On consecutive reds, dig immediately; the moment the root cause is known, cut; never
  wait for the instrument to burn out.**
- **Front-loaded-slow runs are the exception to the throughput kill rule.** Some suites
  are legitimately slow at the start; extrapolating a kill from the first two minutes
  false-kills them. If a run is known front-loaded-slow, restate that caveat in every
  card that mentions the kill rule.

## Cross-journey sequencing — the judgment only COS can make

A PL sees its own journeys. COS sees all of them. That produces a class of ordering
error no PL can catch alone, and catching it before dispatch is COS's job.

**Worked example.** Suppose a PL proposes refreshing a checksum manifest before starting
work, but the journey in flight will edit *a file the manifest covers*. Refreshing first
makes the manifest stale again at once, so the refresh is paid for twice. The correct order
is to land the product change first and refresh last.

Before authorising any parallel dispatch:

- **Map the files each journey will touch.** Two journeys that write the same file must
  not run in parallel. A journey that only *reads* a file another writes is usually safe,
  and that reader must be explicitly forbidden from writing source.
- **Treat that map as a sequencing check only.** Disjoint files never authorise a new
  worktree and do not prove the combined behaviour will merge safely.
- **Order anything that freezes, hashes, snapshots, or measures a file AFTER everything
  that modifies it. Freeze last, always.**
- **Say the constraint out loud in the card, with its reason.** "Do not do X first,
  because Y edits the same file" is absorbed; a bare "do X last" gets helpfully
  reordered.

## Scheduling honesty

When a PL returns an estimate, check it against the **clock**, not only the budget. An
item whose end-to-end estimate exceeds the shift length, or that needs the owner online
twice, cannot start inside the shift. That is a calendar problem, not a scope problem: hold it
for a window where they are available, and fill the shift with bounded work that can seal.

Adopting a subordinate's correct scheduling instinct is a good outcome — name it as
theirs when you adopt it.

## Pausing the lane for an owner-designated evaluation

Run an owner-designated evaluation alongside work that does not depend on its result.
Sequence only the dependent operation after the real result, and keep its owner responsible
for completion. Resolve resource contention by scheduling or using existing isolation; do
not pause unrelated PLs merely because an evaluation is running. Report actual coverage.
