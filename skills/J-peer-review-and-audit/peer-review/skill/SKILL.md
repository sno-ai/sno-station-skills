---
name: peer-review
description: "Adversarial review and fix loop for code, specs, plans, and migration manifests."
requires:
  programs: []
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
    - {slot: 4.background-processes, need: required}
---

# Peer Review

Classify → gather context → **run bundled adversarial-review script** → root cause → fix/report → repeat until clean.

"Owner" below means whoever owns the work, usually the user.

Prerequisites: Linux, bash, python3, GNU `date`, `sha1sum`, `pgrep` and GNU `xargs`, plus at least one of the `codex` or `claude` CLIs (installed and logged in). Without python3 the findings ledger and receipts do not work.

The bundled script's adversarial-review pass is the authoritative reviewer. It runs in a fresh, separate headless session that has none of the caller's conversation, which is what makes it independent. It prefers the other vendor's CLI (Claude callers use Codex; Codex callers use Claude) when that CLI is installed and logged in. Otherwise it runs the review with the caller's own CLI in a fresh session and states on the first line of the report that it was a same-vendor review; a missing CLI never blocks the review. The active agent gathers context, investigates root causes, and applies fixes — it never overrides, filters, softens, or rewords the nested reviewer's findings. Every authoritative finding reaches the user; tag suspected false positives `[Possible FP]` with your reasoning instead of dropping them. Findings the active agent adds on its own are labeled "Active-agent supplementary" and kept clearly separate.

Works for both code and documents: classify first, then load the right verification layers. Code gets a root-cause-driven fix loop; documents get a structured report with optional edits.

## Review Calibration

The review exists to catch expensive failures — data loss, security holes, silently wrong results, primary flows breaking under real production conditions — not to audit style or completeness. Review primary flows first: establish what the artifact is for and where failure costs most, then trace those paths end to end; do not sweep line-by-line collecting local blemishes.

**First, simulate the ordinary use and prove it cannot go wrong there.** Before anything else, write down how this artifact is *normally* used — by a person, by an LLM, by an agent — and walk each of those paths end to end with the values they will really carry: the actual input formats produced by the surrounding system, the actual calls those callers make, and the actual ways their inputs fail (empty, blank, truncated, missing, stale). **A defect on the ordinary path outranks any number of exotic ones.** Edge cases deserve a few probes and never the bulk of the review; if the findings list is mostly exotic inputs, the review has not been done yet.

Exotic-input hunting feels like rigour and reliably misses the main path — a review whose findings are mostly extreme inputs has not walked the common call yet. The common failure it misses is the plausible, silent one: a caller whose variable broke passes an empty value and the tool answers with a default that looks right.

**Process-machinery doctrine:** when the
target is agent-process machinery — orchestration/supervision scripts, task
templates, skill process text, messaging contracts — the severity order is fixed:
**silent death, stalls/deadlocks, wrong-flow execution, and agents
stepping on each other outrank everything else.** A judgment error is
recoverable; a process that dies quietly, waits forever, or tramples a
parallel agent's work is not. Hunt specifically: paths where a failure
produces NO signal; waits without timeouts; state that can go stale without an
alarm; two writers on one resource; steps that can be skipped with the gate
still passing. Wrong-but-loud is acceptable; wrong-and-silent is the bug.

**What is extra comes before what is missing.** The reviewer fills a **"Cut"** tier first: what the
change added that no observed failure or stated requirement needs (a lock, cap, retry, hash, alias
map, flag, gate, state table, queue, one-caller abstraction, un-retired old path, test that restates
the code). A Cut item is always a deletion or a swap for something that already exists, never an
addition, and it counts against the verdict: unrequested behaviour is a defect.

