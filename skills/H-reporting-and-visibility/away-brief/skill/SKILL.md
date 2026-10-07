---
name: away-brief
description: "Give the owner one page when they come back from sleep, a meeting or a long run: what got done, what is stuck, what waits for their answer, and what it cost in quota. Use when the owner asks what happened while they were away, wants a status page, or when you finish a long stretch of work and must report it."
requires:
  programs:
    - {name: reach, min_version: "2.0"}
    - {name: heartbeat, min_version: "1.0"}
    - {name: subscription-quota-check, min_version: "1.0"}
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
---

# away-brief

`sno away-brief run` reads what already exists and prints one page of at most 60 lines. It changes nothing
except its own list of quota readings, and Reach, which may note that it has seen the cards that the inbox
read listed (it never moves, accepts or finishes them).

```
## Done       new commits, charters delivered since the cutoff (with how many checks are proven),
              progress records that finished or are still going
## Stuck      charters not finished (with the numbers of the checks not yet proven), progress records
              with tasks left that nobody has touched for two hours
## Needs you  Reach cards of type question or decision waiting in the inbox
## Spend      your heartbeats, and each vendor's quota now with the change since the last reading
```

A source it cannot read prints `not read: <what> -> <why>` and the rest of the page still prints. Each section has
its own share of the 60 lines; items beyond it are replaced by an `and N more not shown` line, so a long Done list
never pushes out what waits for the owner or the quota.

Prerequisites: bash 4+, GNU coreutils, git and jq. It uses `sno deliver-proof` (the `deliver` skill) to count
proofs, `sno reach inbox`, `sno heartbeat --list` and `sno subscription-quota-check` when they are installed.

## Use

1. Run `sno away-brief run --since 12h` in the project's git folder. Change `--since` to the time the owner
   left (`8h`, `2d`, or a date). Add `--repo DIR` for each other repository and `--charters DIR` for
   folders that hold charters or progress records outside those repositories. Add `--as <your seat>` (or
   set `SNO_REACH_ADDR`) so the inbox is read.
2. Read the page and tell the owner the three things that matter most, in plain words: what is finished,
   what is blocked and why, and what needs their answer. Keep the page's evidence paths so they can open
   the file. Do not add work that is not on the page.
3. Quota: a reading shows usage now, not spend. When the owner is about to leave, run `sno away-brief mark`
   once; it stores a reading, so the next page can show what was spent since. Without an earlier reading
   the page says so instead of guessing.

## What the page can and cannot say

- "Done" is only what is in git, in a delivered charter, or in a finished progress record. Work that was
  never committed or recorded does not appear.
- "Stuck" is a charter whose recorded proofs are missing or failing, or a progress record (written by
  `sno handoff-checkpoint`) with tasks left and no update for two hours. An agent that is busy but does not
  write records looks quiet.
- "Needs you" is only the seat you name. Questions sent to other seats are not shown.
- The change in quota compares two readings of the same window; if the window reset in between, the page
  says so instead of showing a negative number.
