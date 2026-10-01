---
name: handoff
description: "Transfer full task ownership to a fresh agent with a verified brief and explicit release. Use for replacing the current executor, including a directly assigned task with no work card; not for supervising a helper."
requires:
  programs:
    - {name: reach, min_version: "2.0"}
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
---

# Handoff

Transfer the owner's task, current state and existing authority to one receiving agent.
The owner is whoever owns the work, usually the user.
**The receiver does not edit until explicit release.** After verified release the sender
stops task execution; it does not become a supervisor or wait for completion.

Use the installed Reach guide and `sno reach --help` for exact card syntax and command
arguments. [The bundled contract](references/reach-contract.json) bounds the text self-test;
it does not prove an installed runtime. Confirm `sno reach --version` and the required
runtime before creating a receiver. If unavailable, retain ownership and report the missing
input. No runtime or installation is bundled with this skill.

Install and update the program through `sno setup`. If the installed command names a
missing prerequisite, install that named tool and retry before transferring ownership.
On macOS use the corresponding Homebrew formula: `bash`, `coreutils`, `findutils`,
`gnu-sed`, `gnu-tar`, `flock`, `tmux`, `jq`, or `util-linux`; follow the installed guide's
GNU command PATH instructions. Windows requires WSL.

## Three entry shapes

A is the outgoing executor; B is the receiving executor. Seat, card, ring, X-Work and
Message-ID are Reach terms, defined in the `reach` skill.

- **Card-backed work:** A owns a real original work card. Record its path, Message-ID and
  X-Work. Choose a continuing reply recipient R, normally the original requester, who stays
  registered after A leaves. The original card's Reply-To, when present, determines its
  reply destination; otherwise From does. Verify R before cancelling anything.
- **Direct owner task, no work card:** record the actual authorizing instruction and the
  destination session where B will show its final result to the owner. Do not invent an
  original card, acceptance or cancellation just to fit a mailbox sequence.
- **Sender gone:** A already stopped (quota refused, crash, closed window) and cannot take part.
  Nothing can be verified with A and there is no A to release, so the procedure below does not apply;
  follow "When the sender is gone" instead. It only works if A kept a progress record.

Use real addresses and the existing
checkout. Preserve owner-locked decisions, exclusions and the repository's own rules. No second owner
approval is needed for already authorized work. Do not create or switch checkouts as a side
effect of handoff. Secrets and raw credentials do not belong in the brief.

## Procedure

1. **Pause and capture.** A pauses edits. Record Git status, staged and unstaged binary diffs,
   untracked-file content hashes and the current checkout. Write one complete handoff file
   outside the repository: objective, progress, authorization, settled decisions, exclusions,
   important files/evidence, acceptance checks, unfinished work and risks. Run
   `handoff-checkpoint <file>` to write the git and file-state part of it; it also creates
   the sections you fill in by hand (see "Progress record" below). For card-backed
   work include A's original card identity, X-Work and R. Reserve a fresh Message-ID for
   B's transfer card and include it in the brief before measuring the brief. For direct work state that no
   original work card exists.
   End with the standalone marker `<!-- AGENT_CUTOVER_EOF -->`.
   Measure the exact byte count and SHA-256; reread the tail before delivery.
2. **Initialize before spawn.** Select the requested agent kind, or the same kind as A when none was
   specified, a fresh address B and a display name. Run `sno reach init --as <B> --name <display>`
   and verify success **before** `sno reach spawn <agent> --as <B> --cwd <checkout> --window`.
   Always pass `--window`: an ACP seat (the non-terminal Agent Client Protocol seat that `spawn` creates without `--window`) shows its work only while a caller holds its prompt,
   so once that caller's `--timeout` expires the rest of the turn is invisible to `watch` and
   its output is lost; a receiver owns the task for hours after A leaves, so it must sit on a
   tmux seat. Never hand a task to an ACP seat. Inspect the returned
   seat/channel/handle and the actual runtime/checkout; `sno reach doctor --as <B>` checks
   readiness. If A will send cards,
   initialize and register A's own existing runtime as needed. A direct call does not
   require a fabricated A work card. On retry inspect the existing B before creating another.