**By default (a project may choose otherwise), a finding is not an instruction to add code.** The defect report comes back
in two tiers and the active agent keeps them apart: **"Must fix"** holds only findings on the
ordinary call path, caused by the change, whose smallest remedy adds no new behaviour — no new
mechanism, constant, threshold, state table, lock, queue, alias map, retry policy or reply shape.
**"Also found"** holds everything else the reviewer dug up (edge paths such as concurrent
same-session calls, mid-flight cancellation, cleanup with a partial identity; findings whose only
remedy is a new mechanism; pre-existing debt; context-invalid triggers). "Also found" is recorded
and reported under its own heading; it is never turned into code in the same task, and a remedy
that would add behaviour goes to the owner as a decision, not to a worker as a task.

Every finding must pass three gates: **Trigger** (a realistic one-to-two-sentence sequence by which a real user, operator, integration, deploy, or retry reaches the failure), **Consequence** (operational impact: what breaks, for whom, how visible, how reversible), **Refutation** (an honest attempt to kill the finding against guards, caller contracts, and framework guarantees). These gates bind the nested reviewer at generation time and any supplementary finding the active agent adds. For a nested-reviewer finding the active agent believes fails a gate, authority still holds: do not drop it — tag it `[Possible FP]` with the refuting evidence so the user decides. Boundary, null, empty, concurrency, retry, and partial-failure issues count only when a supported path actually reaches them. Low-severity findings are omitted unless the user asks for an exhaustive pass. Recommend the smallest concrete change that removes the risk — never speculative redesigns, abstractions, or "make this more robust" feedback. For documents and plans, prioritize what would make an implementer ship the wrong thing, force rework, or block execution. Plan severity order is fixed: contradicted or unverified load-bearing premises > instructions an executor would implement wrong > steps that cannot succeed as specified > guarantees with no enforcing check > everything else — and internal precision is never evidence of correctness.

## Routing rules — read first

Recurring failure modes, all from picking the wrong tool:

1. **Do not hand review work to a write-capable delegate agent; call the script.** Such an agent runs a task, not a review (no structured findings, no severity tags, unsolicited edits). "Review", "audit", "validate", "check", "look at" ⇒ this skill and its bundled script.
2. **Do not invoke any other tool's adversarial-review command from inside this skill.** The bundled script starts the reviewer CLI directly with the same adversarial prompt.
3. **Never inline the prompt + heredoc in your own Bash call.** Reconstructing it trips quoting and shell-sandbox edge cases. Always call `scripts/run-adversarial-review.sh`.

## Phase 0: Classify

| Signal | Type | Reference |
|--------|------|-----------|
| `.py`, `.ts`, `.tsx`, `.js` extension | `code` | `references/code-layers.md` |
| `.md`, `.txt` with code blocks as primary content | `code` | `references/code-layers.md` |
| Any design or spec document set | `spec` | `references/doc-layers.md` |
| Architecture docs, PRDs, migration plans | `plan` | `references/doc-layers.md` |
| Test/eval **plans** | `plan` with test-scope admission | `references/doc-layers.md` |
| Test **source** — a path under `tests/`, `test/`, `spec/`, `__tests__/`, or a file named `*.t`, `*.test.*`, `*.spec.*`, `test_*.py`, `*_test.py`, `*-e2e.sh` | `test` — **auto-selected, cap 1** | this table's note below |
| Mixed (code + significant prose) | `code` | Both, code-primary |

**Test source is a different review, not a smaller one.** A test
exists to prove one thing about something else; it has no users and nobody depends on its
internals. Pointed at one, the code prompt produces findings about the *test's* robustness
and edge cases — work nobody asked for, on the wrong artifact. `REVIEW_KIND=test` asks one
question instead: **does this test prove what it claims to prove?** Can it go red for the
right reason, can it go red for a wrong one, is the proof boundary the lowest sufficient
one, is it already proven elsewhere, does its setup guard fail loudly. Style, robustness,
refactoring and speculative extra cases are explicitly out of scope.

Three things follow, and the wrapper enforces all three so a caller cannot forget:

- **The cap is 1.** No rounds on test material. Say everything in one pass.
- **The cap binds the FILE, not the target set.** The same-scope cap keys on the whole file
  list, so re-batching would mint a fresh scope and restart the counter; a test file that has
  had its pass is refused by path.
