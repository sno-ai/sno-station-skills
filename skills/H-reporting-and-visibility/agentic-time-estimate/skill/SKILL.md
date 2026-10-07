---
name: agentic-time-estimate
description: "Answer how long agent work will take, how much longer active work needs, or what clock time applies. Estimate full AI-agent wall time, measure active progress first, and get owner-facing times from `sno report-time`. Never estimate human-developer time."
requires:
  programs:
    - {name: report-time, min_version: "1.0"}
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
    - {slot: 4.background-processes, need: required}
---

# Agent time — how long, how much longer, and what time it is

Before running the scripts below, set `AGENTIC_TIME_ESTIMATE_SKILL_DIR` to the absolute path of this skill's directory (the folder that holds this `SKILL.md`) in the same shell command.

**Prerequisites.** Linux with procps `ps` (with the `etimes` column) and `pgrep`, plus the `sno report-time` command from Sno Station; `sno report-time --pid` also needs `/proc` and GNU `date`. `time-left` stops with one clear message when they are missing.

"Owner" below means whoever owns the work and reads the answer, usually the user. A "journey" is one piece of delegated work from request to close. A "route card" is the record that dispatched it, and the "routing ledger" is a project file with one row per journey (the `pl` skill writes both when it is installed); every rule below that mentions them applies only when the project keeps them, and is skipped otherwise. A ledger's `closed` event and its fields (`anchor_key`, `actual_body_h`, `actual_process_h`, `calibration_note`) are defined by the `pl` skill; without a ledger, still emit `anchor_key` in the estimate, so a later close can copy it.

Three questions live here. **What clock time to write for the owner** is the
`sno report-time` command, immediately below. **How much longer** for work already running is
the in-flight section after it — measured facts first, judgment last. **How long** a fresh
piece of work will take is the estimator, everything from Step 1 down. All three are
answered from a script or a table before they are ever answered by thinking about it.

## Clock times for the owner — the `sno report-time` command

Sno Station provides `sno report-time`; `sno setup` installs it.

**Never write a clock time for the user that the command did not produce.**

    sno report-time

