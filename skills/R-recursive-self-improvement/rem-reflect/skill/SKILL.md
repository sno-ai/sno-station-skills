---
name: rem-reflect
description: "The local experience loop: once a day, turn this machine's own Claude Code and Codex sessions into human-gated skill changes and lessons. Run, review with accept/reject/tbd, recall at session start."
requires:
  programs: []
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
    - {slot: 4.background-processes, need: preferred}
    - {slot: 3.reader-to-agent-delivery, need: preferred}
    - {slot: 2.pre-turn-context-injection, need: preferred}
---

# rem-reflect — the local experience loop

> **Before you use it.** The default consent is `full`. With the nightly-upload setting on, this tool sends the text of your
> Claude Code and Codex sessions and the full text of every installed skill to Sno's cloud, and it copies your own Claude and
> Codex login files into its private store to label sessions. "What a run reads, copies and uploads" below lists everything.
> Turn uploading off at any time with `sno station telemetry consent set off`.

`rem-reflect` reads this machine's Claude Code and Codex sessions once a day. When the Sno Station
settings allow the nightly upload and telemetry consent is full, each session's own CLI (on the
host's default model) conservatively decides keep/drop and labels its outcome, and
every kept preprocessed session and every installed skill's complete `SKILL.md` leave the machine
for Sno's cloud service, which judges them under your Sno account. A bounded excerpt of each kept interactive session is ranked by Sno's cloud to set processing order; ranking never drops a session. The cloud writes
experience pages and possible skill changes or lessons; local adoption still waits for the owner (here, you: the person who owns the machine and its skills).

**What a run reads, copies and uploads.** A run reads the session transcripts under `~/.claude/projects` and `~/.codex/sessions` (the first run looks back seven days, later runs continue where the last stopped), Claude's `history.jsonl`, every installed `SKILL.md` under `~/.claude/skills` and `~/.codex/skills`, and each session's git `origin` URL. It keeps a locally redacted copy of what it reads in its own store (`~/.sno/experience`, or `$REM_REFLECT_STORE`). To label sessions with your own CLI, it copies `~/.claude/.credentials.json` and `~/.codex/auth.json` (mode 0600, refreshed every run, nothing else from those directories) into `<store>/.loop-home/`, and the labeling turns send the rendered session to your own Claude or Codex account. Only when the nightly-upload setting is on and consent is `full` does it upload to Sno's cloud: the kept session text (common secrets such as API keys, bearer tokens and private keys are pattern-redacted first, best effort), tool-call targets and error excerpts, the project id (the normalized git remote, or a hash of the directory when there is none), and the complete text of every installed `SKILL.md`. Consent `off` or `metadata-only` uploads none of it. When no consent file exists yet, installation announces this boundary and selects `full`; change it any time with `sno station telemetry consent set off|metadata-only|full`.

The program is TypeScript run directly by Node; it needs Node 22.6 or newer on PATH as
`node`, the `sno` CLI from Sno Station (consent, settings and the cloud calls go through it) and the session's own Claude Code or Codex CLI. The `heartbeat`
command, when installed, can schedule the daily run. Without a scheduler the commands still work manually and
`status` reports that the loop is not armed. If `node` is older, install a current Node and
retry; nothing here downloads or bundles a runtime.

## Commands

- `rem-reflect run` — harvest recent session versions and, only when the nightly-upload setting
  is on and consent is full, persist one conservative local decision per session and send every
  kept chunk and complete installed skill body to the authenticated cloud. It writes returned cited pages, eligible lessons and at most
  one warranted skill proposal per harness (Claude Code, Codex) into the local store, then reports actual uploads,
  likely failures, decisions and later lesson impact. `off` and `metadata-only` consent, a
  nightly-upload setting that is off, and a missing settings file each finish a no-upload day
  that names the reason. Cloud outages fail the day for retry. Held human verdicts are sent at the next
  full-consent entry even when today's reflection already succeeded.
