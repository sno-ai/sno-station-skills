---
name: pl-audit
description: "PL (Project Lead) role sub-skill for acceptance and close-audit. Loaded ONLY through the pl core routing table; NEVER auto-load from context, never invoke directly."
requires:
  programs: []
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
    - {slot: 4.background-processes, need: required}
---

# PL · Audit — acceptance gatekeeping

Scripts named below run as `bash "${PL_SKILL_DIR}/scripts/<name>.sh" ...`, where `PL_SKILL_DIR` is the
absolute path of the `pl` skill directory; set it in the same Bash call.

Sub-skill of the PL role. The pl core skill invokes this EXPLICITLY when an
executor report lands (the owner asks you to review / audit / find faults; "owner" means whoever owns
the work, often the user), when ANY close signal appears, at estimate reconciliation, and at the final
acceptance gate. Core iron rules bind unchanged — above all iron rule 2: **never trust report prose; what is on
disk counts**. The owner is addressed in the user's own language; agent-to-agent text uses the project's
working language. Canonical scripts: the pl skill's `scripts/`. The workspace layout (`ai-doc/...`, ledgers)
is documented in the pl core's State files section. Words such as journey, callsign, window, night shift
and take-over are defined once, in the pl core's Terms glossary. The rules in this file are the PL role's
defaults; a project may choose otherwise.

## Report audit (owner pastes an executor report)

Extract the report's key claims (what was deleted, test state, invariants, line
counts) and verify each against disk: grep call sites, git log/diff (when the project uses git), run the
targeted tests, query real data with the project's own database or cache clients. Destructive data
operations (DROP, migrations) get endorsed only after you have counted the affected rows yourself.
Verdict format: one-line judgment first (pass / fail / pass-with-conditions), then
"points verified + evidence"; **any claim you did not verify is explicitly marked
"unverified" — silent omission is forbidden**; end with the reject list. The
verdict is delivered to the owner in the user's own language; the marking is normative, the wording is not.
Error-masking (assertions weakened to go green, swallowed exceptions, mocking the
code under test) = immediate reject. At the end of every audit, glance at the
journey's verbatim ask: does the output still point at the intent? Smell drift →
call it out now, don't wait for the final acceptance.

## Close-audit — the six points, canonical

The trigger and the checklist:

**Trigger**: a `decision` card "close-audit requested: <journey>" is the
normal wake. But ANY close signal — an info card saying closed, a ledger
`closed` line appearing without a matching audit, a CASE CLOSED banner, a
roster CLOSE-STALLED alarm — is equally a trigger: an executor closing itself
does NOT discharge the audit, and "it already closed" is never a reason to
skip. Audit every close, always.

**Read the existing functional result before requesting more work.** Record checks may
identify missing or unreadable evidence, but their status is not a development or closure
prerequisite. Do not wait for a record's formatting to pass, or rerun functionality merely to repair a record.
Unknown functional results remain unverified; actual failures remain failures. Continue
independent work and inspect the relevant existing output before ordering a targeted rerun.

1. **Commit integrity** (when the project uses git): `git log --stat` the journey's commits — explicit
   paths only, no foreign files riding along, `bash "${PL_SKILL_DIR}/scripts/fence-check.sh" --repo <r> --commit <sha> --fence <fence-file>` on each commit.
2. **Claims vs disk**: inspect recorded output to verify the report's counts
   (tests, deletions, zero-callers); the journey's `closed` ledger line (written by the PL by hand) is
   complete and its outcome carries a one-line calibration note (estimate versus actual). `todo.sh close --outcome ...`
   writes a separate `board_closed` line for the board row; that line does not replace the `closed` line. Check the charter's success checks: when `deliver` is
   installed run `deliver-proof check <charter>` and read its output (which checks it lists as
   unproven), not only its exit status; otherwise read the charter's Proof table yourself,
   latest row per check. A success check without a passing latest row is unverified.
3. **Independent adversarial review** of the journey's final diff
   (the `peer-review` skill in journey mode with charter and fence when installed, otherwise a fresh
   separate session of any installed agent CLI; at most two rounds) —
   self-verification never seals a case. Blocking
   findings reopen the close; non-blocking ones go to debt.