- **A mixed batch is split.** Test files are moved out of a code review and named. They are
  not run automatically — the exact command for their own pass is printed.

Production source keeps its own review: same prompt, same cap of 3, same loop. Re-reviewing a
source file after a fix is the intended behaviour and nothing here touches it.

For `spec` / `plan` artifacts, run the bundled script with `REVIEW_KIND=plan` — it swaps in the plan-specific adversarial prompt (`assets/adversarial-plan-review.prompt.md`: load-bearing-claim classification, probe-evidence ground truth, mandatory coverage statement) instead of the code prompt.

For a test/eval plan, the review is an admission gate before test files are written. Review the final plan, not a sample or early draft, together with the behavior contract or bug report, a plan-hash receipt (a file holding the output of `sha256sum <plan>`, passed as an extra target), and relevant probe evidence. Apply the same rule to every row: admit it only when the current change can turn the test from green to red, a realistic supported path reaches it, the selected layer is the lowest sufficient proof boundary, existing proof does not duplicate or subsume it, and the command/environment is feasible. Reject unchanged unrelated behavior, unreachable states, framework or upstream behavior, fixed-ratio or quota filler, layered duplicates, and speculative cases. Return an explicit admitted/rejected disposition for every row and copy the exact plan SHA-256 from the receipt; a changed plan has no inherited approval.

If ambiguous, ask: "This looks like it could be reviewed as code or as a plan — which angle do you want?"

Review mode from user intent:

| User says | Mode |
|-----------|------|
| "review", "audit", "check" (default) | `review-and-fix` (code) or `report-only` (docs) |
| "just report", "don't fix" | `report-only` |
| "fix this", "clean this up" | `review-and-fix` |
| "review and suggest edits" | `report-and-edit` (docs only) |

## Phase 1: Context & Review

Read every target file first. Then gather related context until you can answer: "If I were implementing this, what would confuse or trip me up?" The active agent uses this context to enrich authoritative findings, not to relitigate them.

