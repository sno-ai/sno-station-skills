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

> **Before you use it.** Sno Station sets the sharing level when it installs, by mode: `full` for `agent-native` and
> `rem-enhanced`, `metadata-only` for `local-first`; it never overwrites a choice you already made. At `full`, this tool sends
> the text of your Claude Code and Codex sessions and the full text of every installed skill to Sno's cloud, and it copies your
> own Claude and Codex login files into its private store to label sessions. In `local-first` nothing is sent to Sno, but the
> text of a few sessions a night still goes to your own Claude Code or Codex account when this tool asks it for lessons.
> "What a run reads, copies and uploads" below lists everything.
> Turn uploading off at any time with `sno station telemetry consent set off`.

`rem-reflect` reads this machine's Claude Code and Codex sessions once a day. When the Sno Station
settings select `agent-native` or `rem-enhanced`, each session's own CLI (on the
host's default model) conservatively decides keep/drop and labels its outcome. Each completed run
is sent through `sno rem judge`; that command permits session and skill uploads only at full consent.
Only `rem-enhanced` uses the returned judgments, experience pages, skill proposals and lessons
in its report and local store. `agent-native` keeps its local report and saves returned links
for delivering later user verdicts. `local-first` sends nothing: each night it asks the session's own CLI
about the few sessions with the most failures and owner corrections, and stores the lessons and at most one
skill reminder per harness that it can quote verbatim from the session, for you to accept or reject.
Local adoption still waits for the owner (here, you: the person who owns the machine and its skills).

**What a run reads, copies and uploads.** A run reads the session transcripts under `~/.claude/projects` and `~/.codex/sessions` (the first run looks back seven days, later runs continue where the last stopped), Claude's `history.jsonl`, every installed `SKILL.md` under `~/.claude/skills` and `~/.codex/skills`, and each session's git `origin` URL. It keeps a locally redacted copy of what it reads in its own store (`~/.sno/experience`, or `$REM_REFLECT_STORE`). To label sessions with your own CLI, it copies `~/.claude/.credentials.json` and `~/.codex/auth.json` (mode 0600, refreshed every run, nothing else from those directories) into `<store>/.loop-home/`, and the labeling turns send the rendered session to your own Claude or Codex account. Only in `agent-native` or `rem-enhanced` with consent `full` does it upload to Sno's cloud: the kept session text (common secrets such as API keys, bearer tokens and private keys are pattern-redacted first, best effort), tool-call targets and error excerpts, the project id (the normalized git remote, or a hash of the directory when there is none), and the complete text of every installed `SKILL.md`. Consent `off` or `metadata-only` uploads none of it. When no consent file exists yet, installation announces this boundary and selects `metadata-only` for `local-first`, `full` for `agent-native` and `rem-enhanced`; change it any time with `sno station telemetry consent set off|metadata-only|full`.

The program is TypeScript run directly by Node; it needs Node 22.6 or newer on PATH as
`node`, the `sno` CLI from Sno Station (consent, settings and the cloud calls go through it) and the session's own Claude Code or Codex CLI. The `sno heartbeat`
command, when installed, can schedule the daily run. Without a scheduler the commands still work manually and
`status` reports that the loop is not armed. If `node` is older, install a current Node and
retry; nothing here downloads or bundles a runtime.

## Commands

- `sno rem-reflect run` — harvest recent session versions and, in `agent-native` or `rem-enhanced`,
  persist one conservative local decision per session and send the completed run through
  `sno rem judge`. That command rejects session and skill uploads unless consent is full.
  Only `rem-enhanced` writes returned cited pages, eligible lessons and warranted skill proposals
  into the local store and uses their judgments in the report. `agent-native` keeps the local
  report. `local-first` uploads nothing; for up to three sessions per harness a night it asks that session's own
  CLI for one lesson and stores each answer whose quotes occur verbatim in the session as a page, a listed lesson
  and, for a lapse in using an installed skill it read, one staged reminder proposal; the report lists them with
  their accept commands, and a session is asked about once. A missing settings file finishes a no-upload day
  naming the reason.
  A failed or rejected send is logged with the run id and leaves the local day successful;
  the saved request can be sent on the next daily run. Held human verdicts are retried at the
  next entry even when today's reflection already succeeded.