Output is always a pair, local time with its zone then UTC, and it is the only accepted form (the zone shown is the machine's own; `CET` here is only an example):

    09:31 CET (08:31 UTC)

Dates appear on both sides when the instant is not today.

**Run it whenever a clock time is about to appear in something the owner reads** — a
deadline, a "measured at", a "last written", an "N minutes ago" being turned into a time.
That is the trigger; nothing else is required.

**Do not bother agent-to-agent (by default; a project may choose otherwise).** Cards, dispatch text, commit messages, journals, logs and
ledgers stay UTC-only. Machines do not misread UTC and the pair is noise there. The pair
exists for exactly one reader.

### The five forms

    sno report-time                          now
    sno report-time --in 3600                3600 seconds from now
    sno report-time --pid 2750721            when that `timeout` wrapper fires and the job stops
    sno report-time "<UTC timestamp>"       that instant, read as UTC
    sno report-time @<epoch>                  that epoch

A bare time string is read as **UTC**; convert source timestamps to UTC before passing them.

`--pid` reports **the instant the wrapper fires** — when the job is signalled and stops.
Where the wrapper carries `--kill-after=N`, a forced kill lands N seconds after that; this
reports the first instant, because the first is when the work ends. Do not describe the
number as "when it is killed" if the wrapper has a kill-after: it is when it is stopped.

`--pid` **reads the wall limit off the process itself and refuses everything else.** You
cannot supply the limit, because a caller-supplied wall is a caller-supplied wrong answer —
and this mode exists precisely because a wrong deadline is indistinguishable from a right
one. It refuses if the pid is dead, if it is not a `timeout` wrapper, or if its duration is
unreadable. `--expect-wall <seconds>` is an optional cross-check that **refuses on mismatch**
rather than picking one of two answers.

### Why a command and not arithmetic

Source timestamps may be UTC while the user reads in a different zone. `sno report-time`
uses the machine's local zone, including its `TZ` setting, unless
`REPORT_TIME_USER_TZ` overrides it. A wrong hour can look right, so use the command
for every user-facing clock time. `--pid` requires Linux `/proc` and GNU `date`.

Two rules follow, and the command exists to make both automatic:

- **Never copy a time out of another agent's card.** Re-derive it. A stated deadline is a
  claim like any other.
- **Derive a deadline from the process, not from prose** — `sno report-time --pid <pid>` reads
  the wall limit off the process's own command line and anchors on its start time. The
  optional guard is spelled `--expect-wall <seconds>`; any other trailing argument is refused
  rather than ignored, so a mistyped guard cannot look like a guard that ran.

The pair is not decoration: the two clocks differ by the user's UTC offset, so a wrong
conversion is visibly wrong to both the writer and the reader. It converts a silent failure
into a loud one.

---

## How much longer — work already in flight

The user asks how much longer / when will it be ready / is it stuck. Answer in
this order: use measured facts first, then estimate any completion time they do not establish:

1. **Measure first — `time-left`.** Deterministic facts only; it never estimates.
   Resolve it once, then call it — a bare relative path is not runnable from the
   repository you are standing in:

   ```bash
   TL="${AGENTIC_TIME_ESTIMATE_SKILL_DIR}/scripts/time-left"
   bash "$TL" --find <pattern>     # candidate pids + how long each has run
   bash "$TL" --pid <pid>          # deadline: <local/UTC pair>  |  running: 3h07m elapsed
   bash "$TL" --tasks <file>       # tasks: 3/4 done (75%), 1 open
   ```

   **Do not hunt the pid with a bare `pgrep -f`** — the pattern sits in the command line
   of the shell running the search, so that shell matches first and reports minutes of
   elapsed time for a job that has run for hours. `--find` excludes its own process and
   ancestry; use it.

   A **deadline line is the timeout signal deadline, not a completion estimate**.
   Report it as a limit; continue with the remaining-work estimate when asked when results
   will be ready. Confirm process exit separately. Pass whichever pid you have: a wrapped job is
   two processes, and `--pid` walks up to find the wrapper, so the worker's pid answers
   the same as the wrapper's.

   Point `--tasks` at the checklist this work is tracked in: a task-list file with one
   checkbox per task (create one if absent).

   **Exit 2 never means zero, and it usually does not mean "go to step 3".** Read which
   refusal it is. A bad search pattern, a whitespace pattern, a wrong pid, or a checklist
   with rows the counter could not count all mean *this measurement was not taken* — fix the
   input and measure again. Only a refusal saying the thing genuinely cannot be measured
   sends you onward.

2. **Price the remainder — never subtract.** With progress facts in hand, run the
   estimator below over what is genuinely LEFT: unchecked tasks, tests still red, gates not
   yet run. `remaining = original estimate − elapsed` is FORBIDDEN — if the original
   estimate was wrong, the subtraction is wronger, and elapsed time is evidence about the
   past, not the future. Elapsed only moves confidence: already past the original
   estimate → confidence low, and say so.

   Two counting traps:

   - **`0 open` is not `0 time left`.** A task list reading `21/21 done (100%), 0 open` can
     still have close-out ahead of it: final review, release, hand-over. Those steps are
     never checkboxes. When the checklist is exhausted, price the close, not zero.
   - **Checklist rows are not `slices`.** A checklist can split one deliverable into
     many sub-steps. Group open rows into independently committable units before
     pricing them; compare the result with the repo's own observed maximum.

3. **Fallback — bare judgment, labeled.** When nothing is measurable (no pid, no
   checklist, no countable remainder — e.g. "waiting for an external service", a debug
   session with no bottom in sight), give the owner your own judgment in one sentence,
   marked as judgment: a range, what it hangs on, and what would firm it up. This is the
   LAST step, never the first — reaching for it while a pid or a checklist sits unmeasured
   is the failure mode this section exists to prevent.

**Chat answers are chat-sized.** A conversational ask gets one or two plain sentences —
the figure and what it hangs on. No JSON line, no eight-line block. **And a chat answer is
never recorded**: it must not become a recorded estimate, a run's time budget, a ledger row, or
an est-vs-actual comparison. Anywhere the figure gets written down, the full Step 6 output
is mandatory.

## The estimator

Every number comes from a table lookup or arithmetic below — no invented rates, no
deep reasoning. **Human-coding time
anchoring is FORBIDDEN** (no "story points", no "a developer would take 2 days").
Agent code-writing is nearly free; wall-clock is dominated by test runs, review
rounds, real-dependency verification, deploy/observe cycles, and rework loops —
count THOSE.

Tables: `references/unit-rates.md` (rates, gate pricing, `speed_factor`),
`references/train-set.tsv` (a 51-case reference library of `workload_class`, `novelty` and
`actual_h`; it has no slice or run counts, so it feeds only the class-level reality band of
Step 5a, never anchor matching) and `references/case-table.md` (the numeric-feature rows
used as anchors, eligibility rules inside). **Calibration: v1.3**.
Validity comes from prospective live journeys only
(`references/VALIDATION-REPORT.md`); no other score may be cited as current. Known weak spots — disclose
when hit: single-host GPU serving (environment-vs-lighter sub-shape ambiguity),
vague-open epics (information-limited → low confidence), ui-web (thin data), and
infrastructure multipliers that overprice small operational tasks.

The training table's other columns (`repo`, `source`, `pool`, `group`, `date`, `bucket`,
`task_summary`) are neutral provenance tokens; none selects anchors or contributes to rates
or the train-class reality band.