- **Code:** files importing/imported by the target; the interfaces/types it implements or consumes; related tests; config it reads (env vars, YAML, references to the project's secrets store); AGENTS.md/CLAUDE.md/README conventions in the same app directory.
- **Plans/specs:** sibling documents of the same change (a design, its spec and its task list are one unit), and the base spec when the document only describes a change to it; the actual source the plan references (verify paths, function names, line numbers are current); prior related plans and decisions; the current state of code the plan proposes to modify.

**Probe ground truth (plans/specs) — required, not optional.** Before running the script, verify the plan's load-bearing empirical claims against reality — run the counts, check the files exist, dump the schemas, excerpt the referenced docs — and write the raw command output to a `PROBE-RESULTS-<topic>.md` file. Pass it as an additional target: the plan prompt treats probe files as authoritative reality and the plan's text as claims, which is what lets it mark premises CONTRADICTED instead of merely unverified.

Without one, the reviewer is sitting a closed-book exam: it is told not to use tools (Codex runs in a read-only sandbox, Claude with tools disabled), so it can catch internal contradictions and unenforced guarantees but *cannot* see that the document claims A while the code does B — and every empirical claim comes back UNVERIFIED rather than refuted. The wrapper warns on stderr and records `probe:false` when a plan review has no `PROBE-RESULTS` target; a review carrying that flag has established less than its verdict suggests, and the receipt says so. Skip the probe only when the artifact makes no empirical claims at all, and say that you did.

For code reviews, also read the bundled standards reference (`references/python-standards.md` for `.py`, `references/ts-standards.md` for `.ts`/`.tsx`). They are defaults: where the project's own conventions or configuration say otherwise, the project wins.

### Run the review script

Read the relevant layers file (`references/code-layers.md` or `references/doc-layers.md`) first. The wrapper at `scripts/run-adversarial-review.sh` (next to this SKILL.md):

- pipes the prompt + each target file's full contents through stdin — the reviewer never needs filesystem access, so no sandbox permission can block the read;
- when the reviewer is Codex, runs `codex exec --skip-git-repo-check --sandbox read-only` at `low` effort (the reviewed text arrives on stdin and the prompt forbids tools, so nothing needs write or full access); `scripts/lib/sno-model.sh` reads role `reviewer` from `${XDG_CONFIG_HOME:-$HOME/.config}/sno/models.toml`. An absent file, missing role, or empty value means no model flag; the harness selects its current default. There is no model environment override or fallback name. To set a model, create the optional file with `[models]`, `reviewer = "model-name"` and `reviewer_claude = "model-name"`.
- honors `FOCUS` (focus area), `REVIEW_KIND` (`code` default | `plan` for specs/plans/PRDs), `CODEX_EFFORT`, and the reliability knobs below as env overrides;
- writes the structured review to a Markdown file under `REVIEW_ARCHIVE_DIR` (default `~/.local/state/codex-reviews/<date>/`, path printed on stderr; override with `REVIEW_OUTPUT_FILE=…`) — read that file instead of grepping stdout for large files, since codex echoes the full inlined prompt.

`low` is the default effort for Codex review passes, including reviews before merging. Use a different `CODEX_EFFORT` only when the caller explicitly requests it.

Every invocation must set `REVIEW_CALLER` to the current executing harness: `REVIEW_CALLER=codex bash scripts/run-adversarial-review.sh ...` from Codex, or `REVIEW_CALLER=claude-code bash scripts/run-adversarial-review.sh ...` from Claude. Do not use the identity of the agent that originally delegated the task. Only `codex` and `claude-code` are supported values; any other value exits 5, so agents on a third harness cannot use this wrapper. This explicit value avoids inherited environment markers selecting the wrong reviewer. Without it, the script checks `CODEX_THREAD_ID`, then `CLAUDECODE`; an unmarked shell is treated as a Claude caller.

**Reviewer choice.** The script picks the reviewer once, before the first attempt. The other vendor's CLI is used when it is installed and logged in (`codex login status` / `claude auth status`). Otherwise the caller's own CLI runs the review in a fresh session, and the saved report and stdout begin with `Reviewer: same-vendor review (...)`. Copy that fact into your final report's `Source` line. The script exits 2 when neither CLI is installed, when the prompt file is unreadable, or when `models.toml` is malformed. Both vendors use the same prompt, report archive, timeout and retry handling; after the choice is made, a failed reviewer is never replaced by the other one.
- Claude reviewer: `claude -p [--model <reviewer_claude>] --effort medium`, model from role `reviewer_claude` in the same optional `models.toml` (an absent file, missing role, or empty value omits `--model`). It receives the file contents on stdin with tools disabled and writes its final text to the report file.
- Codex reviewer: as above, low effort.
- Both run with the caller's session markers removed, so the review never inherits the caller's session.

**Choose the wave size; do not inherit it.** `MAX_FILES_PER_WAVE` decides how many files one
reviewer sees at once, and the 8 in the script is a default nobody picked for your case — the
wrapper says on stderr whether the number was chosen or defaulted. The trade runs both
ways and only you know which side this review needs. **Larger** puts more files in front of
one reviewer, which is the only way a contradiction *between* files becomes visible:
cross-document contradictions are only reachable when both documents sit in one wave.
**Smaller** buys depth per file and less
dilution, which is what a correctness or security pass over dense source wants. Rough
starting points: a cross-document consistency review wants the whole set in one wave if it
fits under `PAYLOAD_LIMIT`; a security sweep over unrelated modules wants 2–3; the default 8
is for a batch of related files where neither concern dominates.

**Reliability.** Before launch, state the target file count, expected wave count, one response per wave, and projected runtime. The script prints a heartbeat every `PROGRESS_SECS` (default 30s), kills the whole reviewer process tree if stdout, stderr, and the final-message file show no activity for `STALL_SECS` (default 600s) or an attempt exceeds `TIMEOUT_SECS` (default 3600s), and retries stalls, timeouts, nonzero exits, and empty final responses up to `MAX_RETRIES` (default 2, so 3 attempts) with bounded backoff. It clears the final-message file before every attempt and treats that file — not incidental CLI output — as the success proof and canonical report. `POLL_SECS` and `BACKOFF_BASE_SECS` are also overridable. Reviews are safe to run in parallel: with Codex, reasoning summaries stream, so a live reviewer keeps resetting the stall counter. `MAX_PARALLEL` (default 8) caps how many reviews run at once machine-wide; over the cap the script exits `9` immediately rather than queueing, so a caller is never left blocking on a slot — treat exit `9` as "retry this file later", not as a review failure. If the payload exceeds `PAYLOAD_LIMIT` (default 90KiB) or `MAX_FILES_PER_WAVE` (default 8), it auto-splits into waves with the same watchdog/retry; plan mode pins the first target into every wave. Exhausted single-wave retries exit `6`; exhausted batched retries exit `7` and retain capture paths. A legitimately quiet large run can need a larger `STALL_SECS`, but never replace this wrapper with an unbounded direct call.

**A review that produced nothing must not read as a clean bill of health.** Every invocation writes a `start` line to `~/.local/state/codex-review-stats.jsonl` at dispatch and one terminal line — `end` or `refused` — when it stops; a start with no terminal line is a run that was killed, and is the only trace an uncatchable kill can leave.

`review-receipt.sh` reads that record; `review-findings.sh` keeps a separate findings ledger. Neither makes a reviewer call:

```bash
scripts/review-receipt.sh [--since <date|today|all>] [--journey <id>] [--check]
```
One row per invocation — status, round, verdict, finding count, targets — then a **"not actually covered"** section listing every run that was killed, failed, or refused. Run it after any fan-out of more than a couple of reviews, and before reporting what a batch covered. `--check` exits non-zero when anything is uncovered, so it can gate.

```bash
scripts/review-findings.sh list [--status undecided] [--file <substr>]
scripts/review-findings.sh set <id> <accepted|rejected|superseded> [note]
scripts/review-findings.sh prior <file>...
```
Findings are filed automatically by every successful review, keyed by reviewed file plus title, with a `status` column that starts `undecided` and only a human sets. A finding raised again in a later round updates its row rather than arriving as new — so the ledger keeps one row per finding across rounds. `prior` prints the settled (rejected/superseded) rulings for given files, size-capped on purpose; to show earlier rulings to the next review, save that output to a file and pass it as an extra target.

`scripts/review-backfill.sh [--since <date>]` recovers past Codex-reviewer reports from `~/.codex/sessions` when report files were lost.

```bash
# <skill-dir> is the directory that holds this SKILL.md.
REVIEW_CALLER=claude-code bash <skill-dir>/scripts/run-adversarial-review.sh \
  apps/foo/src/a.ts apps/foo/src/b.ts

# Focused review:
FOCUS="concurrency" REVIEW_CALLER=claude-code \
  bash <skill-dir>/scripts/run-adversarial-review.sh apps/foo/src/a.ts

# Plan/spec review (plan-specific prompt + probe evidence):
REVIEW_KIND=plan REVIEW_CALLER=claude-code \
  bash <skill-dir>/scripts/run-adversarial-review.sh \
  docs/plans/migration-plan.md PROBE-RESULTS-migration.md
```

Paths outside the repo are fine (plans, manifests) — the script never asks the reviewer to read them. The structured Markdown review (verdict + findings + next steps) on stdout is the canonical output of this skill; parse it as the source of truth.

With findings in hand: **enrich** each with cross-file context, **deepen** to root cause, **classify** severity and layer per the layers reference, and **preserve** every finding. Prioritize Critical and High.

## Phase 2: Fix (code) or Report (docs)

**Scope-capped kickoff:** when the user's request limits scope ("do not widen the scope",
"fix only the necessary issues", "only fix serious problems", "don't touch unrelated code"),
fix ONLY Critical/High findings; Medium/Low are reported, never fixed — no matter
how easy they look. Every fixed line must trace to a Critical/High finding.

