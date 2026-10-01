#!/usr/bin/env bash
# Text contract for the pl-analyze skill: the load-bearing rules must still be stated.
# Reads only this payload's own SKILL.md, so a deployed copy tests itself.
set -Eeuo pipefail

selftest_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill="$(cd -- "$selftest_dir/../.." && pwd)/SKILL.md"

python3 - "$skill" <<'PY'
import pathlib
import sys

text = " ".join(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").split())
rules = {
    "never ambient-loaded": "NEVER auto-load from ambient context.",
    "reports are hypotheses": "are HYPOTHESES to check against this record, never evidence",
    "judgment lapse needs a mechanism": "a memory note is NOT a fix",
    "join failures before diagnosing": "get ONE joined timeline BEFORE any is diagnosed separately",
    "lessons need an owner file": "A lesson without a named owner file is not landed.",
    "settled rulings stay settled": "never reopens settled owner rulings",
}
missing = [name for name, phrase in rules.items() if phrase not in text]
if missing:
    raise SystemExit(f"missing pl-analyze rules: {', '.join(missing)}")
PY

printf 'pl-analyze rule contract passed\n'
