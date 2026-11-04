---
name: rotate-agent
description: "Quota-triggered failover from Claude Code, Codex, Cursor, Hermes or OpenClaw. When armed, it reads the sender quota and tries other-vendor models in place, then receiving agents in the configured order. Use when a long run must finish even if one vendor's quota runs out. Not a monitor for anything else."
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

Needs: `tmux`, `jq`, GNU `timeout`, and `sno` with Reach, heartbeat and
subscription-quota-check, plus the `handoff` skill. The provider-reading script also
uses `awk` and OpenClaw's session exporter. Install programs through `sno setup`.
A seat is a registered terminal address (see `join-talk`). The owner owns the work;
the watchman reads ticks and acts on them, preferably from a seat other than the busy sender.

Rotation keeps one authorized long run working when its model's quota is low.
Agent ids are `claude-code`, `codex`, `cursor`, `hermes`, `openclaw`. Selection belongs
to `sno subscription-quota-check --pick handoff`: other-vendor models inside the sender
first, then other agents in `handoff_order`. Never replace the returned order with your own.
A Cursor quota reading belongs to one conversation, so `--from cursor` needs
`--sender <A-seat>` on the preflight and `--seat <A-seat>` on the watch; without it
the reading is unreadable and the watch holds. A Cursor receiver is always a new
Cursor CLI seat on a tmux window (`sno reach spawn cursor-agent --window`). The trigger
is the threshold read only; a quota error message from Cursor does not start a rotation.

Quota normally is read only on request or refusal. Asking to arm rotation authorizes
these periodic sender reads. Only the sender is read on ordinary ticks; the full pick
runs once at a crossing. No other process should poll quota.

## Three seats

| seat | who | does |
|---|---|---|
| working agent (A) | the agent executing the task | registers; checkpoints after each task; hands off when ordered |
| watchman | an agent with background execution and delivery of its results | arms, reads ticks, walks candidates |
| receiver (B) | an agent chosen by the pick | starts on a tmux window; takes the same checkout and authority |

## Working agent: three lines added to its prompt

```
$join-talk
Keep the exact unfinished action and expected result in Next before undertaking it. At real task boundaries, before an orderly stop and before compaction run `sno handoff-checkpoint` (or the same explicit record path) and update Done, Next and the latest failed operation/target/error. Commit only if the owner authorized it.
When told to ROTATE, pause edits and run $handoff with the specified receiver kind, model and provider.
```

`$join-talk` and `$handoff` are the Codex form; in Claude Code and Cursor write `/join-talk` and `/handoff`.

Checkpoints limit lost progress when A cannot answer. Registration lets the watchman
reach A. A seat marked `stale` is not proof that its agent is gone: check its terminal
or process before treating it as dead.

## Watchman: arm, read, act

The scripts ship under this skill's `scripts/`; use their full paths or put them on PATH.
A next-agent candidate can be tested before arming:

```
rotate-agent-preflight --from codex --to claude-code --cwd <checkout> --sender <A-seat> --model <M> --provider <P>
```

It checks tools, checkout, sender registration, the two selected model quotas, and a
trial receiver's fresh answer. The trial seat is removed. `unread` quota is available;
actual start and answer decide whether it works. Do not arm on a `FAIL`: repair the
named failure or try the next candidate. The preflight is not needed to read a tick.

Create a fresh empty log with `mktemp "${TMPDIR:-/tmp}/heartbeat.XXXXXX"` and a new
state path under `${XDG_STATE_HOME:-$HOME/.local/state}/rotate-agent/<label>.state`.
Arming with Claude Code's tools (other harnesses use their own equivalents):

```
Bash({
  run_in_background: true,
  command: "sno heartbeat --interval 5 --max-hours 0 --label rotate-agent-<work> --log \"<LOG>\" \
    -- rotate-agent-watch --from <agent> --seat <A-seat> --threshold-pct 2 --state \"<STATE>\" --cwd \"<checkout>\""
})
Monitor({
  command: "tail --pid=<from the arm output> -F -n +1 \"<LOG>\"",
  persistent: true,
  description: "rotate-agent ticks"
})
```