3. **Verify readiness without writing.** Send the short launcher below through
   `sno reach call <B> <launcher> --expect <ready-nonce> --timeout 300`.
   B reads the whole brief, verifies bytes, SHA-256 and end marker, then returns the fresh
   readiness nonce, measured digest and intended checkout. B makes no task edits. A checks
   new receiver output, not a prompt echo, then repeats and compares its Git/untracked-file
   observations. Any difference or incomplete brief fails the transfer; A retains ownership.
4. **Prepare a new card only for card-backed work.** Use the fresh Message-ID reserved for B under
   the same X-Work, with From A, To B, and **Reply-To R**. Link A's original card and the
   verified brief in the body, and say "accept, but do not edit before explicit release".
   Validate with `sno reach lint <B-card-file>` before changing A's terminal state.
   R must remain initialized and registered for B's acceptance and final answer after A
   unregisters. The installed public contract must preserve Reply-To for validation,
   delivery and ringing; otherwise stop here with A still owning the task. For a direct
   owner task skip card creation entirely.
5. **Transfer the recorded card responsibility.** For card-backed work, A sends a nonblank
   body to `sno reach reply --as <A> --card <A-original-card> --state cancelled --reason <transfer-to-B>`.
   Check `sno reach state --work <work>` for A's original Message-ID and recipient A.
   Then `sno reach send --as <A>` reads the prepared B card on stdin. B uses its own original
   inbox card for `sno reach reply --as <B> --card <B-original-card> --state accepted`, with
   a nonblank body, and remains paused. A observes acceptance using
   `sno reach state --work <work> --json` and
   `sno reach export --work <work> --output <outside-state-file>`, matching **B's new
   Message-ID and recipient B**. Do not use `wait --reply-to` for acceptance: it matches
   answers only, while B is waiting for release. R may dismiss the received acceptance
   status after reading it; B does not dismiss its actionable work card. For a direct
   owner task skip cancellation and mailbox acceptance; verified readiness is sufficient.
6. **Explicit release, then receiver writes.** For either entry, A sends
   `sno reach call <B> <release-message> --expect <release-receipt-pattern> --timeout 300`.
   Use the release template below with the verified brief digest, a fresh release nonce,
   and B's card ID when present. Match the standalone line `HANDOFF_RELEASED <release-nonce>`
   from new receiver output, not an echo of the request. B verifies these, emits the
   release receipt and only then starts authorized task writes.
   The receipt is proven by order, not by promise: A must see the standalone line before it
   sees any change in the checkout (repeat the Git and untracked-file observations from
   step 1 after the call returns). A change that appears first fails the handoff even if the
   line follows: A calls B with `PAUSE HANDOFF RECOVERY: stop, emit HANDOFF_PAUSED` and
   `--expect HANDOFF_PAUSED`, rewrites the brief with the checkout as B left it, and repeats
   steps 3 and 6 against the new digest.
   This direct release creates no additional actionable work card. If receipt is uncertain,
   A remains paused and inspects B's new output with `sno reach watch <B> --timeout 300`;
   A never resumes competing edits. Do not release an unverified brief.
7. **Sender leaves.** After verified release, A runs `sno reach unregister --as <A>` if it
   was registered, checks absence with `sno reach seats --json`, tells the owner where B
   continues, and stops. Leave the brief available for B. Failure to unregister requires
   cleanup, not reclaiming B's execution authority.
8. **Receiver completes.** B preserves scope and authorization. For a card-backed task it
   checks `sno reach seats --json` and confirms A is absent before sending its terminal
   answer. If A is still registered, keep the completed result and use the bounded
   observation rule below; report a cleanup failure at the deadline instead of claiming
   the transfer has finished. B retains ownership and must not ask A to resume task edits.
   After A is absent, B
   sends exactly one `completed` or `failed` reply on **B's same original work card**, with
   a nonblank result/reason on stdin. That answer goes to R after A has left; R can use
   `sno reach wait --as <R> --reply-to <B-card-id> --from <B> --timeout 300` for the answer and export/state
   for its chain. R dismisses the received reports after reading. For direct owner work,
   B reports completion and the observable result in the destination session; no artificial
   mailbox terminal reply is required.

## Progress record

`handoff-checkpoint <file>` writes a progress record and refreshes it in place. Keep the file outside
the checkout. It holds, between two marker lines, what git and the file system can state: the checkout,
branch, HEAD and subject, the last five commits, and every uncommitted path with its SHA-256. Below the
markers are five sections for the agent: Objective and authorization, Done, Next, Decisions and
assumptions, Risks and open questions. The command never touches text outside the markers.

