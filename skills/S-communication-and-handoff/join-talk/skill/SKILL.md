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

Needs: tmux (or the optional Orca app) as the terminal, `jq`, `flock`, and the `sno` CLI with its Reach runtime.
Reach is the messaging layer between agents (see the `reach` skill): a seat is one registered terminal with an
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
this terminal; `sno reach call` works for a tmux terminal, not for an Orca one.

Options, only when the person names them: `join-talk.sh review.example-repo@host1` picks the address;
`--name Fjord` picks the display name. Otherwise the address is `hand.<repo>@<host>` and the
name is the repository name.

## After joining

- A card for you arrives with a ring in this terminal. Read it with
  `sno reach inbox --as <address>`; reading does not accept it.
- Answer with `sno reach reply --as <address> --card <card> --state <state>`, body on stdin.
  The installed Reach guide (`sno reach --help`) shows the card shape and states.

## When it refuses

- `no terminal to be reached at` — this shell is under neither tmux nor the optional Orca
  app; nobody can ring it. Tell the person; do not retry.
- `sno is missing` — the machine lacks the Reach install (`sno setup` installs it). Tell the
  person; do not retry.
- `jq is missing` or `flock is missing` — install it (`flock` comes from util-linux), then run it again.
- `ORCA_TERMINAL_HANDLE is empty` — an Orca shell without a terminal handle; Reach cannot
  address it. Tell the person; do not retry.