- `rem-reflect run --trigger timer|manual` — records what started the run; the scheduled daily
  job passes `timer` (see Owner actions), a hand-typed run defaults to `manual`.
- `rem-reflect run --now <timestamp>` — use a specified timestamp for a directly invoked
  acceptance run; the scheduled command remains `rem-reflect run --trigger timer`.
- `rem-reflect accept|reject|tbd <id>` — apply the owner's decision locally to a staged skill
  proposal (`<run-id>/<harness>`) or listed lesson (`L-<page-id>`), then send its linked cloud
  judgment verdict only when consent is full. A failed send remains pending locally.
- `rem-reflect accept <lesson-id> --all-projects` or `--this-project` — the owner's override of
  the layer the cloud gave a lesson: all of the owner's projects, or only the project it was learned
  in. A plain accept keeps the cloud's user-wide or project layer; a skill lesson changes `SKILL.md`
  only when promoted to all projects.
- `rem-reflect recall --agent <kind>` — run by the harness session-start hook; prints, for each
  recallable lesson of the session's project plus user-wide lessons, its trigger and advice,
  independent of agent kind, and one line naming how to read one in full. A lesson is recallable
  when the owner accepted it, or when it is listed and its cloud verification accepted it; a
  rejected lesson never is.
- `rem-reflect recall --agent <kind> --first-message` — run by the harness prompt hook on a
  session's first prompt only; asks the cloud which one recallable lesson fits that message and
  prints its trigger and advice. It sends the message only when the first-message setting is on
  and consent is full, and never blocks the prompt.
- `rem-reflect lesson <lesson-id> --session <id> --agent <kind> --cwd <dir>` — print one recallable
  lesson in full.
- `rem-reflect status` — print the last run's status and whether the daily job is armed; exits
  non-zero when the job is stale, failed, or not armed.
- `rem-reflect install-hooks --print` — print the session-start and first-prompt hook entries for
  the owner to install (the program never writes those files itself).

## How proposals are classified

The cloud puts each finding in one of two classes. `SKILL_DEFECT` means the skill's own text is
wrong or missing something, so the proposal patches the body of that `SKILL.md`. `EXECUTION_LAPSE`
means the skill was right and the agent did not follow it, so the proposal adds one short line to
the skill's reminders block: the region between `<!-- reminders:start -->` and
`<!-- reminders:end -->` at the end of a `SKILL.md`, which is empty until such a line is accepted
and has a size cap.

## Owner actions

Set these up once. The program never edits these files itself.

- **Arm the daily run.** Register the once-a-day job with `heartbeat`:

  ```
  heartbeat --interval 24h --max-hours 0 --label rem-reflect -- rem-reflect run --trigger timer
  ```

- **Install the session-start and first-prompt hooks.** Run `rem-reflect install-hooks --print` and merge the
  Claude fragment into `~/.claude/settings.json` and the Codex fragment into `~/.codex/hooks.json`.
  Codex runs its `SessionStart` hook only after you approve it once in an interactive session.
- **Allow the recall detail command.** Permit `rem-reflect lesson` in the harness so a session can
  read a listed lesson in full from the recall index.
- **Check the Sno Station settings.** `sno setup` writes `~/.sno/settings.json` (or
  `$SNO_PROFILE_DIR/settings.json`). Under its current `mode` (the mode `sno setup` chose), three rows of `modelCalls` decide what this
  skill does: `R2` labels sessions on each session's own CLI with the host's default model, `R3`
  is the nightly upload and `R4` the first-prompt lookup. `R3` and `R4` send to the Sno cloud only when their cell is `sno-gpu`, and both also need consent
  `full`. With `R2` off the sessions still upload, kept with an unknown outcome. A missing settings file or
  row makes the skill call nothing and say which is missing; these rows have no default.
- **Control upload.** `sno station telemetry consent get` shows the local choice. Only `full`
  permits session/skill uploads, the first-prompt lookup and held verdicts; installation never overwrites an existing choice.

<!-- reminders:start -->
<!-- reminders:end -->
