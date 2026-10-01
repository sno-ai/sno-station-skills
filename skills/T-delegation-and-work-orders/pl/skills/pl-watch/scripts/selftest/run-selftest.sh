#!/usr/bin/env bash
# Text contract for the pl-watch skill: the load-bearing rules must still be stated.
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
    "reading does not clear a card": "both stop it; reading does not",
    "clear cards before arming": "clear ALL pending cards BEFORE arming",
    "closure diverges on any increase": "on a closure journey ANY increase fires it immediately",
    "alarms only from results": "comes only from class 5, and only after you confirm it independently on disk",
    "no deadline extension": "No extension authority, no sunk-cost pleas.",
    "movement is not progress": "Files are moving",
}
missing = [name for name, phrase in rules.items() if phrase not in text]
if missing:
    raise SystemExit(f"missing pl-watch rules: {', '.join(missing)}")
PY

printf 'pl-watch rule contract passed\n'
