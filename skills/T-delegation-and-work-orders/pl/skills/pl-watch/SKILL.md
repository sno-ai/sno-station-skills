---
name: pl-watch
description: "PL (Project Lead) role sub-skill for supervising in-flight executors. Loaded ONLY through the pl core routing table; NEVER auto-load from context, never invoke directly."
requires:
  programs: []
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
    - {slot: 4.background-processes, need: required}
---

# PL · Watch — in-flight supervision & process control

Scripts named below run as `bash "${PL_SKILL_DIR}/scripts/<name>.sh" ...`, where `PL_SKILL_DIR` is the
absolute path of the `pl` skill directory; set it in the same Bash call.

Sub-skill of the PL role. The pl core skill invokes this EXPLICITLY whenever
executors are in flight: a watch fires, a card lands, a stall or convergence
doubt appears, an expensive run is requested, or a GPU phase starts. Core iron
rules bind unchanged: never write product code; never trust report prose — disk
over words; the owner ("owner" means whoever owns the work, often the user) is addressed in the user's own
language, while agent-to-agent text uses the project's working language (English by default). Canonical scripts:
the pl skill's `scripts/`. The workspace layout (`ai-doc/ACTIVE/PL/`, ledgers) is documented in the pl core's
State files section. Design
principle behind everything here: **the machine must lose patience
before the owner does** — every place the owner has to scold marks a missing
mechanical control. Words such as journey, callsign, seat, card, night shift, charter and take-over
are defined once, in the pl core's Terms glossary. The rules in this file are the PL role's
defaults; a project may choose otherwise.

## Card-handling discipline (PL side of Reach)

**Wake sequence is fixed**: the core boot/wake ritual runs FIRST —
`bash "${PL_SKILL_DIR}/scripts/roster.sh" --git <repo-path>` (when the project uses git), then the inbox read
(`sno reach inbox --as "$PL_ADDR"`; pl core §Communication, boot
ritual); everything below applies AFTER that ritual, when reasoning about a
specific journey or card.
**Every wake includes the journey thread** — rings, watch firings, monitor events,
background-task completions, owner messages alike: run
`sno reach log --as <your-strict-address> --work <active>` BEFORE
reasoning about anyone's state;
never declare an executor unresponsive without reading the journey thread
(the cards cross — a reply and a fresh question can land within
seconds of your own card). There is no idle:
after any reply you end the turn with the heartbeat-ring armed — copy the standard command verbatim,
never improvise shell:
```bash
# From the repo root. Ten minutes is the default while a night shift is declared; 3m in a launch window,
# 20-30m steady daytime, 45-60m when everything waits on someone else.
# One resolver, never a repository-only first-row lookup: on a repository with several PL lanes
# that would silently hand one lane another lane's seat; the resolver refuses rather than guesses.
PL_ADDR=$(bash "${PL_SKILL_DIR}/scripts/lane-resolve.sh" --repo "$PWD" --field addr) || exit 64
label="pl-${PL_ADDR#pl.}"; label="${label%@*}"
if heartbeat --list | awk -v l="$label" '$3==l{f=1} END{exit !f}'; then
  echo "heartbeat already armed for $label" >&2
  exit 64
fi
heartbeat --interval 10m --label "$label" -- sno reach ring "$PL_ADDR"
```
The heartbeat hook rings your own seat; the ring starts your next turn, and no listener or reader
is needed. Nothing here blocks: you arm it and end the turn.
**Arm at most one**: the block above checks for a live heartbeat with this label
before arming; if one exists, do not arm another — per-turn arming
without the check stacks heartbeats, and every one rings on its own clock. **Ordering iron rule: clear ALL
pending cards BEFORE arming** — a card left unanswered when the turn ends is found only by
the next ring. A
downgrade to the owner counts as a reply (send the downgrade answer card);
only then arm. **Every inbound card is handled, never left — and handled has two
verbs.** Reach keeps an unhandled card in your queue, and its prompt reminder keeps naming it, on
UNHANDLED mail, not on unread mail and not on
content: a card you read and correctly judged to owe no answer keeps being named until it is
handled. `reply` and `dismiss` both stop it; reading does not.
So triage by header, one card at a time and never in bulk — `sno reach inbox --as
<addr>` prints each delivered path and its subject, and `grep -m1 -i '^x-type:' <path>` types it. `question`
and `decision` both owe you an act: reply on the card's own path
(`sno reach reply --as "$PL_ADDR" --card <path> [--state accepted|completed]`, body on stdin;
work you carry out is accepted, then completed; a question that only asks you for information is
answered without `--state`), and for a decision reply with the disposition. `dismiss` refuses those
types and is ONLY for a card that owes no answer —
an `info`, or an `answer` you have absorbed. A type you do not recognise is not
dismissible: treat it as actionable.

