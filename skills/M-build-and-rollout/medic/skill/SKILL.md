---
name: medic
description: "Check that this machine's agent team can work and say what is wrong in plain lines: tools installed, core skills installed, skill commands runnable, hooks configured, Reach seat live, a heartbeat running, both vendors' quota readable, temp space free. Checks only, never repairs. Use on a new machine, when agents stop reaching each other or a long run fails to start, or when the owner asks whether everything is healthy."
requires:
  programs:
    - {name: reach, min_version: "2.0"}
    - {name: heartbeat, min_version: "1.0"}
    - {name: subscription-quota-check, min_version: "1.0"}
  harness:
    - {slot: 4.shell, need: required}
---

# medic

`sno medic run` looks at the agent team on this machine and prints one line per check. It reads and
reports; it never installs, repairs, starts, stops or spends anything.

```
OK <check>: <what was found>
WARN <check>: <what is wrong> -> <the command that fixes it>
FAIL <check>: <what is wrong> -> <the command that fixes it>
MEDIC ok=N warn=N fail=N
```

`FAIL` means the team cannot work at all (a required program is missing, no agent command line is
installed, Reach is broken). `WARN` means it works worse than it should. Exit status is 0 when there is
no `FAIL`, 1 otherwise, 2 for a wrong command line.

Prerequisites: bash 4+, GNU coreutils and jq. `sno medic` with no arguments, or `--help`, prints the usage.

## Use

1. Run `sno medic run`. It takes about ten seconds because it asks `sno doctor` and reads both quotas.
2. Tell the owner the result in plain words: the counts, then each `WARN` and `FAIL` line with its fix.
   Do not paste the whole output when everything is `OK`; one sentence says so.
3. Run a fix only when the owner asks for it. Installing and updating change the machine, and one
   warning is often not worth a fix (for example no heartbeat when nothing long is running).
4. After a fix, run `sno medic run` again and read the same line: it must now say `OK`.

## What each check reads

| Check | Looks at | Common fix |
|---|---|---|
| `tools` | `sno`, `jq`, `tmux`, `git` are on PATH, and `sno heartbeat` and `sno subscription-quota-check` run | install the named program |
| `agent-cli` | `claude` or `codex` is on PATH | install one of them |
| `skills` | the six core skills (`reach`, `heartbeat`, `join-talk`, `handoff`, `deliver`, `charter`) exist where each installed agent reads skills | reinstall the skills |
| `commands` | `sno deliver-proof`, `sno handoff-checkpoint`, `sno rotate-agent-resume` and `sno rem-reflect` answer `--help` | reinstall the skills |
| `hooks` | `sno doctor` reports hooks configured (and trusted, for codex) for each installed agent | reinstall the skills |
| `reach` | `sno doctor` reports Reach as ok | the fix `sno doctor` names |
| `skill-files` | every installed skill file passes `sno doctor` | update the skills |
| `seat` | this agent's own seat (`SNO_REACH_ADDR`) is live, or at least one seat is live | run `join-talk` in this window |
| `heartbeat` | at least one heartbeat is running on this machine | arm one when a long job starts |
| `quota` | each installed agent's subscription quota can be read and is not `wait` | log in, or wait for the reset |
| `temp-space` | free space in `$TMPDIR` (or `/tmp`) is at least 500 MB; change it with `--min-free-mb N` | free space or point `TMPDIR` elsewhere |

A check that cannot run because a program is missing prints `WARN <check>: not checked, <program> is
missing`; fix the `tools` line first.

## Limits

`sno medic` does not prove that an agent can answer a prompt or that a seat delivers a message: for a live
receiver test before a vendor switch use `rotate-agent-preflight` (the `rotate-agent` skill), and for a
single unit's behaviour use that unit's own self-test.
