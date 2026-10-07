#!/usr/bin/env bash
# Text contract for the away-brief skill plus the behaviour test of its command.
set -Eeuo pipefail

selftest_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd -- "$selftest_dir/../.." && pwd)"

python3 - "$skill_dir" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
text = " ".join((root / "SKILL.md").read_text(encoding="utf-8").split())
rules = {
    "four sections": "## Done",
    "needs you section": "## Needs you",
    "cannot read prints and continues": "the rest of the page still prints",
    "changes nothing but its readings": "except its own list of quota readings, and Reach, which may note that it has seen the cards",
    "quota shows usage not spend": "a reading shows usage now, not spend",
    "mark before leaving": "sno away-brief mark",
    "sections keep their own share": "and N more not shown",
    "no invented work": "Do not add work that is not on the page",
    "limits of done": "Work that was never committed or recorded does not appear",
}
missing = [name for name, phrase in rules.items() if phrase not in text]
if missing:
    raise SystemExit(f"missing away-brief rules: {', '.join(missing)}")
PY

bash "$skill_dir/scripts/away-brief.t"
printf 'away-brief text contract and behaviour test passed\n'
