# sno-station-skills — the skill library Sno Station ships

**This is the Sno Station skill library.** Each published unit carries a publish stamp
proving its self-tests passed. Install Sno Station's `sno` command first (see the Sno Station
documentation), then `sno setup` installs a release into every agent it finds on your machine.

Sno Station puts two or more AI agents on one team — Claude Code, Codex, Hermes, OpenClaw,
whatever the user already has — and gives them the working habits of a real team: they review
each other, they hand work over with full context when one is rate-limited, a lead delegates
work orders, everyone can see what got done, and the team learns from its own mistakes.
These skills are those habits.

All skill text is written in English.

## Six categories

The library is organised by what a team has to be able to do, not by tool or language.
The order is fixed; each code is used in directory names and in the registry.

| Code | Category | One sentence |
|---|---|---|
| **J** | Peer Review & Audit | Colleagues review each other's work, and nothing counts as done until it passes audit. |
| **M** | Build & Rollout | Get the team set up on any workstation with one step, build what the work needs, then roll it out to every machine. |
| **S** | Communication & Handoff | People talk through a shared inbox, and when one is out the other takes over with full context. |
| **H** | Reporting & Visibility | Everyone can see what got done, who caught what, who covered for whom, what's in progress. |
| **T** | Delegation & Work Orders | A lead delegates work as work orders, and decides who takes each job. |
| **R** | Retrospective & Improvement | The team looks back at its own work and turns lessons into rules and better practice. |

Setup itself is not a skill: it is the `sno setup` command in the `sno` CLI, and every
skill's requirements declaration (below) tells it whether to install, degrade or skip the skill
on a given agent. `skills/README.md` lists every unit by category; `registry.yaml` is the
same list in machine-readable form.

## Layout

```
skills/
  README.md                     the category index
  <category>/<unit>/
    skill/                      one skill: SKILL.md, references/, scripts/
    skills/<member>/            or a family of skills that ship together
    overlay/claude|codex/       per-agent differences, when a skill needs them
    public-bin/                 commands the skill puts on PATH
    PUBLISHED.json              the stamp written by the publish step
registry.yaml                   unit -> category code (and tier)
scripts/
  requirements-contract.json    the requirements declaration contract
LICENSE                         Apache-2.0
```

Each published unit carries a `PUBLISHED.json` stamp: unit, publication date, positive
self-test count, and contract and payload SHA-256 digests. The stamp is written by the
publish step, never by hand.

## Skill requirements

Every `SKILL.md` starts with a `requires:` block that says what the skill needs from the agent
and from Sno Station, so `sno setup` can decide per agent whether to install it.

```yaml
requires:
  programs: [reach]                          # Sno Station programs the skill calls
  harness:
    - {slot: 4.shell, need: required}        # what the agent itself must be able to do
```

- **programs** are Sno Station programs installed next to the skills: `reach`, `heartbeat`,
  `subscription-quota-check`, `report-time`.
- **slots** name an agent ability: `4.shell` (run shell commands), `4.file-read-write` (read and
  write files), `4.background-processes` (run a command in the background),
  `2.pre-turn-context-injection` (add text to the agent's context before each turn) and
  `3.reader-to-agent-delivery` (output of a background reader reaches the agent).
- **need** is `required` (an agent without the slot does not get the skill), `preferred` (the
  skill is installed and works in a reduced way) or `optional` (only a convenience).

## Publish checks

Every unit in a release passed the same checks before it was published:

1. the repository carries `LICENSE` and `NOTICE`;
2. the payload is copied whole, with shared, family and per-agent overlay structure kept;
3. no personal binding survives: home paths, owner names, internal hosts, hard-coded models,
   and no Chinese, Japanese or Korean characters;
4. every `SKILL.md` frontmatter parses and its `requires` declaration validates against
   `scripts/requirements-contract.json`;
5. each skill's own self-test passes on the copy, not on the author's tree;
6. `PUBLISHED.json` is written last, with the contract and payload digests.

A skill that fails a check is not published.

## License

Apache-2.0. See `LICENSE`.
