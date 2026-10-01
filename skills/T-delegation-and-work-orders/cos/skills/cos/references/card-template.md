# COS → PL card — required shape

Before running these commands, set `PL_SKILL_DIR` to the absolute directory of the installed `pl` skill, in the same Bash call.

Read together with the core skill's **mail law**, which governs *whether the card
can land at all*. This file governs *what the card must contain once it does*.

## The reader you are writing for

**Assume a fresh session with no memory of the conversation that produced this card.**
That is usually literally true — the PL may have restarted, may be running on cached
skill text, and certainly did not watch you reason. **A card that only makes sense to
someone who was present is a card that will be misread.**

## Required contents, in this order

### 0. The authority line — first line of the body, no exceptions

Exactly one of:

```
RECOMMENDATION — you decide; these are the facts and the rule they touch.
OVERRULE — <which of the three cases>, and the reason, written out.
OWNER RULING — relayed verbatim, with the date. Not COS's to soften or dispose.
```

`decision` is the transport's word for *requires action*; it is **not** a claim of
authority. The default COS card is a recommendation the PL disposes of, and without this
line a recommendation reads as an order. **A card whose first line is none of the three is
malformed — do not send it, and a PL receiving one should ask which it is.** The three
overrule cases are in the core skill: redoing sealed work, burning a large block of time
with no estimate, contradicting a recorded owner ruling.

`OWNER RULING` exists because the other two both frame COS as the source, and a ruling
that came from the owner must not arrive looking like COS's opinion — the PL's response
to a recommendation is judgment, and to a ruling is compliance. Carry the date, and quote
them where the wording matters.

### 0b. The execution line — second line of the body, no exceptions

Exactly one of:

```
EXECUTION: PL RUNS IT — authors nothing, and finishes inside the PL's 600-second
  wall. It runs in the PL's own shell under `timeout 600`.
EXECUTION: DISPATCH AN OPERATIONAL RUNNER — authors nothing, but runs longer than that
  wall. Spawned and callsigned like any executor, with NO charter. PL iron rule 6.
EXECUTION: DISPATCH AN EXECUTOR — authors or edits deliverables and works from a charter.
  Its first instruction is one bare skill call naming the charter: `/deliver <charter>`
  (Claude) or `$deliver <charter>` (Codex).
```

**Two mechanical questions decide it: does this job author or edit anything the repository
keeps — source, tests, documents, configuration, data — and if not, does it finish inside
ten minutes?** Nobody needs experience to answer either, which is why this line can be
required rather than judged.

**Not "does it change source code".** A long documentation or configuration edit changes no
source and would fall through that wording into an operational runner, which executes and
never authors. Such a job is neither, has no settled route, and is a decision to put to the
owner rather than a box to default it into.

**The middle value is the one most easily left out.** A PL may not hold a run past its
600-second wall (iron rule 6), so naming a multi-hour evaluation "PL runs it" orders
something illegal — the same dead end one step later.

**A card whose second line is none of the three is malformed — do not send it, and a PL
receiving one must not start work.** Its move is to bounce the card back and ask, exactly
as with the authority line above.

The line exists because omitting it is not neutral. A card that says what to run, where,
how to watch it and how to report it, and never says who runs it, falls to the PL's
default route — dispatch — and a plain script run gets wrapped in a development lifecycle:
mission files, dispatch orders, callsign claims, and no run. The charter requirement is
scoped to executors that author; an operational runner has no charter.

**Paste this rule inline into any dispatch card**, alongside the line itself. A PL running
on cached skill text has never read this file.

### 1. The correction to their world-model, with evidence

What they currently believe · what is actually true · the commit hash or file path that
proves it.

**Lead with this whenever it exists.** A stale board silently makes a *correct*
subordinate wrong, and correcting the document is worth more than correcting the agent —
so fix the document too, and say in the card that you did.

Table form works well when more than one row is wrong:

```
| Charter filename | Board says | Disk/git truth |
|---|---|---|
| 12-example-charter.md | blocked on evidence | evidence SEALED — commits abc1234, def5678 |
```

**Any field, path, or command you name, you have opened.** Before writing "copy X from
Y", read Y and confirm X is in it. A card carries COS's authority, so a name in it reads
as verified.

### 2. What must NOT be redone

Name the sealed artifacts explicitly, with their commits and paths. **Re-collecting
evidence that already exists is one of the most expensive silent failures available to a
night shift** — it looks like diligent work the whole way through and produces nothing.

### 3. The order itself

Addressed by **charter filename**. If it spans more than one journey, decomposed into named
slices of that charter, and one executor owns one slice.

Never a module name, never a letter code, never "the X work".

### 3b. The attempt tag — required the second time you card the same problem

A card intervening in a problem you have carded before carries, in subject and body:

```
attempt: <problem-slug> #N — success check: <command>
```