**Code (`review-and-fix`):** For each finding, before touching code: trace where the bad state originates (follow imports, callers, data flow); search for sibling instances of the same pattern elsewhere; classify fix depth — **Local** (isolated mistake), **Structural** (design flaw), **Systemic** (repeated pattern: when the user limited scope, fix the instance here and flag the rest; otherwise fix every instance once at the shared layer they route through). A Local classification states what was searched and why no sibling exists. Present the root-cause analysis to the user before applying fixes.

**"Cut" is applied first, by deleting.** By default (a project may choose otherwise) it is the one tier the active agent acts on without
asking, because removing unrequested behaviour cannot widen scope; if a Cut item is something the
owner explicitly asked for, keep it and say so. **Then the "Must fix" tier is fixed.** Walk it most-severe-first. Every "Also found" item is
recorded with `review-findings.sh` and listed to the user under its own heading; if one of them
looks worth building, say so as a proposal and stop — do not dispatch it, do not fold it into the
fix. A fix that would add new behaviour to close a "Must fix" item is a sign the item was
mis-tiered: report the tier disagreement instead of adding the behaviour.

Fix the cause rather than the symptom — a flagged missing null check means deciding whether the caller should guarantee non-null, the function should accept null, or the type should be narrowed upstream, not just adding `if (x != null)`. Simple fixes (formatting, imports, single-line logic): smallest safe direct edit. Complex fixes (architecture, algorithms, security): implement locally after root-cause analysis; delegate to workers only with explicit user authorization. Run the repository's own lint/typecheck command after each batch of related fixes. Assign each issue a stable ID (`C1`, `S1`, …) to track persistence vs rephrasing across iterations.