4. **Debt & artifacts**: every debt row landed with an id; the journey's
   journal entry exists; TECH_DEBT.md updated (cleared = struck through, never deleted).
   **When the project stores encrypted user data, one class may never appear as a debt row, a
   parked row, or a "known limitation" anywhere in the close** — a key that can become unreachable
   or be lost (core iron rule 8). Read the new rows and the journal entry for it; finding one
   REOPENS the close, exactly like a blocking review finding. A journey that shipped an encrypted
   store also owes the evidence, not the claim: the keyring really made unusable and
   the store really opened, and a restore procedure actually executed.
5. **Resource sweep — and first, is the charter finished?** A seal has two legal
   shapes and the audit picks between them (core iron rule 7, one charter one
   agent):
   - **Charter finished** → close it out: callsign released (only the claiming journey can free it),
     window signaled (banner present), processes exited or explicitly handed
     off.
   - **Charter still open, more slices to come** → **the agent stays alive and
     parked, and that is the correct outcome, not a loose end.** Killing it
     makes the next slice a fresh hire that re-learns everything this one
     already knows. Record the disposition as "parked for <next slice>" and
     leave the callsign claimed. A live window under an open charter is never an
     audit finding.

   Either way: convergence series at CLOSED (a closure series whose
   remaining work ever went up gets that increase recorded in the audit).

