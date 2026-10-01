# Document Verification Layers

Use when reviewing plans, architecture docs, and specs, including any design or spec document set. Documents fail through ambiguity, gaps, and hidden assumptions rather than runtime errors — but the same materiality bar applies: a finding must change what gets built, block execution, or force rework. The reader to protect is an implementer following the document as written.

## Method: the rework-forcing four first

Before any layer sweep, hunt the four failure classes that actually cost projects:

1. **Wrong or contradictory decisions** — a stated choice conflicts with another section, a prior decision, or the referenced code's reality; the implementer ships the wrong thing.
2. **Missing critical dependency, migration, or rollback** — the plan cannot survive contact with production; forces rework or an outage.
3. **Infeasible sequencing** — tasks ordered with forward dependencies or steps that cannot be executed as written; blocks the work.
4. **Materially ambiguous requirements** — two reasonable implementers would build materially different things.

Verify referenced reality: file paths, function names, line numbers, and API shapes the document cites must match the current code. Stale references are a top source of class-1 failures.

Everything below feeds these four. Vague wording, terminology drift, or a missing acceptance criterion is a finding only when it produces one of them — not because a checklist says every requirement must be testable.

## Layer sweeps

1. **Intent & scope** — problem stated; goals/non-goals bounded; success criteria measurable; can a reader tell what's IN vs OUT?
2. **Requirement precision** — observable and falsifiable where it matters; weasel words ("should", "may", "as needed", "where appropriate") flagged only when the readings diverge into different implementations; non-functional requirements (latency, throughput, availability) quantified when they drive design.
3. **Completeness & dependencies** — prerequisites and external dependencies identified; data contracts/API shapes/schemas specified; migrations, rollback, backfill addressed; monitoring for new components; implicit assumptions made explicit.
4. **Internal consistency** — sections agree; terms used uniformly; assumptions in one section match constraints in another; versions/dates/references consistent.
5. **Sequencing realism** — ordering implementable, blockers and critical path identified, robust to partial completion (what if task 3 slips?).
6. **Failure modes** — unhappy paths, partial failure (1 of N services updated), rollback/recovery, compatibility during transitions, degraded-mode behavior — for scenarios normal rollout or recovery can actually hit.
7. **Traceability** — requirements ↔ tasks: orphans on either side matter when they mean work will be silently skipped or unowned, not as bookkeeping.
8. **Decision debt** — unresolved choices called out explicitly rather than hidden as assumptions; alternatives dismissed with reasoning; risks paired with mitigations.

## Overlays for design, spec and task-list documents

When the material is a set of separate documents, additionally:

- **Rationale / scope document** (if there is one): states the problem, lists concrete deliverables, identifies affected components, and draws explicit scope boundaries.
- **Design**: decisions trace to the stated requirements; interface contracts specified; testable — acceptance tests could be written from it.
- **Spec**: behaviors implementable as written; state transitions and error responses covered; examples match the specified behavior.
- **Task list**: every task has a "done" definition; test tasks paired with implementation tasks; dependencies before dependents; atomic enough to be checked off independently.

## Severity Guide for Documents

Document severity maps to implementation risk:

| Severity | Meaning | Example |
|----------|---------|---------|
| **Critical** | Will cause rework or system failure if implemented as-is | Missing data migration for schema change; decision contradicting the referenced code's actual behavior |
| **High** | Significant gap that blocks confident implementation | Requirement with multiple materially different valid interpretations |
| **Medium** | Gap that raises implementation risk but has reasonable defaults | Missing failure-mode spec for a common retry path |
| **Low** | Polish; report only on an explicit exhaustive-pass request | Terminology inconsistency between sections |
| **Decision-Required** | Not a defect — an unresolved choice needing a human decision | "Support both v1 and v2 during migration?" |

## Issue Report Format

```
## Findings: [count]

### [ID] [Finding Title]
- **Severity**: Critical/High/Medium/Low/Decision-Required
- **Layer**: [layer name or rework-forcing class]
- **Location**: [section heading or quoted text]
- **Problem**: [what's wrong, missing, or ambiguous]
- **Evidence**: [the text that shows the issue, quoted]
- **Consequence**: [what an implementer following this doc would ship, skip, or block on]
- **Recommendation**: [specific change or question to resolve]
- **Decision needed?**: yes/no — if yes: who decides, and the options

[Repeat for each finding, ordered by severity]

## Strengths
[What the document does well — anchors for the author]

## Summary
- Critical: [count], High: [count], Medium: [count], Low: [count], Decision-Required: [count]
- Top 3 priorities: [list]
- Overall assessment: [ready for implementation | needs revision | needs major rework]
```
