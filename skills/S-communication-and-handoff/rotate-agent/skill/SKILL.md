---
name: rotate-agent
description: "Quota-triggered failover between agent harness vendors, either direction. When asked to arm it, it starts a watch (optionally time-limited) that reads the working vendor's remaining subscription every few minutes; below a threshold, and only while the sender is still alive, it orders a handoff to a receiver from the other vendor, once. Use when a long run must finish even if one vendor's quota runs out. Not a monitor for anything else."
requires:
  programs:
    - {name: subscription-quota-check, min_version: "1.0"}
    - {name: heartbeat, min_version: "1.0"}
    - {name: reach, min_version: "2.0"}
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.background-processes, need: required}
    - {slot: 3.reader-to-agent-delivery, need: required}
---

# rotate-agent

Needs: `tmux`, `jq`, the `sno` CLI with its Reach runtime (`sno reach`), both vendor CLIs
(`claude` and `codex`, each installed and logged in, since the quota of both is read), plus
`heartbeat` and `subscription-quota-check` from the same install, and the `handoff` skill (its `handoff-checkpoint` keeps the progress record). A seat is a registered terminal
address (see `join-talk`). The owner is the person (or agent) who owns the work; the watchman
usually is that owner's session. The `heartbeat` command runs in the background
and its log is read by a reader (a background-process tool and a log-tail tool; the examples below
are Claude Code syntax, so use your harness's equivalents).

Rotation is who steps in when the one working is throttled. This skill makes that automatic
for one long run: a watchman agent arms a heartbeat whose hook reads the working vendor's
quota, and when the remaining share falls to the threshold the watchman tells the working
agent to hand the task over to a fresh agent from the other vendor. The handoff itself is the
`handoff` skill, unchanged; rotation only decides **when** and **to whom**.

Quota is normally read on demand only: `subscription-quota-check` reads it when the person asks
or after a vendor refuses work, and never on a timer of its own. Rotation is the one deliberate
exception. The person's request to rotate is the moment; arming this skill authorizes the
watchman's heartbeat to read the working vendor's quota every few minutes (the arming example
below has no time limit; set `--max-hours <N>` to bound it) so the handoff can happen before the refusal. Nothing else should poll quota.

Either direction works. `--from codex --to claude` and `--from claude --to codex` are the same
procedure with the seats swapped.

## The one rule

**Rotate while the sender is still alive.** A handoff needs the sender to write the brief,
verify the receiver and release. Once a vendor refuses work, none of that is possible. So the
trigger is a threshold on remaining quota, read a few minutes apart, never the refusal itself.
If a tick prints `LATE`, the window was missed: the receiver must resume from disk state
instead (see below).

## Three seats

| seat | who | does |
|---|---|---|
| working agent (A) | the agent executing the task, vendor `--from` | registers with `join-talk` before starting; checkpoints after every task; runs `handoff` when ordered |
| watchman | any agent with background processes and a reader (usually the session of the task's owner) | arms the heartbeat, reads ticks, sends the order |
| receiver (B) | a fresh agent of vendor `--to` | spawned by A inside `handoff`; continues to completion |

## Working agent: three lines added to its prompt

Put these after the task instruction:

```
$join-talk
After every completed task, commit and run `handoff-checkpoint <record>` (the progress record, kept outside the checkout), then update its Done and Next lists.
When you receive "ROTATE: hand off to <vendor> now", stop editing and run $handoff to a receiver of that vendor at once.
```

Per-task checkpoints bound what a receiver has to redo. Registration is what lets the
watchman reach it.

## Watchman: preflight, then arm, read, order, stop

Before arming, prove the rotation can happen at all. `rotate-agent-preflight` and
`rotate-agent-watch` both ship in this skill's `scripts/`; put them on PATH or give their full
paths (the examples below use bare names). Run the preflight in the working agent's checkout:

```
rotate-agent-preflight --from codex --to claude --cwd <checkout> --sender <A-seat>
```

It checks, in order, that the tools are installed, the receiver vendor's command exists,
the checkout is a git work tree, the sender's seat is registered, both quotas can be read
and the receiver has headroom, and finally that a receiver of the `--to` vendor can be
spawned on a tmux seat in that checkout and answers a call; the trial seat is torn down.
Every line is `OK <check>` or `FAIL <check>: <what> -> <what to do>`; the last line of a
clean run is `READY`. Do not arm on a `FAIL`: give the owner the `->` part verbatim (a
vendor's first run in a directory stops at its trust prompt, and that key is the owner's
to press) and rerun the preflight after they act.

Arming is two calls, as `heartbeat` requires (shown in Claude Code syntax: one call starts the
background process, the other tails its log; use your harness's own tools for both). Create a fresh empty log with
`mktemp "${TMPDIR:-/tmp}/heartbeat.XXXXXX"` and a state path under
`${XDG_STATE_HOME:-$HOME/.local/state}/rotate-agent/<label>.state` that does not exist yet.

```
Bash({
  run_in_background: true,
  command: "heartbeat --interval 5 --max-hours 0 --label rotate-agent-<work> --log \"<LOG>\" \
    -- rotate-agent-watch --from codex --to claude --threshold-pct 2 --state \"<STATE>\""
})

Monitor({
  command: "tail --pid=<from the arm output> -F -n +1 \"<LOG>\"",
  persistent: true,
  description: "rotate-agent-<work> ticks"
})
```

`--max-hours 0` matters: a heartbeat stops itself after 24 hours by default, and the quota
trigger would then never fire on a longer run; give a number of hours instead to bound the watch.

Every tick of `rotate-agent-watch` prints one line. Say what it says, then act on the first word:

| line | meaning | watchman does |
|---|---|---|
| `HOLD from=… remaining=N% threshold=T%` | above threshold | nothing |
| `HOLD receiver-<verdict> …` | threshold crossed but the other vendor is also blocked | nothing; report it — the run will end at refusal and needs resume from what is on disk |
| `HOLD unreadable …` | quota could not be read on this tick | nothing; three in a row is worth reporting |
| `ROTATE from=X to=Y remaining=N% …` | threshold crossed, receiver has headroom, state file written | send the order (below), then `heartbeat --stop rotate-agent-<work>` |
| `DONE rotated <time> …` | a ROTATE already fired | stop the heartbeat if still running |
| `LATE blocked …` | sender already refused | resume from what is on disk (below); stop the heartbeat |

The hook fires `ROTATE` once: the state file is the lock, and every later tick prints `DONE`.
To re-arm for a second rotation (the receiver may run out too), use a new label and a new
state path with the seats swapped.

Only the `--from` vendor is read on ordinary ticks. The `--to` vendor is read once, at the
moment of crossing, so the rate-limited side is not polled.

### The order

Seat on tmux:

```
sno reach call <A-seat> "ROTATE: hand off to <to-vendor> now. Remaining quota <N>%. Run the handoff skill; receiver kind <to-vendor>, spawned --window (a tmux seat, never an ACP seat: the non-terminal Agent Client Protocol seat that `sno reach spawn` uses without `--window`; see the reach skill); same checkout; report to <owner session>." --expect HANDOFF_RELEASED --timeout 300
```

If the seat runs in another terminal host, send the same text there, press Enter, and read its
new output (repeating a bounded number of times) for the release line.

`HANDOFF_RELEASED` in new output means B holds the task. No release inside the deadline
means A did not finish the handoff: inspect A's screen; do not send the order twice — a
second order is a duplicate, not a retry.

A seat marked `stale` in `sno reach seats --json` is not proof that its agent is gone: the
mark only says the record was not refreshed for 15 minutes, and an agent that works without
sending mail never refreshes it. Before treating A or B as dead, look at the terminal or
process behind the seat.

## When the window was missed: resume from the progress record

If a tick says `LATE`, or the order gets no release, A is gone. Start B with one command. It points B
at the progress record A kept with `handoff-checkpoint`, so B continues from the record's Next list and
does not redo what Done lists:

```
rotate-agent-resume --to <to-vendor> --cwd <checkout> --checkpoint <record> --work <work> --report-to <owner session>
```

The command first refuses (`FAIL checkout`) when the record belongs to a different checkout than `--cwd`,
naming both. It then compares the record with the checkout (`MATCH`, or `DRIFT` lines naming what changed
after the last checkpoint, which it hands to B to inspect), then runs `sno reach init` and
`sno reach spawn --window` to put B on a tmux window, and waits for B's fresh `RESUME_ACK` line, not an
echo of the prompt. Every step prints `OK <step>` or `FAIL <step>: <what> -> <what to do>`; the last
line of a clean run is `RESUMED seat=<address> verify=MATCH|DRIFT`. A `<work>` label resumes once: a
second call names the existing seat instead of starting another receiver.

B prints `DONE_<work>` on its own line when every task is done. When a task needs the owner it prints
`BLOCKED_<work> <reason>` on its own line instead.
It never prints `DONE_<work>` while any task waits on the owner.

`--window` puts B on a tmux seat, which keeps working and stays readable after every call to it has
timed out; an ACP seat's work (see the `handoff` skill, step 2) is lost once its caller's `--timeout`
expires.

This is the fallback, not the design: it loses whatever A had half-done since its last checkpoint,
which is why the working agent runs `handoff-checkpoint` after every task.

## Five things that stay true

1. **The threshold is code, not judgement.** `rotate-agent-watch` decides; the watchman relays.
2. **Never rotate on a blind read.** `unknown` and `needs_auth` hold; a percentage that cannot
   be shown current is not a percentage.
3. **Never hand to a vendor that is also out.** The receiver is checked at the crossing.
4. **Once.** The state file makes a second `ROTATE` impossible under the same label.
5. **Vendor names are seats, not sides.** Nothing here assumes which vendor is which.