**Docs (`report-only` / `report-and-edit`):** Documents have gaps, ambiguities, and risks rather than bugs — present findings grouped by severity using the doc format from `references/doc-layers.md`. In `report-and-edit` mode, show current text → proposed replacement → why it matters, and apply edits only after the user confirms; doc changes are often product decisions the reviewer shouldn't make unilaterally.

## Phase 3: Re-review loop (code only) — HARD-CAPPED

Documents and plans do not run confirmation loops. A plan/spec/doc gets at most **five** judgment
passes per window, counted across the plan, spec and doc kinds, any change of target set, and one
`REVIEW_JOURNEY` label (below) — a file may be judged up to five times in a day; set `REVIEW_CAP_OVERRIDE=<reason>` to lift it; the reason is recorded on the stats line.
After the last pass, fix current-slice blockers, record non-blockers, run deterministic
validation once, and implement. For code, re-run the same script invocation on the same
target paths, then decide. **The wrapper enforces a hard cap on same-scope
invocations regardless of what reviews return: code = 3 (2 fix rounds + 1
confirmation), plan/spec/doc = 5, test = 1; test and planning caps bind beyond the exact target set** — later rounds have diminishing returns. Over the cap the wrapper exits 10 and refuses another review. The caller continues
direct repair and targeted verification; this is not permission to stop the assignment. Changing `REVIEW_KIND`, adding/removing a companion
file, or inventing a planning override does not start a sixth planning pass; only `REVIEW_CAP_OVERRIDE=<reason>` does.

**Every cap counts only the passes inside a rolling window — `REVIEW_CAP_WINDOW_HOURS`,
default 24.** A cap is a loop-breaker for one working session. Counting all history would
retire an artifact from review for good after its facts were corrected, which is the opposite
of what a loop-breaker is for. Passes older than the window do not count against any cap, so
an artifact that genuinely changed weeks later gets a fresh review without an override and
without dodging the scope key. Within the window the cap binds in full.
`REVIEW_CAP_WINDOW_HOURS=0` counts all history. If GNU
`date -d` is unavailable the window is disabled and the wrapper says so on stderr, so a
missing dependency fails closed rather than silently un-capping every review.

