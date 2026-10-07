---
name: subscription-quota-check
description: "Read remaining Claude Code and Codex subscription quota without spending it. Use when the user asks or after a vendor rejects work for quota; a caller such as rotate-agent may also arm a scheduled read on purpose. Never poll on your own; after a `wait` verdict, pass the reset wait to `sno heartbeat` and re-read once when it ends."
requires:
  programs:
    - {name: subscription-quota-check, min_version: "1.0"}
    - {name: heartbeat, min_version: "1.0"}
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.background-processes, need: preferred}
    - {slot: 3.reader-to-agent-delivery, need: preferred}
---

# subscription-quota-check

## The one rule

**Read it on demand: when the human asks, or when something was actually blocked.**

This skill is not a monitor and never schedules a read of its own, apart from the single re-confirmation read after a `wait` verdict (see "When it says wait"). The Claude usage endpoint
is itself rate limited, so a probe on a timer eventually earns a 429 and starts serving
cached numbers — a checker that reports confidently while reading nothing. A caller such as
rotate-agent may arm a scheduled read deliberately; that is the caller's decision, and the
rate-limit risk is then the caller's to manage. Outside such an armed schedule, every run
must trace to one of the two moments above.

The anti-pattern it replaces has a name: **finding out you are out of quota by making a real
call and reading the error.** That spends quota to learn you have none, and the error does
not say when it comes back. This reads the same state for free and tells you the reset time.

## Running it

Use the command installed by `sno setup`, with the installed `sno heartbeat`
command for the wait branch. If a command names a missing prerequisite, install that
tool and retry. On macOS use `bash`, `jq`, and `coreutils` for the named shell/JSON/GNU
tools; put `coreutils/libexec/gnubin` on PATH. Windows requires WSL. Only the wait
branch needs `sno heartbeat`, a proven background process and a reader-to-agent delivery path;
if either capability is unsupported or unverified, skip the wait branch and name the missing
capability. The read itself needs none of them.

[The bundled command contract](references/subscription-quota-check-contract.json) pins
the public syntax and verdicts checked by this skill's offline self-test. Use
`sno subscription-quota-check --help` for the installed program.
The wait example is checked against its own bundled
[heartbeat contract](references/heartbeat-contract.json).

```
sno subscription-quota-check [--vendor codex|claude|both] [--json|--human] [--quiet]
```

`--vendor` defaults to `both`. `--human` is the default on a terminal, `--json` everywhere
else. A vendor whose CLI is not on PATH is reported as `unknown` for that vendor (so a
`both` run exits 3); a single-vendor user should pass `--vendor codex` or `--vendor claude`.
One run is ~8 s: about 1 s for Codex, and ~7 s for Claude because its structured answer is
also checked for staleness against the Claude CLI's own text `/usage` report, the only place
that says when the numbers are last-known rather than current.

## What comes back

A verdict per vendor, and one overall. The exit code carries the same answer, so a caller
can branch without parsing.

| verdict | exit | means |
|---|---|---|
| `go` | 0 | the tightest window still has headroom |
| `short_only` | 0 | usable, but the tightest window is nearly full — do not start long work |
| `wait` | 1 | blocked now; `seconds_to_reset` says for how long |
| `owner_action` | 1 | a workspace limit blocks work; contact the workspace owner instead of waiting |
| `unknown` | 3 | could not be read, or the numbers could not be shown to be current |
| `needs_auth` | 4 | credentials need refreshing — this is NOT out of quota |
| `n/a` | 0 | not a subscription session (API key / Bedrock / Vertex); plan limits do not apply |

`short_only` is a threshold decision, and the threshold is one number inside the installed
program: in the current release `short_only` means less than 20% of the tightest window
remains. It is **picked, not measured**: a single reading says how much is used, never how fast it burns, so nothing here can prove a long job will fit. Owning one
number beats every caller inventing its own. Use the installed program's verdict; do not
edit installed releases or infer a different threshold in the skill.
Every JSON envelope reports the threshold it judged by, so a reading is never unattributable.

`tightest_window` names the window the verdict came from, so `short_only` is never a mystery.
In the JSON envelope each vendor is one entry of `vendors[]`, with `verdict` and
`tightest_window.{used_pct,seconds_to_reset}`.

## When it says wait

Take `seconds_to_reset` from the **blocking** window. Set `delay_seconds` to that value
plus five seconds, then arm `sno heartbeat` using its background-and-reader procedure with:

```sh
sno heartbeat --label quota-reset --interval "${delay_seconds}s" --max-ticks 2 --max-hours 0 -- date -u
```

The first tick runs immediately; it is only an arming observation. Do not query quota
on that tick. The second tick arrives after the delay and ends this bounded watch.
On that second tick, run `sno subscription-quota-check` once and inspect its fresh verdict.
In this wait, never put the quota command in a recurring hook. `--max-ticks 1` would finish immediately
and would not wait for the reset. The watch ending is not proof that quota has reset.
If the fresh verdict is still `wait`, create a new bounded watch from its new blocking
reset value. Reuse a label only after the prior watch has ended.

**Re-confirmation is not optional.** The reset instant belongs to the server and it can move;
only a fresh read proves a block is gone. And never hand-write the waiting itself — a loop
that polls is banned here for the same reason it is banned everywhere: a dead waiter looks
exactly like a quiet one.

Never schedule from an idle window. An unconsumed window reports `now + window length` and
slides forward every time you ask; only a consumed window reports a real instant.

When it says `owner_action`, do not arm a wait. Report `required_action` to the workspace owner. A
workspace credit or usage limit does not clear when the account's rate window resets.

## Five things that stay true

1. **Never redeem a usage reset.** Next to the read-only usage request, the vendor tools
   offer an action that spends a finite, purchasable reset credit. Neither this skill nor the
   program's read path may call it.
2. **A window's length is not a wait.** A weekly window can be minutes from resetting.
   Deriving the wait from the window length sleeps a week.
3. **Not logged in is not out of quota.** They exit 4 and 1 for a reason; reporting the first
   as the second sends someone to wait for a reset that was never coming.
4. **Numbers that cannot be shown to be current are not reported.** The Claude structured
   usage answer can serve up to an hour of cached data with no flag saying so. When freshness cannot be
   established the answer is `unknown`, never a percentage.
5. **Every reading names its host and the CLI build it came from.** These describe the
   accounts these two CLIs are logged into, on this machine. They do not measure accounts reached through a
   custom endpoint (for example the `OPENAI_BASE_URL` environment variable) or on any other host. If none is set, say
   "using the harness's own endpoint" and continue; do not infer another account's quota.

## Version fragility, stated plainly

Neither vendor offers a supported way to read this. The Codex path rides `codex app-server`,
which its own documentation calls experimental and unsupported for production, and whose
method names move between builds. The Claude path uses a `get_usage` control request that its own schema
describes as experimental. Both are pinned to observed builds, and both must be re-verified
after either CLI updates.

So a shape change is expected, not exceptional. It surfaces as `unknown`, which is the
correct answer. Retain the reported reason and CLI build, and report the mismatch to the
Sno Station maintainers. Update through `sno setup` after a verified fix; do not loosen
a check or substitute a cached percentage to make it green.
