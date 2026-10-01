#!/usr/bin/env python3
"""Assert the COS core SKILL.md still states its load-bearing supervision rules."""
import pathlib
import sys

RULES = {
    "manual-only activation": "MANUAL-ONLY: load solely when the human owner types `/cos`",
    "pen boundary excludes charters": "never a charter (a charter records OWNER decisions",
    "verification names its tree": "a verification NAMES THE TREE it ran against",
    "circuit breaker caps at two": "the third same-shape card is FORBIDDEN",
    "value-class is never self-approved": "never self-approved and never settled by COS",
    "delivery is the sender's job": "DELIVERY IS THE SENDER'S JOB",
}

skill = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[2] / "SKILL.md"
text = " ".join(skill.read_text(encoding="utf-8").split())
missing = [name for name, phrase in RULES.items() if phrase not in text]
if missing:
    raise SystemExit(f"{skill}: missing COS core rules: {', '.join(missing)}")
print("cos core text: supervision rules pass")