Deliver user-facing phrases in the user's chosen language, as stated in their instructions.

## Step 1 — Extract countables (deterministic schema)

From the input (dictation, requirements document, prompt file, route card — read files given as
paths), extract. Count what the text NAMES; do not imagine work it doesn't imply.

| Field | How to count |
|---|---|
| `slices` | independently committable units: items of the task-list file (one checkbox per task; create one if absent) if present; else distinct deliverables/files-to-mutate groups named in the text |
| `test_files` | test files to author or extend (bugfix ⇒ ≥1) |
| `armed_gates` | the review and verification gates the work requires, from the route card or plan if one exists; else arm by rubric: durable-data/contract → plan review + code review; real-model behavior → smoke run; files an agent loads as standing instructions or memory → check that the loaded copy is the new one |
| `suite_runs` | by default, change-scoped suite runs for modified behavior and directly affected consumers only; count full-suite runs when the task explicitly asks for them; pure docs/config with a named deterministic check → 0 suites, count that check instead |
| `smoke_runs` / `e2e_runs` | counted separately, from what is named or armed |
| `deploy_cycles` | deploy+verify cycles named (0 if none) |
| `workload_class` | judge by the work's PHYSICAL SHAPE, never by repo or given labels: `ml-training` (eval/tuning LOOPS — eval toward a target, several variants compared, re-running acceptance evals, retrain, evals against a reference answer set, benchmark sweep — wall-clock lives in runs) \| `source-code` (incl. generating full spec/plan ARTIFACT SETS — that is authoring) \| `infra-agent-config` \| `ui-web` \| `review-fix` (review NAMED artifacts + fix only what the review finds, scope explicitly capped) |
| infra sub-shape | exactly one of: `environment` (BUILDING/migrating env: install, passthrough, new service) \| `repo-tooling` (scripts/skills/process, no env) \| `operational` (RUNNING something existing: release script, regenerate, restart) \| `planning` (SHORT decision docs from KNOWN/GIVEN info: pricing, naming, memos). **`planning` requires low `investigation_surface` — a short output SYNTHESIZED from a wide read is NOT planning (see next row).** Precedence when several verbs appear: classify by the PRIMARY deliverable; ties break toward the heavier sub-shape (environment > repo-tooling > operational > planning) |
| `investigation_surface` | the INPUT-side cost the output size hides: count distinct sources the task must READ + SYNTHESIZE before it can produce its deliverable — named files/modules/specs/subsystems, or an OPEN surface ("assess/audit/synthesize across the whole history / repo / all X" = high by default). **When a small output (a doc, an assessment, a "10-line summary") has surface ≥3 or open AND the read genuinely dominates the writing, it is INVESTIGATION-dominated — set `workload_class=source-code`, `novelty=exploratory` (ONE deterministic mapping, not a slash), and price the reading via `investigation_surface` rounds** (unit-rates §Investigation). The ≥3 is an ADVISORY trigger to CONSIDER this, not a hard branch — judge whether the read actually dominates; a 1–2-source memo stays `planning`. Confidence caps at `med` while this rate is provisional. |
| `novelty` | `mechanical` (same edit × N sites, deletion, rename) \| `familiar` (existing repo pattern) \| `exploratory` (new design, unknown API, research, or high `investigation_surface`) — judge by the WORK's nature |
| `provenness` | how much of the hard design is ALREADY RESOLVED in the inputs, independent of the work's apparent complexity. **`frozen-proven` requires ALL THREE, each citing a NAMED on-disk artifact (no citation = condition unmet):** ① exact interfaces/signatures/SQL frozen in the plan (cite file+section); ② the hardest mechanism de-risked upstream — a passing spike (cite the spike test/evidence) OR ≥2 recorded review passes on the design (cite them); ③ acceptance tests specified — RED tests committed (cite paths) or exact executable scenarios named in the plan. **Missing any one, or unable to cite its artifact → do NOT use frozen-proven**: fall to `approved` (a plan/tasks artifact exists but implementation may still discover) or `open` (design happens in THIS session). The three are a strict AND, never an OR — a spike without frozen interfaces, or review passes without committed tests, is `approved`, not `frozen-proven`. **Never for `workload_class=ml-training` (hard exclusion — run wall-clock survives any design freeze; see Step 4b).** Under-triggering here is cheap (you over-budget, agent finishes early); OVER-triggering underprices → the launcher's hard time limit (the launcher is the process that starts the run and enforces its time limit; in the `pl` skill, `spawn-exec.sh`) kills the run mid-flight and work is lost. When in doubt, drop to `approved`. **`frozen-proven` OVERRIDES novelty → `transcription` rate** (the session types known code; the design discovery already happened in the planning layer — see unit-rates §Scope-Expansion). |
| `incident` | true if an ACTIVE production incident is involved |

