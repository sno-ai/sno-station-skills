#!/usr/bin/env python3
"""Assert the cos-review SKILL.md still states its load-bearing batch-review rules."""
import pathlib
import sys

RULES = {
    "core-only load boundary": "Loaded ONLY by the cos core via its routing table; NEVER auto-load from context",
    "missing records do not block functional review": "Missing board metadata does not reject the close or skip the functional checks below",
    "a supervisor may not drop an item": "dropping owner-requested work still requires the owner's instruction",
    "a parked window over an open charter is correct": "a live parked window is the CORRECT state and must not be flagged",
    "calibration is not pushed downward": "Never answer an over-estimate by telling the estimating layer to shrink",
    "core work is not debt": "Core-path work is never debt",
}

skill = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[2] / "SKILL.md"
text = " ".join(skill.read_text(encoding="utf-8").split())
missing = [name for name, phrase in RULES.items() if phrase not in text]
if missing:
    raise SystemExit(f"{skill}: missing batch-review rules: {', '.join(missing)}")
print("cos-review text: batch-review rules pass")