```
IF "Cut" and "Must fix" tiers are both empty:
  -> APPROVE. Exit loop. Every "Also found" item (including a fix-now item whose only
     remedy is new behaviour) is already filed in the findings ledger with status
     `undecided` — it never blocks, never triggers a fix or a re-review here.
     Rule on it with `review-findings.sh set`, or put it to the owner as a proposal.
ELSE IF round < cap:
  -> Delete every "Cut" item, then fix the "Must fix" tier (Critical/High first), then re-review (focused on what changed)
ELSE (cap reached, "Must fix" still open):
  -> End the review loop, not the task. Record "Also found" as debt.
     Fix the verified "Must fix" defects through direct diagnosis and affected checks
     under the existing execution authorization, still without adding behaviour. By default, do not
     require a new brief or owner approval for ordinary repairs. Never claim a new
     review ran when the cap refused it.
```

**Labelled reviews (journey mode).** A "journey" is one piece of work that gets several reviews. Setting `REVIEW_JOURNEY=<label>` groups every review of it under one name, so the planning cap counts across it. When it is set the wrapper refuses to run (exit 11) unless you also pass:
- `CHARTER=` — the variable name is literal: one line, or a file path, saying what the change is for;
- `FENCE=` — the path of a file listing the paths the change may touch;
and you should also pass:
- `CONTEXT_FILE=` — a file describing the deployment context (trust model, platform, format invariants). Severity is judged against it, and a severity cap is legal only when it cites an entry there.

Findings are classified by causality × delivery impact: `fix-now` (caused by the change, or verified to block the deliverable), `debt` (real, pre-existing, recorded not fixed), `out-of-context` (impossible under a cited context entry). Invocation statistics land in `~/.local/state/codex-review-stats.jsonl`.

## Phase 4: Final report

### Code report
```
## Code Review Summary

**File(s)**: [list]
**Iterations**: [count]
**Issues**: [initial] -> [final] ([fixed] fixed)
**Source**: adversarial-review script, reviewer <codex|claude>, <cross-vendor | same-vendor (fresh session)> (authoritative)

### Reviewer Findings

#### [C1] [Issue title]
- **Severity**: Critical/High/Medium/Low
- **Category**: [Correctness/Security/Performance/Type Safety/Quality]
- **Root cause**: [Why this issue exists — the origin, not just the symptom]
- **Fix depth**: Local | Structural | Systemic
- **Fix applied**: [What changed and why it addresses the root cause]
- **Siblings**: [Other instances of the same pattern, if any]

### Active-Agent Supplementary Findings (if any)
[Non-authoritative, clearly labeled]

### Systemic Patterns
[Patterns recurring across findings — worth addressing at a higher level]

### Remaining (if any)
- [S2] [Issue title] (Severity) — why it couldn't be auto-fixed

### Next Steps
[Manual actions, systemic fixes beyond this file, tests to add]
```

### Document report
```
## Document Review Summary

**Artifact**: [file path]
**Type**: [plan | spec]
**Issues**: [count by severity]

### Findings

#### [D1] [Finding Title]
- **Severity**: Critical/High/Medium/Low/Decision-Required
- **Layer**: [layer name]
- **Location**: [section heading or quote]
- **Problem**: [what's wrong or missing]
- **Evidence**: [the text that shows the issue]
- **Recommendation**: [specific change]
- **Decision needed?**: yes/no

### Strengths
[What the document does well]

### Top Priorities
1-3. [Most impactful findings]
```

## Safety

- The wrapper caps same-scope code reviews at 3; the same issue surviving two fix attempts requires a new diagnosis and approach; continue the authorized repair.
- Show diffs for complex code changes; run the repository's check command after each fix batch, not only at the end.
- Never auto-apply doc edits without user confirmation.
- Every finding cites its exact location.

## Usage examples

```
User: Review src/orders/service.py          # code, auto-fix loop
User: Check src/api/routes/*.ts for security     # focused code review
User: Audit src/storage.py but just report          # report-only
User: Review docs/design/foo.md                              # spec review
```