Cursor has no `Monitor`: run the same `sno heartbeat` command from Cursor's shell and follow the reader
instruction it prints for a Cursor conversation (the heartbeat skill says how ticks reach Cursor).

`--max-hours 0` removes heartbeat's default 24-hour limit; use a finite value when
requested. Hermes and OpenClaw instead run one background command per tick:
`sleep <interval-seconds>; sno heartbeat --label rotate-agent-<work> --max-ticks 1 -- rotate-agent-watch --from <agent> --seat <A-seat> --state <STATE> --cwd <checkout>`.
Re-arm after each native completion notice. Hermes delivers the notice at the next
turn boundary; OpenClaw delivers during a turn. OpenClaw's command must run without
an approval prompt for its completion notice to arrive. Prefer a separate watchman.

| line | meaning | watchman does |
|---|---|---|
| `HOLD from=… remaining=N% threshold=T%` | above threshold | keep watching |
| `HOLD unreadable …` | sender quota unknown | keep watching; report repeated failures |
| `HOLD no-candidate …` | no available receiver | sender continues; keep watching |
| `ROTATE … verdict=… candidates=[…]` | low remaining share, or `wait`/`owner_action` | walk the candidates below |
| `DONE rotated …` | a real handoff was recorded | wait for COMPLETE |
| `COMPLETE …` | new commit after the recorded handoff | stop this heartbeat |

### Walk every candidate in order

Read `candidates[]`, not just `chosen`. Keep the original model and raw provider from
the triggering line's `sender` object (`--pick`'s `from`). Log each failed operation, agent, model, seat and error;
then take the next candidate. `go`, `short_only` and `unread` candidates are available.

For `in_place:true`, run:

```
rotate-agent-switch --agent <agent> --seat <A-seat> --model <M> --provider <P> --original-model <O> --original-provider <OP>
```

It polls the pane footer every three seconds. The entire first attempt has a
100-second deadline; recovery starts with a fresh 150-second deadline, shortened
only if needed to keep the entire operation within 280 seconds. Timed-out commands
are killed immediately. Each phase prints its elapsed seconds on stderr. Hermes is idle when the last
15 pane lines contain a line starting with `❯` and no `msg=interrupt`, including
when the composer shows a rotating suggestion; OpenClaw must show `connected | idle`. It sends
Hermes `/model M --provider P`, OpenClaw `/model P/M`, Cursor `/model M` through
`sno reach call <seat> <command> --raw`, never as a queued model command. It waits
for idle again and calls `continue` with at most 60 seconds. Confirmation requires
exit status 0 and non-empty reply text; Reach does not return JSON here. Hermes and
OpenClaw use `rotate-agent-answer-provider --agent <agent> --seat <A-seat> --latest --with-model`
to read `<provider> <model>` from the last successful Hermes API call or the last
OpenClaw assistant answer's runtime event. Unanswered background turns do not erase
that result. Without `--with-model`, output remains the provider only. A switch needs
a new assistant answer from P and the selected current model. A logged `custom`
provider also matches a configured custom endpoint name when the answer model is M;
it never substitutes for openai, openai-codex, codex, chatgpt, anthropic, claude,
google, gemini, xai, grok, openrouter, deepseek, nvidia, zai, kimi or minimax.
Only `SWITCH OK` counts.
Then append `switched <UTC-timestamp> model=<M> vendor=<V>` to the state file.
This does not stop the watch: the next tick reads the new model, and another
crossing runs the pick again. Never write `rotated` for an in-place switch.

Failure restores O/OP with the same idle, raw command and confirmed-turn procedure.
`SWITCH FAIL restored=yes` means try the next candidate with the sender still able
to hand off. `restored=no` means all next-agent candidates use resume from disk.

