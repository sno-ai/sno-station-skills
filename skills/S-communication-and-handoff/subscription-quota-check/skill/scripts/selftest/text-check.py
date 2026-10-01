#!/usr/bin/env python3
"""Check the packaged quota instructions without querying a vendor."""
from pathlib import Path
import re
import json
import sys

# The SKILL.md frontmatter this check reads is a fixed, tiny shape: scalar keys, and
# `requires` holding two lists of inline maps. Parsing it here keeps the self-test on the
# standard library; a PyYAML import would make deploying this skill fail on any machine
# that does not happen to have it, and nothing in the repository installs it.
def parse_frontmatter(text):
    def scalar(raw):
        raw = raw.strip()
        if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
            return raw[1:-1]
        return raw

    def inline_map(raw):
        raw = raw.strip()
        assert raw.startswith("{") and raw.endswith("}"), f"expected an inline map: {raw}"
        row = {}
        for pair in raw[1:-1].split(","):
            key, _, value = pair.partition(":")
            assert _, f"expected key: value in {pair}"
            row[key.strip()] = scalar(value)
        return row

    data, section, key = {}, None, None
    for line in text.split("\n"):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if stripped.startswith("- "):
            assert section is not None and key is not None, f"list item outside a mapping: {line}"
            data[section].setdefault(key, []).append(inline_map(stripped[2:]))
            continue
        name, _, value = stripped.partition(":")
        assert _, f"expected key: value in {line}"
        if indent == 0:
            section, key = (name, None) if not value.strip() else (None, None)
            if section is None:
                data[name] = scalar(value)
            else:
                data[section] = {}
        else:
            assert section is not None, f"nested key outside a mapping: {line}"
            key = name
            if value.strip():
                data[section][key] = scalar(value)
    return data



root = Path(__file__).resolve().parents[2]
text = (root / "SKILL.md").read_text()
try:
    assert not ((root / "scripts/subscription-quota-check").exists() or (root / "scripts/subscription-quota-check").is_symlink()), "runtime belongs to the installed core program, not this skill"
    contract = json.loads((root / "references/subscription-quota-check-contract.json").read_text())
    assert contract["schema_version"] == 1 and contract["program"] == "subscription-quota-check", "public contract identity"
    assert contract["min_version"] == "1.0", "public contract version"
    allowed = set(contract["flags"])
    for fragment in re.finditer(r"```[^\n]*\n(.*?)```|`([^`\n]+)`", text, re.S):
        code = fragment[1] if fragment[1] is not None else fragment[2]
        for command in re.finditer(r"(?<![\w/-])subscription-quota-check(?=\s)([^\n]*)", code):
            arguments = re.split(r"\s--\s", command[1], maxsplit=1)[0]
            for flag in re.findall(r"(?<![\w-])--[a-z][a-z-]*", arguments):
                line = text.count("\n", 0, fragment.start()) + code.count("\n", 0, command.start()) + 1
                assert flag in allowed, f"SKILL.md:{line}: unknown subscription-quota-check flag {flag}"
    assert "references/subscription-quota-check-contract.json" in text, "bundled contract link"
    heartbeat_contract = json.loads((root / "references/heartbeat-contract.json").read_text())
    assert heartbeat_contract["program"] == "heartbeat" and heartbeat_contract["min_version"] == "1.0", "wait command contract"
    for command in re.finditer(r"^heartbeat ([^\n]+)$", text, re.M):
        arguments = re.split(r"\s--\s", command[1], maxsplit=1)[0]
        for flag in re.findall(r"--[a-z][a-z-]*", arguments):
            assert flag in heartbeat_contract["flags"], f"unknown wait command flag: {flag}"

    assert text.startswith("---\n"), "SKILL.md frontmatter is missing"
    frontmatter, body = text[4:].split("\n---\n", 1)
    requires = parse_frontmatter(frontmatter)["requires"]
    assert set(requires) == {"programs", "harness"}, "requires fields"
    programs = requires["programs"]
    assert len(programs) == 2 and all(set(row) == {"name", "min_version"} for row in programs), "requires.programs shape"
    assert {row["name"]: row["min_version"] for row in programs} == {"subscription-quota-check": "1.0", "heartbeat": "1.0"}, "requires.programs wait dependency"
    slots = requires["harness"]
    expected = {"4.shell": "required", "4.background-processes": "preferred", "3.reader-to-agent-delivery": "preferred"}
    assert len(slots) == len(expected) and all(set(row) == {"slot", "need"} for row in slots), "requires.harness shape"
    assert {row["slot"]: row["need"] for row in slots} == expected, "requires.harness: shell required, wait-branch slots preferred"
    assert contract["verdict_exits"] == {"go": 0, "short_only": 0, "wait": 1, "owner_action": 1, "unknown": 3, "needs_auth": 4, "n/a": 0}, "public verdict contract"
    for verdict, status in contract["verdict_exits"].items():
        assert re.search(rf"^\| `{re.escape(verdict)}` \| {status} \| .+\|$", body, re.M), f"missing verdict row: {verdict}"
    for name, pattern in {
        "on-demand": r"Read it on demand: when the human asks, or when something was actually blocked",
        "reset window": r"seconds_to_reset.*?\*\*blocking\*\* window",
        "bounded delayed wake": r"heartbeat --label quota-reset --interval.*?--max-ticks 2.*?--max-hours 0.*?-- date -u",
        "no immediate read": r"first tick runs immediately.*?Do not query quota\s+on that tick",
        "one delayed read": r"On that second tick, run `subscription-quota-check` once",
        "no recurring probe": r"never put the quota command in a recurring hook",
        "wait dependency": r"arm `heartbeat` using its background-and-reader procedure",
        "fresh confirmation": r"only a fresh read proves a block is gone",
        "authentication": r"Not logged in is not out of quota",
    }.items():
        assert re.search(pattern, body, re.S), f"missing instruction: {name}"
except (AssertionError, KeyError, TypeError, ValueError, OSError) as error:
    print(f"SKILL.md: {error}", file=sys.stderr)
    raise SystemExit(1) from None
print("quota text: requirements, verdict rows, on-demand and wait rules pass")
