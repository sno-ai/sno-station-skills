---
name: cos-evolve
description: "Turn repeated management failures into enforced COS or PL rules. Load ONLY after the owner has explicitly activated the cos role for this session and the COS core routes here. Never invoke directly."
requires:
  programs: []
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
---

# COS — harvesting friction into law

Before running these commands, set `PL_SKILL_DIR` to the absolute directory of the installed `pl` skill, in the same Bash call.

Load only when the owner has explicitly activated the COS role for this session and the
COS core routes a repeated management failure here.

**Exclusive authority of this overlay: the pen over skill files and `LEARNING.md`** (the
batch review only appends the decision-rights lines named in its Pass 1). No other part of
the COS tree, and no PL, may edit them. PLs propose by card.

**The decision-rights file is different.** `~/.config/sno/decision-rights.md` is the owner's.
This overlay may propose a diff to its tunable parts only — the thresholds and the PL and
COS tables — from the batch review's recorded overturns and repeatedly approved queued
items. Nothing lands without the owner's explicit yes for that change, and each landed
change gets one line in the file's change log. The "Fixed by the skills" list and the red
buttons change only on the owner's own explicit instruction, never on a proposal.

**Never edit the skill tree mid-journey.** Evolution runs through a retro pass. A running
session carries the old text in memory anyway, so a mid-flight edit changes nothing for
the agent it was aimed at while silently changing the rules for everyone else.

## The pen's boundary — how, never what

**Whoever holds this pen may card any agent about HOW it works, and may never card it
about WHAT to work on.** Amendments have to travel as cards — a skill edit does not reach
a session that booted before it, so pasting the new text inline is the only delivery that
works. That is the whole licence, and it stops there. Telling an agent to reload, and
telling it what its next task is, feel identical to send and are not: the second creates a
second supervisor, and an agent taking orders from two places gets whipsawed between them.
That can kill a live journey.

**The line in practice.** "Re-read these two files, here is what changed and why" is the
pen. "Go card your executors about it" is a work order, however procedural it sounds —
route it to the COS that owns the lane and let it decide when. The tell is whether the
sentence spends the recipient's *time* or changes its *rules* — a line crossed most
easily by whoever just wrote it.