```bash
sno reach dismiss --as "$PL_ADDR" --card <delivered-path> --reason '<why none is owed>'
```

Dismiss writes no card, keeps the card's bytes and thread history, and moves your copy from the
actionable queue to handled `cur/`; it deletes nothing. Replying to a card that owes no answer
also stops the reminder — at the cost of an echo the other side must then dismiss.
**Card age changes URGENCY, never authority**: on an old card, inspect the
linked thread first — a terminal park/ruling already there means respond on
that thread; otherwise apply the Triage Predicate regardless of age — age proves
neither escalation nor resolution.
**Armed CONTINUOUSLY, not merely "before idle":**
a blocker landing while the PL is HEADS-DOWN on a different task — spawning an
adversarial probe, running a close-audit, writing an owner report — sits unseen
until the PL resurfaces UNLESS the heartbeat is already live. The rule is not "arm when you go idle,"
it is "a heartbeat is live whenever a card could land" — the same heartbeat keeps ringing across
long tasks, so after every ring you handle the cards and end the turn again; re-arm only when
`heartbeat --list` shows it gone (a heartbeat ends after its maximum hours). A
**headed executor (one the owner opened in their own terminal, not one the PL spawned) has NO `spawn-exec` ack/no-ack alarm** (that
alarm exists only for PL-spawned tmux sessions): the heartbeat — or a manual inbox
read — is the ONLY thing that catches its Blocker cards, so treat any headed session
as extra-vigilance and never promise to "catch its card" without a live heartbeat
behind the promise. Two more hygiene clauses: a heartbeat is yours to stop
(`heartbeat --stop <label>`) when its journey or shift ends, so it does not ring for nothing; and
another seat's heartbeat is left alone — killing
someone else's machinery is whack-a-mole you lose.

**Supersede protocol**: a superseding
order must NAME and VOID the card it replaces ("this voids m-…"); an order that
merely contradicts an earlier card leaves two live rulings and the executor
free to obey the stale one — an executor deaf inside a long subprocess resumes
and obeys whichever card it reads first. When the
executor is subprocess-blocked, delivery is NOT a card it cannot read: the PL
terminates the subprocess AT ORDER TIME — the termination IS the delivery — and
posts the superseding card before the executor resumes.

## Who rules, and how

Who may rule and how — the Triage Predicate (canonical text), the severity checklist,
the closed five-option disposition menu, the HIGH-solo second look, and the circuit
breaker — is in the `pl` core, §Decision discipline. Read them there before
disposing of any card. The bands and lists of what the PL may decide alone, and what is
owner-only, live in the decision-rights file (`~/.config/sno/decision-rights.md`; shipped default
`references/decision-rights.md` in the pl skill); it wins over any text here. This file keeps only the mechanics around them — card
handling, watching, take-over, verification time budget.

## Live log watching — four tiers, four different questions

The four watch tiers sit beside the communication mechanisms; do not collapse them. Reach cards
are the asynchronous record, the live agent seat is the instant channel (`sno reach call`), and
`sno reach ring` is the wake. Reading a seat is one bounded `sno reach watch <seat> --timeout 5`,
never a long or unbounded watch.
Ordinary progress only streams and must never create a card. Only approval-waiting,
idle and dead states may ring. Repeated repaint of the same state rings once. A ring only wakes
the PL and never proves processing. A durable instant order is carded first and the
window message names the exact Message-ID. An in-window owner ruling is written back to that
thread. Outside the launch window, take another bounded read whenever COS requests a pinned watch or
the PL needs direct progress evidence; otherwise the persistent log watch and the heartbeat-ring are the
cruise posture.

A poll answers "alive or dead". It cannot answer "doing the right thing". **Anything running
longer than five minutes gets a live stream, not a poll**; the poll demotes to a fallback
whose only job is to guarantee you can still be reached. Keep the four tiers separate — each
answers a different question, and a supervisor who merges them ends up with one mechanism
that answers none of them:

| Tier | The question it answers | Mechanism | Cadence |
|---|---|---|---|
| 0 · liveness | is the process alive, is the log growing | `bash "${PL_SKILL_DIR}/scripts/roster.sh"` for the fleet, `bash "${PL_SKILL_DIR}/scripts/exec-state.sh" --callsign <name>` for one agent | fallback only, ~20 min |
| 1 · event stream | did something happen I would act on | persistent `log-watch.sh` (below) on the executor log, armed **at spawn** | continuous, push |
| 2 · orientation read | is it pointed at the right tree, branch, files | one bounded `sno reach watch <seat> --timeout 5` on the retained address, plus **you** reading the log UNFILTERED | T+5 and T+10, then stop |
| 3 · convergence | is it getting closer | cards with numbers, commits, `bash "${PL_SKILL_DIR}/scripts/convergence-watch.sh"` | 30 min / on card |

**"Alive" is not a state, and a pid check cannot produce one.** The pane's shell answers a
liveness ping forever, and it is never the runtime — an executor stopped by a stop signal before
drawing a character still reports health to every such check. Read the roster, and
the per-agent state when one agent is in question (commands in the table). What the
four loud answers mean, and what you do about each:

- **`STOPPED` / `stopped`** — the runtime is halted by a stop signal (SIGSTOP) and **will not resume on its
  own**. Not a slow agent. Attach to the pane, then relaunch; nothing you send it will arrive.
- **`unknown` on a Claude executor** — this instrument cannot read that runtime (its
  background helpers make it look busy forever, and its turn record never reads as closed). Read
  the pane yourself; do not treat it as idle and do not treat it as working.
- **`runtime-mismatch`** — the spawn record and the process in the pane are different things. The
  record is stale, or the pane is not the executor it names. Check which agent actually holds
  that callsign before sending it anything.
- **`ambiguous-runtime`** — two processes in one pane answer to the same name, so nothing can say
  which is the executor. Usually two agents sharing a window: separate them.

**Tier 2 is the highest-value ten minutes of the run, and it is a different method — not a
denser tier 1.** That window is when an executor picks its checkout, its branch and its
target files, and reads or fails to read its charter. A wrong pick is one sentence to correct
at T+5 and a lost run at T+6h. No filter can do this job: one tuned for failure markers stays
perfectly silent through a flawless run in the wrong directory. Confirm four things by name —
which checkout, which branch, which files it opened, and whether its first actions match
the charter's first instruction.

### An executor log is not an event stream

Five kinds of line interleave, and only the last is a fact about the world:

1. **Echo** — content the agent READ (file contents, a doc it grepped, a skill it loaded).
   Carries the vocabulary of whatever it read, and is evidence of nothing.
2. **Diff output** — the result of comparing two trees. A deletion in a diff is a
   difference, not an action.
3. **Intent** — plans and reasoning. Future tense wearing present-tense clothes.
4. **Invocation** — the command it launched. A fact that it ran; not a fact about the result.
5. **Result** — tool output, commit lines, test summaries, exit codes.

**An alarm, a stop order, or a report upward comes only from class 5, and only after you
confirm it independently on disk.**

> **Class 2, worked.** A `deleted file mode …` line in a diff between two trees is not an
> executor deleting anything: a file that exists in only one of the two trees reads as deleted
> when diffed from the other.

### The tier-1 filter — use the script, and know why

```bash
bash "${PL_SKILL_DIR}/scripts/log-watch.sh" --log <spawn-log> \
     --ring "$PL_ADDR" --journey <j-id>        # background it
```

**`--ring` is required on Codex, and kept on Claude.** The watch exits 2 when the run
ends — on Claude that exit re-invokes the session and really is a wake, but on Codex
nothing does, so a backgrounded watch exits into an empty room and you sleep through the
completion you armed it to catch; on Claude keep `--ring` anyway so the ring is the
wake. With `--ring` it rings you on
every terminal outcome: the run ended, the spawn never started (it gives up after the
10-minute launch window rather than waiting forever on a log that will never exist), or the
watch itself lost its tail. Silence in any of the three is the same defect in three
costumes: the watch stops working and you keep believing it is watching.

Hand-rolling the grep is how rule ① below gets broken, so the script owns the filter:

① **Match runner markers, never domain vocabulary**, anchored at line start. The journey's
own words — the feature name, the branch, the test names, `passed`, `failed`, `deploy`,
`RED` — appear constantly inside class-1 echo, because the executor is reading the very
documents that define them. An unanchored `grep -c 'failed in'` counts text the agent has
read, not runner failures; the anchored filter returns real events only, a fraction of a
percent of a large log's lines.
② **Both directions, always.** A filter matching only progress is silent through a
crashloop, and silence is indistinguishable from work. Before arming, ask: *if this process
died right now, would a line reach me?* If not, widen it.
③ **The watcher dies silently — so check the watcher first.** A flooding monitor is
auto-stopped by the harness and nothing announces it. You are then blind while believing you
are watching, and that blindness looks exactly like a quiet executor. So the tier-0 poll
checks the monitor's own state first and the executor's second, never that order reversed —
and it is one command, so there is no excuse for it being a duty instead of a check:

```bash
bash "${PL_SKILL_DIR}/scripts/script-running.sh" log-watch.sh --arg <spawn-log> \
  || echo "WATCHER DEAD — re-arm before reading anything else"
```

**Not `pgrep -f`, and this is not a style preference.** `pgrep -f` and `ps | grep` match a
process whose command line merely MENTIONS the name — including the checking shell itself,
and including any executor whose charter text names the command it chartered. Such a check
can report a process that is not running, and the same shape produces a false "watcher already armed".
`script-running.sh` matches by argv POSITION — argv[0] is the
script, or argv[0] is the interpreter and argv[1] is the script — so text carried further
right can only narrow a match, never invent one.

**Going to look pays in both directions** — it catches the stall you would have missed, and
it catches the alarm you would have wrongly raised.

## Big-run posture — front-run the launch, stop on first red

**Card-waiting is the cruise posture, never the launch posture — and that holds for
everything you start, not just big runs** (the two ladders are core
Iron rule 0b, the tiers are the section above). Neither firing and forgetting nor sitting
blind in front of a run is a posture available to you. For any big multi-phase run (e2e
suite, eval campaign, ingestion, training) the same launch-first principle expands into:

1. **Launch window**: from run start until the first phases prove green, read
   the run's startup output and early results YOURSELF at minutes-cadence —
   do not park behind the heartbeat-ring. The densest friction (env decay,
   missing bindings, orphan processes, dead hooks) lives in the first minutes;
   an obstacle you clear before the executor cards it costs one minute, the
   same obstacle discovered by card costs a round-trip.