**Countability states** (drive Step 4b and the exit):
- `countable` — slices counted from text → normal path.
- `partially_countable` — SOME deliverables countable, others vague → count what
  you can, use the vague-multiplier row, confidence ≤ med.
- `uncountable` — NOTHING nameable → output
  `{"outcome":"insufficient_information","questions":[…≤3 concrete questions…]}`.
  Do not guess.

## Step 2 — Rounds (agent-active work)

`rounds = slices × per-slice-rounds(novelty) + 2 × test_files`; ui-web doubles the
slice term. Rates from unit-rates.md. **`provenness=frozen-proven` uses the
`transcription` per-slice rate (1 round) AND drops the `2 × test_files` term** —
the reds are pre-specified, so authoring them is transcription, not design.

**review-fix shortcut (skip Steps 2–4b):** `E = named_files × review-fix per-file
rate + 2 suite runs` (rework and review are inside the per-file rate; NO expansion
multiplier — a scope-capped ask is a ceiling, not a floor). Continue at Step 5;
class is anchor-thin → confidence ≤ med.

## Step 3 — Four disjoint clocks (minutes; each event in exactly one clock)

- `agent_active = rounds × round_rate ÷ speed_factor` (only clock the factor touches)
- `env_execution = suite_runs×suite_rate + smoke_runs×smoke_rate + e2e_runs×e2e_rate + deploy_cycles×deploy_rate`
- `review` = per-gate pricing from unit-rates.md §Gate Pricing (plan review 1×15 min;
  code review ⌈slices/3⌉×10 min; smoke run and load check are env runs, not review time)
- `mandated_wait = fixed observation windows` (e.g. post-deploy watch) — never scaled
- Owner-wait is EXCLUDED from these four clocks — and from E, multipliers, and
  anchors (all agent-clock quantities). It gets its own line in Step 5b.

## Step 4 — PERT (closed form)

One rework cycle = `0.3 × agent_active + (1 suite run IF suite_runs > 0, else the
task's named check) + (1 reviewer rework round of 10 min IF code review armed)`.
`E = Step-3 sum + 1 × rework` (algebraic collapse of O/M/P with M=O+1, P=O+2).
`completion_risk`: low; med if exploratory / incident / anchor-thin class; high if
several decisions are left open to the owner (say to settle them first).

## Step 4b — Scope-expansion multiplier (mandatory)

`E_expanded = E × factor` from unit-rates.md §Scope-Expansion, keyed on
workload_class (+ infra sub-shape) × countability state. Precedence: **ml-training
×35 beats the mechanical cap** (a mechanical edit bundled with training loops is
still a training journey); the mechanical ×1.5 cap applies within all other
classes. **Scope-cap rules (the resolved-upstream family — when several apply, the
lowest wins):** `provenness=frozen-proven` → **×1** (design decided AND
spike-validated AND exact — the hidden work was already surfaced upstream); an estimate
sourced from an APPROVED-but-not-frozen plan/tasks artifact → **cap ×1.5** (planning
surfaced the hidden work but implementation may still discover more); an ask that explicitly
caps scope / review-fix class → **×1** (a ceiling, not a floor). Full multipliers
are calibrated on opening-ask text only. Never re-apply any factor to anchors
(they are real durations).

## Step 5 — Anchor shrinkage (never hard override)

