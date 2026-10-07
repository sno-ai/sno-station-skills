---
name: catch-report
description: "Report how many problems the two brains found: mutual review (the other model checks the work, from the peer-review records) and self-check (an agent finds its own error in its own conversation, judged by that agent's own model), side by side. Use when the owner asks whether the second agent or the reviews are worth it, or wants the week's review results."
requires:
  programs: []
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
---

# catch-report

The product claim is two brains: one does the work, another checks it. `sno catch-report` puts numbers on that
claim from records already on this machine. It changes nothing.

- **Mutual review** is every review the `peer-review` skill recorded: a different model read the work and
  reported problems. `sno catch-report run` prints those numbers.
- **Self-check** is an agent finding its own error inside one conversation. `sno catch-report self` reads the
  agents' own conversations (`~/.claude/projects`, `~/.codex/sessions`), picks the moments where an agent
  reacted to a failing command or test, or admitted a mistake, and asks that agent's own model (claude
  judges claude conversations, codex judges codex conversations) whether the agent found the error itself or
  was told. It then prints the two side by side.

Prerequisites: bash 4+, GNU date, find and grep, and jq. `self` also needs the `claude` and/or `codex` command
line, logged in.

## Use

1. To show the user what the two brains caught, run `sno catch-report brief --since 7d` (or `12h`, `30m`, `30d`, or a
   date). It measures both and prints one page: a headline with the problems the second model caught and the moments in which the agents caught their own mistakes (kept apart, never added together), the second brain's
   numbers with its biggest catches quoted by title, the agents' own catches in their own words, and how to read
   the numbers. Tell the user first that the self-check part sends short excerpts of their conversations to their
   own claude or codex (100 by default, about four minutes, it costs tokens); `--limit N` changes that, and
   `--agent claude` or `--agent codex` narrows it.
2. Hand the page to the user as printed, headline first, in English: do not translate it or re-word it. Keep every number and the plausible range exactly as
   printed, keep the quotes, and keep the "How to read this" notes. Do not round up, do not add a claim the page
   does not make, and do not say the findings are "real problems" or whose work was wrong: the records hold no
   author and most findings are undecided. You may add one sentence on what stands out.
3. When the page says the self-check could not be measured, say that; do not report a zero. The self-check count
   is an estimate from a sample when there are more moments than `--limit`, and only sees errors an agent said
   out loud within ten steps of a failure or in a known admission phrase (English and Chinese); quiet fixes are
   not seen.
4. For the details behind a number: `sno catch-report run` prints the review records (reviews started, finished,
   refused and never finished; per reviewer model the high and medium findings, `fix-now` and `debt`; verdicts;
   the five reviews with the most `fix-now`; findings the owner has ruled on), and `sno catch-report self --list`
   prints each self-check moment with the model's verdict. Both take `--stats FILE` and `--findings FILE` for
   records kept elsewhere. The records are `~/.local/state/codex-review-stats.jsonl` and
   `~/.local/state/codex-reviews/findings.jsonl`.
5. To make the ruled column mean something, rule on findings with
   `review-findings.sh set <id> accepted|rejected|superseded` (the `peer-review` skill); this command never
   rules on anything.
