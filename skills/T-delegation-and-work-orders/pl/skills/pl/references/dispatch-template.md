# Dispatch Template + Default Working Rules

A dispatch is the prompt that starts an executor. Dispatch prompts are agent-facing: write them in
English (or the project's working language). "Owner" means whoever owns the work, often the
user; the PL is the project lead writing the dispatch; the executor is the agent that receives it.

**Script paths.** The scripts named below live in the pl skill's `scripts/` directory. When the
PL runs one, it uses `bash "${PL_SKILL_DIR}/scripts/<name>.sh" ...`. An executor has no
`PL_SKILL_DIR`, so in every command you write into a dispatch, put the absolute path of the pl
skill's scripts directory where this template shows `<PL_SKILL_DIR>`; the PL substitutes it when
it writes the dispatch (the samples below keep the placeholder).

Show a clearly marked first line ("copy the whole block below") to the owner immediately before
the dispatch block, but never include it inside the copied dispatch. The mission header must
remain the payload's first non-empty line.

## Mission header (required in EVERY dispatch)

One line, read by spawn-exec.sh into the mission registry (a field left out is recorded as
`unspecified`, so write all of them):

    mission: <id> · operation: open|delegate|transfer · success-test: <criterion>
    · evidence: <recorded proof that closes it> · owner: <callsign> · parent:
    <mission-id|none> · predecessor: <callsign|none>
    [· predecessor-spawn-id: <spawn id, delegates only>]
    [· why-not-incumbent: <one line>] [· replaces: <outgoing callsign>]

This header is the first non-empty line.

**What follows depends on the kind of agent (core Iron rule 6).** For an **executor
that works from a charter** — the job authors or edits deliverables — the next non-empty line is exactly one bare
`deliver` invocation naming the charter: Codex `$deliver <charter>`, Claude `/deliver <charter>`.
Put nothing else on that line. Journey ids, artifact paths and task prose follow on
later lines. The spawner does not check this line; a wrong or missing one launches an
executor working outside the charter — verify the line yourself before spawning. When the
`deliver` skill is not installed, use the entry instruction the charter names.

For an **operational runner** — the job executes something already written and authors
nothing — there is **no `deliver` line**. In the six-part template below, **part 1 is replaced**:
instead of the invocation line, the dispatch names the exact command, the working directory,
and the artifact that proves it ran, as lines `command: ...`, `working-directory: ...` and
`artifact: ...` (spawn-exec.sh refuses `--class operate` without all three). **Parts 2 through 6
apply unchanged** — estimate, fence, evidence, card forms, the on-station card. Read "every part
present" as every part of the template that belongs to this kind of dispatch; a runner dispatch
carrying a `deliver` line is the defect this split exists to stop.

`predecessor-spawn-id:` is needed only for `operation: delegate`: the `spawn_id` of the primary's
latest `open` or `transfer` event in `ai-doc/ACTIVE/PL/missions.jsonl`. spawn-exec.sh reads it;
without it the delegate's exit bookkeeping prints a CRITICAL line and records nothing.

The two other bracketed fields serve the one-charter-one-agent rule (core Iron rule 7). Nothing reads
them; the PL checks these before dispatch:

- `why-not-incumbent:` — required on any `open` while another mission is live.
  One line, and `different charter: <filename>` is a complete answer. Writing it is
  what makes the decision conscious instead of reflexive.
- `replaces:` — required when re-opening a mission that was aborted within the
  last hour; this is where a replacement has to say it is one. Before writing it, try
  `bash "${PL_SKILL_DIR}/scripts/spawn-exec.sh" --resume <session-id>` (plus the usual
  flags, including `--addr`) — a hung agent is resurrected, not replaced, and resurrection
  keeps the callsign.
- `--resume` may never be paired with `operation: open`; a resumed session
  carries its predecessor's context, so it is a `transfer` (or `delegate`).

Failure-set missions ("make red X green") use debug-mode dispatch — one standing
debugger and a write-scope fence only (pl-dispatch, "Debug-mode dispatch").

## The six-part template (full dispatches)

Every part present, fixed order. Present a clearly marked first line ("copy the whole block
below") outside and immediately before **one copy-paste block**. The marker is
UI guidance, not dispatch content; selecting the block starts at `mission:`.

1. **Invocation line**: one bare `$deliver <charter>` (Claude `/deliver <charter>`); it contains only the
   skill token and the charter path. Put journey ids and other fields on the following lines.

   Worktrees: where the project uses git worktrees, the PL and every lower layer never create,
   request, delegate or arrange one (core Iron rule 9). The executor works in the checkout the
   spawner was given.

   Delivery: the DEFAULT is PL self-spawn via `bash "${PL_SKILL_DIR}/scripts/spawn-exec.sh"`
   (pl-dispatch, "Writing the dispatch"). The launcher enforces the wall budget (SIGTERM at the
   budget T, SIGKILL at 1.5T), claims the callsign and appends the deadline block; a bare `nohup codex exec`
   is a violation. Produce the owner copy-paste block only when the owner asks to watch in a window.
   Then the dispatch itself must still contain the deadline block: budget T, absolute T and 1.5T
   timestamps, closure-only grace, `date` checks at phase boundaries. A hand-opened window has NO
   launcher wall: its deadline block is contractual only, so the PL tracks overrun via
   the roster and convergence series and takes over past 1.5T itself (pl-watch, "Take-over &
   convergence supervision").

   Carry the journey id, and **the callsign**. **One journey = one id everywhere**: callsign
   claim, state calls, convergence series, fence filename, mission ledger line and the Reach
   `X-Work` header all use the same journey id (any short id the PL picks, for example `j-1`);
   the human-readable name goes in `--label`, never in the id slot. If convergence is recorded
   under one id while the callsign is claimed under another, the roster cannot join them and
   shows conv=none for a live executor.
   The PL claims the callsign BEFORE dispatch (`bash "${PL_SKILL_DIR}/scripts/callsign.sh" claim
   --journey <j-id> --repo <repo> --kind executor`) and writes it into the dispatch ("your
   callsign is <name> — carry it in every card title and report header; set your window state
   on every change: `bash "<PL_SKILL_DIR>/scripts/callsign.sh" title run|wait|done <name> <label> --journey <j-id>`,
   wait = parked on a card/gate, with what you await in the label"). Windowless spawns skip
   titles, never the callsign.

   **On-station ACK (no dispatch without it)**: the dispatch text itself orders the executor's
   FIRST act, before any work: send a complete on-station card to the PL seat with
   `sno reach send`, following the guide at
   `$HOME/.local/lib/sno-reach/current/guide/agent-reach.md`, from its own address
   `executor.<journey>@<host>` (`<host>` is `hostname`), echoing the charter and fence paths it
   actually read (a missing fence file surfaces HERE, not at close-audit). This order rides IN
   the dispatch text, so it binds however the window was opened — spawn-exec, owner-pasted,
   hand-opened.

   **PL side, the ten minutes after the spawn are yours to watch actively** (core Iron rule 0b):
   background `bash "${PL_SKILL_DIR}/scripts/log-watch.sh" --log <spawn-log> --ring "$PL_ADDR"`
   in the same turn as the spawn, read the log yourself unfiltered at T+5 and T+10 (which
   checkout, which branch, which files, does its first action match the dispatch's first
   instruction), keep your own heartbeat-ring at 3m and the persistent log watch armed until
   launch is confirmed, and never block on anything. The ACK proves the order arrived and
   nothing about whether work started.

   Keep the seat address returned by the spawn. Confirm it with
   `sno reach doctor --as <address>`, then read it once with `sno reach watch <seat> --timeout 5`.
   The status callbacks are the log watch with `--ring` (above) and the sentinel
   `sno heartbeat --interval 1m --label sentinel-<callsign> -- bash "${PL_SKILL_DIR}/scripts/exec-sentinel.sh" --log <spawn-log> --repo <worktree> --journey <j-id> --pl "$PL_ADDR" --cos "$COS_ADDR" --tick-secs 60`
   (`PL_ADDR` and `COS_ADDR` come from the boot ritual's lane-resolve row; on a lane no COS
   has claimed, `COS_ADDR` is the owner's address);
   a ring is wake-only, never processing proof. Use `sno reach seats --json` only to recover
   or confirm an existing or owner-opened seat, and refuse zero or multiple matches. Nothing alive at
   10 min = it never launched: kill and `--resume` the same session.

   **No on-station card within 15 min of dispatch = failed delivery** — keep the one stored card,
   point the instant channel at its exact Message-ID once, then re-dispatch if execution remains
   unverified; a command without an ACK is a wish, not a command. **That 15-minute timer is the
   backstop, not the check**: spawn-exec persists `ack_due`/`conv_due` in the spawn record and
   `roster.sh` raises NO-ACK / NO-CONVERGENCE alarms on every wake and sweep — if an alarm is
   what tells you the agent never started, you were already fifteen minutes late. For hand-opened
   windows (no spawn record) the dispatching PL notes the send time and checks at its next wake;
   never assume delivery because you sent.

   Same discipline mid-run: cards are the default asynchronous channel. For low-latency contact,
   send the durable card first, then use `sno reach call <seat> <text>` to send one immediate
   instruction naming its exact Message-ID. Seat output proves immediate action; the reply card
   closes the durable thread. When a concrete result is knowable, match output the instruction
   did not contain; the Message-ID and echoed instruction are never proof. Any owner ruling
   received in-window is written back to that thread.
2. **Task + scope fence**: state the task in one plain paragraph — target state
   over process description; make explicit "scope = X; DO NOT touch Y — another
   journey is editing it in parallel". **Declare the journey class**:
   `closure` (finish/verify/close/revert/cleanup), `build` (creating new
   things) or `operate` (running something already written), and write it in the dispatch text for
   the reader. The class the launcher uses is the one passed as `--class` to spawn-exec.sh; a
   `class:` line in the text is not read, and a missing `--class` defaults to `build`, so pass
   `--class closure` for a closure journey.
   **Closure-class dispatches carry two defaults verbatim**: (1) "New
   findings default to DEBT, not fix — this journey fixes only what the
   charter names." When the project stores encrypted user data, add: "ONE EXCEPTION: a key that
   can become unreachable or be lost is never a debt row and never a known limitation — fix it
   here, or stop." (2) "Stop rule: if a check round leaves more remaining work than the
   previous round, stop work immediately and close by subtraction."
   **Convergence recording is not optional** — every dispatch carries verbatim:
   "each fix-verify cycle, record
   `bash "<PL_SKILL_DIR>/scripts/convergence-watch.sh" record --journey <j-id> --remaining <N> --class
   <class> --cycle <k>` (remaining = failing tests + open must-fix findings + unchecked charter
   checklist items, the same formula every time) — the supervisor treats a series with NO
   samples for 90 min as SILENT and comes looking; silence is an alarm, never a default-OK"
   — an executor that runs for hours with zero samples leaves the watchdog
   nothing to watch. **The fence is machine-readable**: write
   the allowed paths (dirs ending `/`, exact files, or globs) to
   `ai-doc/ACTIVE/PL/fence/<journey>.fence` and name that file in the
   dispatch — every checkpoint/close commit is verified against it with
   `bash "${PL_SKILL_DIR}/scripts/fence-check.sh" --repo <repo> --commit <sha> --fence <fence-file>` (out-of-fence commit = rejected/reverted).
   **Forbidden deliverable — charter authorship**: writing or
   editing a charter is NEVER a spawnable task — a charter records OWNER
   decisions and forms only in owner-participating dialogue (the `charter` skill, with the owner); an agent prompted to author one
   invents the missing decisions and everything downstream inherits the
   divergence. Nothing mechanical catches a charter path in a fence — the PL reads the
   fence before spawning and refuses it, unless the fence carries an explicit
   `# OWNER-APPROVED-CHARTER: <ref>` marker placed under a live owner approval.
   List every on-disk plan/proposal/evidence
   file by path, marked "read these before acting" — **always including the
   repo's lessons file** (`ai-doc/LESSONS.md`, when it exists): read it
   before acting, re-check it on any failure.
3. **Mandatory checklist**: numbered; every item demands **fresh evidence**
   ("re-grep before acting; citing old scans is invalid"); red lines flagged with a warning sign
   (for example: the database is shared between production and development — count table rows and keep a
   JSON export before any drop; any non-empty table = stop and ask the owner).
   **When the project stores encrypted user data, one red line is standing and is pasted
   verbatim into EVERY dispatch**, because the executor is the layer that actually hits it and
   cannot read any skill file where this rule lives (core Iron rule 8):

   > WARNING - Keys: never lock yourself out, never lose the key. "I can't find the key"
   > and "I'm locked out" are NOT blockers and NEVER go to the owner — search
   > first: `bash "<PL_SKILL_DIR>/scripts/general-env-doctor.sh" secret <NAME>`
   > (looks in this shell, then in the wrapper named by `${SNO_SECRETS_CMD:-}`; unset wrapper →
   > "no secrets wrapper configured", continue; prints no values). A key that
   > survives that search is a **defect to design out** — fix it in this
   > journey, never file it as debt or a "known limitation". "Encrypted but we
   > cannot open it" is never an acceptable end state; prove any rescue road by
   > really making the keyring unusable and really opening an encrypted store;
   > never weaken encryption on user data to get past your own problem; never
   > print key material at any log level.
4. **Process**: which gates are armed, which are waived (waivers cite precedent);
   **what the single human gate is, and which standing authorizations the owner
   grants at that one approval** (checkpoint-commit authorization etc.); the
   finite estimate and the available timing evidence or stated uncertainty;
   estimate affected tests from available prior runtimes; by default do not add a calibration run
   or a new test kill timer. Include preparation, execution, and reporting in the budget.
   `layers: 2|3` + justification (routing rule in pl-dispatch, "Writing the dispatch": default three
   layers; only work that is mechanical/review-fix/pure-deletion AND <4h AND
   fork-free passes at two); wall-clock budget. Pass that whole-task budget to
   `spawn-exec.sh --budget-h`; do not require estimator-specific output fields.
   When the journey has an acceptance gate armed: the plan
   deliverable must attach a short list (5-8 items) of candidate end-to-end user journeys, so
   the owner can pick the must-pass ones via the PL.
5. **Commit discipline** (when the project uses git): "the selected checkout may hold other sessions' uncommitted
   files — `git add -A` / `commit -am` are forbidden; commits list explicit paths
   only." New journey = new session, never reuse old context.

   **Mid-run Q&A protocol** (applies to Codex AND Claude executors, included in
   every dispatch): evidence-class questions (answerable from a file, a command or a test
   result) go as a
   complete question card sent with `sno reach send` (see the guide), then arm
   `sno heartbeat --interval 45m --label pl-<callsign> -- sno reach ring <your-address>` and end the
   turn; the answer's own ring, or the heartbeat, starts the next turn. Read
   `sno reach inbox --as <your-address>` first, so crossed cards are handled first. If a heartbeat turn finds no answer,
   or the question is value-class (scope/tradeoffs/red-lines): **FIRST send a `decision` card to the PL** carrying
   the question + the on-disk facts + your read of the options, **THEN** park on
   a Blocker Card (the question stated in plain text). Every stop routes through the PL first; the PL triages under the
   Triage Predicate (pl core SKILL.md, "Decision discipline") and rules everything except the owner-only
   items in the decision-rights file (spend beyond a grant, irreversible actions that leave
   the machine, overturning an owner ruling, a novel product-direction fork, and a few more), so
   expect a PL ruling, not an owner wait; you may be unparked by a card ruling or by the owner
   in-session, terminal either way. Parking = plain-text statement of the question + the
   heartbeat-ring armed + end the turn; **never pop an interactive choice widget** (a widget
   suspends the session; card answers cannot arrive). All Q&A lands on disk — it is part of
   this journey's audit log.

   **Inbound checkpoints**: an executor only ever sees cards it goes looking
   for. A mid-run instruction to a live executor — including an owner override reversing an
   earlier ruling — is read only if the executor looks, and an unread one means work continues
   against a decision that has already been withdrawn. So run
   `sno reach inbox --as <your-address>` at four fixed points: **before
   starting any step of your task list, before launching anything expected to run
   over ten minutes, immediately after any long run returns, and before sending a
   completion or close-audit card**, and also whenever more than 20 minutes of wall
   clock have passed since your last read, whatever you are in the middle of — run
   `date` and compare, because you cannot feel time.

   **The 20-minute read is a courtesy, not a guarantee, and it is written that way on
   purpose.** Nothing makes an agent run `date` when twenty minutes pass, so a clause
   phrased as a promise is a promise nobody keeps. The guarantee is the ring: it
   starts a turn in your window when a card lands, so you are interrupted rather than left to
   remember to look. The 20-minute read exists to make you handle a card properly
   rather than clear it to get unblocked. A `decision` or `question` card found there
   outranks whatever you were about to do — handle it first. An inbox read is a file read;
   it costs nothing, and skipping it is how a withdrawn ruling stays in force.

   **Gate-stop leg**: on reaching the single human
   gate, BEFORE parking, send a complete decision card to the strict
   registered PL seat, following the Reach guide, with a
   `gate reached: <gate> (<journey>)` subject and the proposal/deliverable path in the body — the PL
   cannot see your session; without this card the gate stop is invisible and
   the journey strands until the owner happens to look. Then park in the same
   posture as a Blocker (plain text + heartbeat-ring + end
   turn). Approval may arrive EITHER in-session from the owner (the receiving side writes it
   back to the thread) or as a card relaying the owner's ruling — both unpark you. Gate
   approval authority stays with the owner; the card leg only makes the stop visible and the
   reply routable.
6. **Close**: the close has three parts — (1) journal entry; (2) the charter's `## Report` and
   (when `deliver` is installed) `sno deliver-proof check <charter>`; (3) the journey's `closed` line in
   `ai-doc/JOURNAL/routing-ledger.jsonl` (written by hand; `todo.sh close` adds its own
   `board_closed` line for a board row), which carries a one-line estimate-versus-actual note in its outcome: estimate vs actual
   in one line and WHAT the estimate missed, or "on-target"; future estimates anchor on
   these. Also feed `ai-doc/TECH_DEBT.md` (cleared items struck through, new findings get
   rows), and make the last line of the close report name the next baton. **The baton must be ARMED** — a
   close that ends on a clean status list leaves the owner to hand-compose the
   next order, its estimate, and its budget: when a
   natural next step exists (deploy, push, E2E, next slice), the close report
   ends with a pre-priced proposal — what the step is, its finite time estimate based on available timings or stated uncertainty, the verification plan, the budget/kill line,
   and the single word that launches it ("reply GO and it starts"). The owner's control
   point stays (no push/deploy without the owner's word); the owner's cost
   collapses from composing an order to answering one word. A close that hands
   the owner a blank next step is a violation.

   **Then the window signal, BEFORE the close-audit card**:
   `bash "<PL_SKILL_DIR>/scripts/callsign.sh" banner <callsign> <journey> <journal-path>` — it
   prints the standardized "CASE CLOSED · awaiting close-audit — PL announces when sealed"
   banner, so even a wall-killed window still visibly states its true state (a finished agent
   that doesn't visibly say so is a protocol violation). The word window-closable/sealed is
   NEVER yours — the PL says it after the six-point audit.

   **After the ledger closed line and the banner, send a complete close-audit card to the strict
   PL seat.** This wakes the PL for its six-point close verification (pl-audit, "Close-audit") —
   a close with no card leaves the PL asleep and the journey's staged, uncommitted lines
   undisposed. Before sending it, verify the project's change record (`git status`, when the
   project uses git) shows none of THIS journey's work still staged or uncommitted —
   verified-but-uncommitted work in a shared index is a data-safety hazard.

   **Sending the close-audit card is NOT done.** "Close-audit requested" is not "I am done"; you
   are done only when the PL's SEAL (or an explicit release) arrives. So after sending it, arm
   `sno heartbeat --interval 10m --label pl-<callsign> -- sno reach ring <your-address>`, end the
   turn, and on each ring read `sno reach inbox --as <your-address>` and act on the reply: a
   SEAL/PASS ends you; a fix list means fix + re-request + keep the ring. **If a ring turn finds
   no verdict after 45 minutes, escalate a DURABLE record before you can be wall-killed**: send a
   `decision` Blocker to the PL AND an `info` card Cc'd to the owner's seat (`$SNO_OWNER_ADDR`, or
   the address the charter names; no To) ("CLOSE-STALLED: <journey> awaiting seal since <t>") —
   so a slow or dead PL produces a card the owner sees, never a silent idle death — then keep the
   ring. Never end a turn without the ring armed: an idle executor is invisible to everyone and
   the launcher wall will eventually kill it, and if the close verdict never landed the case
   strands with no durable trace. The roster's CLOSE-STALLED alarm is the machine backstop, but
   the durable owner card is yours.

### Full dispatch sample (imitate this shape — every part of the six-part template present)

The sample is for a project that stores no encrypted user data, so the standing keys line is
omitted.

```
mission: example-dead-code-sweep · operation: open · success-test: targeted cleanup verified and closed · evidence: journey close artifacts · owner: <pl-callsign> · parent: none · predecessor: none
$deliver <charter>
journey: j-1
Your callsign is <callsign> — carry it in every card title and report header; set
your window state on every change: bash "<PL_SKILL_DIR>/scripts/callsign.sh" title run|wait|done <callsign> <label> --journey j-1
(wait = parked on a card/gate, with what you await in the label).

FIRST ACT, before any work: send a complete on-station card to the PL seat with
`sno reach send`, following the guide at $HOME/.local/lib/sno-reach/current/guide/agent-reach.md,
as executor.j-1@<host>, echoing the charter path and the fence path you actually read.

Task: targeted cleanup of "fake control" dead code — things that look
alive but are dead: parameters nobody reads, branches that can never run, config
variables short-circuited by hardcoding, flags with no consumer. These generate
false findings in every review, which is why they are the target; plainly dormant
cold code is NOT (do not let this grow into a repo-wide sweep). Scope =
apps/api and its lib dependencies; DO NOT touch apps/web (another
journey is editing it in parallel).
class: closure
Fence: ai-doc/ACTIVE/PL/fence/j-1.fence (allowed: apps/api/,
libs/api-*/, ai-doc/TECH_DEBT.md) — every checkpoint and
close commit is checked against it; out-of-fence = rejected.
Closure defaults: (1) New findings default to DEBT, not fix — this journey fixes only
what the charter names. (2) Stop rule: if a check round leaves more remaining work than
the previous round, stop work immediately and close by subtraction.
Convergence: each fix-verify cycle, record
bash "<PL_SKILL_DIR>/scripts/convergence-watch.sh" record --journey j-1 --remaining <N> --class closure --cycle <k>
(remaining = failing tests + open must-fix findings + unchecked charter checklist items)
— the supervisor treats a series with NO samples for 90 min as SILENT and comes
looking; silence is an alarm, never a default-OK.
Read before acting: ai-doc/TECH_DEBT.md; ai-doc/LESSONS.md (re-check it on
any failure).

Mandatory checklist:
1. Discovery scan for dead code in scope; produce a candidate list.
2. Verify and disposition the three old dead-code rows in ai-doc/TECH_DEBT.md (none
   recently verified — re-grep before acting):
   [per item: what it is → verification method → disposition ruling]
   WARNING - Red line: the database is a shared server — count table rows and keep a JSON
   export before any drop; any non-empty table = stop and ask the owner.
3. Every deletion item carries zero-caller evidence in the plan (fresh rg
   output; citing old scans is invalid).

Process:
- Illustrative whole-task estimate: 6h including preparation, implementation, focused
  tests, waits, and reporting; replace with available timings or stated uncertainty.
  Wall budget 6h; hard wall at 1.5x = 9h (closure only past 6h). Run `date` at
  phase boundaries.
- layers: 3 — default; this is not mechanical/review-fix/pure-deletion under 4h.
- The deletion list (one page; per item: what/evidence/lines removed) goes in the
  charter's Plan. This is the single human gate; the owner approves once, granting standing
  checkpoint-commit authorization with that approval. Run the project's own lint/type checks
  and the affected focused tests. A full suite requires the owner's explicit request for that run.
- Gate-stop leg: on reaching the gate, BEFORE parking, send a decision card to
  the registered PL seat with subject "gate reached: plan (j-1)" and the
  charter path in the body; then park (plain text + heartbeat-ring + end turn).
- Mid-run Q&A rides Reach cards: send a complete question card as executor.j-1@<host>,
  then arm `sno heartbeat --interval 45m --label pl-<callsign> -- sno reach ring executor.j-1@<host>`
  and end the turn; read `sno reach inbox --as executor.j-1@<host>` first on every
  ring; no answer on a heartbeat turn, or a value-class question → decision card to the PL
  FIRST (question + facts + options), then Blocker Card, park. Never pop an interactive choice widget.
- Inbound checkpoints: `sno reach inbox --as executor.j-1@<host>` before starting
  any step, before launching anything expected to run over ten minutes, immediately
  after any long run returns, before sending a completion or close-audit card, and
  whenever more than 20 minutes have passed since the last read. A decision or
  question card found there outranks whatever you were about to do.
- Commit discipline: the selected checkout may hold other sessions' uncommitted
  files; git add -A / commit -am are forbidden; explicit paths only.
- Close: move the three old TECH_DEBT.md rows to Cleared (struck through, never
  deleted); new undispositioned findings get new rows; journal + charter Report +
  `sno deliver-proof check <charter>` (when deliver is installed) + ledger closed line with an estimate-versus-actual note; last line names the next baton, ARMED
  (step, estimate, verification plan, budget/kill line, "reply GO and it starts").
  Then bash "<PL_SKILL_DIR>/scripts/callsign.sh" banner <callsign> j-1 <journal-path>; verify git status
  shows none of this journey's work still staged; send the close-audit card to the
  PL seat; arm `sno heartbeat --interval 10m --label pl-<callsign> -- sno reach ring
  executor.j-1@<host>`, end the turn, and act on the verdict read from the inbox on each
  ring. If a ring turn finds no verdict after 45 minutes send a decision Blocker to the PL AND
  an info card Cc'd to the owner's seat ("CLOSE-STALLED: j-1 awaiting seal since <t>"),
  then keep the ring. Never end a turn without the ring armed.
Follow the owner's instructions. By default a charter or review cannot authorize a full test run or
a new security check; report conflicting requirements and continue authorized work.
```

### Minimal variant

```
mission: <mission-id> · operation: open · success-test: <criterion> · evidence: <proof> · owner: <callsign> · parent: none · predecessor: none
<runtime-correct deliver invocation naming the charter>
Background: <one sentence>. All owner decisions in the charter are locked — do
not reopen them.
```

Only two ingredients: the invocation naming the charter (the executor reads the
rest itself) and one sentence of background. Everything else lives in the charter.
The minimal form never waives the finite whole-task estimate: use available timing
evidence, or state a provisional estimate and uncertainty without blocking dispatch.

## Paths outside the selected checkout — cite ABSOLUTE, and check before sending

**A charter may be read from a checkout the PL is not standing in.** Anything visible from
your own working directory is not thereby visible to the executor. Gitignored directories and
untracked files are the common cases.

`ai-doc/ACTIVE/PL/dispatch/` is gitignored, so a repo-relative briefing path may be
absent from the executor's checkout. When an executor actually needs a file from another
checkout, give it an accessible path. Check only that needed path if its location is
uncertain; log a missing file and continue independent work. A missing close evidence
path is reported by `todo.sh close` and does not hold a completed task open.

## State the owner's authority in every dispatch

Follow the owner's instructions. By default, charters and reviews describe the requested behavior;
they do not override the owner's test-scope limits or authorize new security checks.
Report conflicting requirements and continue independent authorized work.

## Default working rules (a project may choose otherwise)

The PL applies these when writing and auditing a dispatch. They are defaults: the owner or the
project's own conventions may replace any of them, and a replacement is written into the charter
or the dispatch so the executor sees it.

| Rule | Content |
|---|---|
| Evidence must be fresh | Deletions and dispositions rest on evidence re-run on the spot; citing old scans is invalid |
| No error-masking | Weakened assertions to go green and swallowed exceptions are rejected at audit |
| Environment self-service | Never park on an environment blocker: verify the absence with a fresh command, then fix it yourself (start stopped services, install dependencies, look up a secret through the configured wrapper, fix paths). Restarting a RUNNING service requires a `RESTART_OK` verdict from `bash "<PL_SKILL_DIR>/scripts/docker-env-doctor.sh" <service>`; do not kill processes directly. A "blocked on environment" claim without fresh evidence is invalid |
| Keys (when the project stores encrypted user data) | Never lock yourself out; never lose the key. Neither is ever a question for the PL or the owner: search first with `bash "<PL_SKILL_DIR>/scripts/general-env-doctor.sh" secret <NAME>` (this shell, then the wrapper named by `${SNO_SECRETS_CMD:-}`; never prints a value). Then design so it cannot recur: (a) "encrypted but we cannot open it" is never an acceptable end state; (b) a design where the key can become unreachable (revoked keyring, no desktop session, sandbox that cannot read `$HOME`, moved config path, new machine) is wrong — fix it, do not record it as a known limitation; (c) a design where the key can be lost (one copy, no backup, or a restore procedure nobody has run) is equally wrong — an unrun restore procedure does not exist; (d) a keyring failure must fall through to a rescue road that an operator can reach, proven by really making the keyring unusable and really opening an encrypted store; (e) never weaken encryption on user data to solve a problem of ours; (f) never print key material at any log level |
| Tests stay within the requested change and a finite budget | Before launch estimate setup, execution, and reporting from available prior runtimes; with no history, state a provisional estimate rather than building estimation machinery, preflight, calibration, or kill timers. Run only changed behavior and direct consumers. By default do not add unrequested gates or run the full evaluation, unit, integration, E2E, or repository suite; propose it to the owner as a question instead. A skill, charter, default command, final gate, or PL/COS card does not grant that permission. Reuse relevant results; rerun only for affected changes, failures, or missing functional evidence. Auxiliary checks log failures and never block the main function or independent development |
| Wall budgets | Spawn only through spawn-exec.sh so the launcher enforces the wall (SIGTERM at the budget T, SIGKILL at 1.5T). Up to T: chartered work, in-scope extras welcome. From T to 1.5T: closure only; an out-of-charter addition past T ends the run on detection. After 1.5T the process is gone; relaunching needs the owner, and the PL has no authority to extend. Supervise convergence (`convergence-watch.sh`), not just liveness: a DIVERGING series means take over (snapshot, kill, fresh smallest-close executor). Review rounds on the same scope are capped by the review wrapper of the `peer-review` skill (when installed); a second fix-created regression means close by subtraction. Fences are checked per commit (`fence-check.sh`) |
| Walk the path before a decision run | Before a measurement run that a decision will rest on, the PL walks every important path by hand with the `agentic-walkthrough` skill; see the hand-walk gate below |

## The hand-walk gate

**Before any measurement run that a decision will rest on, the PL personally walks the path
by hand and produces the proof.** After code review, never instead of it — **a review reads
the diff; the walk reads the path.** A reviewer confirms the change is correct; only the walk
asks whether the change is *reached*. A suite can be green while a feature is switched off or a
job opens the wrong installation: every assertion true, every suite silent.

**The procedure itself lives in the `agentic-walkthrough` skill — invoke it, do not restate it
here.** This section owns only what is PL policy rather than technique:

- **Every important path gets walked — plural, not the one path that looks suspicious.**
  At the PL's own level, enumerate the paths a decision rests on and walk
  each of them. Picking the single most likely one is how the other five stay unexamined.
- **The PL performs it personally.** It is not delegable to a test suite and not satisfiable by
  a subordinate's summary.
- **Executors the PL spawns may run the skill too**, and should be told it exists — it is a
  general technique, not a supervisor ritual. That does not discharge the PL's own walk.
- **The report carries the skill's exit numbers with line references**, never "the walk went
  well". A number a no-op could not produce is the bar; zero is a gate failure, not a result.

**Why it is standing rather than a one-off:** every green light can be true while the work
is still not done. When no assertion in any suite is false, no suite can catch it. A stage can
run perfectly and change nothing that anyone downstream can see — the walk finds that; a full
test suite cannot.

## Audit quick reference (minimum verification set for the report audit)

| Report claim | Minimum verification |
|---|---|
| "Fully deleted / zero callers" | `rg` the symbol project-wide (direct calls, type refs, string literals, tests) |
| "All tests green" | Read the recorded command and output for the changed behavior; rerun only when relevant changes or failures make the result insufficient. State the tested scope; never infer a full-suite pass |
| "Table is empty / safe to drop" | Connect to the DB yourself (credentials via `${SNO_SECRETS_CMD:-}`; unset → "no secrets wrapper configured", continue) and count rows; endorse only at 0 |
| "Committed / archived" | When the project uses git: `git log --stat` the actual commit contents; confirm no other session's files rode along |
| "Acceptance passed" | Inspect existing functional results for the requested behavior; report actual failures and unverified results. Auxiliary hashes, formatting, and session pointers are not prerequisites and do not authorize a rerun |
| "The encrypted store works" / "key handling is done" (when the project stores encrypted user data) | Make the keyring **really** unusable and open a **really** encrypted store — a simulated failure or a test that supplies the answer proves nothing. Also grep the diff for a key value reaching any log sink, and confirm the restore procedure was actually executed, not merely written |
| "The stage ran" / "the job completed" | Not sufficient. Walk the path: name the switch and its value, and produce a number a no-op could not produce. A completed job with a zero count is a gate FAILURE — typically a job that finishes in milliseconds because it never reached its own work |
| "The batch ran" / any batch or side-effect stage | Confirm the stage opened the store the reader queries, not a fallback path. A path-resolution fallback resolves to whatever store exists on the host — prove the target by path, and require the code to REFUSE rather than fall back |
| "The key is missing / I am locked out" (when the project stores encrypted user data) | Not a valid report at any layer. Reject it and hand back `bash "<PL_SKILL_DIR>/scripts/general-env-doctor.sh" secret <NAME>` (checks this shell and the configured wrapper). A key that survives that search is a defect to design out — never a card, and never a question for the owner |