Anchor rows must have fully numeric features + exact `actual_h` (rows with `?`,
`~`, `+`, or censored markers are INELIGIBLE). **Leave-one-out: a case never
anchors itself.** Feature vector: `workload_class` exact match required; distance
over `slices`, `suite_runs+smoke_runs+e2e_runs`, `deploy_cycles`, `novelty` —
normalized (no other feature). Eligible = distance ≤ 0.5 AND `anchor_actual` ∈
[E_expanded/4, E_expanded×4]. If eligible: `final = √(E_expanded × anchor_actual)`;
disagreement >2× → report both numbers + drop confidence one level. No eligible
anchor: `final = E_expanded`, JSON anchor fields = null.

### Step 5a — Repo reality band (MANDATORY, runs even when no anchor is eligible)

**The anchor path fails silently.** Anchoring needs a `workload_class` match; a `closed`
ledger event with no `anchor_key` can never join, so `anchor` silently resolves to null and
`final = E_expanded` ships uncalibrated. The core `agent_active` terms (round rate,
per-slice rounds) are themselves provisional defaults in unit-rates, so with the anchor
starved the estimate is a guess compounded by a multiplier. The band below exists so that
state never produces an unchecked number.

**The band is NEVER skipped and NEVER null.** An estimate emitted with no band is the
failure this step exists to end — "not enough rows" is the excuse that reproduces it. Walk
the ladder until something answers; something always does:

| # | Source | Minimum | Note |
|---|---|---|---|
| 1 | target repo's `closed` events, same `workload_class` | 5 rows | preferred — same repo, same class |
| 2 | target repo's `closed` events, all classes | 5 rows | what this repo actually does |
| 3 | `references/train-set.tsv`, same `workload_class` | any | **last resort — a DIFFERENT and much slower population; see the warning below** |

Compute `actual_body_h + actual_process_h` per row for repo sources (**body alone excludes
review and process time — a band built on body-only understates and violates the
like-with-like rule in Step 5b**); the train set's `actual_h` is already a total. Take p50,
p90 and the maximum, and record which rung answered.

**The train set may differ from the target repo.** When rung 3 is used, name its
source in the output and cap confidence at `med`. Compare its distribution with
the target repo's own closed work when that becomes available.

Without a routing ledger (rungs 1 and 2 empty), only rung 3 can answer, and the train set holds no
`review-fix` rows and a single `ui-web` row: an estimate for those classes without a ledger is expected to
exit as `insufficient_information`.

**If no rung yields rows, there is no band and no estimate**: emit
`{"outcome":"insufficient_information","questions":["no closed actuals in <repo> and no train-set rows for workload_class=<class> — which comparable journey should anchor this?"]}`
and nothing else. "Something always answers" is a premise, not a guarantee; this is its
exit. **A numeric estimate carrying `repo_band_h: null` is malformed — never emit one.**

Then, in order:

1. **Work beyond the fixed wait is capped at the band maximum.** Keep `mandated_wait`
   outside this cap. `est_total_h`, `bucket` and `schedule` include that full wait;
   `confidence` = `low` when work is capped; the chat
   block names the maximum, the row count and the rung. **Naming a "new property" of the
   task does not lift the cap** — an executor asserting novelty is an unfalsifiable claim,
   not evidence. The cap
   lifts only with an owner-approved replacement band, cited in
   `band_override` by a reference to that approval.
2. **The excess is never destroyed, it moves**: `wall_budget_h` keeps the **uncapped**
   figure, exactly as the frozen-proven split does in Step 6. So the schedule stops being
   absurd while the run's hard time limit still funds a run that genuinely needs the time. **Capping
   the schedule must never shorten the wall**, and the two numbers differing is the normal
   state here, not an inconsistency to reconcile.
3. `final` over p90 → state `final` beside p50 and p90; confidence caps at `med`.
4. Emit `repo_band_h`: `{"n":<rows>,"p50":<h>,"p90":<h>,"max":<h>,"source":"repo-class|repo-all|train-class"}`.

### Step 5a-2 — Era multiplier (owner-set constant, applied last)

Apply this once to the uncapped `final` from Step 5; `final` and `mandated_wait` are
minutes, while `band_max_h` is hours. Value of `era_multiplier`: unit-rates §Global config.

```python
final = mandated_wait + min(max(0, final - mandated_wait), 60 * band_max_h) * era_multiplier
```

**Recheck this constant when agent capability changes.** First-try correctness can
remove whole rework cycles without changing typing speed, so token speed alone
cannot calibrate total wall-clock.

**Deliberately a hard-coded constant, not a learned one**: the user adjusts
it when observed outcomes drift. Do not build an
auto-fit — a self-tuning multiplier on top of an anchor mechanism that is itself learning
from actuals would double-correct, and neither would be inspectable when it went wrong.

