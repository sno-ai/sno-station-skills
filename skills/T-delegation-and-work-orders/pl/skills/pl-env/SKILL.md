---
name: pl-env
description: "PL role sub-skill — environment doctoring. Loaded ONLY by the pl core via its routing table; NEVER auto-load from context, never invoke directly."
requires:
  programs: []
  harness:
    - {slot: 4.shell, need: required}
    - {slot: 4.file-read-write, need: required}
---

# PL · Env — environment self-service

Scripts named below run as `bash "${PL_SKILL_DIR}/scripts/<name>.sh" ...`, where `PL_SKILL_DIR` is the
absolute path of the `pl` skill directory; set it in the same Bash call.

Sub-skill of the PL role. The pl core skill invokes this EXPLICITLY on any
environment doubt: a "not available / missing / down" claim, a restart wish, a
VM/host question, or before opening an evaluation or end-to-end run. Canonical scripts:
the pl skill's `scripts/`. Read the host/VM registry from `${SNO_ROSTER_FILE:-}`;
when unset, report "no roster configured" and continue. The TSV columns are
name, address, kind, purpose, and check; no machine inventory ships with the skill.
Use the repo's documented service-address source when one exists.
Read `${SNO_SECRETS_CMD:-}` for an optional secrets wrapper: one executable path
that accepts a command and its arguments, injects secrets, and preserves its exit status.
When unset, report "no secrets wrapper configured" and continue.
Read `${OPENAI_BASE_URL:-}` for model connectivity; when unset, report
"using the harness's own endpoint" and continue.
**Known environment traps**: read the project's lessons file (`ai-doc/LESSONS.md`) when it exists;
propose additions by card.

## Environment self-service

The environment doctor is software-flavoured: each check below applies when the project uses that
tool (Docker, uv/bun, git, a GPU, a VM roster); a check for a tool the project does not use is
reported as not applicable, never as a failure.

Environment, resource, and startup blockers are yours (and every executor's) to
fix, not to wait on — parking on an environment blocker without attempted
self-service is a protocol violation. Most external stalls are environment-class,
and a large share of those are FALSE blockages built on stale premises. Hence:

1. **Fresh evidence or it didn't happen**: any BLOCKED-on-environment verdict
   must attach the on-the-spot command + output (health probe, `docker ps`,
   `ls`, configured secrets-wrapper check). A remembered/recorded "not available" is invalid.
2. **Self-serve the fix — `general-env-doctor.sh` is the standard tool**:
   run `bash "${PL_SKILL_DIR}/scripts/general-env-doctor.sh"` (optionally `--fix`) before ever declaring an environment blocker.
   Classes: secrets / creds (auto-repair through the configured wrapper) /
   connectivity / deps (uv/bun sync, CLI tools) / workspace (stale locks,
   scratch directory, disk) / drift (documented ports versus Docker listeners).
   `bash "${PL_SKILL_DIR}/scripts/general-env-doctor.sh" secret <NAME>` answers "the key is missing" claims —
   it checks this shell and the configured secrets wrapper
   without printing values; every name, including API-key names, takes the same lookup.
   An unset wrapper is an unavailable check, not a missing key.
   Query the supplied roster with `bash "${PL_SKILL_DIR}/scripts/general-env-doctor.sh" host [<name>]`.
   Before dispatching a VM-dependent journey, run `bash "${PL_SKILL_DIR}/scripts/general-env-doctor.sh" vm`.
   A missing roster reports "no roster configured" and proves no VM reachable;
   obtain the run's host configuration before dispatching. A failed VM probe
   means do not dispatch onto it.
3. **Restart of a RUNNING service is script-gated** (when the project uses Docker): run
   `bash "${PL_SKILL_DIR}/scripts/docker-env-doctor.sh" <service>` (deterministic).
   `START`/`RESTART_OK` → run `bash "${PL_SKILL_DIR}/scripts/docker-env-doctor.sh" <service> --execute`
   (Docker Compose by default, or the executable named by `ENV_DOCTOR_REBUILD_CMD`; two more optional settings, `ENV_DOCTOR_COUNTER_REQUIRED_RE` (services that must pass a work-counter probe) and `ENV_DOCTOR_QUEUES` (Redis queues that must be empty), are described in the script header); `NO_GROUNDS` → investigate logs instead;
   `BLOCKED_BUSY` → another session's work is in flight: do not restart,
   report with the script's evidence; `INDETERMINATE` → a safety signal could not be verified: take no
   action and report which signal is missing. By default, direct process kills (`pkill`,
   `kill -9`) are forbidden. Verdicts auto-append to
   `ai-doc/ACTIVE/PL/docker-env-doctor-verdicts.jsonl` (audit trail).
4. **Escalate only five things** ("the owner" means whoever owns the work, often the user): restart denied by the busy check; shared
   prod-data mutations; money; interactive auth (gcloud/gh login — state the
   exact command the owner must run); a resource verified absent that needs
   provisioning. Escalations are precise, never a generic "environment stuck".
   Money beyond the ceiling or an existing grant, and any irreversible action that leaves the
   machine, go straight to the owner: the PL sends that card to `SNO_OWNER_ADDR` (the owner's own
   Reach address, exported before the PL starts) with the COS that supervises this lane (the
   Chief of Staff agent; see the pl core's Terms) on Cc, and that COS may not approve, hold or
   edit it (bands and lists: the live decision-rights file,
   `~/.config/sno/decision-rights.md` when present, otherwise the shipped `references/decision-rights.md` in the pl skill).
   **A credential is never one of the five.** "I cannot find the key" and "I am
   locked out" are not escalations at any layer; check the available credential
   sources first. Interactive auth stays legal only
   because a browser genuinely needs a human at it, and only with the exact
   command written out; it is not a place to file a key you did not find.

## Keys — the one class that is never an escalation

Two rules outrank everything else in this file: **never lock yourself out, never
lose the key**. The encrypted-store rule below applies when the project stores encrypted
user data. The operational half is here because this is where an agent lands the moment a
key fails.

- **`bash "${PL_SKILL_DIR}/scripts/general-env-doctor.sh" secret <NAME>`** — the `secret` lookup in item 2. Run it
  before the thought "the key is missing" is allowed to become a sentence in a
  card. If the configured sources miss, inspect the repository's documented
  credential source before declaring the key absent.
- **A failure to open an encrypted store is a defect, not a finding.** Never write it into a
  document as a known limitation, never trade it away, never weaken encryption on
  user data to get past it. Build the rescue road, and prove it by really making
  the keyring unusable and really opening an encrypted store — a simulated
  failure proves nothing, and a restore procedure nobody has run does not exist.

## Pre-run environment self-check

Before opening any evaluation or end-to-end run, check the host you will run it on ONCE: probe
the run's real dependencies up front and declare any degradation BEFORE the run starts. A
failing probe means choose the host NOW from the available ones; do not discover the
degradation mid-run, where it costs rounds on a degraded attempt before the host question is
even asked.
