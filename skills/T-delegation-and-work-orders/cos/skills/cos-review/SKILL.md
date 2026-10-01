---
name: cos-review
description: "Review PL self-approvals, estimates, board drift, and close quality after a declared night shift. Loaded ONLY by the cos core via its routing table; NEVER auto-load from context or invoke directly."
requires:
  programs: []
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
---

# COS — batch review

Apply the COS core's finite development budget and affected-test scope. Estimate setup,
execution, and reporting from available prior runtimes; do not add estimation machinery
or preflight. Full suites and new security checks need the owner's specific approval,
never COS approval. Missing auxiliary records do not stop functional work.

Before running these commands, set `PL_SKILL_DIR` to the absolute directory of the installed `pl` skill, in the same Bash call.

Loaded when the owner returns from a declared night shift, or after a batch of closes lands.

**Exclusive authority of this overlay:** issuing the doubt list that reaches the owner.
Nothing else in the COS tree may put a "this may be wrong" item in front of them.

This is **one batch pass, never per-decision interrupts**, run when the owner returns from a declared night shift. Do the
approval pass once, as one batch when the owner returns; then whatever you cannot approve, or
think has a problem, goes to the owner to confirm together.

## Why a batch review is safe at all

Because everything done during the night shift stayed revertable. **Treat "a revert path exists" as a
hard precondition, not a nice-to-have** — unpushed commits, commits that record checksums,
checksum files, preserved copies of replaced work.

If a night decision left **no** revert path, that is itself a doubt-list item regardless
of whether the decision looks correct.

## Pass 1 — validity of what the PLs self-approved

Do not rubber-stamp PL prose. Re-derive each self-approval and classify it by the
four classes in the `cos` core, §What may settle a decision — evidence-class,
ruling-derived, delegated band, value-class — with the bands and owner-only list read from
`~/.config/sno/decision-rights.md`, validating each exactly as that table specifies (open the cited evidence; a citation that does not resolve, or a ruling
with a surviving second reading, converts the item to the doubt list; a value-class
item goes there directly). The table lives in the core because it governs live dispositions as much as this batch pass; this pass is its
re-audit application. **While classifying, also re-run the circuit-breaker count**
(core, §The circuit breaker; `attempt-gate.sh count --slug <slug> --scan <card directory>`
per recurring problem): three or more same-shape attempts at one problem in the
night's cards is a breaker miss — and so is a recurring problem carded with no
`attempt:` tag at all — and it goes on the doubt list even when the final attempt
worked. **Also re-audit every `slow-ruling:` record from the shift** (core, §Fast
thinking, slow thinking): its QUESTION line carries the original question and the one
actually answered — when the two differ and the record answered the substitute, that
is a substitution, and it goes on the doubt list like any invalid self-approval.

**Feed the decision-rights file.** Record in `~/.local/state/cos/LEARNING.md`, one line
each with numbers: every time the owner overturns something decided alone (the decision and
the file row it came under), and each kind of queued item the owner keeps approving. This
pass only records; `cos-evolve` turns repeats into proposals for the file.

Output: an **approved list** and a **doubt list**. The doubt list goes to the owner with
grounded background per the core's iron rule 3 — which repo, which charter filename, what
was decided, what makes it doubtful, and what changes if they rule either way.

## Pass 2 — close quality, against the four failure modes

Compare the close with available open-board records to catch omitted work. Use the
recorded `board_before` revision when it exists; when it is absent or unreadable, report
which comparison could not be made rather than inventing a historical board state.
Keep actual omitted deliverables distinct from a missing record. Missing board metadata
does not reject the close or skip the functional checks below. Report remaining work as
carried, awaiting a named decision, or completed from available evidence; dropping
owner-requested work still requires the owner's instruction.

Then the taxonomy. These are the four ways a night goes wrong, and three of
them look green from inside:

1. **Under-delivery.** Read each charter's Proof table and success checks (run
   `deliver-proof check <charter>` when installed; read its output, not only its exit
   status) and diff the checks and deliverables against what actually landed. "Tests
   green" is not the check; the charter's numbered success checks are. A close that quietly
   dropped an item is the most common one.
2. **Scope inflation.** Diff the touched paths against the
   charter's fence. Files outside it need a justification in the close record, not an
   explanation invented now.
3. **No clean stop.** Ask first whether the **charter** is finished,
   not whether the journey is. Charter finished → the window should be disposed, the callsign
   released, and the audit thread free of dangling questions; a card arriving after that
   seal is lost forever. **Charter still open → a live parked window is the CORRECT state and
   must not be flagged** (core iron rule 11, one charter one agent): killing it turns the next
   slice into a fresh hire that re-learns what this agent already knows. What this pass
   actually hunts is the third case — a window left running with no charter behind it and
   nobody watching.
4. **Edits outside the assigned project.** When the project uses git, check
   `git log` in the assigned repo and, when there is any doubt, the sibling repos the
   executor could reach.

## Pass 3 — estimate reconciliation

Collect every estimate-versus-actual pair from the batch and add them to the calibration
record kept by the `agentic-time-estimate` skill when installed; otherwise list the pairs in
the return report's tail.

- **Over-estimation is the direction that costs schedule, and its loss is invisible.**
  Small work whose design is already settled tends to be priced too high, and the damage
  is **work skipped because the estimate would not fit in the shift** when a much shorter
  run would have done it. When a small design-settled item prices above an hour, discount
  it and say that you did.