**Why this and not `speed_factor`: `speed_factor` mathematically cannot do this job.** It
divides `agent`-class rates only, leaving the other clocks untouched. Reaching them requires
touching the number after the four clocks, the rework cycle and the expansion multiplier
have all been applied. That is here. `speed_factor` remains what it is: the rate-level
knob for raw agent throughput.

**Never applied to `wall_budget_h`.** The asymmetry that governs every choice in this
skill applies with full force: under-correcting is cheap (over-budget, the agent finishes
early); over-correcting underprices, the hard time limit kills a healthy run mid-flight, and
the work is lost. When unsure, move the multiplier less than the data suggests.

**This is a coarse outlier check.** The band maximum bounds large schedule estimates,
but it cannot correct smaller biased estimates. Eligible anchors below can adjust
those estimates using the target repo's own closed work.

**Ledger anchors outrank the case table.** Before reaching for a case-table anchor,
scan the target repo's routing ledger (if it keeps one) for `closed` events of the same
workload class — most-recent first.

**The anchor duration is `actual_agent_h`, persisted at close as
`actual_body_h + actual_process_h`.** Never anchor on `actual_body_h` alone: body excludes
review and process time, so a body-only anchor is a different clock from the `final` it is
shrinking and violates the like-with-like rule in Step 5b. A `closed` event carrying
`actual_body_h` without `actual_process_h` cannot produce `actual_agent_h` and is
therefore ineligible — the same way a row with `?` or `~` is.

**A `closed` event that omits `anchor_key` is not an eligible anchor and never will be.**
If the scan returns nothing while the ledger clearly holds actuals, that is a recording
gap, not an absence of comparable work: **say so in the output** rather than silently
resolving to `anchor: null`, because the two look identical downstream and only one of
them is fixable. The `calibration_note` field of each scanned event (a free-text note on
what an earlier estimate got wrong) is BINDING context:
producing an estimate that repeats a mistake a prior note already names (e.g.
"estimate priced a full suite the change class caps at targeted verification",
"anchor matched workload class but not blast radius") is a violation, not a
judgment call. A class-matched anchor with a much larger blast radius (e.g. a
repo-wide change anchoring a small deletion) must be rejected on the blast-radius
axis even when `workload_class` matches.

## Step 5b — Owner-wait line (separate; never touches the agent clocks)

Human approval time IS time — it just lives on its own line so the two case shapes
(coding-heavy/few-waits vs coding-light/many-questions) stay distinguishable.

- `waits` (count, from the input): the points where the work must stop for a person —
  0 for a small self-contained task, 1 for one approval gate, 2 where plan approval and
  final acceptance are separate — **plus +1 per decision the input explicitly leaves to
  the owner**. Decisions stated as settled count 0.
- `waits_effective = waits × (1 − approval_absorption)` (knob in unit-rates §Owner-Wait: the share of approval waits an automated reviewer absorbs).
- `owner_wait_h = waits_effective × daytime response price` (unit-rates §Owner-Wait).
- **Overnight barrier**: a wait expected to cross the person's normal sleep gap in
  the user's zone is not priced in minutes — flag it ("overnight barrier: resumes next morning") and prefer daytime scheduling for any
  approval-bearing work.
- `elapsed_h = final(agent) + owner_wait_h` — the calendar end-to-end number.
  Est-vs-actual comparisons MUST pair like with like: agent line vs agent clock,
  wait line vs wait clock, never `final` vs elapsed.

- **By default (a project may choose otherwise), agents run continuously; there is no working week.** When hours become a date, the
  only divisor is real elapsed time: 24 hours to the day, seven days to the week. Never
  insert a weekend, holiday, or business-day count — those are properties of human
  employment and agents do not have a working week. An executor started on a Friday evening
  runs through weekends exactly as it runs through weekdays.
  - Concretely: hours ÷ 24 gives days, adjusted only for real serialisation you
    can name — a dispatch cap, an owner decision that has to land first, a
    wall-clock run that cannot be compressed. If you cannot name the mechanism
    that idles the hours, the hours do not idle.
  - Whenever a date is stated, state the conversion beside it — "N hours running
    continuously from <timestamp>" — so a reader can check the arithmetic instead
    of trusting it.

## Step 6 — Output (chat block + one JSON line)