The slug is minted on the first card and reused verbatim on every later one — a fresh
slug for an old problem resets a counter that exists to stop you. `#N` comes from the
gate, never from memory:

```bash
bash "${PL_SKILL_DIR}/scripts/attempt-gate.sh" check --slug <problem-slug> \
  --scan <the lane's maildir>    # prints "ok next-attempt=N", or REFUSES with exit 3
```

**At #3 the card is not sent** — the gate exits 3, and the circuit breaker (core
skill, §Decision discipline) forbids the third same-shape attempt and names the legal
moves instead. Transport repairs and safety stops carry no tag — they are not attempts
at the problem.

### 4. Hard constraints, restated inline — not referenced

**Never assume a linked document will be opened.** Every constraint expensive to violate
is pasted into the card body: the scope fence, the project's evidence rules, the runtime, the
long-running-process kill line, and the relevant lines from `LEARNING.md`.

This is the same doctrine as the learning-file read hooks: the duty must ride the
artifact the recipient necessarily reads.

For a **newly opened PL**, this section must also contain the heartbeat-ring block from the
core skill — `heartbeat --interval 10m --label pl-<name> -- sno reach ring <ADDR>`, **with
this lane's strict address already substituted**. A skill amendment does not reach a session
that booted before it, and a PL handed a role alias in a multi-lane repo goes blind to its
own mail while appearing to have followed the rule. The PL's seat must also be registered
from its own window (`sno reach register`), or it cannot be rung.

A shift-start card also names the live decision-rights file, `~/.config/sno/decision-rights.md`,
which the PL reads now; a red-button item goes from the PL straight to the owner with COS on
Cc, and COS never approves, holds or edits it.

### 5. Ordering constraints, with their reason

If this journey must run before or after another, **say why in the card.** "Do not do X
first, because Y edits the same file" is absorbed. A bare "do X last" gets helpfully
reordered by a competent executor who cannot see the other journey.

The rules that generate these constraints:

- Two journeys that **write** the same file never run in parallel.
- A journey that only **reads** a file another writes is usually safe — and that reader
  must be explicitly forbidden from writing source.
- **Anything that freezes, hashes, snapshots, or measures a file is ordered AFTER
  everything that modifies it. Freeze last, always.**

*Worked example:* a PL correctly finds a checksum manifest has gone stale and proposes an
hour refreshing it first. The journey in flight is going to edit a file the manifest
covers — refreshing first re-stales it immediately and pays the hour twice. Correct
order: land the change, refresh last.

### 6. What COS requires back

Concretely, as a list the PL can answer point by point:

- the fresh wall-clock estimate;
- whether one executor can own the whole charter; if not, say so in the charter;
- the callsign and journey id it launches;
- **the specific condition under which it must speak up early rather than at the end.**

That last one is what turns a silent night into a supervised one. Name the condition —
"card me the moment the first phase goes red", "card me if the estimate moves past 3
hours" — never a generic "keep me posted".

## Card mechanics

`ADDR` is this lane's strict registry address, not a role alias. Resolve it
before use. The complete header and command contract lives
only in `~/.local/lib/sno-reach/current/guide/agent-reach.md`.

```bash
# One resolver, never a repository-only first-row lookup: a repository may carry several
# lanes, and taking the first row addresses the wrong PL. It refuses rather than guesses.
ADDR=$(bash "${PL_SKILL_DIR}/scripts/lane-resolve.sh" --repo "$PWD" --field addr) || exit 64
# card.eml is complete RFC 5322 mail per the Reach guide.
sno reach send --as <this COS registry address, as printed by cos-roster.sh> < card.eml
# The card must appear at that exact address.
sno reach inbox --as "$ADDR" | grep -qF "<the card's subject>" \
  || echo "UNDELIVERED: not in $ADDR's queue — wrong type or wrong address"
```

- Use the exact registry address printed by `cos-roster.sh`.
- **Aim the thread.** Answer with `sno reach reply --card <original>` and inspect the
  recipient's queue after sending.
- Send exit 5 or 6 means delivered, wake failed: never resend the card; repair the seat.

## Title discipline

The title is often all that appears in a queue listing. It must say **what changes**, not
what the card is about.

- Good: `12-example-charter.md evidence is SEALED — dispatch the product implementation only`
- Bad: `re: lifecycle question` · `status update` · `a few notes`

## Before you send, and after

1. `sno reach seats` — is **that exact address** registered and live? Without a turn lock
   the ring must start a turn: send and judge by the ring outcome. A Claude agent has no
   lock at all.
2. Send.
3. `sno reach inbox --as "$ADDR"` — **the card must appear.** Absent means it did not reach
   the required queue; treat it as never sent. Appearing is the queue, not a receipt.
4. Next tick: check absorption. Unanswered two ticks later is a **delivery failure**,
   not slow comprehension. Act on it — do not re-send into the same silence, and do not
   re-report the same stall every tick.
