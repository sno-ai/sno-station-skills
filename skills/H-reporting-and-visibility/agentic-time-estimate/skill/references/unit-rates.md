# Unit Rates — default costs of atomic activities

These are calibration v1.3 defaults, not measurements of the user's work.
Replace a default with comparable local measurements when available. Estimates
carry `"calibration":"v1.3"`.

Every rate has a scaling class: `agent` rates divide by `speed_factor`; `infra`,
`reviewer`, and `wait` rates do not. A faster model does not shorten a test run
or a person's response gap.

## Global config

| Key | Value | Reason |
|---|---|---|
| `speed_factor` | 1.0 | Default agent-throughput adjustment; divide `agent` rates only. |
| `era_multiplier` | **0.4** | Default whole-estimate adjustment, applied to `final` LAST (SKILL Step 5a-2); never apply it to `wall_budget_h`. Replace with local measurements. |

## Rates

| Activity | Class | Rate | Reason |
|---|---|---|---|
| round (agent-active think→write→inline-check cycle) | agent | 3 min | Default assumption; replace with local measurements. |
| per-slice rounds · transcription | agent | 1 round | Pre-specified interfaces and tests reduce design work; provisional default. Do not add the `2×test_files` term. |
| per-slice rounds · mechanical | agent | 2 rounds | Default assumption; replace with local measurements. |
| per-slice rounds · familiar | agent | 4 rounds | Default assumption; replace with local measurements. |
| per-slice rounds · exploratory | agent | 8 rounds | Default assumption; replace with local measurements. |
| ui-web slice multiplier | agent | ×2 | UI work may require repeated visual checks; provisional default. |
| reviewer wave (one fresh headless review pass) | reviewer | 4 min median · 5.5 p75 · 8.8 p90 | Default distribution; replace with local review timings. |
| reviewer round for PLANNING (1–2 waves + retries; use p75-based) | reviewer | 10 min | Default planning review; use 15 min when payload >100KB. |
| full test suite run | infra | 4 min | Default assumption; measure the target suite before pricing it. |
| 1-entry real-dependency smoke | infra | 10 min | Default assumption; replace with local measurements. |
| full-chain E2E | infra | 15 min | Default assumption; replace with local measurements. |
| deploy cycle (build+install) | infra | 10 min | Default assumption; replace with local measurements. |
| post-deploy observation window | wait | 10 min | Fixed observation time; never scale with agent speed. |
| rework-cycle overhead factor | agent | 0.3 × agent_active | Default allowance for another correction pass. |
| review-fix per named file (SKILL Step-2 shortcut; review waves + Critical/High fixes + rework all included) | agent | 8 min | Scope-capped review default; replace with local measurements. |

## Investigation surface (SKILL Step 1 `investigation_surface`)

Reading and synthesizing inputs can dominate a small output. When
`investigation_surface ≥ 3 named sources` or the surface is open, and reading
genuinely dominates writing:

- Set `workload_class=source-code` and `novelty=exploratory`.
- Add approximately `investigation_surface × 4` rounds to Step 2; price an
  open surface as at least 5 sources. These are provisional defaults.
- Counting the reading makes the work countable: use source-code countable ×2.5,
  not vague ×5 on top of the added rounds.
- Cap confidence at `med` until prospective local cases support the rate.
  The ≥3 threshold is advisory; a short memo over one or two sources can remain
  `planning`.

## Owner-Wait Rates (SKILL Step 5b — human time; never enters agent clocks or anchors)

These are defaults for a person reading during a normal working day and crossing
a sleep gap. Interpret all hours in the user's zone and replace them with the
person's own availability when known.

| Key | Value | Reason |
|---|---|---|
| daytime response price (per wait, start 08:00–22:00 in the user's zone) | 50 min (0.83 h) | Default working-day response allowance. |
| night-awake response (start after 22:00 in the user's zone, person still active) | 15 min | Optional awake response; do not budget on it without evidence. |
| overnight barrier (wait crosses sleep) | ≈11 h; resume ≈ next 12:00 in the user's zone | Default sleep-gap allowance; flag it, never fold it into `owner_wait_h` minutes. |
| `approval_absorption` | 0 | Share of approval waits an automated reviewer absorbs. Default: no approval step is automated; adjust only when one is. |

## Gate Pricing (SKILL Step 3 `review` clock)

| Gate | Review minutes | Basis |
|---|---|---|
| Plan review | 1 round × 15 min | Default planning review for a large payload. |
| Code review | ⌈slices/3⌉ rounds × 10 min | Default review round covers about three slices. |
| Code-review rework round (Step 4, only if code review armed) | 1 × 10 min | Same review rate. |
| Smoke run / load check | 0 review minutes | Price these as environment runs, not review time. |

## Scope-Expansion Multipliers (applied AFTER PERT, before anchors — Step 4b)

Opening requests may omit rework, discovered bugs, or environment work. Use
the class and countability defaults below; replace them with local measurements.

| workload_class | condition | multiply PERT `E` by | Reason |
|---|---|---|---|
| source-code | slices countable | ×2.5 | Default allowance for discovery beyond named slices. |
| source-code | slices `?` | ×5 | Vague work has a wider discovery range. |
| infra-agent-config | environment-fighting = BUILDING/migrating env (install, passthrough, migrate host, new service) | ×13 | Environment setup can dominate agent work. |
| infra-agent-config | operational = RUNNING something existing (release script, regenerate, restart, unblock) | ×2 | Running existing tools needs less discovery than building an environment. |
| infra-agent-config | planning = SHORT decision docs (pricing, naming, memos). Full spec/plan artifact sets count as source-code authoring | ×1.5 | Short planning over given facts has limited implementation work. |
| infra-agent-config | repo-tooling (scripts/skills/process, no env) | ×4 | Tooling changes can expose repository-specific behavior. |
| ml-training | any (GPU train/eval loops: retrain, evals against a reference answer set, sweeps over N settings, re-running acceptance evals) | ×35 (PROVISIONAL) | Training and evaluation runs dominate elapsed time. |
| ui-web | any | ×4 (PROVISIONAL; confidence stays low) | Thin reference data; replace with local measurements. |

Mechanical novelty caps the multiplier at ×1.5, except `ml-training`.
`ml-training` always uses ×35, even with a frozen plan, because the train/eval
loops must still run. It never uses transcription or an approved-plan cap.
Partially countable source-code work uses the vague row; fully uncountable work
exits as insufficient information.

## Known Gaps

- `provenness_evidence` paths rely on review rather than an automated citation
  resolver; provisional `wall_budget_h` uses the approved-plan fallback.
- Mixed ML authoring and training have no component split; the entire
  `ml-training` journey keeps ×35.
- The `wall_budget_h` to launched timeout binding has no end-to-end fixture;
  verify the launch argument when a run is closed.

## Scope-cap rules

Full multipliers apply to an opening request. Resolved design or an explicit
scope ceiling uses the lower multiplier below. When several apply, use the
more-resolved (lower) one; `ml-training` still uses ×35.

| Input shape | Multiplier | Reason |
|---|---|---|
| **FROZEN-PROVEN** plan (exact interfaces/SQL frozen; hardest mechanism spike-validated or ≥2 recorded design reviews; acceptance tests specified; cite each artifact) | ×1 and novelty→transcription; confidence capped at `med` while provisional | Design and test scenarios are already specified; keep a larger approved-plan wall budget while the rate is provisional. |
| estimate from an APPROVED plan/tasks artifact, without frozen proof | cap ×1.5 | Planning has surfaced some work, but implementation can still discover more. |
| explicit scope-cap ask / review-fix class | ×1 | The named review scope is a ceiling. |