Buckets (half-open, minutes, **agent clock `final` only** — owner-wait never moves
the bucket): `<60 → "<1h" do-now` · `60 ≤ x < 240 → "1-4h" short-day` · `240 ≤ x < 480 →
"4-8h" long-day` · `x ≥ 480 → ">8h" overnight`. (The four labels are fixed English
words, emitted exactly as written: do-now = do it now, short-day = short daytime job,
long-day = long daytime job, overnight = overnight job.) `exceeds_6h = final > 360` (agent
clock; used by the launcher's time-limit check). **Borderline disclosure (enforceable): if `final`
is within ±10% of 360 or 480 (i.e. 324–396 or 432–528 min), the chat block MUST
state both sides ("5.8h, borderline against the 6h line") and confidence
caps at med.** The word `borderline` is emitted verbatim.
`formula_h` in JSON = E_expanded (post-expansion, pre-anchor).

`schedule` (agent clock × waits) — the emitted values are `daytime` and
`overnight`, and the literal `owner-online` is emitted verbatim: `waits ≥ 2` →
`daytime, owner-online N times` · `waits ≤ 1` AND `final ≥ 8h` → `overnight` candidate (any
leftover wait falls to the next morning, marked as an overnight barrier) · else `daytime`
(`do-now` when the bucket is <1h).
`journey_id` comes from the route card / ledger
(null when there is none).

**`anchor_key` is REQUIRED on every numeric estimate** — the seven fields Step 5's
eligibility test matches on, emitted so the journey's `closed` event can copy them
verbatim. Without it the closer has nothing to transcribe and every future estimate in
that repo ships `anchor: null`. **An estimate JSON missing `anchor_key` is malformed.**

**Frozen-proven output rules (auditable + kill-safe):**
- **`provenness_evidence` is REQUIRED when `provenness":"frozen-proven"`** — a JSON
  object `{"interfaces":"<file+section>","spike_or_review":"<spike test / ≥2 review
  cites>","tests":"<committed RED paths / exact scenarios>"}`. Any field empty or
  uncitable ⇒ you are NOT frozen-proven: recompute as `approved` (or `open`). This
  makes the strict AND self-enforcing and lets a later reviewer distinguish a valid
  low estimate from an underpriced one. Non-frozen-proven estimates emit
  `"provenness_evidence":null`.
- **`wall_budget_h` — the two consumers split while the rate is provisional.** The
  estimate feeds two decisions with OPPOSITE risk preferences: *scheduling/bucket*
  wants the accurate low number; the *hard time limit* on the run wants safety against a
  premature kill of good work. While frozen-proven is provisional (confidence <
  high, n<5): `est_total_h`/`bucket`/`schedule` use the transcription `final`
  (accurate), but `wall_budget_h` = the **approved-plan fallback E** (recompute
  without the transcription discount — novelty as judged, ×1.5 cap). **Whoever launches the run
  passes `wall_budget_h` as its time limit (for the `pl` skill, `spawn-exec.sh --budget-h`),
  never `est_total_h`; the launcher kills the run at 1.5× whatever budget it receives and
  cannot tell a safe budget from an optimistic schedule.** The binding is by discipline
  (unit-rates §Known Gaps: no end-to-end fixture), so it is closed after the fact, not
  prevented: the close audit compares the launched budget against this estimate's
  `wall_budget_h` and a mismatch is a finding. A too-low transcription rate therefore cannot
  silently kill a run mid-flight without leaving an auditable trace. Once validated (n≥5)
  the two converge and `wall_budget_h` = `est_total_h`. Non-frozen-proven:
  `wall_budget_h` = `est_total_h` **unless Step 5a capped the schedule at the band
  maximum, in which case `wall_budget_h` keeps the uncapped figure.**
  **In both cases `wall_budget_h` is computed WITHOUT `era_multiplier`** (`unit-rates.md`
  era row; Step 5a-2 "Never applied to `wall_budget_h`"); this line is downstream of that
  rule, never an exception to it. Read the other way, a 0.4 multiplier reaching the
  time limit would kill the run at 2.5× less wall-clock than it needs, and with no one
  able to extend the limit in an autonomous run that is work destroyed with no recovery
  path.

The structure below is normative (`<slug>` stands for a short name of the work being estimated). Line labels may be translated into the user's
language, but the token values are fixed English words and are emitted exactly as written:
the `bucket` and `schedule` values (`do-now` / `short-day` / `long-day` / `overnight` /
`daytime`) and the literals `owner-online` and `borderline`. Line labels, in
order: agent hours · dominant cost · owner involvement (N waits expected, daytime price per
wait) · end-to-end and schedule (owner online N times) · nearest anchor (actual, distance —
same direction / divergent) · this repo's measured band (median, p90, all-time max — inside
band / above p90 / above all-time max) · confidence.

