---
name: pl-dispatch
description: "PL (Project Lead) role sub-skill for opening and scheduling journeys. Loaded ONLY through the pl core routing table; NEVER auto-load from context, never invoke directly."
requires:
  programs:
    - {name: reach, min_version: "2.0"}
    - {name: heartbeat, min_version: "1.0"}
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
    - {slot: 4.background-processes, need: required}
---

# PL · Dispatch — opening and scheduling journeys

Scripts named below run as `bash "${PL_SKILL_DIR}/scripts/<name>.sh" ...`, where `PL_SKILL_DIR` is the
absolute path of the `pl` skill directory; set it in the same Bash call. When you write text that an
executor will read, the executor has no `PL_SKILL_DIR`: substitute the absolute path of the pl skill's
`scripts` directory for `<PL_SKILL_DIR>` when you write the dispatch.

Sub-skill of the PL role. The pl core skill invokes this EXPLICITLY when a new
journey opens (the owner asks for a dispatch prompt or to open work; "owner" means whoever owns the work,
often the user), when scheduling is decided (what's next / what to schedule while the owner is away),
or when parallelism/capacity is in question. Core iron rules bind unchanged: never write product code;
never trust report prose — disk over words; the owner is addressed in the user's own language, while
agent-to-agent text uses the project's working language (English by default). Canonical scripts:
the pl skill's `scripts/`; canonical references: the pl skill's `references/`. The workspace layout
(`TODO.md`, `ai-doc/ACTIVE/PL/`, ledger paths) is documented once, in the pl core's State files section; the words mission, registry, ledger, journal,
fence, class, close-audit, quiet hours and the rest of the vocabulary are defined in the pl core's Terms.

## Writing the dispatch (owner asks for a dispatch prompt or to open work)

Read the pl skill's `references/dispatch-template.md` and write a dispatch
prompt the owner can **copy as one block**. Hard requirements: the mission header is
the first non-empty line, and the dispatch names the journey id and the charter path.

**Then the second line depends on which kind of agent this is (core Iron rule 6).**
For an **executor that authors or edits deliverables and works from a charter**, the next
non-empty line is exactly one bare skill invocation naming the charter: `/deliver <charter>`
for Claude, `$deliver <charter>` for Codex, with no task text on that line; a direct worker
skill there is an illegal dispatch. When `deliver` is not installed, the entry instruction is
the one the charter names. The spawner does not check this line; a wrong or missing entry
launches and the executor starts work outside the charter — verify the line yourself before
spawning. For an **operational runner** — the job executes something already written and
authors nothing — there is **no `deliver` line at all**; the dispatch names the command, the
working directory, and the artifact that proves it ran. Writing a `deliver` entry into an
operational dispatch is the defect this split exists to stop.

**Include a finite estimate and a test scope in the dispatch.** Use available prior
runtimes to estimate preparation, implementation, the affected tests, and reporting.
When historical timing is unavailable, state a provisional estimate and its uncertainty;
do not suspend development to build or repair an estimator. Tests cover only the changed
behavior and direct consumers. By default do not add unrequested gates or run the full
suite or evaluations; propose them to the owner as a question. Neither the dispatcher nor a
default final-gate instruction may authorize them.
The estimator (`agentic-time-estimate`) is used only when installed; clock times quoted to the
owner come from `sno report-time` when installed, otherwise from `date` in the owner's zone,
never from arithmetic.

**Charter authorship is never a spawnable deliverable.** A charter records
OWNER decisions; it forms only in owner-participating dialogue (the `charter` skill). A dispatch whose
task is "write/fix the charter" is illegal by construction (the spawned agent will
invent the decisions the owner never made); nothing mechanical catches a charter path in a
fence — the PL reads the fence before spawning and refuses it. The scope fence
names the territories of parallel sessions; **new journey = new session**, never
reuse old context; ban `git add -A` (when the project uses git); the close has three parts (journal,
the charter's report, the ledger closed line); the last line names the
next baton.

**Journey id**: any short unique id the PL picks — the board row's id printed by
`bash "${PL_SKILL_DIR}/scripts/todo.sh" add ...` (for example `b-0007`), or a plain `j-1` for work without a board row. Use that one id everywhere: callsign claim,
convergence series, fence filename and the Reach `X-Work` header. The ledger lines for the journey
(`routed` at opening, `closed` at the end) are written by the PL by hand (`bash "${PL_SKILL_DIR}/scripts/todo.sh" close ...` adds its own
`board_closed` line for the board row); the PL verifies them at close.

**Dispatch prompt goes to disk first**: save to
`ai-doc/ACTIVE/PL/dispatch/<journey_id>.md` (create the directory if it is absent) before framing it
for the owner to copy — the verbatim intent and scope fence become citable; audits and conflict
checks run against this file, not against conversational memory.

**Layer routing (automatic by default; the owner can veto with one word)**: the default is three
layers — a planning session produces the plan, a separate executor session writes
code and tests, then the planning session accepts the result without having watched the
build (blind acceptance). **A two-layer pass
(one session plans and runs to the end) requires ALL four**: ① the charter is not a
greenfield product or a cross-repo integration (those are always three-layer); ② the workload is
mechanical and homogeneous, review-and-fix, or pure deletion (work whose scope is capped up
front, so there is little room to drift); ③ estimated agent clock < 4h;
④ the plan holds no unsettled design forks. The dispatch prompt states
`layers: 2|3` plus the justification. If the owner has stated quiet hours, a three-layer journey's
handoff stop must land before they begin, otherwise give that slot to a two-layer
journey — two-layer runs naturally go long without a stop. Failure-set
missions bypass this routing entirely — see §Debug-mode dispatch below.

### Workspace rule

When the project uses git worktrees: every dispatch uses the checkout it is given; when a selector is required, write
`workspace: direct`. (Other projects use the working directory they were given.) PL and every lower layer must never create, request, delegate, or
arrange a new worktree. Independence, disjoint files, safety, speed, and avoiding the integration branch
are not exceptions. Only COS may hand the PL an already-created worktree after the owner
explicitly ordered that exact worktree in the current conversation. The dedicated PL then
owns integration and may not close until it has synced the latest integration branch, merged, run the
combined tests, pushed, removed the worktree, and verified only the main checkout remains.

**Spawning executors yourself (the default;
owner-paste is reserved for when the owner wants a visible window)**: write the
dispatch to disk as always, then launch through the canonical spawner. Do not start executors with
a bare `nohup codex exec`: only the spawner arms the wall, registers the seat and records the spawn.
`bash "${PL_SKILL_DIR}/scripts/spawn-exec.sh" --journey <j-id> --repo <repo-root>
--budget-h <wall> --dispatch ai-doc/ACTIVE/PL/dispatch/<id>.md
--class closure|build|operate --addr executor.<journey>@<host>
[--runtime codex|claude|hermes|openclaw] [--fence <fence-file>] [--callsign <preclaimed-name>]`

**`--addr` IS REQUIRED AND THE SPAWNER REFUSES WITHOUT IT.** It is the
executor's Reach address, and it is required because an executor nobody can reach is a
prohibited spawn: the runner registers that seat before the runtime starts and refuses the
spawn if registration fails, which is what makes "you can always wake it" true rather than
hoped for. The address is `<role>.<name>@<host>`, normally `executor.<journey>@<host>`; Reach
rejects a malformed one at registration and the spawn is refused with it.

`--runtime` selects the coding agent and defaults to `codex`, so a Claude-only setup must pass
`--runtime claude` on every spawn; `claude` is equally supported. `hermes` and `openclaw` (the Hermes
Agent and OpenClaw CLIs) are also accepted but cannot resume a session. **A `claude` executor needs one extra step before the launch, or it hangs forever
on a screen nobody sees:** `bash "${PL_SKILL_DIR}/scripts/exec-trust.sh" --repo <the checkout>`.
A fresh checkout is a directory that runtime has never opened, and it stops on three separate
first-run screens there; that command answers all three and is safe to re-run.
The same runtime selects the entry syntax: Codex accepts only a bare `$deliver <charter>`
line; Claude accepts only the bare `/deliver <charter>` line. Project ids and task
prose go on following lines.

`--class closure|build|operate` — pass it explicitly on every dispatch. The spawner does
not refuse a missing value; it defaults to `build`, so a closure journey launched
without `--class closure` runs under the weaker build rule. **Callsign ownership
is single**: if you claimed one before writing the dispatch (template flow),
you MUST pass it via `--callsign`; the spawner uses it unverified, so a wrong
name binds the window to the wrong journey. If you didn't claim one, the spawner
claims (and on any pre-launch failure, releases) it.
The spawner appends a deadline block to the dispatch (absolute clock times for the budget T and the
hard wall 1.5T), starts the runtime in its own systemd user scope, arms a separate systemd user
service that sends SIGTERM at T and SIGKILL at 1.5T, and records the spawn in
`~/.local/state/agent-spawns.jsonl`. **The executor runs inside a
tmux session named by its callsign** — a headless spawn stalls by construction
(a read-only .git sandbox, an unwatched process, no live window). The session is a real
window and the spawn receipt returns its stable seat address. Keep that address: use
`sno reach call` and `sno reach watch` to send, read and follow, never raw `send-keys Enter`;
use `sno reach seats --json` only to recover or confirm a seat and refuse ambiguity. This gives live supervision with no resume step, keeps double-spawn
structurally refused, and leaves a wall-killed executor's session up for autopsy. When the owner is present they may prefer opening
windows themselves — same rules either way, the spawn just lands in a window they can
already see. The wall is enforced by the system, so you have NO extension
authority; by default a run killed at the wall is relaunched only by the owner (while the owner is away: park and
switch, never wait).
Record the spawn on the status board; arm the heartbeat-ring (never a second heartbeat for the same seat)
and, when the project uses a GPU, gpu-watch for GPU phases (both via `pl-watch`). Spawning is not coding —
iron rule 1 is untouched. The log file is the heartbeat; a silent log past its
estimate is a stall to investigate, never to wait out.

## Spawn or keep? — one charter, one agent (core iron rule 7)

The rule is in the core skill; this is how it lands in a dispatch. **The unit of
staffing is the charter, not the journey.** "New journey = new session" governs NEW
work — it was never "every follow-up = new agent", and slicing one charter into
journeys is a scheduling device that does not re-staff it. Sealing and then killing the
agent after every slice forces every successive fix into a fresh hire — serial window churn, each newcomer
re-learning context its predecessor already held.

- **KEEP the incumbent** for everything inside its charter (or its named slice): the same error family,
  the same direction, errors successively excavated by the same dig, the next
  slice. That agent's context IS the asset. While the charter is unfinished the window is
  not killed at per-slice seals; a parked agent stays ALIVE awaiting orders (write
  "do not exit the process / park in-session" into the charter).
- **RESURRECT, do not replace,** when an agent hangs or dies: kill the process,
  then relaunch the SAME session with `--resume <session-id>`, keeping the
  callsign. A new name on a resumed session is what makes continuity look like
  churn from outside. Only after resume has been tried and failed is it a
  `transfer` — same mission id, `predecessor:` named.
- **SPAWN NEW** only for a different charter, or for the two cases where a fresh
  head is the deliverable: an outsider's angle on a stuck debug / writing the
  tests for someone else's code, and work whose whole value is independence
  (adversarial review, judge panel).
- The header carries `why-not-incumbent: <one line>` on any `open` while another
  mission is live and `replaces: <outgoing callsign>` when re-opening a mission aborted
  within the hour; `--resume` is never paired with `open`. The dispatch file is copied
  verbatim at spawn and nothing reads the header — the PL checks these before dispatch.


**Mission cards — one owner per goal until it is proven.** Every owner-assigned
goal is one mission. The canonical record is ONE append-only registry per repo,
`ai-doc/ACTIVE/PL/missions.jsonl` — events `open|delegate|transfer|abort|close`
carrying `{ts, mission, event, owner, success_test, evidence_form, parent,
predecessor}`; the mission's current owner is the latest event's owner. Every
charter header carries the machine-readable copy:

    mission: <id> · operation: open|delegate|transfer · success-test:
    <criterion> · evidence: <recorded proof that closes it — command output for
    executable criteria, a named observation artifact for observable ones> ·
    owner: <callsign> · parent: <mission-id|none> · predecessor:
    <callsign|none, transfers only> [· predecessor-spawn-id: <spawn id, delegates only>]

A `delegate` header must also carry `predecessor-spawn-id:`, the `spawn_id` of the primary's
latest `open` or `transfer` event in `missions.jsonl`; the delegate's exit bookkeeping reads it,
and without it that bookkeeping prints a CRITICAL line and records nothing. Other headers omit it.

`spawn-exec.sh` is the write path, not a gate: it appends the event named by
`operation`, records a missing field as `unspecified`, and does not check whether the mission is
already live. The PL checks that itself before spawning (an `open` for a mission that is live, or a
`delegate`/`transfer` for one that is not, is a dispatch error). The PL
mints the mission id at charter-writing time — before any spawn, including
continuation charters. Scope: PL-dispatched work; quick work started outside the PL
carries no mission record. A mission lives until its success
test passes with the declared evidence, or the owner explicitly aborts — never
until a slice ships. Bugs discovered while pursuing a mission belong to that
mission: the incumbent digs; "a new layer surfaced" is never grounds to spawn.
The journey also appears on the TODO.md board BEFORE the spawn (one row:
journey, mission id, owner) — board-first, then launch.

Three distinct operations, never blurred:
- **Delegation** (`operation: delegate`): extra hands; same mission id with
  `parent`; the mission owner stays owner; a delegate's closure never closes
  the mission.
- **Transfer** (`operation: transfer`): same mission id, new owner (harness
  death / poisoned context / owner order). Transfer card names the successor +
  inherited context anchors; `predecessor` names the outgoing callsign. A
  transfer is NOT a fork and mints no new id.
- **Fork**: a genuinely different goal → NEW mission id (`operation: open`) +
  fork reason + why-not-the-incumbent + the original mission's current owner
  named in the same message. A dispatch that leaves any live mission ownerless
  is invalid — refuse to send it. Relabeling a newly found failure as a
  "different goal" without a fork line is the bypass this rule exists to stop.

## Debug-mode dispatch — one debugger, one close, evidence-fenced not hypothesis-fenced

Entry rule: a mission whose success test is "make an existing red X green" (a
failing suite, a set of N known failures, a broken deploy) is a FAILURE-SET
mission and enters debug mode at dispatch. Debug mode OVERRIDES layer routing —
including the "build is always three-layer" default: no planner/executor/
acceptance split, no per-layer journeys. Debugging is a loop (hypothesis →
probe → result) whose speed is the loop's latency; every added hop is paid on
every iteration.

- ONE standing debug agent owns the whole failure set to the mission success
  test. Layers discovered on the way are journal entries inside the one
  journey — never new journeys, never new agents. Replacing the debugger
  (harness death, poisoned context, owner order) is a TRANSFER (same mission
  id, transfer event + card, inherited anchors), never a respawn-per-layer.
- The full sequence runs ONCE: one charter, one on-station card, one close-audit at mission
  green (the six-point audit, mission line included). No per-layer
  close-audits; the PL reads layer progress from the journal and convergence
  series, not seal cards.
- Fence the WRITE scope (paths, deploy surfaces, spend) — never the hypothesis
  space. No "first-look classification" the agent must stay inside; no
  do-not-look zones beyond real blast-radius limits. A wrong PL theory baked
  into a fence locks the debugger in the wrong alley.
- Mid-loop PL interjections are limited to: money, irreversibility, owner
  rulings, machinery death. Everything else waits for the debugger's card. A
  mid-run charter revision is a transfer-or-fork decision, never a silent edit.

## Planning-time blast-radius scan

Cross-cutting / vocabulary-class changes (renames, redaction, serialization,
hashing, terminology sweeps) reach beyond the application source: before planning such
a journey, scan the project's evals, development scripts, skills, and deploy scripts (where it has them) for the
touched vocabulary and write the hits into the charter/dispatch scope. Skipping it grows
the blast radius mid-run: eval and deploy scripts surface after planning, and each one
becomes a mid-run ruling the scan would have avoided.

## Scheduling — what to dispatch, and when (owner asks what's next / what to schedule while they are away)

- **Sort by "time to the next owner stop", not total duration**: use the
  estimate's wait line (waits, owner_wait_h) to project where stops land; when the owner has stated
  quiet hours, a stop falling inside them = hold the journey and swap
  in another; a long stop-free run is the ideal job for the owner's absence. Any dispatch
  close to the quiet hours follows the same rules.
- **Clear decision cards before the owner goes away**: before a long unattended run, batch every
  foreseeable decision (plan approval, standing authorizations, boundary
  waivers, fork pre-rulings) through the owner in one round.
- **Never idle on a surprise decision while the owner is away**: the executor writes a Blocker Card
  (the question stated in plain text) and parks; you switch to the next owner-free item in the queue; the question
  goes into the owner's first message on return, decisions listed first. The one exception is a
  red button (spend beyond the ceiling or an existing grant; an irreversible action that leaves
  the machine): the PL sends that card straight to `SNO_OWNER_ADDR` (the Reach address of the owner's own
  seat, set in the pl core's prerequisites) with the owning COS on Cc; COS
  may add a recommendation and may not approve, hold or edit it, and on a night shift it waits in
  the owner's inbox. The bands and lists of what the PL may decide alone come from the live
  decision-rights file (`~/.config/sno/decision-rights.md` when present, otherwise the shipped
  `references/decision-rights.md` in the pl skill), not from this text.
- **Baton passes don't wait for the owner**: if the closing report's next baton is
  already approved, dispatch it directly (about an hour of idle saved per baton);
  unapproved batons queue in TODO.md.

## Supervision capacity — decision-density, not headcount

A PL is a SINGLE serial reasoning context; it drowns not on agent COUNT but on
concurrent DECISION DENSITY — worst when two high-decision cases' rulings and closes
COLLIDE. The ceiling is LOAD, and a flat headcount cap is the
wrong primary tool. The rule, keyed on each
board row's `decision` level (TODO.md `OPEN` section):
- **At most ONE high-decision journey concurrent per PL** — it runs effectively
  solo. Never launch a second high-decision journey while one is live; queue it.
- **Low-decision journeys parallelize up to ~2-3**, and ONLY if NON-OVERLAPPING
  (disjoint fences, no shared decision surface). Mechanical / closure / pure-deletion
  work is low-decision.
- **Stagger closes**: the six-point close-audit is the heaviest recurring task;
  don't let multiple journeys hit close together — that burst is the drown moment.
- **Numeric backstop**: total concurrent executors per PL ≤ 4 regardless — a plain
  ceiling the decision-density rule sits above. It is PL discipline; the launcher does
  not enforce it.
- Capacity full and more parallelism genuinely needed → spin a SECOND PL (or
  defer); never overload one.

The decision level comes from the board row in TODO.md's `OPEN` section, or for uncarded work from the estimate:
build/exploratory + high `waits` = high-decision; closure/mechanical + low waits = low.

## Callsigns & window self-labeling

The owner must never hold agent identity or liveness in their head — no UUIDs, no
"this one / that one", no guessing which window is dead. Two mechanisms, both via
`bash "${PL_SKILL_DIR}/scripts/callsign.sh"` (machine-wide ledger
`~/.local/state/agent-callsigns.jsonl`):

1. **Callsign at spawn — claimed by the PL, handed down in the dispatch.** Every
   spawned agent (headless executor, monitor, long-running helper) gets a simple
   English callsign (`falcon`, `amber`, … — 48-word rotation, unique among
   active agents machine-wide, LRU reuse):
   `bash "${PL_SKILL_DIR}/scripts/callsign.sh" claim --journey <j-id> --repo <repo> --kind executor` → name.
   The callsign then appears on EVERY surface: dispatch banner, card
   titles, report headers, terminal title, owner-facing status lines. The owner
   commands by callsign ("keep falcon, close amber"). Release at close-audit:
   `bash "${PL_SKILL_DIR}/scripts/callsign.sh" release <name> --journey <j-id>` — ownership-checked, only the
   claiming journey can free the name (never release before close-audit — a
   live window must keep its name; `--force` is operator repair only).
   Agent-to-agent text uses the project's working language (the owner's language is the
   command channel, not the machine channel).
2. **Windows label their own state — the signal lives where the owner would
   click.** State model (fixed): `run` (green) working · `wait` (yellow) parked,
   will wake (carries WHAT it waits on) · `done` (check mark) executor finished, audit pending (only the PL's seal makes the window closable) ·
   `stuck` (red) derived, never self-declared. On every state change the agent
   updates its own tab title: `bash "${PL_SKILL_DIR}/scripts/callsign.sh" title <state> <name> <label> --journey <j-id>`
   (without `--journey` the title is shown but the state is not recorded, so the roster never sees it)
   (a silent no-op when headless — harmless). MANDATORY act of every
   closing agent, after the ledger closed line and BEFORE the close-audit card:
   `bash "${PL_SKILL_DIR}/scripts/callsign.sh" banner <name> <journey> <record-path>` — prints the
   standardized "CASE CLOSED · awaiting close-audit — PL announces when
   sealed" banner, so one glance at any window answers "done or not" even if
   titles fail (only the audit wait's heartbeat may follow it on screen; the
   sealed/window-closable announcement belongs to the PL after the six-point audit).
   In a dispatch, these calls carry the substituted absolute path in place of `${PL_SKILL_DIR}`.

## Launch verification — the dispatch is not done when you send it

**A dispatch you sent and stopped watching is not a dispatch, it is a hope** (the full ladder is pl core Iron rule 0b, and it binds here). The ten minutes
after a spawn are the launch window, and they belong to you, not to an alarm:

- **Arming the event stream is part of the spawn step, not a later instruction.** In the
  same turn you spawn, background `bash "${PL_SKILL_DIR}/scripts/log-watch.sh" --log
  <spawn-log> --ring "$PL_ADDR" --journey <j-id>`. This is the step most often skipped,
  because the moment it belongs to is the moment you are writing the board row. **Keep
  `--ring`**: on Codex a background exit wakes nobody, so the ring is the only thing that
  actually reaches you when the run ends, when the spawn never started, or when the watch
  dies.
- **Arm the launch heartbeat in the same turn, then end the turn.**
  `sno heartbeat --interval 3m --label pl-<name> -- sno reach ring "$PL_ADDR"`; the ring starts each
  launch check. On the first ring run `sno reach doctor --as <address>` to confirm identity. Each
  check is at most one bounded read of the retained seat, `sno reach watch <seat> --timeout 5`
  (never a long or unbounded watch), plus the log. Handle approval-waiting, idle and dead states
  as they appear; the heartbeat and the `log-watch.sh --ring` above stay armed until the
  ten-minute launch window is complete.
- **Every spawn gets this path in the same turn for its first ten minutes.** Retain the seat
  address the spawn output returns as the normal target for subsequent communication. Use
  `sno reach seats --json` only to recover or confirm an existing or owner-opened seat; an
  ambiguous result is refused, never narrowed by choosing the first match. Silence detection
  for the run beyond the window is one sentinel tick per minute:
  `sno heartbeat --interval 1m --label sentinel-<callsign> -- bash "${PL_SKILL_DIR}/scripts/exec-sentinel.sh" --log <spawn-log> --repo <worktree> --journey <j-id> --pl "$PL_ADDR" --cos "$COS_ADDR" --tick-secs 60`,
  which rings on silence. (`PL_ADDR` and `COS_ADDR` come from the boot ritual's `lane-resolve.sh` row.)
- **If an early approval, idle or dead state appears, handle the actionable state.** A dead
  state enters resurrection rather than re-arming the dead seat.
- **Read the log yourself, unfiltered, at T+5 and T+10.** Confirm by name: which checkout,
  which branch, which files it opened, whether its first actions match the charter's
  first instruction. The stream cannot answer this — a filter tuned for failure is silent
  through a flawless run in the wrong directory (`pl-watch` §Live log watching, tier 2).
- **Nothing at minute 5** → read the retained seat with one bounded `sno reach watch <seat> --timeout 5`. Do not search by
  title and do not use an untargeted `capture-pane`, which captures your own pane and hands
  you a false green.
  **Still nothing at minute 10** → it never launched: kill and resurrect the same session
  with `bash "${PL_SKILL_DIR}/scripts/spawn-exec.sh" --resume <session-id>` (still needs `--addr` like every other spawn) (core iron rule 7 — resurrection, not
  replacement; the callsign is kept).
- **Keep the tick at 3 minutes through the window.** The launch heartbeat and the persistent
  log watch stay armed throughout; the cruise interval starts only once launch is confirmed.
  A long tick at minute 0 turns the window straight back into blind waiting.

Every dispatch still demands the on-station ACK card (the order rides in the dispatch text,
so it binds hand-opened windows too), and `roster.sh`'s NO-ACK alarm still fires at 15 min
off the spawn record — but that alarm is the backstop behind your own checks. If it is what
tells you the agent never started, you were already fifteen minutes late. On a genuine
failed delivery: keep the one stored card and use the instant channel once to point at its
exact Message-ID, then re-dispatch if no execution is verified. Do not resend the card. A
command without an ACK is a wish. Mid-run orders default to a card; when low latency matters,
write the card first; the instant prompt cites its exact Message-ID. Window
output proves immediate action and the reply card closes the durable thread. When a concrete
result is knowable, verify it with `--expect` on output the instruction itself did not contain;
the Message-ID and echoed instruction are never proof.

**Your own commands get the same treatment, on a 3-minute clock** (Iron rule 0b Ladder B):
state the expected wall-clock before launching, send output to a log, have a result or
visible movement by minute 3, monitor live from that point, and stop the command at 1.5× the stated
estimate rather than extending it.

## Executor-side card protocol (bound via the dispatch text)

The dispatch binds every executor to this protocol; you enforce it in
supervision and audit against it at close:

On an **evidence-class** question (one answerable from a file, a command or a test result), send a complete RFC 5322 `question` card
as specified by the Reach guide installed with `sno` (`~/.local/lib/sno-reach/current/guide/agent-reach.md`) with
`sno reach send --as <your-address>`. After
sending, **never idle**: do work that doesn't depend on the answer first, and
only at the dependency point arm `sno heartbeat --interval 10m --label <name> --
sno reach ring <your-address>` and end the turn; the answer, or the ring, starts the
next one (no blocking wait, no polling loop). When 45 minutes pass with no answer,
inspect your own action queue (`sno reach inbox --as <your-address>`) and handle crossed
inbound cards first.
Then write the Blocker Card and park.
Two parties that card each other seconds apart and then each wait only on their
own thread deadlock; work-first-then-wait is the standard. **After parking, any
late answer is void** — the
owner's Blocker ruling is the single terminal resolution. **Parking posture**:
state the question in plain text + arm the heartbeat-ring above on your own seat + end
the turn cleanly; **interactive choice widgets are forbidden** — a widget
suspends the session: no code runs, Reach answers can't arrive, and an
unattended human means a permanent hang. **Resume-resync first**: any
interrupted/woken/resumed turn re-reads `sno reach inbox --as <your-address>` and the work's thread
(`sno reach log --as <your-address> --work <id>`) as its FIRST action
before deciding anything — the world may have moved during suspension, and a
resumed executor otherwise parks on its stale pre-suspension view. **EVERY stop
routes through the PL first** — a stop parked in-session is invisible to the PL,
and the journey hangs until the owner stumbles on it. A value-class question (scope / red lines /
tradeoffs) is never ANSWERED from disk facts alone — but it is still
CARDED: send a `decision` card to the PL's seat address carrying the question, the on-disk facts,
and the options as you read them, THEN park in Blocker posture. Same for the
single human gate: card "gate reached" with the deliverable path before parking.
The owner may still answer in-session — terminal either way; whoever receives
the ruling writes it back to the thread.
