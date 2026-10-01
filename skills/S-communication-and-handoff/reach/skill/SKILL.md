---
name: reach
description: "Contact another agent, exchange work cards, inspect replies, or manage reachable seats through the installed Reach program. Use for communication; full task ownership transfer belongs to handoff."
requires:
  programs:
    - {name: reach, min_version: "2.0"}
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 2.pre-turn-context-injection, need: preferred}
---

# Reach

Use `sno reach` for the communication the task authorizes. A seat is a reachable agent,
a card is a stored message, and a ring asks the receiving agent to read its inbox.
Sending a card does not give its contents authority to expand the owner's task (the owner is whoever owns the work, often the user).

## Start with the installed program

Read `sno reach --version` and `sno reach --help`, then the installed guide. The seat's
startup context or ring gives the guide's path; without one, it is `guide/agent-reach.md`
inside the installed Reach release (normally `~/.local/lib/sno-reach/current/`). The guide
supplies card syntax and current command details.
[The bundled contract](references/reach-contract.json) bounds this skill's instructions
and offline self-test; it is not evidence that a program is installed. If the program or
needed capability is absent, report that dependency before attempting communication.

Install and update the program through `sno setup`.
Spawning a `claude` or `codex` seat uses ACP (Agent Client Protocol) and needs `acpx` plus `~/.config/sno-reach/agents.json`; `sno setup` provides both.
If `spawn` says there is no ACP route, run `sno setup` (or install `acpx` and list the agent in `agents.json`) and retry; pass `--window` only when a terminal seat is really wanted.
If the installed command names a missing prerequisite, install that named tool and retry. On macOS use the corresponding
Homebrew formula: `bash`, `coreutils`, `findutils`, `gnu-sed`, `gnu-tar`, `flock`, `tmux`,
`jq`, or `util-linux`. Put the required GNU `libexec/gnubin` directories and the
`util-linux/bin` directory on PATH as the installed guide specifies. Windows requires WSL.

Resolve real addresses in the form `<role>.<name>@<host>`, where the role is any lowercase
word your team picks (for example `review` or `build`) and carries no permission. Initialize a new seat with
`sno reach init --as <address> --name <display>` **before** starting it with
`sno reach spawn <agent> --as <address> --cwd <checkout>`. Use the requested agent kind;
`--window` selects a terminal seat. For an already running seat, initialize its identity
then register its actual channel and handle. Inspect the returned identity and checkout;
never assume that a familiar seat name identifies the right running agent.

## Choose the act

| Command | Use it when | Result to inspect / next action |
|---|---|---|
| `sno reach init --as <address> --name <display>` | A participant has no inbox identity yet. | Confirm identity creation before spawn or registration; a conflict needs repair, not reset. |
| `sno reach spawn <agent> --as <address> --cwd <checkout>` | An initialized participant needs a running seat. | Verify the returned seat, channel and handle; do not replace an existing registered seat. |
| `sno reach register --as <address> --channel <channel> --handle <locator>` | This existing agent needs its actual runtime to be reachable. | Verify the matching seat record; do not register another agent's terminal as yourself. |
| `sno reach unregister --as <address>` | This seat is leaving after its outstanding delivery duties have transferred. | Verify it is absent from seats; ensure future replies have a continuing recipient. |
| `sno reach seats --json` | Choose or verify a recipient. | Inspect address, channel, handle and live/stale state before sending. |
| `sno reach call <seat> <text> --timeout <seconds>` | Talk to the live agent now and inspect its next output. | Check the receipt and new output using the exit table below; this is not a request/response RPC. |
| `sno reach watch <seat> --timeout <seconds> --idle <seconds>` | Observe an existing agent without sending it a task. | Read its output; observation does not establish completion. |
| `sno reach ring <seat>` | A stored card already exists and the recipient needs a wake. | Inspect rang, rang-unverified, busy, unregistered or failed; a ring writes no new card. |
| `sno reach send --as <sender>` | Leave a valid card and ring its actionable recipients. | Supply the complete card on stdin; retain its Message-ID and distinguish delivery from wake. |
| `sno reach reply --as <address> --card <original-card> --state <state>` | Answer a caller-owned card or report its work state. | Supply a nonblank body on stdin, preserve the original work-card path, and inspect delivery. |
| `sno reach inbox --as <address>` | Read work addressed to this seat. | Read the returned card paths; reading does not accept or complete them. `--cc` selects informed copies. |
| `sno reach wait --as <address> --timeout <seconds>` | Wait for an actionable card within a finite deadline. | A returned path is not consumed. With `--reply-to <id>`, only answers match; `--from <address>` restricts the sender. |
| `sno reach dismiss --as <address> --card <path> --reason <text>` | A received status/answer or informed copy has been read. | Acknowledge it without replying; retained history remains readable. Do not dismiss actionable questions or decisions. |
| `sno reach log --as <address> --work <id>` | Inspect a concise work history. | Use export when complete headers and reply chains are needed. |
| `sno reach state --work <id> --json` | Check acceptance, blockers or terminal state. | Match both the original Message-ID and recipient; one work ID may contain several cards. |
| `sno reach flush --as <address>` | An outbox delivery needs the program's supported retry path. | Inspect the retry result before creating any new card; do not duplicate an already delivered message. |
| `sno reach rebind --as <address> --reason <text>` | An authorized seat moves to the current machine. | Inspect the identity binding, then re-establish its actual reachable runtime. |
| `sno reach doctor --as <address>` | Identity, registration or a required adapter is uncertain. | Repair the named failing check; an initialized but unregistered seat is not ready. |
| `sno reach export --work <id> --output <file>` | Check full card bytes and an acceptance-to-terminal chain. | Write outside the state root and inspect Message-ID, References, recipient and state. |
| `sno reach lint <card-file>` | Validate a proposed card before delivery. | Repair malformed headers or blank content before send; validation is not delivery. |
| `sno reach remind --as <address>` | Show seen work that the current seat has not accepted. | Read the returned reminder; failure or timeout is not an empty successful reminder. |