6. **Mission line**: the verdict card states the mission id, the current
   result of its success test (from the declared evidence form — recorded
   command output or the named observation artifact; never memory), and who
   owns the mission now (mission, success test, evidence form, fence, journal and ledger are defined in the pl core's Terms glossary). No owner nameable → the audit FAILS. Sealing the
   mission's last active agent while the success test is red is forbidden:
   transfer to a new owner first, or escalate to the human owner (through COS; a red button goes
   straight from the PL to `SNO_OWNER_ADDR`, the owner's own Reach address; see below). On a green
   success test with its declared evidence (or an explicit owner abort), the audit records the outcome in the
   verdict card and in the journey's `closed` ledger line; it never edits `ai-doc/ACTIVE/PL/missions.jsonl`,
   whose only writer is `spawn-exec.sh`. The board and TODO.md update ride the seal:
   move the journey row to closed, and flip the backlog block to `done` ONLY
   when ALL of the block's missions/slices are closed or explicitly aborted —
   report failed board updates separately from the functional result.

Verdict card: "CLOSE-AUDIT PASS: <journey> sealed (6 points)" or the specific
failing point + what reopens. Include any relevant lessons-file entry that exists; missing
auxiliary lines are reported, not closure prerequisites. **And the seal is not
done until the OWNER has been told** (the owner must never
return to a wall of windows with no idea which are dead). Everything in ①–③ below is
delivered to the owner in the user's own language;
the structure is normative, the wording is not. After PASS, ① for
tmux sessions, set the window title to the shape the seal actually took —
`bash "${PL_SKILL_DIR}/scripts/callsign.sh" title done <name> "SEALED — window closable" --journey <j-id>` when the charter is finished, or
`bash "${PL_SKILL_DIR}/scripts/callsign.sh" title wait <name> "SEALED slice — agent stays, waiting for the next slice" --journey <j-id>` when it is not.
**Use the second one whenever the charter is still open**; ② **in the same breath as
the PASS card, send the durable announcement** — an `info` card (no To) with `SNO_OWNER_ADDR` on Cc
("SEALED: <callsign> · <journey> · window closable" + one-line outcome). This
card is the of-record announcement and survives your own death. ③ in your very next
owner-facing message, one line per sealed case: "<callsign> · <journey> ·
audited, formally closed, window closable" — and the card waits in the owner's inbox,
so nothing sealed while the owner was away is ever silent. The executor's own banner only
ever says "CASE CLOSED · awaiting close-audit — PL announces when sealed"
(what `callsign.sh banner` prints) — the word window-closable/sealed belongs to you, after
the six points, never to the executor. A sealed case the owner was not told
about is an unfinished close.

## Probe discipline at close

- **Cross-cutting changes get an internal-data check.** For any change
  to a cross-cutting surface (redaction, serialization, hashing), the close probes
  include an "internal data intact" check, not only the user-facing surface.
- **Report exactly what the targeted checks establish.** A close never authorizes a
  full suite; by default propose one to the owner as a question rather than running it. Reuse relevant results and name
  concrete unverified behavior without inventing a later full-suite gate.
- **A probe is an independent verifier session.** Record each probe's verdict in the
  journey's journal entry at seal time, never batched later. Spawn probes long-lived (tmux session
  under a callsign, same as executors): a probe that exits the moment it
  delivers leaves you guessing when follow-up questions come.

## Estimate reconciliation — at every close

Compare the recorded estimate with actual preparation, implementation, testing, and
reporting time. Record available values and explain material differences; do not invent
missing timing or require estimator-specific fields to close verified work. If scope
changes, revise the remaining budget from available timings and state uncertainty.
The launcher budget describes the whole remaining task, not just implementation time.
No new calibration run or estimation tool is required; the estimator (`agentic-time-estimate`)
is consulted only when installed, and clock times come from `report-time` when installed,
otherwise from `date` in the owner's zone, never from arithmetic.

## Triage-ruling reconciliation — at every close

Alongside the estimate pair, sweep the journey thread's PL rulings: for each
severity call + disposition the PL made mid-run, did the outcome prove it
right? A ruling that turned out wrong (severity under/over-called, disposition
that caused rework or a needless owner stop) is a lessons-file candidate
(`ai-doc/LESSONS.md`) — the
same close-the-loop pattern that calibrates the estimator (method:
`pl` core §Severity & disposition). While sweeping, also check the breaker
(`pl` core §The circuit breaker), counted from the thread's `attempt:` tags with
`bash "${PL_SKILL_DIR}/scripts/attempt-gate.sh" count --slug <slug> --scan <thread-file-or-dir>`:
three or more same-shape attempts at one problem is a miss, and so is a
recurring problem ruled with no tag or a fresh slug each time. The same sweep
reads the thread's `slow-ruling:` records (`pl` core §Fast thinking, slow thinking): a
switch signal that visibly fired — a breaker refusal, a ruling reversed twice —
with no slow-ruling record behind the next ruling is a miss of the same kind. **This rides
the seal**: the close-audit verdict card carries one line — "rulings reconciled: N,
misjudged: M (+ lessons-file disposition for each M)" — and beside it `breaker: clear` or
`breaker: missed #<count>` (each miss is also a lessons-file candidate). A missing line is
reported as a record gap, and N=0 is stated, never implied.

**Reconciliation against the decision-rights file after a night shift.** The bands and lists of what the PL
may decide alone, and what is owner-only, are in the live decision-rights file
(`~/.config/sno/decision-rights.md`; shipped default `references/decision-rights.md` in the pl
skill); it wins over any text here. When reconciling a night shift, check every decision taken
alone against it: one outside the "PL may decide alone" table, or one on the owner-only list, is a
miss reported first, by path. A red button (spend beyond the ceiling or an existing grant; an
irreversible action that leaves the machine) that was decided rather than carded to the owner is
the gravest miss. Red buttons go from the PL straight to `SNO_OWNER_ADDR` (the owner's own Reach
address) with the owning COS on Cc; COS may add a recommendation and may not approve, hold or edit them.

## Acceptance gatekeeping — journeys with a final end-to-end acceptance run (the last gate)

- **Opening end**: during plan review, take the candidate list of end-to-end user journeys
  from the executor (already-run + should-run, ~5–8 items), **discuss it with the owner
  in a real back-and-forth, and let the owner pick the must-pass few**; picked
  items are written into the final end-to-end acceptance run marked as chosen by the owner — no later stage
  may remove or downgrade them. The owner's picks are added on top of the coverage already planned for
  the requested behavior and never remove or replace any of that coverage. This discussion happens
  during the plan-approval step — not as a separate interruption of the owner.
- **Closing end**: inspect existing functional results for the owner-requested behavior.
  Report actual failures and any result that remains unverified. Missing hashes, sidecar
  files, report fields, or session pointers do not prevent closure and do not authorize
  another verifier run. Rerun only when relevant changes, failures, or absent functional
  evidence require it; keep the run within the affected scope and remaining budget.
