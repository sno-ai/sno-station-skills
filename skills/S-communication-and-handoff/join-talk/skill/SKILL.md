---
name: join-talk
description: "Register this agent and terminal with Reach for cards, calls and wake-ups. Use when asked to join, connect, or become reachable, or when a manually opened agent lacks `SNO_EXECUTOR_ADDR`."
requires:
  programs:
    - {name: reach, min_version: "2.0"}
  harness:
    - {slot: 4.shell, need: required}
---

# join-talk

Needs: `jq`, `flock`, and the `sno` CLI with its Reach runtime. Ordinary terminals on macOS,
Linux and Windows WSL are discovered by their input endpoint; there is no terminal-brand allowlist.
Reach offers **Instant Messenger** for a response now and **Agent Email** for saved
messages or tasks handled later. Join Talk registers this existing conversation for both;
it does not start a replacement agent. See the `reach` skill for choosing commands.

Reach is the messaging layer between agents: a seat is one registered conversation with an
address, a card is a stored message, and a ring is the wake-up that asks the agent to read its inbox.
`SNO_EXECUTOR_ADDR` is the environment variable holding that address for agents opened through Reach; a
manually opened agent has none, which is what this skill fixes.

Run this once, from your own shell tool, in the repository you are working on. The script
ships beside this file:

```bash
bash scripts/join-talk.sh
```

(Give the full path of this skill's `scripts/join-talk.sh` under whichever skills root your
harness loaded it from.)

It prints one line, `joined <address>`. Tell the person that exact address, then go back
to what you were doing. Rerunning it from the same terminal changes nothing. The seat is
registered wherever agents on this machine are addressed, so cards, rings and a handoff find
this conversation. Instant Messenger can use threaded mail replies for supported local
and cross-machine calls; it does not always need terminal output capture.
A Cursor IDE chat has no terminal: it is registered by its conversation id (channel `cursor-ide`), and a
card reaches it when its turn ends. Other manually opened agents use their discovered terminal input
endpoint. Codex uses its native message queue when available, independently of the terminal.

For another machine, registration alone is not connection setup. Both machines need
Reach's receiving process and reciprocal contacts (`network` and `peer` in the installed
help). Once configured, give the caller this conversation's exact returned address.
Preserve any collision suffix. Do not promise receipt merely because registration succeeded.
On macOS, Ghostty can also receive input through its scripting interface without a restart.
`sno reach terminal -- <agent command>` gives Reach its own input endpoint in any terminal, including
Ubuntu and Windows WSL, without requiring tmux. Use it when the operating system refuses input into
an already running terminal; preserve the existing conversation with the agent's resume command.
Explain an observed failure and its remedy, never reject an unfamiliar terminal name.

Options, only when the person names them: `join-talk.sh review.example-repo@host1` picks the address;
`--name "Mac Coder"` picks the display name and derives `maccoder.agent@<host>`.
The display name is preserved. The call name is lowercased and removes whitespace and characters
outside Reach's address alphabet (letters, digits and hyphens). Without `--name`, the repository
name supplies the display name. Another terminal using the same call name gets a numeric suffix,
such as `maccoder-2.agent@<host>`. An explicit address is used as given.

## After joining

- A card for you arrives with a ring in this terminal. Read it with
  `sno reach inbox --as <address>`; reading does not accept it.
- Answer a `[CALL]` that requests mail with `sno reach reply --as <address> --card <card>`,
  body on stdin and no `--state`. For task mail, use `--state accepted` before doing the
  work, then `--state completed` or `failed`. The installed Reach guide gives the full lifecycle.

## When it refuses

- `terminal discovery failed` or `no terminal input endpoint` — inspect the actual Reach error.
  A detached shell may have no controlling terminal. Use an agent session endpoint when available,
  or start/resume the agent with `sno reach terminal -- <agent command>` and register there.
- A failed wake is not a failed mail delivery. Keep the original card and fix the named input
  failure; never resend the card or claim the recipient read it merely because input was accepted.
- `sno is missing` — the machine lacks the Reach install (`sno setup` installs it). Tell the
  person; do not retry.
- `jq is missing` or `flock is missing` — install it (`flock` comes from util-linux), then run it again.
- `ORCA_TERMINAL_HANDLE is empty` — an Orca shell without a terminal handle; Reach cannot
  address it. Tell the person; do not retry.
- `Claude Code background session` — this conversation runs in the background (forked, `--bg`
  or a reused spare), so its terminal settings belong to another window and a wake would land
  there. Never register it by hand from those settings. Tell the person the two commands the
  message names: stop it, resume it in the window they want, and join again there.
