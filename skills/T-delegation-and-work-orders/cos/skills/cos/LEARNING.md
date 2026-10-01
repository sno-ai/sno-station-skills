# COS Learning — management judgment only

**What lives here:** when to block, when to let run, how to shape a process.
**What never lives here:** bugs. A broken script, a wrong path, a protocol hole is fixed
where the code lives and it disappears. Writing it down instead leaves the bug *and* adds
a line nobody can act on. A bug is a bug: fix it now, never bank it as experience.

**Nor does law.** Where a rule is already written into a skill file, this file keeps the
**evidence** — what happened, what it cost — and points at the law rather than restating
it. A body that reproduces a section of `SKILL.md` is padding: it doubles the maintenance
and the copy goes stale silently.

**How it gets read** — storage is not reading, so three injection points, all load-bearing:
① the boot ritual reads the index; ② **every wake tick re-reads the index** (≤64 lines,
effectively free — this is what defeats stale-cache drift inside a long session);
③ **every outgoing card pastes the relevant lines inline**, because a PL will never open
this file.

**Therefore every index line must be executable standing alone.** The index is the only
text guaranteed to be re-read; a line that cannot be obeyed without opening its body has
failed, however elegant it reads. Bodies exist for the audit trail, not for the rule.

**How it grows** — `cos-evolve` owns the pen and holds the promotion ladder; it is not
repeated here. Three facts a *reader* needs.

**Entries are never deleted and never struck out.** What can happen is that an entry
**leaves the index**: once its rule is enforced by a check that cannot be bypassed, you no
longer need to remember it, so its line is retired and its body stays forever as the audit
trail. That is the only legal way to free a slot. The index is the working set; the bodies
are the archive.

**The index holds at most 64 lines**.
At 64 lines the re-read is roughly two thousand tokens a tick — cheap enough that machine
burden is not what the number is protecting. What it protects is the pressure to
mechanize: reaching the cap forces a retirement, and a retirement requires a real check.

**And at most 16 of them may run on prose alone** — an entry with no `**Enforced by**`
line. That is the limit that actually bites, because prose is what has demonstrably
failed: a rule written into this file does not survive contact with a plausible-looking
green state. The 17th does not get added; something gets mechanized first. This set should shrink, but **it will never
empty** — some of these are pure judgment, and inventing a check for judgment is machinery
for its own sake.

The index below is a starter set: index lines only, with no bodies, and exempt from both
caps until the first retirement. From then on both caps apply.

Shared by every COS instance for this user. This is the shipped seed; at run time the
working copy is `~/.local/state/cos/LEARNING.md`. Append under `flock`; never rewrite
wholesale.

**Entry shape**

```markdown
## <one-line claim, stated as a rule>
**Situation** — what was in front of the supervisor.
**What went wrong** — the decision actually taken, and its cost, with numbers.
**The rule now** — imperative, checkable. One or two sentences.
**Enforced by** — the script, required field, or numbered step. Omit until it exists.
**Hits** — one line each. Increment on every recurrence.
```

---

## Index

- [mail] · Delivery is the sender's — send rings the window; unabsorbed = failure, not slow reading
- [intervene] · Report a static alarm once with the action that clears it, then stop
- [intervene] · Give facts and the rule broken; the PL picks the fix — overrule in 3 cases only
- [intervene] · One role can have two live sessions — check ledger and process list before ruling
- [evidence] · Verify the load-bearing claim on disk yourself; never rule from a summary
- [evidence] · Never authorise N repairs off one measurement — measure the real rate first
- [evidence] · "Most cases undetermined" means audit the instrument, not condemn the product
- [evidence] · Report the number; name the fact that would settle its cause, never guess it
- [docs] · Fix the stale document first, then card the agent with the evidence
- [authority] · An artifact a journey wrote cannot authorize it — check the author before the size
- [authority] · If the main loop won't run without it, it is the next dispatch, never a debt row
- [schedule] · Order anything that freezes, hashes or measures a file after everything that edits it
- [schedule] · Settled small work prices several times too high — discount it; never order the estimator to shrink
- [run] · Read the first minutes yourself; on the first red root-cause now, and cap any continue
- [run] · No relaunch of an expensive run without a named delta — canary first, full run as the gate
- [owner] · No repo, charter filename, and what changes either way → the question does not get asked
- [owner] · Close with the next step priced and its check planned — their cost must be one word
- [close] · Every close: too little, too much, never stopped, wrong repo — three of four look green
- [close] · Drain the inbox before a seal; dispose the window only once the charter itself is done
- [process] · Catching yourself noticing instead of acting proves a machine check is missing
- [alive] · No turn lock = no turn (Codex on Linux with systemd; otherwise judge by the seat and inbox), so ring it; a heartbeat armed is still not a turn started or work done
- [intervene] · Read the journey's decision thread before any deletion alarm — no exception
- [timing] · After launch send only stop-the-bleeding; buffer the rest, ride their next card
- [authority] · Confirm a new KIND of work; never the next step of work already ordered
- [feed] · Parked is not a state — re-task against what the blocker actually forbids
- [evidence] · A described next step is not a started one — demand its on-disk start proof
- [evidence] · Never hand-write a liveness or did-it-move check — cos-roster.sh and cos-since.sh only
- [authority] · A general owner go-ahead never clears a row blocked on a specific question — re-ask in one line

---
