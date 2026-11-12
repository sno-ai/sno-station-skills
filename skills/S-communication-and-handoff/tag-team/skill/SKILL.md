---
name: tag-team
description: "Put two agents on one task: one builds, the other reviews what it built, and they settle the findings between themselves. Use when asked to pair agents, tag-team a task, or have work built and reviewed without the person carrying it between agents. Not for reviewing work that already exists (peer-review) or for passing a task on (handoff)."
requires:
  programs:
    - {name: reach, min_version: "2.1.7"}
  harness:
    - {slot: 4.shell, need: required}
---

# tag-team

One command starts two new agents on the same task in the current project folder. The first
implements. The second reads the result and the changed files and answers with concrete
defects or an explicit no-defect result. Their assignments tell them to keep exchanging fixes
and reviews through Reach, the messaging layer between agents (see the `reach` skill). The
command itself brings back only the first review; following the rest is your job (below).

Needs: the `sno` command with its Reach program, version 2.1.7 or later, tmux, and at least
one signed-in agent CLI (Claude Code, Codex, Cursor, Hermes or OpenClaw).

## Before you start

1. Check that the command exists: `sno reach pair --help` prints a usage line and starts
   nothing. If the `sno` command itself is missing, Sno Station is not installed: stop and
   point the person to its install instructions at https://github.com/sno-ai/sno-station. If
   `sno` runs but `pair` is not a known verb, its Reach program is older than 2.1.7 and
   `sno setup` updates it. In both cases do not imitate the pair by hand.
2. Both agents run with approval prompts off. Start a pair only when the person asked for
   one. If you are proposing it yourself, say that the two agents will act without asking
   and wait for a yes.
3. Write the task as one self-contained string. The two agents are new: they have none of
   this conversation. Name the goal, the files or area, and how to tell it is done.
4. Run it from the folder the work belongs to. Both agents start there.

## Start the pair

```bash
sno reach pair "Fix the login redirect so a signed-out visitor returns to the page they asked for"
```

The command takes exactly one nonblank task string, and the string must not begin with `-`: a
task copied from a list as `- fix the login` is read as an option and refused. Start it with a
word.

## Read what it prints

- `Agents use <a> (<vendor>) and <b> (<vendor>).` This run has one agent from each of two
  vendors, so the review comes from the other vendor.
- `Both agents use <a> (<vendor>). ... this pair has no cross-vendor review.` This run uses
  one agent kind for both roles. The pair still builds and reviews; tell the person that this
  review is not a cross-vendor review. The line does not say why, so do not add a reason.
- `Implementer: <address>; view: tmux attach-session -t <name>` and the same line for
  `Reviewer`. Pass both lines to the person unchanged: that is how they watch.
- `Review returned by <address>:` followed by the first review. Relay its findings or its
  no-defect result.

The command waits a few minutes for the first review and then returns. A final line saying
`no verified review result` means only that no review reached this command before it
returned; the two assignments stay stored. It does not show that the pair failed, and it does
not show that both agents are still working. Check before you report: `sno reach seats --json`
for the two addresses, then `sno reach watch <address> --timeout 60 --idle 10` on each. Tell
the person what you saw and give the two `view:` lines. Do not start the pair again.

## After the first review

- The first review says no defect: the pair is finished. Report that, with the changed paths
  it names.
- The first review lists defects: the pair is not finished. Report the findings as open. The
  fix and the next review travel between the two agents' mailboxes, not back to this command.
- To learn where it stands, ask the reviewer:
  `sno reach call <reviewer address> "In one line: is your latest review of the fixed files clean, or what is still open?" --timeout 120`.
  Read the output itself. Exit 0 only means the reviewer received the question; it is not a
  promise that it answered. Only an explicit answer from the reviewer to this question
  counts. With any exit code, if the output holds no such answer, say the state is unknown
  and give the two `view:` lines.
- After a first review that listed defects, report the work as reviewed clean only when the
  reviewer's own answer says so.

## While they work

- The pair is self-contained. Do not start a third reviewer and do not run `peer-review` on
  the same change while the pair is still exchanging fixes.
- To look without interrupting: `sno reach watch <address> --timeout 60 --idle 10`.
- To say something to one of them: `sno reach call <address> "<text>" --timeout 120`.
- The two agents edit the same checkout you are in. Leave the files they are changing alone
  until the review is clean.

## When it refuses

- `pair requires one nonblank task string`: pass the whole task as one quoted argument.
- The usage line is printed and nothing starts: the task began with `-`. Reword it to start
  with a word.
- `no usable signed-in agent found; no agents started`: nothing was selected. The lines
  printed just before it name each agent and why it was passed over (`CLI unavailable`, or
  `login signed out` or `unknown`). Pass those lines on as printed; do not guess a cause they
  do not state, and do not retry.
- `no implementer started`: the first agent could not be launched; nothing is running. Report
  the line as printed.
- `pair assign <address>: delivery failed`: both agents started but one of them did not get
  its assignment, and the command stops without waiting for a review. Report the line as
  printed, check both addresses with `sno reach seats --json` and `sno reach watch`, and do
  not start the pair again.
- `reviewer launch failed ... only implementer started`: one agent is working without a
  reviewer. Tell the person, and offer `peer-review` on the result once it is finished.
