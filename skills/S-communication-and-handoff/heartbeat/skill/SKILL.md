---
name: heartbeat
description: "Set recurring checks or completion watches with `sno heartbeat` and its persistent log reader. Use for periodic reports or unattended long runs. Not for calendar scheduling or commands watched directly."
requires:
  programs:
    - {name: heartbeat, min_version: "1.0"}
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.background-processes, need: required}
    - {slot: 3.reader-to-agent-delivery, need: required}
---

# heartbeat

Use the `sno heartbeat` command installed by `sno setup`. This skill supplies
instructions, not a program copy. If the command names a missing prerequisite, install
that tool and retry. On macOS `coreutils` supplies GNU `timeout` and `tail`; put its
`libexec/gnubin` directory on PATH, and install `bash` and `flock` when required.
Windows requires WSL.

[The bundled command contract](references/heartbeat-contract.json) pins the public syntax
checked by this skill's offline self-test. Use `sno heartbeat --help` for the installed program.

Before arming, verify that this harness provides both background execution and a
persistent reader that delivers new output into the agent's conversation. If either is
unsupported or unverified, skip this skill and name the missing capability. The examples
below require those tools and use Claude Code's `Bash` and `Monitor` tool names; other harnesses use
their own equivalents. A background process or a log file alone is insufficient.

Before either shape, create a fresh empty log with `mktemp "${TMPDIR:-/tmp}/heartbeat.XXXXXX"`.
Use its returned path as `<LOG>` in both calls. Never reuse a previous run's log.
Copy one of these two blocks and set the label, interval and paths. Both calls are required.
When armed, `sno heartbeat` prints its process id and a suggested reader command of the form
`tail --pid=<PID> -F -n0 <log>`. Put that process id in `<PID>` below; the reader here uses
`-n +1` instead of `-n0`, for the reason given under "The one rule".

## 1. Report every so often

A long run you want progress from — training, an exam, a generation queue, a build.

```
Bash({
  run_in_background: true,
  command: "sno heartbeat --interval 30 --label train-1500 --log \"<LOG>\" \
    -- tail -1 outputs/train-1500/metrics.jsonl"
})

Monitor({
  command: "tail --pid=<PID> -F -n +1 \"<LOG>\"",
  persistent: true,
  description: "train-1500 ticks"
})
```

`--interval 30` is thirty MINUTES. **A bare number is minutes, never seconds**: `--interval 5`
is five minutes, and a seconds habit like `--interval 600` is refused outright rather than
read as ten hours. Add a unit to override: `30s`, `10m`, `2h`. `--every` is accepted as the
same flag.

Every tick arrives as one message carrying the hook's latest output (the hook is the command after `--`). **Say what it says** — a
tick you receive and do not pass on is the same silence as no tick at all.

## 2. Wait until something is done

The commonest job there is, and the one most often replaced with three lines of homemade shell.

```
Bash({
  run_in_background: true,
  command: "sno heartbeat --label build --until-file out/result.json --log \"<LOG>\""
})

Monitor({
  command: "tail --pid=<PID> -F -n +1 \"<LOG>\"",
  persistent: true,
  description: "build ticks"
})
```

No interval and no hook needed. Each tick says `waiting`, which is the proof it is still alive;
when the file finally has content the heartbeat ends by itself and its last message says
`FINISHED`. The file is checked every second whatever the interval is. `--until` is accepted
as the same flag.

**Before you pick the file, prove it is a completion marker.** Read the job's own code and
confirm it writes that path ONLY at the end. Most jobs create their output — a results file, a
log — the moment they start, and a log grows content on the first line, which ends the watch
hours early. If you cannot prove the file appears only at the end, do not use `--until-file`:
arm shape 1 with an interval instead and let the ticks and the wall clock cover you. Two
guards catch the commonest halves of this mistake for you: a path that already exists at arm
time is refused (exit 2), and an empty file appearing later does not end the watch — but a
file the job starts writing early is yours to rule out, and only the job's code can rule it
out.

## The one rule

**The tick is guaranteed to happen. Being told is not — you have to attach a reader.**

Ticks land in a file, and a file reaches nobody on its own. Arming a heartbeat and walking away
is silence, which is the exact thing it exists to prevent. So arming is always two steps, and
the second one is not optional. Use the PID and log path printed when you arm, but read
from line one with `tail --pid=<PID> -F -n +1`. If the printed reader command uses `-n0`, use
`-n +1` instead: `-n0` skips lines already in the log and can lose a completion that arrived
before the reader attached.
The fresh per-run log prevents old results from being replayed. GNU tail delivers the
existing lines even if the heartbeat has already exited, then ends; `--pid` also retires
a reader attached while the heartbeat is still running. Quote the returned log path.

Once the reader is attached, the guarantee holds all the way through:

