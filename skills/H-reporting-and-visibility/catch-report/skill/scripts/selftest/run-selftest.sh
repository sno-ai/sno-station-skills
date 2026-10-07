#!/usr/bin/env bash
# Text contract for the catch-report skill plus the behaviour test of its command.
set -Eeuo pipefail

selftest_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd -- "$selftest_dir/../.." && pwd)"

python3 - "$skill_dir" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
text = " ".join((root / "SKILL.md").read_text(encoding="utf-8").split())
rules = {
    "two brains": "The product claim is two brains",
    "changes nothing": "It changes nothing.",
    "mutual review is the peer-review records": "Mutual review** is every review the `peer-review` skill recorded",
    "self-check is judged by the agent's own model": "asks that agent's own model",
    "tells the owner about the excerpts and cost": "sends short excerpts of their conversations",
    "fix-now is defined": "`fix-now`",
    "states the limit": "the records hold no author",
    "self number is a lower bound or estimate": "an estimate from a sample",
    "no claim of real problems": 'do not say the findings are "real problems"',
    "zero is not reported when nothing was judged": "do not report a zero",
    "ruling is the owner's": "this command never rules on anything",
    "brief is the page for the user": "run `sno catch-report brief --since 7d`",
    "page goes out as printed": "Hand the page to the user as printed, headline first, in English: do not translate it or re-word it.",
    "no added claims": "do not add a claim the page",
}
missing = [name for name, phrase in rules.items() if phrase not in text]
if missing:
    raise SystemExit(f"missing catch-report rules: {', '.join(missing)}")
PY

bash "$skill_dir/scripts/catch-report.t"
printf 'catch-report text contract and behaviour test passed\n'