2. **First confirmed red = go in NOW.** A failing phase repeated twice is
   already at the repeat-failure stop line. Read the failing phase's logs
   yourself and attempt the root cause on the spot (minutes, your own hands).
   Exactly two legal outcomes: (a) root cause found and fixable → pause /
   checkpoint the run, fix through the executor, relaunch — never let further
   phases re-confirm a known-broken component ("files are moving" logic
   applies: a run hammering a dead hook produces phases, not evidence);
   (b) not diagnosable quickly → an EXPLICIT CAPPED continue ("N more phases /
   M minutes for evidence, then cut"). An uncapped "continue for evidence" is
   illegal.
3. **Corrupting-class reds invert the forensics argument**: when the red is in
   storage/data integrity, continuing WRITE phases can destroy the very scene
   "run to completion" claims to preserve. Evidence preservation defaults to
   STOP + snapshot; finishing the suite requires a stated reason why later
   phases add evidence the snapshot cannot.

Creed: consecutive reds mean drill in; a found root cause means cut
now; never wait for the instrument to finish burning.

Continuing "for evidence" past a suspected regression burns every later phase
on a dead component.

## Roster anomalies

`roster.sh` is the ONE deterministic join of callsigns + states + spawns + tmux
+ convergence — never reconstruct the fleet by hand.

**The repo half is `--git <repo-path>` (repeatable), and it is not optional when the project uses git.**
Never hand-type `git log … ; git status --short -- <paths>`: a hand-typed line
differs from sweep to sweep — different commit counts, different path lists — so
two consecutive sweeps cannot be diffed and a repo that stopped moving reads as
normal. `--git` emits the same five sections in the same order every time
(BRANCH / LOG / DIRTY / PROT / PROTLOG), byte-identical for unchanged repo
state, so two sweeps diff.

**To detect a stall, diff `--git-only`, never the full roster.** The fleet table
carries relative ages (`moved=3h22m`, `last heartbeat 21h00m ago`) that change on
every run by design — diffing full output buries the repo block in churn and the
stalled repo reads as normal, which is the exact failure this feature exists to
prevent. `bash "${PL_SKILL_DIR}/scripts/roster.sh" --git-only --git <repo>` is the whole of stdout and differs
only when the repo actually moved:

```bash
# At every wake, from the repo root. Copy verbatim — do not improvise.
prev=~/.local/state/pl-sweep/$(basename "$PWD").last
mkdir -p "$(dirname "$prev")"; : >> "$prev"
bash "${PL_SKILL_DIR}/scripts/roster.sh" --git-only --git "$PWD" > "$prev.new"
diff "$prev" "$prev.new" && echo "NO REPO MOVEMENT since the last wake"
mv -f "$prev.new" "$prev"
```

`diff` printing nothing (and the `NO REPO MOVEMENT` line appearing) means the
repo is byte-for-byte where it was last wake. That is a **finding**, not a
pass: if an executor claims to be working, go look at its window now. Only the
very first wake is exempt, because the baseline file starts empty.

Which paths count as
work-in-progress and which are protected is repo knowledge and lives in
`<repo>/.pl/watch.paths`, never in the command line. A repo with no such file
still reports — DIRTY covers the whole tree and the protected sections say
`(undefined)` rather than pretending everything is guarded; that `(undefined)`
is a prompt to write the file, not something to ignore. Anomaly lines are acted on
NOW, not noted: DEAD/SILENT/GHOST → check the window/session, repair via
`bash "${PL_SKILL_DIR}/scripts/callsign.sh" release <name> --journey <j-id> --force` / re-claim, log the repair. **CLOSE-STALLED**
(a close-audit was requested >30 min ago and no seal followed) → run the
close-audit immediately (invoke `pl-audit`); a parked executor that carded its
close and went quiet is the case this alarm exists for. A quiet PL heartbeat (>30 min) reads as
**state UNKNOWN — verify now**, never as "dead" (a PL between heartbeat rings
is legitimately quiet; the flag demands a check, and the checker escalates
only on evidence).

## Take-over & convergence supervision

By default three moves are not allowed here: extending a deadline by issuing more cards (issuing cards,
setting deadlines, extending timeouts — a deadline itself produces no progress), watching
liveness instead of distance-to-close, and inflating "PL writes no code" into "PL
does not take over execution".

1. **Watch convergence, not liveness — and a closure journey's remaining work may only
   go down** (treating a still-moving run as converging is the failure; every
   other symptom is downstream). Every
   dispatch declares `class: closure | build | operate` (closure = finish/verify/close/
   revert/cleanup; build = creating new things; operate = running something already written, which
   the spawner treats as a closure series). The class is written in the
   dispatch file and fixed on the convergence series' first record —
   **the spawner defaults a missing `--class` to `build`, so closure journeys
   must claim `closure` explicitly at dispatch**; changing class = new
   journey + escalation. (A review-round find-count series is class `review` —
   advisory only, never a stop signal.) The remaining-work formula is FIXED for a journey:
   red tests + open blocking review findings + unchecked charter checklist items (non-blocking
   findings are excluded because they are recorded as debt with a debt id instead; the reviewer
   decides which findings block, never the executor).
   Record with `bash "${PL_SKILL_DIR}/scripts/convergence-watch.sh" record
   --journey <j> --remaining <N> [--class ...] [--cycle <k>]` — one sample per
   completed fix-verify cycle (`--cycle` coalesces; a report plus a test batch
   of the same unchanged slice is ONE sample, not two flat steps). Recording is
   event-bound: when a test-batch result, review round or executor report lands
   (a Reach card), record BEFORE replying — timed sweeps are backstop only.
   Verdicts: WARNING = pre-position (verify snapshot exists); **DIVERGING =
   stop NOW** — on a closure journey ANY increase fires it immediately.
   **The stop order is your unilateral authority** (inside the Triage
   Predicate's delegated band and the decision-rights file): no escalation card, no waiting for the next
   checkpoint — order "stop expanding, all new findings to debt, close by
   subtraction", then inform the owner in the next status line (visibility,
   not permission). "Files are moving" is never evidence of progress; a
   moving-but-diverging run is worse than a dead one.
2. **Take-over is a defined PL action** — replacing the executor with a fresh one; it is re-dispatch, not
   coding; iron rule 1 is untouched:
   ① Snapshot (when the project uses git): verify a ≤15-min checkpoint commit of the journey's explicit
   paths exists, else make one now (explicit paths only, in the selected checkout).
   ② Kill: terminate the executor (with the checkpoint in place the kill loses nothing; before
   the wall, TERM the recorded pid from `~/.local/state/agent-spawns.jsonl`).
   ③ Re-dispatch: spawn a FRESH executor via `bash "${PL_SKILL_DIR}/scripts/spawn-exec.sh"` (see `pl-dispatch`) chartered for the
   SMALLEST CLOSE ONLY (keep green, revert broken, ledger the rest as debt) —
   never "continue where it left off".
3. **No extension authority, no sunk-cost pleas.** The wall (SIGTERM at the budget T, SIGKILL at
   1.5T, sent by a system service) is the wall. "It would lose work" is a banned argument — snapshots make kills
   cost minutes. Budget breach while the owner is away = park and switch journeys
   (as on a night shift), never wait, never extend. A red button — spend beyond the ceiling or an
   existing grant, or an irreversible action that leaves the machine — goes from the PL straight
   to `SNO_OWNER_ADDR` (the owner's own Reach address) with the owning COS (Chief of Staff, the optional supervisor
   of several PLs) on Cc; COS may add a recommendation and may not
   approve, hold or edit it, and on a night shift it waits in the owner's inbox.
4. **Fence enforcement at every commit boundary** (when the project uses git): run
   `bash "${PL_SKILL_DIR}/scripts/fence-check.sh" --repo <r> --commit <sha>
   --fence <fence-file>` on every checkpoint/close commit (the dispatch writes
   the fence file; see dispatch-template; fence, mission and journal are defined in the pl core's Terms glossary). VIOLATION = reject/revert that
   commit — it is the executor's own commit, so the revert cannot harm parallel
   sessions.
5. **Review convergence cap**: two review rounds maximum; the second
   fix-created-regression triggers close-by-subtraction. You enforce the cap —
   a third round request is answered with the subtraction order, not a waiver.

## Verification time budget

Use the core's development scope and time rules: estimate setup, execution, and reporting
from available prior runtimes before launching only the changed behavior's tests and
direct consumers. A missing timing record is uncertainty to report, not a prerequisite
to build. By default do not run a full suite or evaluation and do not add unrequested gates; propose it to the
owner as a question — the PL cannot authorize it. There is no automatic final full run, calibration run, preflight, or new kill
timer. When a proposed check adds no distinct evidence about the requested behavior,
remove it and continue the functional work. Reuse valid results instead of repeating them
for a close card or format change.

## GPU liveness probe (optional, only when the run uses a local GPU)

If the run uses a local GPU, it is an honest liveness probe: when a
GPU-dependent phase (ingestion / eval / extraction / training) is healthy, the
cards keep arriving; a card stream that WAS moving and goes silent ~20 min is almost certainly
a stall or a wrong turn. Two habits:

1. **Glance at every wakeup**: `nvidia-smi --query-gpu=index,utilization.gpu,memory.used
   --format=csv,noheader` costs nothing — read it whenever you wake during a
   GPU-phase journey and put the reading on the status board.
2. **Arm the bounded probe when a GPU phase starts**:
   `heartbeat --interval 4m --label gpu-<id> -- bash "${PL_SKILL_DIR}/scripts/gpu-watch.sh" --journey <id> --tick-secs 240`
   (arm-at-most-one per journey). Each tick samples once; the interval must equal
   --tick-secs. Read its exit: STALL (active then silent ≥20 min) or
   NEVER-STARTED (nothing within the 45-min grace) → read the executor
   transcript + the Reach thread, then stop-and-report or a Blocker Card as the facts
   dictate; WINDOW-ELAPSED → re-arm if the phase continues.

**Phase awareness is the whole trick**: GPU silence during planning/coding
phases is normal — arm the probe only for phases that SHOULD be computing.
And utilization sampling is BLIND to short-call workloads:
for phases made of ~seconds-long inference calls, the honest liveness probe is
the inference service's request counts, not utilization — check them
before believing a NEVER-STARTED alarm.
Samples append to `ai-doc/ACTIVE/PL/gpu-watch.jsonl` (audit trail).