Run it after every finished task and then update Done and Next. An agent that does this can be
replaced at any moment, including by a receiver that never meets it. Prerequisites: bash 4+, GNU
coreutils and git; on macOS install `bash` and `coreutils` from Homebrew and put them first on PATH.

`handoff-checkpoint --verify <file>` compares the record with the checkout it names. It prints `MATCH`
(exit 0), or one `DRIFT` line per difference (exit 1): `head moved`, `branch`, `new:`, `changed:`,
`settled:` or `gone:` with the path. Exit 2 with one line means the file is not a usable record. `MATCH` means
the same branch, the same HEAD commit and the same content in every uncommitted file of the working tree; it
does not compare what is staged, and it checks the checkout the record names, not the one you pass elsewhere.

## When the sender is gone

The receiver B works from the progress record alone. Steps 3 to 7 above do not apply: there is no A to
verify with, release, or unregister.

- Run `rotate-agent-resume` (see the `rotate-agent` skill) to start B on a tmux window, or, when B is
  already running, do the following by hand.
- Run `handoff-checkpoint --verify <record>`. `MATCH` means the checkout is exactly as A left it at its
  last checkpoint. `DRIFT` means A kept working after that checkpoint: read the named commits and files
  (`git log`, `git diff`), decide what they finished, and add it to Done before continuing.
- Read the whole record. Done is finished: do not redo it. Next is the task list. Objective and
  authorization is all the authority B has; a step outside it needs the owner.
- Continue in the same checkout. After every finished task run `handoff-checkpoint <record>` and update
  Done and Next, so B can be replaced the same way.
- Report to the owner's session named in the record. If there is none, report in the session that
  started B, and say that the receiver started without a release from the sender.

## Failure and retry

Each call or wait has a deadline of at most 300 seconds. Acceptance observation has one
300-second deadline and at most 60 checks, five seconds apart: run `sno reach state` in the foreground
at most 60 times with `sleep 5` between runs, inside that one 300-second budget. Do not create an unattended background polling loop.

For call exit 0, inspect the new receiver receipt, not just the command status. Exit 3 means
the runtime refused: repair the runtime before retry. Exit 4 means no qualifying output by
the deadline: inspect delivery and seat state before retry. Exit 5 means the seat was unreadable:
verify its registration and runtime. A failed check reports the exact step and current owner.

Before A cancels its card, any failure leaves A owning a paused task. After cancellation,
A still owns delivery of the transfer, but does not reopen the terminal card or resume edits.
Inspect delivered IDs and outbox before retrying the same transfer. A delivery followed by
a failed ring is not permission to send a duplicate card. If B has received release, A stays
paused even when its acknowledgment is lost. Cleanup failure never revokes B's authority.

## Short launcher

```text
This is a full ownership handoff in <CURRENT_CHECKOUT>.
Read <BRIEF_PATH>. Verify exactly <BYTE_COUNT> bytes, SHA-256 <DIGEST>, and the final marker
<!-- AGENT_CUTOVER_EOF -->. Report any mismatch; do not execute an unverified brief.
Read the owner's authorization, exclusions, task state and acceptance checks.
Return <READY_NONCE>, the measured digest and intended checkout. Do not make task edits.
Start only after the sender's explicit release names that digest, your card ID when present,
and its fresh release nonce. Recheck the digest and card identity. Before any task write,
output HANDOFF_RELEASED followed by that nonce as one standalone line, then continue the
authorized task to completion in this checkout. Do not ask again for
permission already transferred. Report the final result to the continuing recipient/session
named in the brief; this is not a supervised helper assignment.
```

## Release message

```text
Release the task in the verified brief with SHA-256 <DIGEST>.
Your original work card is <B_CARD_ID_OR_NO_CARD>. Release nonce: <RELEASE_NONCE>.
Check the digest and card identity against your verified brief. If they differ, report the
mismatch and remain paused. Before any task write, emit exactly HANDOFF_RELEASED followed
by <RELEASE_NONCE> as one standalone line. Then perform the authorized task and report its
result to the continuing recipient or owner session named in the brief.
```
