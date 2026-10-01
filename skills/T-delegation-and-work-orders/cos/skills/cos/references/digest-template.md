# Return report — shape

Delivered when the owner says they are back from a declared night shift. Not tied to a
clock, and never sent mid-shift.

One batch, written to disk **progressively through the shift** so it survives a session
death, delivered in chat the moment they speak. In the owner's chosen language and time zone (from the user's instructions), conclusion first, plain language, every charter named by its
exact filename with a plain-language gloss of what it does.

Everything they must act on is above the fold. The record is below it.

The structure below is normative, the wording is not.

---

## 0. Red-button cards waiting for you

First, before everything else: each card a PL sent straight to the owner on a red button
(spend beyond the ceiling or an existing grant; an irreversible action that leaves the
machine), listed unedited by its path. COS adds no summary in place of the card and never
approved, held or edited one. Omit this section when there are none.

## 1. Conclusion in one sentence

What the night amounted to, and whether anything needs them. If nothing needs them, say
that in the first sentence.

## 2. What moved

One line per charter filename, in queue order. Filename · what it does in plain words ·
what changed · state now.

```
`12-example-charter.md` (adds the export feature)
  → phase two done, sealed, commit abc1234.
```

State words only: sealed / running / stopped on you / stopped on something else / hit a problem.

## 3. For you to rule on (the doubt list)

**The only part that asks anything of them.** Empty is good news — say "none" and
move on.

Each item, in this order:
- which repo, which charter filename, what the thing actually is;
- what the PL decided on its own during the night shift;
- what makes it doubtful — the citation that did not resolve, the ruling that has two
  readings, the value call that was self-approved;
- **what concretely happens if they rule each way.**

No codenames inside the sentence that asks them to choose.

## 4. Blocked on you

Each with **the literal text they must type or the single decision they must make, written
out in full** — never a description of what they should say.

```
[copy this whole block verbatim]
<the exact line>
```

## 5. Estimate reconciliation

One line, and only when a miss is worth naming. Estimate versus actual, and the named
cause. Skip the section entirely when nothing missed.

## 6. The armed baton

The armed baton: the next charter filename, what it does, the pre-priced estimate, the
verification plan, the kill line — launchable with one word.

**It is quoted verbatim from the repo's `TODO.md` `OPEN` section** (core iron rule 12),
not chosen from memory and checked against the board afterwards.

## 7. Board disposition — required, and the report is not finished without it

```
board_before: <commit of the TODO.md that was read>
open lines at that commit: <N — must equal what cos-roster.sh printed>

1. "<line quoted verbatim>" → the armed baton (section 6)
2. "<line quoted verbatim>" → carried
3. "<line quoted verbatim>" → blocked on <person or lane> for <the exact decision>
4. "<line quoted verbatim>" → closed, removed in <commit>
```

Every open line at `board_before`, one entry each, count-matched. **Three dispositions
and no fourth** — carried, blocked on a NAMED person or lane, or closed with the commit
that removed the row. **Dropping work is the owner's call**; an entry saying dropped
quotes their ruling or the report is rejected.

**This block is the enforcement.** A close whose report has no section 7, or whose count
does not match, is not a close — the section exists because a rule in a skill file that
has no field in the artifact it governs is a rule with nothing to land in.

If the roll call reported the board `MISSING`, `NO-OPEN-SECTION`, `UNPARSED`, `TOO-LARGE`
or `UNREADABLE`, this section instead names that status and the repair state — never a count
of zero.

---

## Below is the record; no need to read it

- What ran clean.
- What COS decided under its own authority, and the reason for each — especially any of
  the three overrule classes, and any PL reopened.
- Intervention count for the night. **This number should trend to zero**; a rise is a
  finding about the layer below, not about the night.
- New learning entries — one line each, not the entry body.
- Anything COS deliberately did not report at the time, and why.

---

## Rules for writing it

- **Never attach an invented cause to a real measurement.** The guess inherits the
  number's credibility and spreads.
- **One fixed metric and one comparison frame per report.** No metric-switching between
  sections.
- Report what was skipped as plainly as what was done. A gap named is a gap they can price;
  a gap omitted is a surprise later.
- If a claim was not personally verified against disk, either verify it before writing or
  label it unverified with the one command that would settle it.
