---
name: pl-analyze
description: "PL (Project Lead) role sub-skill for incident analysis and process evaluation. Loaded through the pl core routing table, or when the owner explicitly asks for a retrospective or root-cause write-up; NEVER auto-load from ambient context."
requires:
  programs: []
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
---

# PL · Analyze — incident analysis & process evaluation

Scripts named below run as `bash "${PL_SKILL_DIR}/scripts/<name>.sh" ...`, where `PL_SKILL_DIR` is the
absolute path of the `pl` skill directory; set it in the same Bash call. The workspace layout (`ai-doc/...`,
ledgers) is documented in the pl core's State files section; a source that does not exist in this project
is skipped and noted in the analysis.

Sub-skill of the PL role, also usable standalone. Words such as journey, callsign, night shift and
take-over are defined once, in the pl core's Terms glossary. The rules in this file are the PL role's
defaults; a project may choose otherwise.

Invoke when something went
wrong — an escaped bug, a stalled run, a run killed at its time limit, an estimate blowup, a
protocol breach, a close-audit FAIL — or when the owner ("owner" means whoever owns the work, often
the user) asks for a retrospective, a root-cause account of what went wrong, or for periodic process
evaluation (patterns in estimate errors, recurring frictions). The deliverable is never just an explanation: it is a
verified cause AND a fix landed in the right place. Core iron rules bind
unchanged; the owner is addressed in the user's own language.

## Method — evidence first, always from disk

Sessions lie and die; disk is the memory. Rebuild the timeline exclusively from:

- `sno reach log --as <your-strict-address> --work <id>` — the journey's
  full message provenance (`sno reach export --work <id> --output <path>` keeps the full
  thread bytes); command grammar is defined in
  `~/.local/lib/sno-reach/current/guide/agent-reach.md`
- `ai-doc/JOURNAL/routing-ledger.jsonl` — routed/closed/correction events (`board_closed` lines are written by `bash "${PL_SKILL_DIR}/scripts/todo.sh" close`; the PL writes the journey's own `routed`, `closed` and `correction` lines by hand)
- `ai-doc/ACTIVE/PL/exec-logs/` + dispatch files under `ai-doc/ACTIVE/PL/dispatch/`
- git log/diff of the journey's commits when the project uses git (the fence file lists the paths the journey may touch)
- the convergence series (the recorded remaining-work counts per fix cycle; `bash "${PL_SKILL_DIR}/scripts/convergence-watch.sh" verdict --journey <id>`)
- `~/.local/state/agent-spawns.jsonl` + `agent-callsigns.jsonl` + tmux autopsy
  (an executor killed at its time limit leaves its session up — read the screen)

Reports, memories, and your own recollection are HYPOTHESES to check against
this record, never evidence. Timestamp every step; a contradiction between two
sources is a finding, not noise. N different-looking failures arriving together
get ONE joined timeline BEFORE any is diagnosed separately — join the
timestamps in the target machine's system log first; cascades collapse into
one root event and red herrings die at the join — several apparently separate
failures are often one shared cause. A status table built from disk beats a report built from a
stale card — trust the freshest disk join, not the most confident narrator.

## Root-cause classification → fix location

The class DECIDES where the fix lands — never write a note where a mechanism
belongs:

| Class | Signature | Fix lands in |
|---|---|---|
| Machinery bug | a script/skill deterministically did the wrong thing | the skill CODE (script fix + test), then reinstalled |
| Judgment lapse | the agent saw the signal and chose wrong / waited on a human | MECHANIZE it — an alarm/verdict/gate in scripts (e.g. a stalled-close alarm); a memory note is NOT a fix |
| Estimation error | estimate vs actual > 2× | the est/actual pair → calibration material for `agentic-time-estimate` (when installed; otherwise a plain note of the pair) |
| Knowledge trap | a known trap, hit again | the lessons file `ai-doc/LESSONS.md` (written only by the PL; a trap enters the index on its SECOND hit — see the pl core, Lessons file) |
| Process gap | no rule existed for the situation | retro proposal → owner approval → skill text patch (never self-edited mid-journey) |

Design principle: **the machine must lose patience before the owner
does** — every place the owner had to scold marks a missing mechanical control;
an analysis is not done until that control is named (or shown to already exist).

## Output shape

Owner-facing report, written in the user's own language, four sections: (1) conclusion — what broke, one line;
(2) evidence chain — the 2–4 load-bearing facts, each with its path/command;
(3) where the fix lands — the fix and its location per the table above; (4) recurrence prevention — the
check/alarm/rule that now exists. Agent-facing: the same content as an English
postmortem section in the journey's journal entry, plus ledger `correction` events
wherever the durable record was wrong.

## Routing the lessons

A finished analysis routes each lesson to the file that OWNS the behavior:
dispatch-time rules → `pl-dispatch`; in-flight controls and alarms →
`pl-watch`; close/probe rules → `pl-audit`; environment checks → `pl-env`;
board/memory/Reach-substrate law → the `pl` core. A lesson without a named
owner file is not landed.

## Boundaries

- Script/machinery fixes land directly ONLY within the core iron-rule-1
  exception: PL-owned control scripts under the pl skill's `scripts/`,
  with a test, then reinstalled and reported to the owner. Anything else that needs code —
  repo source, other skills' scripts — is dispatched to an executor, never
  hand-edited. SKILL text changes still ride the retro → owner-approval path
  (core boundary).
- Estimation analysis only FILES the calibration pair — rate/multiplier changes
  belong to the estimator skill's own validation loop (when installed).
- Analysis of a journey never reopens settled owner rulings; if the cause traces
  to a ruling, report the trace, don't relitigate.
