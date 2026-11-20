---
name: codex-coder
effort: low
description: Route production coding tasks from Claude Code to the user-level Codex Shell, TypeScript, Python, or Rust workflow through a direct `codex exec` run. Use for "codex-coder", "ask Codex to write code", "generate with Codex", language migrations, or mixed Shell/TypeScript/Python/Rust implementation.
requires:
  programs:
    - {name: heartbeat, min_version: "1.0"}
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
    - {slot: 4.background-processes, need: required}
    - {slot: 3.reader-to-agent-delivery, need: required}
---

# Codex Coder Router for Claude Code

Carry the task's finite time budget into the coding assignment, including test time.
Require a duration estimate before each targeted test run; full evaluation, unit,
integration, or repository suites require the owner's explicit request, not dispatcher
approval. New security checks require the owner's specific approval; auxiliary checks
must not block the requested function or development work.

Act as a thin dispatcher. Determine the target language, then hand the whole implementation to Codex through a direct `codex exec` run owned by this session. The canonical language instructions live under `~/.codex/skills`; do not use same-named Claude skills as substitutes.

Dispatch always uses `low` effort, set by this skill's frontmatter. The separate Codex coding task uses the model from role `coder` with `high` effort. If the original request selects the reviewer model, use the model from role `reviewer` with `low` effort. Roles live in the `[models]` table of `${XDG_CONFIG_HOME:-$HOME/.config}/sno/models.toml`; an absent file, missing role, or empty value means omit `--model` so the Codex default applies. An effort explicitly selected in the original request overrides either default. Loading a language skill does not switch effort inside a running task: set both values when launching that task.

## Codex runs with the sandbox off

Keep the owner's configured `sandbox_mode = "danger-full-access"`; do not override it
in a dispatch, config, flag, or profile. A connection or credential error does not identify
its cause. Inspect the effective configuration, actual endpoint, and error; repair the
observed cause within existing authority. Preserve valid results from unaffected tests.

## Transport: `codex exec` from the dispatching session

The coding run is a plain `codex exec` started by the session that runs this skill, with
`run_in_background`, and watched by `heartbeat`. Nothing sits between this session and the
Codex process.

Why not the plugin's app-server route: the plugin's
`codex-rescue` subagent starts the task, and the task's life is tied to that subagent's session
plus a broker that is shared by every Claude session in the same directory. The plugin's
SessionEnd hook shuts that broker down and kills the session's jobs without checking whether a
task is still running — so a subagent session ending early, or any other session in that
directory ending, kills a coding run mid-flight and leaves its record saying `running` forever.
A direct `codex exec` has one owner: this session.

Do not:

- dispatch through the `codex:codex-rescue` subagent or the plugin's `task` command;
- call `mcp__codex__codex` as part of this workflow;
- pass any flag or profile that turns a sandbox back on.

## Route the Target Language

Use this precedence order:

1. The language or destination the user explicitly requested.
2. The files the task must create or change.
3. The repository's manifest, immediate callers, and nearby tests.
4. For a migration, the language being produced; treat the source language as context.
5. For generated code, the maintained source or generator language unless the user explicitly asks to edit generated output.

Ask one concise clarification only when those signals still do not identify the destination. Do not infer a language from personal preference or tool availability.

| Destination | Strong signals | Codex skill |
|---|---|---|
| Bash or shell | `.sh`, a Bash shebang, shell CLI, automation, process wrapper, or Git/infra helper | `$shellscript-coder` |
| TypeScript or TSX | `.ts`, `.tsx`, `.mts`, `.cts`, `tsconfig.json`, a typed Node or React target | `$ts-coder` |
| Python | `.py`, `pyproject.toml`, Python service, package, script, or test target | `$python-coder` |
| Rust | `.rs`, `Cargo.toml`, Cargo workspace, crate, Rust CLI, service, library, or FFI target | `$rust-coder` |

JavaScript without a TypeScript target is not automatically TypeScript. An unsupported destination must be surfaced instead of silently routed to the nearest skill.

The language skills are optional. When the selected one is not installed under `~/.codex/skills`, leave it out of the handoff, tell Codex to follow the repository's own conventions, and say in the report which skill was missing.

## Build One Codex Handoff

Use one `codex exec` run for the full user request, including mixed-language work. In the forwarded prompt:

