# Decision rights

This file is a starting point. The owner (whoever owns the work) edits the live copy to say who may
decide what without asking; nothing here is a fixed preference, apart from the short list under
"Fixed by the skills" below.

Terms such as night shift, seat and card are defined in the pl core skill's Terms section.

One file for every role and every hour: it applies in the daytime and on a night shift alike. The
shipped copy is the default. The live copy is `~/.config/sno/decision-rights.md` (created from this
file when absent). The PL and COS read the live copy at boot and again when a night shift is declared;
COS names it in the shift-start card it sends each PL.

Only the owner, or a change proposal the owner approved, edits the live copy. Append a line to the change
log at the bottom for every edit.

Fixed by the skills, not editable here:

- An owner-only item is never self-approved by any agent, and stopping an unsafe action never needs
  permission.
- A red button (below) goes to the owner without passing through COS, and a COS approval never stands in
  for the owner's.

## Thresholds

- `budget_ceiling`: (the owner fills in an amount and currency; blank means any spend beyond what the owner
  has already granted is a red button)
- `schedule_overrun_band`: 50% of the estimate
- `night_shift_owner_contact`: by default, on a night shift (a period the owner has declared away) the
  owner is not messaged; owner-only work stops and queues, everything else keeps moving. The owner may
  change this here.

## Owner only

Red buttons. The PL sends the card straight to the owner's address with COS on Cc. COS may add a
recommendation and may not approve, hold or edit the card. On a night shift the card waits unedited at
the top of the return report.

1. Spending money or quota beyond `budget_ceiling` or beyond a grant already given.
2. An irreversible action that leaves the machine: publishing or releasing, pushing, deleting remote
   resources, destroying production data.

Other owner-only items. The PL sends its audit conclusion (facts verified, rulings consulted, its
recommendation, the exact remaining choice) to COS; COS queues the item for the owner and never approves
it.

3. Overturning a ruling the owner personally made, including by relitigating it.
4. A genuinely new product direction: no recorded ruling or principle covers it even by analogy, and it
   changes what an end user sees.
5. Creating a second working copy of a repository (for example a git worktree).
6. Adding an unrequested gate such as a new security check, or running the full evaluation or test suite;
   by default these are proposed to the owner as a question.
7. Approving the doubt list: the rulings COS could not validate at its post-shift review (see the
   cos-review skill).

## PL may decide alone

Logged on the thread with a one-line reason. COS re-audits every one at its post-shift review.

| Decision | Condition | Undo |
|---|---|---|
| Answer settled by a current file, command output or test result | Evidence cited by path or command and checked now | Re-open with new evidence |
| Answer uniquely entailed by one recorded owner ruling | Ruling cited; only one reading survives; a ruling written by this journey's own agents does not count | Owner overturns |
| Small adjacent bug fix | The charter's success checks are untouched, budget holds, done through an executor | Revert the commit |
| Schedule overrun within `schedule_overrun_band` | Creates no stop for owner-only work; estimate and actual logged | None needed |
| Gate waivers and approvals, finding dispositions, test-infrastructure judgment, debt filing, scope trims already implied by a ruling, choosing which journeys to prove | Ruled on the spot with a one-line reason | Owner vetoes after the fact |
| Local commits and other repository mechanics short of publishing | Nothing leaves the machine | Revert |
| A 50/50 call outside the owner-only list | Pick the safest reversible option, record it, continue; once per problem, never a third time | Reverse the option |

A high-severity ruling made alone gets one independent second look before it ships.

## COS may decide alone

Logged in the return report. The owner reviews every one.

| Decision | Condition | Undo |
|---|---|---|
| Whether to reopen a dead PL | Process confirmed gone; within the cap of three PLs per COS | Close the reopened seat |
| A ruling between two PLs | Facts first; the lead below chooses its own fix unless work is already sealed, a large run has no estimate, or a recorded ruling is contradicted | Owner overturns |
| Answering a PL's escalation that is not owner-only | Same tests as the PL table, one layer up | Owner overturns |
| Carrying a recorded ruling across projects | The ruling is cited | Owner overturns |

## Change log

Append one line per edit: date, what changed, who approved it. (Seeded empty.)