```
[agentic-time-estimate · <slug> · example-journey]
Agent hours: 4.9h (4-8h long-day) · exceeds_6h: no
Dominant cost: <the single biggest clock, one plain line>
Owner involvement: 2 waits expected ≈ 1.7h (daytime price 0.83h per wait)
End-to-end: ≈ 6.6h · Schedule: daytime (owner-online 2 times)
Nearest anchor: <case> (<actual>, distance <d>) — same direction / divergent
This repo's measured band: n=<rows> · median <p50>h · p90 <p90>h · all-time max <max>h — inside band | above p90 | above all-time max
Confidence: high|med|low (<reason, one phrase>)
{"skill":"agentic-time-estimate","journey_id":"example-journey","est_total_h":4.9,"bucket":"4-8h","schedule":"daytime","exceeds_6h":false,"waits":2,"owner_wait_h":1.7,"elapsed_h":6.6,"completion_risk":"low","confidence":"med","formula_h":14.0,"anchor":"<case-id>","anchor_h":10.7,"repo_band_h":{"n":8,"p50":4.0,"p90":9.0,"max":14.0,"source":"repo-class"},"band_override":null,"era_multiplier":0.4,"anchor_key":{"workload_class":"source-code","slices":6,"suite_runs":8,"smoke_runs":0,"e2e_runs":0,"deploy_cycles":0,"novelty":"familiar"},"workload_class":"source-code","provenness":"open","provenness_evidence":null,"wall_budget_h":12.2,"calibration":"v1.3"}
```
(Example arithmetic is real: √(14.0×10.7)=12.2 before the era multiplier, ×0.4 = 4.9;
2×0.83=1.7; 4.9+1.7=6.6; `wall_budget_h` stays 12.2 because the era multiplier is never
applied to it. No anchor → `"anchor":null,"anchor_h":null`. No route card →
`"journey_id":null`. Insufficient → `{"outcome":"insufficient_information","questions":[…]}`
and nothing else.)

Confidence: `high` = eligible anchor within 1.5×; `med` = no anchor, 1.5–2×
disagreement, partially_countable, borderline, or `final` over the repo band's p90;
`low` = >2× disagreement, ui-web, or **`final` over the repo band's observed maximum**
(Step 5a).
**`provenness=frozen-proven` caps confidence at `med`** until the rate is validated
(≥5 frozen-proven anchors accrued; PROVISIONAL while fewer) — the transcription path
underprices, so it must never report `high` while provisional, and the chat block
must name it ("frozen-proven transcription case, provisional, confidence capped at med").

## Boundaries

- This skill estimates; it never routes, implements, or edits the tables. By default a retrospective plus
  owner approval updates rates (`speed_factor` from est-vs-actual drift, about quarterly; a project may choose otherwise).
- Active incident: `stabilize-first` ordering (stop the damage before the full fix) makes
  the FIRST deliverable much smaller than the whole journey — estimate both when asked.
  The word `stabilize-first` is emitted verbatim.

## Rationalizations — pre-refuted

| Excuse | Refutation |
|---|---|
| "A human engineer would take about two days" | Forbidden. Human time has no exchange rate to agent time; count rounds, tests, and gates. |
| "The table has no rate for this activity, I'll estimate one" | Never invent numbers. Use the nearest class and say so, or exit via insufficient_information. |
| "Anchor says 4h, formula says 9h — take the anchor" | Anchors only do geometric shrinkage + a confidence drop, never a hard override. Report both numbers. |
| "Input is too vague, I'll give a rough figure" | Uncountable = insufficient_information + a question list. False precision is more toxic than none. |
| "The task lives in a product repo, so it's source-code class" | Class follows the work's physical shape: tuning loops = ml-training, running a script = operational — the repo is irrelevant. |
| "It waits on the owner anyway, fold the wait into the bucket" | Buckets hang on the agent clock only. Waits are their own line; blend them and the two case shapes (code-heavy/few-questions vs code-light/many-questions) become inseparable forever, and est-vs-actual comparisons run on mismatched clocks. |
| "Remaining = original estimate minus elapsed" | Forbidden. A wrong original makes the subtraction wronger. Price the open items through the tables; elapsed only moves confidence. |
| "No pid handy, I'll just say a couple more hours" | Judgment is the LAST step. A pid, a checklist, or a timeout wrapper unmeasured is a fact you skipped, not a fact that is missing. |