1. Name every selected skill explicitly, such as `$ts-coder` and `$rust-coder`.
2. Tell Codex to read each selected user-level `SKILL.md` and its required references completely before editing.
3. Tell Codex that this `codex exec` run is already the primary execution run. It must follow the selected skill's repository, language, implementation, and verification rules directly, and must not launch a nested Codex process.
4. Preserve the user's request verbatim under a short routing preamble.
5. Include the current working directory and the language-to-file ownership found during routing.
6. For mixed work, require one shared contract, contract-owner-first implementation, language-specific checks, and the smallest cross-language integration check.

Use this prompt shape:

Include this standing test rule in every forwarded prompt: a test written to prove a fix must assert observable results and literal values only; never import or reference a symbol introduced by the same change (a new export, constant, or function). Stashing the source change must let the unchanged test run red, without patching the test.

```text
Use the user-level Codex skills $<language-skill> [and $<language-skill>]. Read each selected SKILL.md under ~/.codex/skills and every required reference completely, then follow their repository, language, implementation, and verification rules as the execution contracts. This `codex exec` run is already the primary execution run: implement directly and do not launch a nested Codex process. Work in <current working directory>. Keep the implementation minimal and verify it with the repository's real commands.

<standing test rule above, verbatim>

Routing evidence:
- <language>: <owned targets and decisive repository signal>

Before editing, name the one claim in this request you would most challenge — a wrong line number, a fix that could change behaviour the request says stays identical, a test that cannot go red — and say why. If there is none, say so in one line.

Original request:
<verbatim user request>
```

Do not restate the language standards in the handoff. The selected Codex skills are the single source of truth; only the transport is this session's `codex exec` run.

## Launch and wait

1. Write the handoff prompt to a file in the scratchpad (`<scratch>/codex-<slug>.prompt.md`).
2. Resolve model and effort from the original request: default to role `coder` and `model_reasoning_effort=high`; an explicit reviewer-model selection uses role `reviewer` and `model_reasoning_effort=low`. Read the role's value from `[models]` in `${XDG_CONFIG_HOME:-$HOME/.config}/sno/models.toml` and pass it as `--model <value>`; omit `--model` when the value is absent or empty. If the request explicitly selects an effort, use it with the selected model.
3. Start the run in the background — one Bash call, `run_in_background: true`, never a trailing `&`:

   ```
   cd <workspace> && codex exec --skip-git-repo-check \
       [--model <value>] -c model_reasoning_effort=<effort> -c model_reasoning_summary=detailed \
       -o <scratch>/codex-<slug>.last.md - < <scratch>/codex-<slug>.prompt.md \
       > <scratch>/codex-<slug>.out.log 2> <scratch>/codex-<slug>.err.log; \
     printf '%s\n' "$?" > <scratch>/codex-<slug>.done
   ```

   Use the coding effort above; do not inherit the dispatcher's `low`. The `.done`
   marker is written only when codex has exited, and carries the exit status.
4. Arm the wait with the heartbeat skill: `sno heartbeat --label codex-<slug> --until-file
   <scratch>/codex-<slug>.done -- tail -c 300 <scratch>/codex-<slug>.err.log`, then attach the
   reader line the arm output prints. Each tick shows the newest reasoning summary, which is the
   only liveness signal a codex run gives (a healthy run can be silent on stdout for minutes).
5. When the marker lands: exit status `0` and a non-empty `.last.md` is the report — relay it.
   Any other status, or an empty `.last.md`, is a failed run: read `.err.log`, say what it says,
   and decide with the user whether to rerun. Never report success without the marker.

`<workspace>` is the checkout and branch the user is working in. Every run, parallel or not, edits there.

A continuation ("continue the previous Codex task") is a fresh `codex exec` whose prompt starts
with the previous run's `.last.md` verbatim under a one-line "previous run said:" header; there is
no session to resume.

Coding is write-capable by default (the sandbox is off). Respect explicit read-only,
diagnosis-only, or review-only requests by saying so in the prompt.

The selected Codex skill owns repository inspection, edits, verification, and refinement. Claude
does not run a parallel implementation or silently repair a failed Codex result.

## Failure Boundary

If `codex` is not on PATH or authentication fails, locate the installed runtime and repair
PATH or the existing sanctioned session setup, then resume. Ask only when authentication
requires an owner-only action; continue independent repository work meanwhile. A run whose `.err.log` says it cannot reach the network or
secrets requires inspection of the effective configuration and actual endpoint. Repair the
measured cause within existing authority and resume; do not infer the cause from the error alone.
A run with no growth in `.err.log` for 15 minutes is stalled: kill that codex process by the pid
the background task reports (never by pattern), record it, and rerun the same prompt once.
