# TODO.md — the shape, and the one command that produces it

**Reading TODO.md needs no command.** Writing it is `bash "${PL_SKILL_DIR}/scripts/todo.sh"
<command>` and nothing else — not the PL by hand, not COS by hand (below, `todo.sh <command>` means
that call). This file documents the shape that script renders, for anyone who needs to know what
they are reading. The rules it enforces live in the pl core skill ("TODO.md — the single plan +
board") and in the script's own `--help`.

There is no separate roadmap file; the roadmap's function lives here as the north-star
header plus the open list.

---

```markdown
# TODO — <repo> (written by todo.sh, owner-reviewed)

> North star: <one or two lines — the current focus>. Detail lives in each charter.

Everything still owed by this repository is the one list below, in priority order. There
is no second list: running, queued, ranked-but-unstarted, blocked-on-the-owner and
owner-FYI are `state:` values on a row. Closed work leaves for
`ai-doc/JOURNAL/routing-ledger.jsonl` and never comes back.

<!-- board-checksum: sha256:… · rows: … · written by todo.sh; rows are not hand-edited -->
## OPEN

- **<block name in plain language>** · state: running · id: b-0007 · prd: <path> · decision: high · verified: <date> · journey: j-x · callsign: vega · budget: 11.0h wall · why-now: <one line> · detail: ai-doc/ACTIVE/PL/board/b-0007.md
- **<block name>** · state: blocked-on-owner · id: b-0008 · prd: <path> · decision: high · verified: <date> · awaiting: <the exact decision, written out>
```

**A row is exactly one line, and the field order is the renderer's, not the author's.**
The COS roster script (`cos-roster.sh`), which every supervisor runs at boot and at every tick,
displays only the first 150 characters of a row — so name, state and id come first, and a long name can
never push the state out of the only part a supervisor sees. It also reports the whole
board `UNPARSED` when an unindented non-list line appears under `OPEN`, which is why the
checksum comment sits ABOVE the heading. **That parser is not what keeps rows one line**:
an *indented* stray line it silently folds into the row above. `todo.sh` is what enforces
the shape — neither kind parses as a row, so `check` names it and the next write stops.

## The fields

| Field | Written by | What depends on it |
|---|---|---|
| name | `add --name`, `set --name` | the selection proposal, and the close's verbatim quote |
| `id:` | minted by `add`, never reused | the close quote survives a rewording; names the detail file; a hand deletion is detectable |
| `state:` | `add`/`set --state` | running · queued · ranked-next · not-started · blocked-on-owner · owner-fyi |
| `prd:` | `add`/`set --prd` | names the row's charter path (the flag keeps its name). **a block with no source artifact is not ready** — `--prd none` is recorded and reported by `check`. The row stays selectable; what gets dispatched is its first slice, "write the one-page charter" with the owner |
| `decision:` | `add`/`set --decision` | the concurrency rule in pl-dispatch: one `high` running at a time, which `check` reports |
| `verified:` | **`verify`, or `add --command`** | staleness. `set` cannot touch it — otherwise editing one word would claim the row was checked against disk. A row added with no disk check reads `verified: never`, and `check` says so |
| `journey:` `callsign:` `budget:` | `set` | traceability from block → charter → journey, on running rows |
| `why-now:` | `add`/`set` | why this outranks the rows below it |
| `awaiting:` | `set` | the exact decision the owner must make, written out |
| `held-because:` | `set` | why a queued row is held |
| `detail:` | added by `note`/`verify` | where the narrative went |

Order is priority order, and the renderer never sorts — **`todo.sh move <id> --before <id>`
is how a priority is expressed**, since hand-editing the file is not available. **The top
row whose state is not `running` or `blocked-on-owner` is the default next block.**

## How it is used

1. **Selection is board-anchored.** Asked which block to work / what's next: answer from
   this list — the top eligible row in plain language, its charter path, decision level, size,
   one-line why-now, then the runner-up. Never pitch from feature-memory; never a bare
   codename. No board row + cited artifact = not a valid proposal.
2. **Concurrency is decision-anchored.** At most ONE `high` row running at a time; `low`
   rows parallelise to ~2-3 if non-overlapping; the numeric backstop (≤4 executors per
   PL) is PL discipline — the launcher does not enforce it. A held row stays here as `queued` with `held-because:` — never moved to a
   separate waiting area, because a separate area is a place work goes to stop being read.
3. **Re-ordering is the owner's.** The PL proposes, the owner ratifies, like a charter change —
   and then it is one `todo.sh move` call.
4. **A state that claims something is refused unless it carries it.** `set --state running`
   needs `--journey` and `--callsign`; `--state blocked-on-owner` needs the `--awaiting`
   decision written out. Recording a row is never refused; a transition safely can be,
   because the row simply stays where it was, still visible.

## What keeps it short

`todo.sh check` is the whole answer, and it fails loudly rather than tidying silently:

- **Closed rows are gone.** `close` logs a missing optional evidence path without
  blocking a completed task. It appends the close to `ai-doc/JOURNAL/routing-ledger.jsonl`
  before the row leaves so a later task cannot reuse the same identifier, and the renderer
  has no "recently closed" section to put it in. A repo may keep a coarse prose roll-up
  for a person skimming the arc — **it is prose, never the record**, and nothing is
  reconstructed from it.
- **Narrative is elsewhere.** Over-long values are refused and pointed at `note`, which
  appends to `ai-doc/ACTIVE/PL/board/<id>.md`. A row states the current fact; the
  superseded version of it goes in the detail file, never onto the row as its own changelog.
- **Age marks a row, it never removes one.** Over 15 days since `verify`, `check` says so;
  so does a row that was never verified at all. Work that is still owed and has gone quiet
  is exactly the work that must stay visible.
- **Over the display cap, the row is still recorded.** `add` never refuses; `check`
  reports the overflow. Refusing to record real work is how work becomes invisible.
- **Nothing below the rows.** `check` fails on it; `archive-tail` moves it out whole to
  `ai-doc/JOURNAL/board-tail-<date>.md`, summarising and dropping nothing. **The open rows
  never move** — the tail begins at the next heading after them. And archival refuses
  while that history still holds list items, printing them first: an owed item archived by
  mistake is invisible with every later `check` passing. Say `--confirm-no-owed-work yes`
  once every one of them is genuinely history.
