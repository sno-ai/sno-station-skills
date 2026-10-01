#!/usr/bin/env bash
# Text contract for the pl-audit skill: the load-bearing rules must still be stated.
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
    "every close is audited": "Audit every close, always.",
    "record diagnostics do not block development": "their status is not a development or closure prerequisite",
    "unverified claims are marked": "any claim you did not verify is explicitly marked",
    "independent review required": "self-verification never seals a case",
    "owner is told before the seal counts": "the seal is not done until the OWNER has been told",
}
missing = [name for name, phrase in rules.items() if phrase not in text]
if missing:
    raise SystemExit(f"missing pl-audit rules: {', '.join(missing)}")
PY

printf 'pl-audit rule contract passed\n'
