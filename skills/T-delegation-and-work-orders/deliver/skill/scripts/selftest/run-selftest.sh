#!/usr/bin/env bash
# Text contract for the deliver skill plus the behaviour test of its proof command.
# Reads only this payload's own files, so a deployed copy tests itself.
set -Eeuo pipefail

selftest_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd -- "$selftest_dir/../.." && pwd)"

python3 - "$skill_dir" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
text = " ".join((root / "SKILL.md").read_text(encoding="utf-8").split())
rules = {
    "success checks define done": "Its `## Success checks` are the definition of done; nothing else is.",
    "reasoned steps only": "name the requested result it proves and what changes if it fails",
    "auxiliary failures never block": "never block the work",
    "no success reported on failure": "never report success",
    "proof is recorded by the command": "deliver-proof run <charter> <n> -- <command>",
    "proof is judged at the destination": "Prove the result where the requester would see it",
    "never edit the proof by hand": "Never edit the Proof table by hand",
    "close requires the check": "Only when it exits 0",
    "one independent review": "**Review once.**",
    "authorization limits": "only within the owner's authorization",
    "resume from an earlier executor's record": "continue from Next instead of starting over",
    "checkpoint after every finished step": "After every finished step run `handoff-checkpoint <charter-name>.state.md`",
}
missing = [name for name, phrase in rules.items() if phrase not in text]
if missing:
    raise SystemExit(f"missing deliver rules: {', '.join(missing)}")
PY

bash "$skill_dir/scripts/deliver-proof.t"
printf 'deliver rule contract and proof command passed\n'
