#!/usr/bin/env bash
# Text contract for the pl-env skill: the load-bearing rules must still be stated.
# Reads only this payload's own SKILL.md, so a deployed copy tests itself.
set -Eeuo pipefail

selftest_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill="$(cd -- "$selftest_dir/../.." && pwd)/SKILL.md"

python3 - "$skill" <<'PY'
import pathlib
import sys

text = " ".join(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").split())
rules = {
    "never self-invoked": "NEVER auto-load from context, never invoke directly",
    "blocker needs fresh evidence": 'A remembered/recorded "not available" is invalid.',
    "self-serve before blocking": "before ever declaring an environment blocker",
    "a key is never an escalation": "A credential is never one of the five.",
    "no direct process kills": "direct process kills",
    "unopenable store is a defect": "A failure to open an encrypted store is a defect, not a finding.",
}
missing = [name for name, phrase in rules.items() if phrase not in text]
if missing:
    raise SystemExit(f"missing pl-env rules: {', '.join(missing)}")
PY

printf 'pl-env rule contract passed\n'