- **The right question is never "did it take longer than we said" but "did the
  verification falsify this change's specific failure modes."** A pure deletion is proved
  by a static scan plus a typecheck; a full suite adds close to zero incremental proof
  and costs an hour.
- **Never answer an over-estimate by telling the estimating layer to shrink.** COS
  tells the PL (the layer that produced the figure) *not* to compress its next one: an
  executor rushing to hit a tightened number is a worse outcome than an inflated estimate,
  and **the calibration gap belongs to the reviewing layer, not the estimating one.** One
  data point per journey is a signal to track, not yet a correction to apply.
- A miss in either direction is a recorded data point, not a scolding.

## Pass 3b — before any deletion-shaped alarm

**A deletion-heavy commit right before a seal is usually a correction, not damage.**
An executor that over-produces gets the surplus correctly ordered removed, and the
resulting commit looks exactly like an accident in `git log --stat`. A deletion-shaped
alarm may not be raised until the three questions in the core's restraint list (who
ordered it, is it untracking rather than deletion, are the files still on disk) have been
answered from the journey's own journal and decision thread. Report a correct PL's
correct intervention as an incident and you teach the layer below that doing the right
thing draws fire — worse than silence.

## Pass 4 — board versus disk

For every owned PL, reconcile the status documents against what is actually on disk:
the routing ledger's latest closed event, `missions.jsonl`, the commits, the evidence
files.

Anything stale enough to mislead an agent is fixed **now** — this is inside the pen
boundary, COS edits documents directly. A stale board silently makes a correct PL
wrong: an index document listing items with the wrong status gives the PL reading it a
wrong picture of an entire lane.

**The open board is reconciled the same way, and it is the one document that must also
be well-formed.** Every owned repo's `TODO.md` carries an `OPEN` heading holding
everything still owed — running, queued, ranked-but-unstarted and blocked-on-the-owner
alike, as `state:` values on one list, never as separate sections. A second list is the
defect — an item under a heading that is not the one a supervisor scanning "the board"
reads is invisible while technically present. Closed work leaves through `todo.sh close`, which records it in
`ai-doc/JOURNAL/routing-ledger.jsonl` — **the durable record, and the only one anything
reads back.** A board whose history
outweighs its open items teaches skimming, and a skimmed board is an unread one.
A repo whose board `cos-roster.sh` reports `MISSING`, `NO-OPEN-SECTION`, `UNPARSED`, `TOO-LARGE` or
`UNREADABLE` gets one built in this pass by the core's §Repairing a board — all six
sources (0–5, and source 0 is the pre-repair board itself, the one most easily skipped),
reconciliation output retained, and coverage rather than existence as the
completion test. That commit is the repo's baseline and the Pass 2 close check starts
there. **Who writes the board.** Day to day the **PL maintains its own repo's board** — it
moves a row's `state:` the same turn the work moves, and that is not a COS action. COS
writes it in exactly two cases: **repairing a malformed or missing board**, and **fixing
a stale row mid-flight** when a PL is about to act on it (act-reason 2, cos core §Decision discipline).
Both go through `"${PL_SKILL_DIR}/scripts/todo.sh"`, which holds the per-repo lock for
the whole read-validate-write, and both are told to the PL in the same turn so two people
are never quietly maintaining one file. This overlay, live supervision, and evolution can
all reach the same file; one command and one lock is what stops two individually correct
sessions from dropping each other's open lines. **A board is never edited by hand** —
`todo.sh check` reports a hand edit, and the next write adopts it if the rows still parse
and stops untouched if they do not.

**Audit the binding itself.** Take every close declared since the last batch, pull the
repo's `TODO.md` as of that close from git, and record two numbers: closes that quoted a
board line, and closes that did not. Report both in the return report's tail. This exists
because "has anyone forgotten the board lately?" answers identically whether the mechanism
works or nobody checked — a silent recurrence and a real success are the same observation.
Counting makes them different. If the second number is not zero, the mechanism is not
enough and the next step is evidence-backed rather than argued. Once a full week of
shifts reports zero, stop counting and say so.

While sweeping, spot-check **one** harness document that nobody owns — a repo's
instructions file, a design doc, a plan under `ai-doc`. Anything teaching a dead process
gets fixed or archived on the spot. An unowned workflow manual teaches a dead process to
every agent that reads it, for as long as it sits there.

## Pass 5 — the debt registry

At every batch: review findings that were **not** fixed in scope must exist as rows in
that repo's `TECH_DEBT.md`. Rows are never deleted; a cleared row is struck through with
the clearing project recorded; a parked row carries "reason → re-trigger".

**Core-path work is never debt.** The routing test: if this is missing, does the main
loop run? No → it is the next dispatch in the plan, never a ledger row. Reaching for the
debt ledger to give core work "a home" is the mistake to avoid.

## Assembling the return report

Written to disk **progressively, throughout the shift** — so it survives a session death
— and delivered the moment the owner says they are back. Shape:
`../cos/references/digest-template.md`.

Order and sections exactly as in `digest-template.md`: red-button cards, conclusion,
what moved, the doubt list, what is blocked on the owner, estimate reconciliation, the
armed baton (quoted verbatim from the repo's `TODO.md` `OPEN` section), and the board
disposition with its count check. Nothing else goes in front of them.

Everything else — what ran clean, what COS decided under its own authority, how many
interventions fired — goes in a short tail. The owner reads the top; the tail is the
record.