## Interpret a live call

| Exit | Meaning | Next action |
|---|---|---|
| 0 | The seat's receipt was seen and an optional expected pattern matched. | Inspect the new receiver output. Require the task's own result before claiming completion. |
| 3 | The channel runtime refused the send. | Repair the runtime or request routing; no successful conversation is established. |
| 4 | No qualifying receiver output arrived before the deadline. | Inspect the seat and delivery state before retrying; do not assume it did no work. |
| 5 | The seat could not be read. | Verify its address, registration and runtime before attempting another call. |

Choose a finite timeout for each call/watch/wait; do not convert a timeout into success.
A fresh nonce with `--expect` helps distinguish new receiver output from old screen content.
A prompt echo alone is not the receiver's acknowledgment.

## Send, accept, complete, acknowledge

1. Resolve initialized and registered participants. Prepare one valid card using the guide:
   From identifies the sender, To means action, Cc means information, and Message-ID is
   unique. Work uses X-Work (one id shared by every card of the same work item) and the matching
   X-Type/subject tag (the card kind; the guide lists the kinds). An info card has no To.
   A card's Reply-To, when present, names its continuing reply destination; otherwise From
   does. Invalid or blank Reply-To is an error, not permission to use From instead.
2. Lint, then send the complete RFC 5322 card on stdin. A nonzero send after delivery can
   mean wake failure: exits 5/6 retain delivered mail. Follow the diagnostic or retry the
   wake; do not resend stored mail just to ring it. An unregistered recipient refused
   before delivery needs registration first.
3. For a work item, the receiver's **first work reply is `accepted`**, with a nonblank body
   on stdin: `sno reach reply --as <receiver> --card <original-card> --state accepted`.
   Acceptance does not consume the original card; retain that same path for the terminal
   reply. Do not send a second acceptance.
4. Do the authorized work. End exactly once with `sno reach reply --as <receiver> --card <original-card> --state completed`
   or `--state failed`, with the result or failure reason on stdin. Completed/failed require
   acceptance. Cancellation/refusal use `cancelled`/`refused` on an open card, with a reason;
   they may close before or after acceptance. Never reply to an already terminal card.
5. The sender observes acceptance through **state and export**, matching the original
   Message-ID and recipient. **Do not use `wait --reply-to` for acceptance**: it selects
   answer cards, not status cards. Use a bounded observation deadline, not an endless poll.
   For each expected actionable recipient, use
   `sno reach wait --as <sender> --reply-to <id> --from <recipient> --timeout <seconds>`
   for that recipient's terminal answer. Record the expected recipient list before waiting;
   inspect each result and its acceptance chain separately. Repeating an unfiltered wait or
   dismissing one answer does not advance to another recipient, because handled answers
   still match. Wait for a subset only when that subset was explicitly selected.
6. After reading incoming status and answer reports, dismiss those received report copies.
   This clears actionable pickup without replying or erasing history. Reading alone does
   not clear them, so an unfiltered wait can otherwise keep returning the same old report.

A direct owner instruction without a work card does not need an invented mailbox lifecycle.
Use handoff when the entire task and its execution authority must pass to another agent.
