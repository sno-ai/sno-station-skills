# Skills

Each unit is one skill, or a family of skills that ship together, and lives in the directory of
its category: `<category>/<unit>/`. `../registry.yaml` records the same category for every unit.
Category codes and order are fixed: J M S H T R. A skill that ships inside another unit's
family but belongs to a different category is listed under its own category below.

## J · Peer Review & Audit

Colleagues review each other's work, and nothing counts as done until it passes audit.

- [agentic-walkthrough](J-peer-review-and-audit/agentic-walkthrough/) — prove that a reported run really produced its effect
- [e2e](J-peer-review-and-audit/e2e/) — end-to-end testing: `e2e-red-triage` classifies one unexpected failure (its companion `e2e-environment-preflight` is listed under M)
- [first-principles-review](J-peer-review-and-audit/first-principles-review/) — challenge an idea or design from first principles
- [less-is-more](J-peer-review-and-audit/less-is-more/) — write the least code that works and cut what was over-built
- [owner-intent-audit](J-peer-review-and-audit/owner-intent-audit/) — check plans, tests or code against what the owner actually asked for
- [peer-review](J-peer-review-and-audit/peer-review/) — adversarial review and fix loop by an independent reviewer

## M · Build & Rollout

Get the team set up on any workstation with one step, build what the work needs, then roll it out to every machine.

- [medic](M-build-and-rollout/medic/) — check that the agent team on this machine can work, in plain lines, and repair nothing
- `e2e-environment-preflight` — check the environment before an end-to-end run (ships inside the [e2e](J-peer-review-and-audit/e2e/) unit)

## S · Communication & Handoff

People talk through a shared inbox, and when one is out the other takes over with full context.

- [handoff](S-communication-and-handoff/handoff/) — hand a task to another agent with full context, or resume from a progress record when the sender is already gone (ships the `handoff-checkpoint` command)
- [heartbeat](S-communication-and-handoff/heartbeat/) — recurring checks and completion watches
- [join-talk](S-communication-and-handoff/join-talk/) — make a manually opened agent reachable
- [reach](S-communication-and-handoff/reach/) — agent-to-agent cards, rings and calls
- [rotate-agent](S-communication-and-handoff/rotate-agent/) — fail over to another vendor's agent when quota runs out, or start a replacement from a progress record (ships the `rotate-agent-resume` command)
- [subscription-quota-check](S-communication-and-handoff/subscription-quota-check/) — read remaining subscription quota without spending it

## H · Reporting & Visibility

Everyone can see what got done, who caught what, who covered for whom, what's in progress.

- [agentic-time-estimate](H-reporting-and-visibility/agentic-time-estimate/) — estimate how long agent work takes and read clock times in the owner's zone
- [away-brief](H-reporting-and-visibility/away-brief/) — one page for when the owner comes back: done, stuck, waiting for an answer, quota spent
- [catch-report](H-reporting-and-visibility/catch-report/) — what the reviews caught, per reviewer, from the review records

## T · Delegation & Work Orders

A lead delegates work as work orders, and decides who takes each job.

- [charter](T-delegation-and-work-orders/charter/) — write, revise or review the one document that says what to deliver and how it will be proven
- [cos](T-delegation-and-work-orders/cos/) — Chief of Staff: the one agent the owner talks to; it coordinates the Project Leads (ships `cos`, `cos-watch`, `cos-review`)
- [deliver](T-delegation-and-work-orders/deliver/) — carry out a released charter to a proven result
- [pl](T-delegation-and-work-orders/pl/) — Project Lead: supervises one project workstream and its executor agents (ships `pl`, `pl-dispatch`, `pl-watch`, `pl-audit`, `pl-env`)

## R · Retrospective & Improvement

The team looks back at its own work and turns lessons into rules and better practice.

- [rem-reflect](R-recursive-self-improvement/rem-reflect/) — turn a machine's own agent sessions into reviewed lessons and skill changes
- `pl-analyze` — incident analysis for the Project Lead (ships inside the [pl](T-delegation-and-work-orders/pl/) unit)
- `cos-evolve` — turn repeated management failures into rules (ships inside the [cos](T-delegation-and-work-orders/cos/) unit)