| | |
|---|---|
| **the tick** | happens on schedule, always writes a line, cannot be stopped by the hook |
| **the reader** | turns every one of those lines into a message you receive |
| **the hook** | may fail, hang, print nothing, or not exist — it is recorded, never obeyed |

A hook that breaks is *fine*: the tick still lands, you are told, you read the failure and fix
it. Being told is what makes the failure repairable.

**Never write the waiter yourself.** Not `until [ -f X ]; do sleep 60; done`, not a polling
script, not a progress reporter with a little parsing in it. Homemade waiters have no wall
clock, so a wrong path waits forever; they leave no trace, so silence proves nothing; and any
logic in them can raise, after which the wake-up is simply gone. This command has all three
covered and costs one line.

## What every ending tells you

When it stops, it says which ending it was — on **stdout**, so the notification that wakes you
carries the answer:

```
heartbeat: FINISHED [build] out/result.json has content (after 37 ticks)
heartbeat: NOT FINISHED [build] reached --max-hours 24 (after 288 ticks)
heartbeat: STOPPED [train-1500] signalled (after 12 ticks)
```

**`NOT FINISHED` means the thing you waited for never arrived.** Giving up can never read as
succeeding, which is the failure that lets an agent report a run that never finished.

## Flags

- `--label` name written on every line, and the name you stop it by (**required**;
  `--name` is the same flag)
- `--interval` time between ticks, in MINUTES (**default 10**). A bare number is minutes; a
  unit overrides it: `30s`, `10m`, `2h`. A bare number above 120 is refused rather than
  guessed at. `--every` is the same flag. Every tick becomes one message once the reader is
  attached, so this is a real cost: ten minutes over five hours is thirty messages. It does
  not affect how fast `--until-file` is noticed — that is every second, except while a hook
  is actually running (the hook is bounded at half the interval)
- `--log` file to append to (**default**: one under the state directory, path printed on arm);
  one write per line, so a tail never sees half of one
- `--until-file` stop cleanly once that path **holds content** (`--until` is the same flag).
  It must not exist yet when you arm, and it must be a path the job writes only at the end —
  see shape 2
- `--max-ticks` optional bound on the number of ticks. Reaching it ends with `STOPPED` when there is no `--until-file` (the expected ending of a fixed-count watch) and with `NOT FINISHED` when there is one
- `--max-hours` **default 24**, so a forgotten heartbeat stops itself. A default, not a ceiling
  — `--max-hours 48` for a two-day run, `0` to remove the limit entirely
- `--` everything after it is the hook, run once per tick; optional when `--until-file` is given

## Starting and stopping

**Use `run_in_background`, not a trailing `&`.** A foreground call ends when the tool call
returns, and the heartbeat can go with it — a wake-up that dies at birth is the exact failure
this exists to prevent.

Three ways down, best first:

1. **Let it end itself.** `--until-file` — the job's own output ends the watch, and nobody has
   to remember anything.
2. **Stop it when you decide.** `sno heartbeat --stop train-1500` — the thing was found, the
   question was answered, the hook is no longer worth running.
3. **The wall clock.** `--max-hours`, default 24. A heartbeat nobody stopped still stops.

`sno heartbeat --list` shows everything running on the machine, yours marked `you`.

Never kill a heartbeat by pid or by `pkill`. `--stop` knows which one is yours; a pattern
match does not, and a loose one matches the shell doing the matching.

## Many agents at once

**A label is not an address. The address is (owner, label).** The owner is the agent session
that armed the heartbeat; it is read from your
session, never typed on the command line, and three rules follow:

- **Two agents may both use `card-B`.** Different addresses; neither can see the other's.
- **You may not use `card-B` twice.** The second arm is refused, so you never end up with two
  heartbeats reporting the same job and no way to tell them apart.
- **`--stop` reaches only your own.** Another agent's is visible in `--list` and is not yours to
  stop. If its session is gone, its wall clock ends it.

There is no lock. Heartbeats share nothing, so nothing is serialized and no agent ever waits on
another. A claim left behind by a process that died is cleared automatically the next time
anyone arms, stops, or lists.

## Reading the log

```
2026-01-01T14:44:09Z [train-1500] tick=7 ok step 700 | loss 0.153
2026-01-01T14:44:09Z [train-1500] tick=8 hook FAILED status=1 (no output)
2026-01-01T14:44:09Z [train-1500] tick=9 hook TIMED OUT after 900s
```

`tick=` counts up by one every time. **A gap in that number is the only way a missed tick can
show, so read it.** A `FAILED` or `TIMED OUT` line means the hook needs fixing, not the
heartbeat. A hook gets at most half the interval before it is killed, and its output is cut at
600 bytes at the source, so a flooding hook cannot take the tick down with it.
