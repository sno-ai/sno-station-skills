#!/usr/bin/env bash
# Text contract for the pl skill: the load-bearing rules must still be stated.
# Reads only this payload's own SKILL.md, so a deployed copy tests itself.
set -Eeuo pipefail

selftest_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill="$(cd -- "$selftest_dir/../.." && pwd)/SKILL.md"

python3 - "$skill" <<'PY'
import pathlib
import sys

text = " ".join(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").split())
rules = {
    "manual activation only": "MANUAL-ONLY — load solely when the human owner types",
    "charter reader is an executor": "you are an EXECUTOR, not the PL",
    "never writes product code": "Never write product code.",
    "disk outranks prose": "Never trust report prose",
    "owner-only interrupts": "The owner is interrupted for exactly the items under \"Owner only\" in that file, nothing else",
    "circuit breaker": "the third same-shape attempt is FORBIDDEN, reworded or not",
    "one charter one agent": "One charter, one agent — replacing is forbidden by default",
}
missing = [name for name, phrase in rules.items() if phrase not in text]
if missing:
    raise SystemExit(f"missing pl rules: {', '.join(missing)}")
PY

printf 'pl rule contract passed\n'
