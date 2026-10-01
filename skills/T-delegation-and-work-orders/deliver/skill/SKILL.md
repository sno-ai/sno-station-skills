---
name: deliver
description: "Carry out a released charter to a proven result: plan only as much as the work needs, do the work through the project's own workers, prove every success check with a recorded real run, get one independent review, and close honestly. Invoke explicitly as `$deliver <charter>` (Codex) or `/deliver <charter>` (Claude), or the way your agent invokes a skill, or when a dispatch names you the executor of a charter."
requires:
  programs: []
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
---

# deliver

Carry out the named charter. Its `## Success checks` are the definition of done; nothing else
is. Read the whole charter and the existing work first. The owner (whoever owns the work,
often the user) can override this skill and any plan an agent wrote. Any kind of project uses
it: for code and tests also read `references/proof.md`.

Prerequisites: `deliver-proof` needs bash 4+ and GNU coreutils (Linux) and prints one message
and stops when they are missing; its selftest also needs python3. On macOS, install bash 4+ and
GNU coreutils (for example with Homebrew) and put them first on PATH. If `deliver-proof` is not
on PATH, run `scripts/deliver-proof` from this skill's folder instead.

## Keep the work useful

- Before adding a prerequisite, test, record or approval step, name the requested result it
  proves and what changes if it fails. If nothing changes, leave it out.
- Check an uncertain fact by reading or calling what exists. If checking needs something built
  first, building it is the first task, not a permission gate.
- Records, telemetry, formatting, identifiers, checksums and review sign-offs never block the
  work. Log the failed action, its place and the actual error, and continue. Do not turn such
  a failure into an assertion, a silent return or a swallowed error. If the main operation
  fails, say so with its cause; never report success. Stop only what cannot proceed and keep
  independent work moving.
- Time is finite and proof shares it: estimate a run from existing timings before starting,
  test only what changed and what directly depends on it, and by default run a full suite only
  when the owner explicitly asks. Do not stop a useful run just because an estimate has passed.
- By default add no security check or new gate the owner did not ask for; propose it as a
  question that says what it would check and what it would block.

## Steps

1. **Start.** If the charter is missing, is not `released`, or has a success check nobody could
   observe, say so once and have `charter` revise it with the owner. Never invent a decision.
   If `<charter-name>.state.md` sits beside the charter, an earlier executor stopped partway:
   run `handoff-checkpoint --verify` on it (the `handoff` skill ships the command), read its Done
   and Next lists, treat Done as finished, and continue from Next instead of starting over.
2. **Plan, only as much as needed.** Work with dependent steps gets a `## Plan` in the charter:
   the steps in order and who does each. One or two steps need none. A plan of more than three
   steps gets one independent review, then work starts; there is no second plan document. A
   product decision the charter does not settle is recorded in the plan and asked once, while
   independent work continues.
3. **Do.** Use the project's own workers and tools: for code, its coder, test and cleanup
   skills when installed; for documents, its writing and review tools. Build the smallest real
   integration early when later steps depend on it. Keep existing behavior unless the charter
   says otherwise. Reproduce a defect before fixing it.
   After every finished step run `handoff-checkpoint <charter-name>.state.md` (beside the
   charter) and update its Done and Next lists, so another agent can take over at any moment.
   If the command is not installed, skip the record and keep working.
4. **Prove.** For each success check, record one of:
   - `deliver-proof run <charter> <n> -- <command>`: the real command, run in the current
     directory; its output and exit status are kept as the log and the table row.
   - `deliver-proof see <charter> <n> <evidence-file> "<what was observed>"`: when inspection is
     the proof (a produced document, a message at its receiver, a screen). The evidence file is
     a nonempty file, named relative to the current directory.

   Prove the result where the requester would see it: read back the saved value, open the
   produced file, read the message at its receiver. Never substitute a mock's answer, a
   successful exit, a call count or the program's own narration. The expected value comes from
   the charter or independent data. Never edit the Proof table by hand, never mark a failed or
   unrun check passed, and after a repair rerun only the affected checks.
5. **Review once.** One independent review of what changed (`peer-review` when installed,
   otherwise a second agent given the charter and the changed work). Fix ordinary-path defects
   in scope; report the rest without growing the job.
6. **Close.** Run `deliver-proof check <charter>` and read its output. Only when it exits 0,
   write `## Report` (what worked, which checks ran and how, anything unfinished) and set
   `status: delivered`. A failing record step is logged and repaired on its own; it does not
   undo working results. Tell whoever dispatched you the result and what remains.

Publish, send to other people, spend, delete, deploy and commit only within the owner's
authorization. If `~/.config/sno/decision-rights.md` exists (the `pl` skill creates it), it
lists what needs the owner. Do not absorb the next charter's work. When you are blocked on a
missing input, state the assumption you proceed under in the plan and keep working.