For a next-agent candidate, map `claude-code` to launch kind `claude`, `cursor` to
`cursor-agent`; the other launch kinds match their ids. Pass `--model M` and the raw
`--provider P` to `sno reach spawn`, always with `--window`. Reach initializes an
OpenClaw model while idle before sending its startup context.

When A can answer, send the order:

```
sno reach call <A-seat> "ROTATE: run the handoff skill now; receiver kind <kind>, model <M>, provider <P>, vendor <V>; spawn --window in the same checkout. Verify the receiver answer vendor before release. Report to <owner session>." --expect HANDOFF_RELEASED --timeout 280
```

The handoff skill verifies readiness without writes. Hermes/OpenClaw readiness
must be attributed using `rotate-agent-answer-provider --agent <agent> --seat <B-seat>
--receipt <REACH-RECEIPT-id>` with the call's `deliveryReceipt`. No provider or a
wrong provider fails that candidate before A releases. Claude Code and Codex have
fixed vendors. Cursor uses the integrated seat's concrete model/vendor reading.
An uncertain release is not permission to start competing receivers: inspect the
seat before proceeding. A known start or acknowledgement failure tries the next.

If the crossing was `wait`/`owner_action`, or restoring A failed, use:

```
sno rotate-agent-resume --to <agent> --cwd <checkout> --checkpoint <record> --work <work> --model <M> --provider <P> --report-to <owner session>
```

The record must belong to the same checkout. The command first uses its exact recorded
vendor session identity with `claude -p --resume <id>` or `codex exec resume <id> <prompt>`;
it never chooses an unrelated latest session. Missing identity skips only native resume.
If native resume is unavailable, it rebuilds from the same readable brief, applicable
Reach card and existing scoped memory retrieval in the original vendor when usable.
Known exhausted quota skips both original-vendor entries and uses the selected other
vendor. Unknown quota or authentication failure is not called exhausted quota. If no
other vendor can execute, it retains the brief and says takeover was skipped and no
recovery completed; a quota blocker does not mean task facts were lost.

`MATCH`/`DRIFT` are auxiliary checkout observations for reconciliation, not admission
requirements. B reads the whole record and emits fresh `HANDOFF_READY <nonce>` without
editing. The command checks the existing selected-provider information where applicable,
then sends `HANDOFF_RELEASE <nonce>` and requires `HANDOFF_RELEASED <nonce>` from new
receiver output before B writes. All calls use stored full-text call mail plus one short
cue; no repeated Enter or second handshake. Call mail is transport-only and never an
owned work card. Card-backed work preserves the original chain, actual receiver card
recipient and Reply-To; direct owner work does not invent an original card. The recovery
initiator uses its real authorization and never fabricates a response from an absent A.
An uncertain release needs inspection of that receiver and Reach records: B may own the
work, so never start another receiver. Reach's existing seat/receipt records suffice;
there is no second per-work once file.

Output distinguishes `resumed` (the exact original conversation), `rebuilt` (new
conversation; original conversation lost) and `lost` (essential next-step facts
unrecoverable). Each is separate from `next_action=completed|unfinished|blocked`.
Startup, readiness and release report the action unfinished; they never prove it
completed. Completion requires the receiver's actual next-step result. B maintains the
complete brief at its default `<Sno profile>/station/handoff/<session-id>.md` path for
next-prompt and post-compaction injection, retaining the prior complete record.

B reports the actual next action result and earlier failure to the continuing destination
in the brief (or `--report-to`). A missing optional observation or failed report delivery
does not revoke B's ownership or let A resume competing task writes.
After confirmed transfer append
`rotated <UTC-timestamp> from=<agent> to=<agent> remaining=<N>% commits=<count>`
with the count printed by the triggering tick. Only this real handoff ends rotation
under that state path; another handoff uses a fresh label and state path.

If every candidate fails, report `HOLD no-candidate`; A continues when still able.
Do not make a blind read or a changed model name into success. Hermes provider
comes from the last successful API call in the receipt's turn span, not a subsequent
background notice; OpenClaw comes from the runtime provider of that answer in its
session export. Unknown attribution is failure, and independent work continues.