- `sno rem-reflect run --trigger timer|manual` — records what started the run; the scheduled daily
  job passes `timer` (see Owner actions), a hand-typed run defaults to `manual`.
- `sno rem-reflect run --now <timestamp>` — use a specified timestamp for a directly invoked
  acceptance run; the scheduled command remains `sno rem-reflect run --trigger timer`.
- `sno rem-reflect accept|reject|tbd <id>` — apply the owner's decision locally to a staged skill
  proposal (`<run-id>/<harness>`) or listed lesson (`L-<page-id>`), then send its linked cloud
  judgment verdict in `agent-native` and `rem-enhanced` through `sno rem verdict`, whose full-consent
  check may reject it. `local-first` sends nothing. A failed send is logged with the judgment id
  and remains pending without changing the local verdict or its successful result.
- `sno rem-reflect accept <lesson-id> --all-projects` or `--this-project` — the owner's override of
  the layer the cloud gave a lesson: all of the owner's projects, or only the project it was learned
  in. A plain accept keeps the cloud's user-wide or project layer; a skill lesson changes `SKILL.md`
  only when promoted to all projects.
- `sno rem-reflect recall --agent <kind>` — run by the harness session-start hook; prints, for each
  recallable lesson of the session's project plus user-wide lessons, its trigger and advice,
  independent of agent kind, and one line naming how to read one in full. A lesson is recallable
  when the owner accepted it, or when it is listed and its cloud verification accepted it; a
  rejected lesson never is.
- `sno rem-reflect recall --agent <kind> --first-message` — run by the harness prompt hook on a
  session's first prompt only; asks the cloud which one recallable lesson fits that message and
  prints its trigger and advice. It sends the message only when the first-message setting is on
  and consent is full, and never blocks the prompt.
- `sno rem-reflect lesson <lesson-id> --session <id> --agent <kind> --cwd <dir>` — print one recallable
  lesson in full.
- `sno rem-reflect status` — print the last run's status and whether the daily job is armed; exits
  non-zero when the job is stale, failed, or not armed.
- `sno rem-reflect install-hooks --print` — print the session-start and first-prompt hook entries for
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

- **Arm the daily run.** Register the once-a-day job with `sno heartbeat`:

  ```
  sno heartbeat --interval 24h --max-hours 0 --label rem-reflect -- sno rem-reflect run --trigger timer
  ```

- **Install the session-start and first-prompt hooks.** Run `sno rem-reflect install-hooks --print` and merge the
  Claude fragment into `~/.claude/settings.json` and the Codex fragment into `~/.codex/hooks.json`.
  Codex runs its `SessionStart` hook only after you approve it once in an interactive session.
- **Allow the recall detail command.** Permit `sno rem-reflect lesson` in the harness so a session can
  read a listed lesson in full from the recall index.
- **Check the Sno Station settings.** `sno setup` writes `~/.sno/settings.json` (or
  `$SNO_PROFILE_DIR/settings.json`). Its current `mode` controls daily sharing. The `modelCalls` rows select local labeling
  and first-prompt lookup. `R5` runs Local First lesson generation on the host and is off in the other modes; the published older table without R5 uses that same default. Its prompt is served by `sno skills get rem-reflect-local-writer` from the CLI binary, not a public skill file: `R2` labels sessions on each session's own CLI with the host's default model, `R3`
  names the nightly upload and `R4` the first-prompt lookup. Daily runs and verdicts share by
  `mode`: both `agent-native` and `rem-enhanced` call the Sno cloud through `sno rem`; those commands
  enforce full consent. Only `rem-enhanced` uses the cloud judgments. `R4` still needs its cell
  to be `sno-gpu` and consent `full`. With `R2` off, sessions upload with an unknown local outcome.
  A missing settings file sends nothing and names the file; there is no default mode.
- **Control upload.** `sno station telemetry consent get` shows the local choice. Only `full`
  permits session/skill uploads, the first-prompt lookup and held verdicts; installation never overwrites an existing choice.

<!-- reminders:start -->
<!-- reminders:end -->
