#!/usr/bin/env python3
"""Offline checks of this payload's public syntax and required workflow clauses."""
from pathlib import Path
import json
import re
import shlex
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



ROOT = Path(__file__).resolve().parents[2]
VERBS = set("spawn register unregister seats call watch ring send reply inbox wait dismiss log state flush init rebind doctor export lint remind".split())


def require(pattern, text, rule):
    assert re.search(pattern, text, re.I | re.S), f"missing rule: {rule}"


def commands(text):
    for fragment in re.finditer(r"```[^\n]*\n(.*?)```|`([^`\n]+)`", text, re.S):
        code = fragment[1] if fragment[1] is not None else fragment[2]
        if not re.search(r"\bsno\s+reach\b", code):
            continue
        number = text.count("\n", 0, fragment.start()) + 1
        lexer = shlex.shlex(re.sub(r"\\\r?\n", "", code), posix=True, punctuation_chars=";&|\n")
        lexer.whitespace = " \t\r"
        lexer.whitespace_split = True
        tokens = []
        for token in lexer:
            if set(token) <= set(";&|\n"):
                if tokens:
                    yield number, tokens
                tokens = []
            else:
                tokens.append(token)
        if tokens:
            yield number, tokens


def check():
    text = (ROOT / "SKILL.md").read_text()
    assert text.startswith("---\n"), "frontmatter delimiter"
    frontmatter, body = text[4:].split("\n---\n", 1)
    metadata = parse_frontmatter(frontmatter)
    name = metadata["name"]
    assert name == "reach", "unexpected skill name"
    contract = json.loads((ROOT / "references/reach-contract.json").read_text())
    assert contract["program"] == "reach" and contract["min_version"] == "2.0", "public contract identity"
    assert set(contract["verbs"]) == VERBS, "public contract verb inventory"
    assert contract["call_exit_codes"] == [0, 3, 4, 5], "public contract call exits"
    requirements = metadata["requires"]
    assert set(requirements) == {"programs", "harness"}, "requires fields"
    assert requirements["programs"] == [{"name": "reach", "min_version": "2.0"}], "requires.programs"
    expected = {"4.shell": "required", "2.pre-turn-context-injection": "preferred"}
    slots = requirements["harness"]
    assert len(slots) == len(expected) and all(set(row) == {"slot", "need"} for row in slots), "requires.harness shape"
    assert {row["slot"]: row["need"] for row in slots} == expected, "requires.harness"

    invocations = 0
    # Inspect each actual command fragment, not other tools' flags in surrounding prose.
    for path in [ROOT / "SKILL.md", *sorted((ROOT / "references").rglob("*.md"))]:
        for number, tokens in commands(path.read_text()):
            if tokens[:2] != ["sno", "reach"] or len(tokens) == 2:
                continue
            verb = tokens[2]
            location = f"{path.relative_to(ROOT)}:{number}"
            if verb.startswith("--"):
                assert verb in contract["global_flags"], f"{location}: unknown global flag {verb}"
                allowed = set(contract["global_flags"])
            else:
                assert verb in contract["verbs"], f"{location}: unknown verb {verb}"
                allowed = set(contract["verbs"][verb]) | set(contract["global_flags"])
                invocations += 1
            # The documented call shape places seat and message before its options.
            arguments = tokens[5:] if verb == "call" else tokens[3:]
            for argument in arguments:
                if argument == "--":
                    break
                if argument.startswith("--"):
                    flag = argument.split("=", 1)[0]
                    assert flag in allowed, f"{location}: {verb} rejects flag {flag}"
    assert invocations, "no public invocations checked"

    if name == "reach":
        rows = {}
        for line in body.splitlines():
            match = re.match(r"\| `sno reach ([a-z-]+)[^`]*` \| (.+) \| (.+) \|$", line)
            if match:
                verb, situation, next_action = match.groups()
                assert verb not in rows, f"duplicate command row: {verb}"
                assert situation.strip() and next_action.strip(), f"empty command guidance: {verb}"
                rows[verb] = (situation, next_action)
        assert set(rows) == VERBS, f"command table missing: {sorted(VERBS - rows.keys())}"
        exits = re.findall(r"^\| ([0345]) \| (.+) \| (.+) \|$", body, re.M)
        assert len(exits) == 4 and {int(row[0]) for row in exits} == {0, 3, 4, 5}, "call exit/next-action rows"
        require(r"sno reach init[^`]+`\s*\*\*before\*\*.*?sno reach spawn", body, "init before spawn")
        require(r"first work reply is `accepted`.*?nonblank body", body, "acceptance before work")
        require(r"same path for the terminal.*?Do not send a second acceptance", body, "same original card")
        require(r"state and export.*?Message-ID and recipient.*?Do not use `wait --reply-to` for acceptance", body, "acceptance observation")
        require(r"For each expected actionable recipient.*?`sno reach wait[^`]*--reply-to <id>[^`]*--from <recipient>[^`]*--timeout[^`]*`", body, "terminal wait selects each recipient")
        require(r"Record the expected recipient list before waiting.*?each result and its acceptance chain separately", body, "all intended recipients complete")
        require(r"Reply-To.*?continuing reply destination; otherwise From", body, "continuing reply destination")
        require(r"complete RFC 5322 card on stdin", body, "complete card input")
        require(r"finite timeout for each call/watch/wait", body, "bounded waits")
        require(r"direct owner instruction without a work card does not need an invented", body, "card-free entry")
        print(f"reach text: {len(rows)} command situations, {len(exits)} call exits and {invocations} invocations checked")


try:
    check()
except (AssertionError, KeyError, TypeError, ValueError, OSError, ) as error:
    print(f"text selftest: {error}", file=sys.stderr)
    raise SystemExit(1) from None
