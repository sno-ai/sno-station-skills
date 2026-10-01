# Functional proof

Choose the smallest check that tells the requested result apart from the reported problem. Do
not repeat the same behavior at several layers unless each layer catches a different defect.

## Any project

- A check starts at the ordinary entry and observes the destination.
  - A document: open the produced file and read the sentence the check names.
  - A message: read it at the receiver, not the sender's "sent" line.
  - Data: recount from the independent source and compare.
  - A model's answer: judge the actual answer against the criterion the charter states.
- The expected result is written in the charter or comes from independent known data, not from
  output pasted after the fact.
- A failed check stays failed until the work changes and the check passes again. Keep the real
  output and exit status.

## A code project

- Bug fix: reproduce the bug and show it fail, then show it pass after the repair.
- New behavior: the smallest check of its real outcome. When the promise crosses components,
  run the real journey from its ordinary entry to its destination (retrieve the saved value,
  read the delivered message at its receiver) instead of a call-level test.
- A changed detector: test the smallest real defect it must catch and the normal case.
- Test code supplies inputs and observes the result; it never implements a missing product
  step and never proves only its own mock.
- Use the project's existing test setup. Check only the dependencies this check needs.
- Estimate the run from existing timings first, run only the changed behavior and what
  directly depends on it, and run a full suite only on the owner's request.
- Commit, push and deploy only within the owner's authorization. Use the project's cleanup
  skill on the final diff when it has one.
