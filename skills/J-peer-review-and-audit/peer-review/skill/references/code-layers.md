# Code Verification Layers

Use when reviewing source code (.py, .ts, .tsx, .js). These layers guide the active agent's context-gathering, severity classification, and supplementary analysis. The same bar applies here as in the adversarial prompt: every finding needs a realistic trigger path, an operational consequence, and must survive an honest refutation attempt.

## Method: primary flows first

Do not sweep layer-by-layer looking for one finding per layer. Instead:

1. Establish what the code is for, who calls it, and what it must guarantee.
2. Identify the 3-5 most expensive failure points: primary execution paths, state that must never corrupt, boundaries that must hold (auth, money, persistence, external contracts).
3. Trace those paths end to end under production conditions — real data shapes, concurrency, retries, restarts, partial completion, dependency failure.
4. Then run the Tier 1 sweeps below. Tier 2 items are reportable only when tied to a Tier 1 consequence.

## Tier 1 — hunt these

### Correctness on primary flows
- Invariants violated along the main execution paths; logic that only works on the happy path
- Interface/contract breaks: inputs/outputs that no longer match callers, tests, schemas, or declared contracts
- State mutation hazards: shared mutable state, stale closures, unexpected side effects
- Race conditions, deadlocks, async/await misuse, ordering assumptions that break under concurrency
- Null/empty/boundary states — only where a supported input or common workflow actually produces them

### Security & trust boundaries
- Injection (SQL, NoSQL, command, template), XSS, SSRF, path traversal, open redirects
- AuthN/AuthZ: missing access checks, IDOR, privilege escalation, weak tokens, session issues, tenant isolation
- External data crossing a trust boundary without validation
- Secret exposure: hardcoded secrets, PII/tokens/internal URLs in logs; flag secret-looking patterns (`sk_live_`, `api_key_`, `password`)
- Cryptographic failures: weak algorithms, misused primitives

### Data integrity & failure handling
- Data loss, corruption, duplication, irreversible wrong state
- Partial failure: 1-of-N succeeds, then what? Idempotency of retried operations; rollback of half-completed writes
- Silent failure: swallowed exceptions, errors converted to empty results, lost stack traces
- Migration/version skew: old and new code or schema coexisting during deploy

### Resources under normal load
- Leaks: unclosed connections, handles, timers; pool exhaustion
- Unbounded growth: queues, caches, buffers without limits
- Missing timeouts on external calls; blocking operations in async contexts
- N+1 queries and algorithmic blowups that plausibly occur at production data sizes

## Tier 2 — report only when tied to a Tier 1 consequence

- **Type safety**: `any`/`Any` abuse, unvalidated external data, union narrowing failures — when they let a Tier 1 failure through the checker
- **Error-handling hygiene**: missing retries, `Promise.all` vs `allSettled` — when a realistic transient failure then breaks a primary flow
- **Observability**: missing logging/metrics — only when their absence would hide a specific Tier 1 failure or block its recovery
- **Code quality**: complexity, DRY, dead code, naming — only when it demonstrably hides a bug or materially raises change risk
- **Performance polish**: micro-optimizations — only with an obvious or measured hot path

## Cross-cutting detectors

High-yield patterns that layer-by-layer analysis misses:

- **Environment bifurcation**: for every config value — what happens in production vs development? Security-sensitive dev defaults that silently become production behavior are bugs.
- **Comment-code mismatch**: when a comment claims behavior, verify the code matches; a lying comment often marks a developer misunderstanding worth tracing.
- **Failure-mode enumeration** for external calls on primary paths: returns null? throws? times out? returns malformed data? partial success? Each unhandled mode that a real dependency outage or retry produces is a finding.
- **Hardcoded values**: IPs, URLs, hostnames, secrets in code; secrets and required config must fail fast rather than default.

## Severity anchors (code)

| Severity | Meaning |
|----------|---------|
| **Critical** | Data loss/corruption, security breach, financial error, or a primary flow broken for most users |
| **High** | Primary flow broken under common production conditions (concurrency, retry, restart, dependency failure); silently wrong results; resource exhaustion under normal load |
| **Medium** | Real degradation on a plausible secondary path — recoverable, but costs an incident, support ticket, or wrong decision |
| **Low** | Everything else that is still true — report only on an explicit exhaustive-pass request |

## Issue Report Format

```
## Issues Found: [count]

### [ID] [Brief Title]
- **Severity**: Critical/High/Medium/Low
- **Layer**: [Tier 1 category or Tier 2 name]
- **Location**: [file:line]
- **Trigger**: [realistic sequence that reaches the failure]
- **Problem**: [description]
- **Evidence**: [code snippet showing issue]
- **Fix**: [smallest concrete change that removes the risk]
- **Why this matters**: [operational impact if unfixed]

[Repeat for each issue, ordered by severity]

## Summary
- Critical: [count], High: [count], Medium: [count], Low: [count]
- Top priority fixes: [list top 3]
- Overall code health: [assessment]
```
