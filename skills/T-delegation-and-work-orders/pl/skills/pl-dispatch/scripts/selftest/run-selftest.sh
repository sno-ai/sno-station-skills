#!/usr/bin/env bash
# Text contract for the pl-dispatch skill: the load-bearing rules must still be stated.
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
    "charter is not spawnable": "Charter authorship is never a spawnable deliverable",
    "missing timings do not suspend development": "do not suspend development to build or repair an estimator",
    "spawn needs a Reach address": "AND THE SPAWNER REFUSES WITHOUT IT",
    "one high-decision journey": "At most ONE high-decision journey concurrent per PL",
    "launch is watched": "A dispatch you sent and stopped watching is not a dispatch, it is a hope",
}
missing = [name for name, phrase in rules.items() if phrase not in text]
if missing:
    raise SystemExit(f"missing pl-dispatch rules: {', '.join(missing)}")
PY

printf 'pl-dispatch rule contract passed\n'
