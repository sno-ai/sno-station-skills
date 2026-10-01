#!/usr/bin/env python3
"""Check the packaged instruction/dependency boundary, without running heartbeat."""
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
    assert not ((root / "scripts/heartbeat").exists() or (root / "scripts/heartbeat").is_symlink()), "runtime belongs to the installed core program, not this skill"
    contract = json.loads((root / "references/heartbeat-contract.json").read_text())
    assert contract["schema_version"] == 1 and contract["program"] == "heartbeat", "public contract identity"
    assert contract["min_version"] == "1.0", "public contract version"
    allowed = set(contract["flags"])
    for fragment in re.finditer(r"```[^\n]*\n(.*?)```|`([^`\n]+)`", text, re.S):
        code = fragment[1] if fragment[1] is not None else fragment[2]
        for command in re.finditer(r"(?<![\w/-])heartbeat(?=\s)([^\n]*)", code):
            arguments = re.split(r"\s--\s", command[1], maxsplit=1)[0]
            for flag in re.findall(r"(?<![\w-])--[a-z][a-z-]*", arguments):
                line = text.count("\n", 0, fragment.start()) + code.count("\n", 0, command.start()) + 1
                assert flag in allowed, f"SKILL.md:{line}: unknown heartbeat flag {flag}"
    assert "references/heartbeat-contract.json" in text, "bundled contract link"
    assert text.startswith("---\n"), "SKILL.md frontmatter is missing"
    frontmatter, body = text[4:].split("\n---\n", 1)
    requires = parse_frontmatter(frontmatter)["requires"]
    assert set(requires) == {"programs", "harness"}, "requires fields"
    assert requires["programs"] == [{"name": "heartbeat", "min_version": "1.0"}], "requires.programs"
    expected = {"4.shell": "required", "4.background-processes": "required", "3.reader-to-agent-delivery": "required"}
    slots = requires["harness"]
    assert len(slots) == len(expected) and all(set(row) == {"slot", "need"} for row in slots), "requires.harness shape"
    assert {row["slot"]: row["need"] for row in slots} == expected, "requires.harness mandatory delivery"
    assert contract["endings"] == ["FINISHED", "NOT FINISHED", "STOPPED"], "public ending contract"
    for name, pattern in {
        "background execution": r"run_in_background:\s*true",
        "persistent reader": r"Monitor\([\s\S]*?persistent:\s*true",
        "reader catches early completion": r"tail --pid=.*?-F -n \+1",
        "unique log": r"mktemp",
        "completion marker": r"writes that path ONLY at the end",
        "bounded failure": r"NOT FINISHED.*never arrived",
        "minutes": r"bare number is minutes, never seconds",
    }.items():
        assert re.search(pattern, body), f"missing instruction: {name}"
except (AssertionError, KeyError, TypeError, ValueError, OSError) as error:
    print(f"SKILL.md: {error}", file=sys.stderr)
    raise SystemExit(1) from None
print("heartbeat text: requirements and background/reader/completion rules pass")
