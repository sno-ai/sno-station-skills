#!/usr/bin/env python3
"""Assert the cos-watch SKILL.md still states its load-bearing live-supervision rules."""
import pathlib
import sys

RULES = {
    "core-only load boundary": "Loaded ONLY by the cos core via its routing table; NEVER auto-load from context",
    "queue beats ring": "THE RING IS A HINT",
    "reachability predicate excludes the lock": "The predicate is the ring outcome plus what the seat then does, never the lock",
    "unreachable is not death": "UNREACHABLE is not death",
    "registry count stays inside the lock": "Counting outside the lock lets two COS both see room for one more",
    "freeze after every writer": "Freeze last, always",
}

skill = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[2] / "SKILL.md"
text = " ".join(skill.read_text(encoding="utf-8").split())
missing = [name for name, phrase in RULES.items() if phrase not in text]
if missing:
    raise SystemExit(f"{skill}: missing live-supervision rules: {', '.join(missing)}")
print("cos-watch text: live-supervision rules pass")
