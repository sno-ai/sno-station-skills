---
name: sno-cli
description: >-
  Operate the `sno` command-line tool: install, update, check, and uninstall Sno
  products, read the exact commands and flags of the installed version, and run the
  account, skills, onboarding, Station telemetry and REM commands. Use when the owner or
  a task says "sno", "Sno CLI", "sno setup", "sno update", "sno doctor",
  "sno uninstall", "sno station", "telemetry consent", "rem verdict", "sno account",
  or "sno skills". The exact flags always come from the installed binary, never from
  this file. Do not use it to decide the owner's choices for them.
requires:
  programs: []
  harness:
    - {slot: 4.shell, need: required}
---

# Sno CLI

`sno` is one binary. This file carries the rules, the task map and the recipes. The exact
commands and flags of the version that is installed are served by the binary itself, so they
cannot be out of date.

## Start Here

Choose the executable once and keep using it:

- Use the absolute path the installer printed.
- Otherwise run `type -a sno` (works in bash and zsh). If two `sno` files are listed, or the version is older
  than the installer said, tell the owner, use the newer absolute path, and note that a
  running shell may need `hash -r` or a new terminal.
- If `sno` is not installed, say so. Do not look for its source.

In every command block, `sno` stands for that absolute executable. Then read the reference
for this exact version, once:

```text
sno --version
sno skills get cli
```

Treat `sno skills get cli` as the authority for every flag. If it is not offered (an older
binary), tell the owner to run `sno update`, and meanwhile read `sno --help` and
`sno <group> --help`.

## Conventions

- Pass `--json` when you parse the output. Stdout is then exactly one JSON value.
- A command you typed incompletely or inexactly is completed, or answered, instead of failing:
  - Unique prefixes of subcommands and flags work: typing sno stat runs sno station.
  - A missing value gets a default, and a note says which (`notes` in JSON, the first line in text).
  - When nothing sensible can run, you get guidance: a JSON object with `"usage": true` and
    `"executed": false`, or full help plus an example, and the exit code is 0. A normal result has
    no `executed` field; a missing `executed` means the command ran.
- After a command that is meant to change something, read the result before you tell the owner it
  worked. A value that does not match is not applied: for example `sno station telemetry consent set`
  with a misspelled level only shows the current level and a note, and the exit code is still 0.
  Check that the returned value is the one the owner chose, and that `executed` is not `false`.
- A real failure keeps a non-zero exit code and its message says what to do next. Report that
  message to the owner; do not retry in a loop.
- Anything that changes the machine is run only when the owner asked for it.

## Task map

| Task | Command |
|---|---|
| Install the default product, or a chosen one | `sno setup`, `sno setup <product>` |
| Update the CLI and installed products | `sno update` |
| Health of programs, skills and Station | `sno doctor` |
| Project memory and improvement records | `sno project status`, `sno project list` |
| Remaining model allowance | `sno usage` |
| Uninstall | `sno uninstall`, `sno uninstall <product>`, `sno uninstall all` |
| Machine identity | `sno account machine register`, `sno account machine claim` |
| Agent instructions served by the binary | `sno skills list`, `sno skills get <name>` |
| Reply to an optional product offer | `sno products answer` |
| Configure and prove Station | `sno onboarding status`, `sno onboarding apply`, `sno onboarding verify` |
| Telemetry choices and export | `sno station telemetry consent get`, `pause`, `resume`, `export` |
| Verify a stored event | `sno station audit verify` |
| Local REM jobs | `sno station rem-start`, `sno station rem-status` |
| REM runs and verdicts | `sno rem judge`, `sno rem recall`, `sno rem verdict` |

Flags are not listed here on purpose; read them from `sno skills get cli`.

## Recipes

### Report a fresh install to the owner

```text
sno --version
sno doctor --json
sno skills get core
```

Tell the owner the version, where it is installed, and the one next step. Station onboarding
questions and product offers are put to the owner as questions; you never answer them.

### Check health

```text
sno doctor --json
sno project status --json
sno usage --json
```

`doctor` exits 0 on warnings. Read the rows whose result is `failed` or `missing` and relay
each with its fix. If `usage` says the machine is not registered, tell the owner and offer
`sno account machine register`.

### Update

```text
sno update --json
```

Any `sno` command also starts a background update check once a day, so a manual update is for
when the owner asks or a command says the version is old.

### Uninstall

```text
sno uninstall
sno uninstall sno-station
sno uninstall sno-station --yes
```

The first two only list and explain; nothing is removed. Uninstalling is the one action that is
asked about even when the owner just told you to do it, the same way `rm -rf` is: a request such
as "uninstall sno-station" is not the confirmation. Run the first two, show the owner what will be
removed, ask "Uninstall now?", and stop. Run the third only after the owner answers yes in a
later message. If there is no later message, your answer is the plan and the question.
`--purge-state` also deletes Reach mail state; ask for that separately.

### Local REM jobs

```text
sno station rem-start --type noop --scope persona:demo
sno station rem-status --wait --timeout 60
```

`rem-status` without an id reads the most recent job started on this machine.

## Owner-only actions

Ask the owner, and wait for the answer, before you:

- set a telemetry consent level (`sno station telemetry consent set`) or pause or resume it;
- record an answer to a product offer (`sno products answer`);
- send a human verdict on a REM judgment (`sno rem verdict`);
- run `sno uninstall … --yes`, or `--purge-state` — even when the owner's own request was to uninstall.

Reading is always fine: `consent get`, `products answer` with no arguments (it lists), `doctor`,
`usage`, `skills`, `project`.