**Anyone whose sender is not a registered owner, COS, PL, planner, verifier, or executor
seat** (planner and verifier are defined in the cos core's Terms) is out of chain by definition and gets only this
licence. The `From` header is on every card, so a crossing is visible
through `sno reach log` after the fact without anyone having to have
been watching.
Out-of-chain authors may send skill amendments only; they cannot assign work.

**Why the fence exists:** a successful `sno reach send` rings
the recipient and can start a turn in a registered agent's window. That is a real
increase in reach, and reach without a stated limit is how a helper becomes a second chain
of command.

## Step 1 — is this even a lesson?

The admission filter: the learning file admits management judgment only — when to block,
when to let run, how a process should be designed. Communication debugging and program
errors never enter it; those are bugs, and fixing them makes them disappear.

Three tests, all must pass:

1. **Is it a judgment call, not a bug?** A broken script, a wrong path, a protocol hole
   is a bug. Fix it where the code lives and it is gone. Writing it down instead leaves
   the bug *and* adds a line nobody can act on.
2. **Would it change what a future supervisor decides**, not merely what it knows?
3. **Can it be stated as a rule?** If the only honest version is "try harder next time",
   it is not a lesson — see step 3.

## Step 2 — the "where" ruling

A machinery or protocol bug is fixed **where the code lives** — the operational script,
the template, the dispatch text — never in memory and never in the learning file. Global
memory holds cross-project non-code facts only.

The meta-lesson from the failure may enter the learning file. The fix goes in code.

## Step 3 — a judgment lapse is mechanized, not exhorted

**When COS catches itself having merely *noticed* something it should have acted on,
that is proof a machine check is missing. Build the check.**

Example: a supervisor that detects a stalled agent and merely waits for the owner is
repeating the waiting the machinery exists to kill, one layer up. The fix is not a note
about vigilance; it is a protocol change plus a roll-call check that raises the condition
for any agent, whether or not anyone is paying attention.

Mechanization targets, cheapest first: a required field in `card-template.md` · a check
in `cos-roster.sh` · a line in the boot ritual · skill text as the last resort, because
skill text is the thing agents drift off under load.

## Step 4 — the promotion ladder

| Occurrence | Action |
|---|---|
| **First** | A journal line only. One occurrence is not a pattern |
| **Second** | An index entry in `LEARNING.md` **and a sharpening of the text.** A lesson stated once and missed anyway is proof prose does not hold — the second strike is the mechanization trigger; do not wait for the third |
| **Third, or one expensive hit** | **Mechanize** it per step 3, then add an `**Enforced by**` line naming the script, required field, or numbered step that now carries it, and cut the body down to the evidence |

**A mechanized entry is never struck out and never deleted.** Striking it through to
protect the index budget is the wrong trade: a mechanism can be removed by someone who
cannot see why it exists, and the evidence in `LEARNING.md` is the only thing that stops
that. The entry stays live and readable, with a pointer to where enforcement lives.

**An entry with no `**Enforced by**` line is running on prose alone**, which is the
condition step 3 exists to end. That set is `cos-evolve`'s standing work list, and it is
supposed to shrink.

**Two caps, and the second is the one that bites.** The index holds at most **64 lines**,
and at most **16 of those may carry no `**Enforced by**` line**. Sixty-four lines re-read
per tick is about two thousand tokens — cheap, so machine burden is not what either number
protects. They protect the pressure to mechanize. Prose is what demonstrably fails: a rule
written into this file does not survive contact with a plausible-looking green state.
The shipped starter set of index lines is exempt from both caps until its first retirement.

**Reaching a cap forces a retirement, and retirement has exactly one legal form.** An
entry leaves the **index** when its rule is enforced by a check that cannot be bypassed —
at that point nobody needs to remember it, so the line goes and **the body stays forever**.
Nothing is ever deleted or struck out; the index is the working set, the bodies are the
archive. Retiring an entry whose `**Enforced by**` names a convention, a habit, or a
document rather than a check is not a retirement, it is a deletion wearing a label.

**Before you retire anything, the cheaper moves, in order:** ① fold the new evidence into
the existing entry it actually belongs to — most "new" lessons are a second face of one
already written, and a shared incident is the tell; ② if it is law rather than judgment, it
does not belong here at all — write it into the skill file and keep only the evidence. What
is **not** legal is quietly adding a 65th line, or a 17th prose-only one.

## Step 5 — route to the right shelf

| Scope of the lesson | Home | Writer |
|---|---|---|
| One repo's pitfalls | that repo's `LESSONS.md` | its PL |
| Workstation-wide traps (hosts, ports, sandboxes, tooling) | a machine-wide traps file the user chooses, if any | PL proposes by card, **COS writes** |
| PL *behavior* — how a PL should supervise, dispatch, audit | the `pl` / `pl-*` skill text | **COS only** |
| COS's own management judgment | the COS learning file (`~/.local/state/cos/LEARNING.md`) | **COS only** |

Routing errors are common and expensive in both directions: a repo-specific pitfall written
into skill text pollutes every project, and a management lesson left in one repo's
lessons file never reaches the other PLs.

## Step 6 — is the prescription a class?

When a PL prescribes good medicine for its own journey, COS's job is deciding whether
the disease is a **class**. If yes, promote the prescription to law the same day and
carry it to every other PL — they cannot see each other. If no, it stays local.

This is the mechanism behind the standing cross-repo propagation duty: a ruling made in
one repo must reach every PL that would otherwise repeat the failure.

## Writing to `LEARNING.md`

Learnings written at run time go to `~/.local/state/cos/LEARNING.md`, seeded by copying the shipped `LEARNING.md` on first use; the installed skill directory is never edited.

Entry shape:

```markdown
## <one-line claim, stated as a rule>
**Situation** — what was in front of the supervisor.
**What went wrong** — the decision actually taken, and its cost, with numbers.
**The rule now** — imperative, checkable. One or two sentences.
**Enforced by** — the script, required field, or numbered step. Omit until it exists.
**Scheduled as** — only when the lesson implies repo work: the repo and the board line, quoted verbatim.
**Hits** — one line each. Increment on every recurrence.
```

Index line:

```
- [tag] · <the rule, executable on its own, ≤115 characters>
```

Keep each index line to 115 characters: a rule that will not fit is almost always two
rules jammed together, and splitting it is the correct response.

Rules for the file itself:

- **Numbers, never adjectives.** "Sat unread six hours" survives; "took a long
  time" does not.
- **The index line must be obeyable without opening the body.** The index is the only text
  guaranteed to be re-read — at boot and on every wake tick — so a line that merely names
  a topic has failed. Write the instruction, not the subject.
- **Never restate law the skill files already carry.** The body keeps the evidence — what
  happened, what it cost — and points at the law. A body reproducing a section of
  `SKILL.md` doubles the maintenance and the copy goes stale silently.
- **Every entry is a rule a future session can check itself against.** If it cannot be
  checked, it is not finished.
- The file is shared by every COS instance for this user. **Append under a lock**
  (`flock` on the file); never rewrite wholesale
  while another COS may be writing.
- New entries are reported in the next return report — one line, not the entry body.

## The read hooks — storage is not reading

A file nobody is forced to open at the right moment does not exist. Three injection
points, and all three are load-bearing:

1. **Boot** — the COS session start reads the index (core boot ritual, step 2).
2. **Every wake tick** — the index is re-read. At most 64 lines, effectively free, and this is
   what defeats stale-cache drift inside a long-running session.
3. **Every outgoing card** — the relevant learning lines are pasted **inline into the
   card body**. A PL will never open COS's learning file. The duty must ride the
   artifact the recipient necessarily reads.

The same doctrine applies to every skill amendment COS makes: **a session that booted
before the edit never sees it.** When an amendment matters to a live PL, paste the new
text inline into a card; do not rely on the file having changed.

**And it applies to the open board, which is otherwise an orphan.** Everything an agent
reads, it reads because something else pointed at it — a card, a review, an error, a
diff. Nothing points at `TODO.md`, so reaching it takes remembering it exists, and memory
is exactly the faculty that fails late in a shift. Its two hooks are load-bearing the same
way the three above are — `cos-roster.sh` prints the `OPEN` section at boot and at every
tick, and every close quotes a line from it (core iron rule 12). An "always read the
board" rule is not a hook: a supervisor who already knows that rule still misses the board,
so knowledge is not the missing part; a path is.

**A lesson that creates work belongs on the board as well as in this file.** The learning
file holds management judgment — when to block, when to let run, how to shape a process.
Where the lesson also implies a concrete change to a repository, that change becomes an
`OPEN` item in that repo's `TODO.md` in the same pass. A lesson recorded only here is a
rule with nothing scheduled to satisfy it, and it reads as done forever.

**And the link is written down, so it can be checked.** Such an entry carries a
`Scheduled as:` field naming the repo and quoting the board line verbatim. Anyone can then check it: the entry is wrong when the quoted line is neither present in that
repo's `OPEN` section nor accounted for by a close record in the routing ledger. Without the field the promise is unfalsifiable — an entry
saying work "was scheduled" reads identically whether the board write happened or was
forgotten, which is the same class of failure as an unquoted close.

**Board writes here go through the same one command as everywhere else**:
`"${PL_SKILL_DIR}/scripts/todo.sh" add` (never a hand-edited row), which holds the
per-repo lock across the whole read-validate-write. This overlay is the third that can
reach a board — live supervision edits stale ones, batch review rebuilds them — and three
writers with no lock silently drop lines. The `Scheduled as:` field quotes the row the
script rendered, and cites its `id:` so the quote survives a later rewording.

## Mirroring — every change, verified

Skills are installed and updated by `sno setup`; change a skill in your own copy. When a live script must be replaced by hand, **copy through a
temporary file in the same directory and rename it into place. Never `cp` onto a live
script.**

```bash
tmp=$(mktemp "$dst.XXXXXX") && cat "$src" >"$tmp" &&
  chmod --reference="$src" "$tmp" && mv -f "$tmp" "$dst"
```

**Why the rename, and it is not style.** Bash reads a script incrementally by byte
offset *while executing it*. `cp`, `install` and every editor that writes in place
truncate the file and rewrite it, so every offset shifts under any process already
running it: the interpreter resumes mid-token and dies with a syntax error naming a
line that is perfectly valid on disk. `mv` swaps the directory entry and leaves the
old inode intact, so a process already executing finishes on the version it started
with.

A script rewritten in place can kill a process already running it, minutes later, with a
syntax error at a line that is valid on disk: the corruption surfaces when execution next
reaches the rewritten region. A watch process killed this way leaves no alarm — it looks
like a quiet queue — and `bash -n` cannot catch it, because the fault is in how the file
was shipped, not in what it contains.

A hand-edited live copy is not done until the same change is in your own copy of the
skill that `sno setup` installs from.
