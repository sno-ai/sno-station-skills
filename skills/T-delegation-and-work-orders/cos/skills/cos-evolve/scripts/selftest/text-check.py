#!/usr/bin/env python3
"""Assert the cos-evolve SKILL.md still states its load-bearing evolution rules."""
import pathlib
import sys

RULES = {
    "owner-activated load boundary": "Load ONLY after the owner has explicitly activated the cos role for this session",
    "the pen changes how, never what": "may never card it about WHAT to work on",
    "no mid-journey skill edit": "Never edit the skill tree mid-journey",
    "bugs are fixed where the code lives": "never in memory and never in the learning file",
    "second strike mechanizes": "the second strike is the mechanization trigger",
    "replace a live script by rename": "Never `cp` onto a live script",
}

skill = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[2] / "SKILL.md"
text = " ".join(skill.read_text(encoding="utf-8").split())
missing = [name for name, phrase in RULES.items() if phrase not in text]
if missing:
    raise SystemExit(f"{skill}: missing evolution rules: {', '.join(missing)}")
print("cos-evolve text: evolution rules pass")
