#!/usr/bin/env bash
# Text contract: check only this payload's SKILL.md, including a negative control.
set -Eeuo pipefail
export PYTHONDONTWRITEBYTECODE=1

selftest_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd -- "$selftest_dir/../.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT

python3 - "$skill_dir/SKILL.md" "$temp_dir" <<'PY'
import pathlib
import re
import sys

import yaml

rules = {
    "command returns only the first review": "The command itself brings back only the first review; following the rest is your job (below).",
    "first review without defects is finished": "The first review says no defect: the pair is finished.",
    "first review with defects is unfinished": "The first review lists defects: the pair is not finished.",
    "ask reviewer with reach call": 'To learn where it stands, ask the reviewer: `sno reach call <reviewer address> "In one line: is your latest review of the fixed files clean, or what is still open?" --timeout 120`.',
    "zero exit confirms receipt only": "Exit 0 only means the reviewer received the question; it is not a promise that it answered. Only an explicit answer from the reviewer to this question counts.",
    "any exit without answer means unknown state": "With any exit code, if the output holds no such answer, say the state is unknown and give the two `view:` lines.",
    "report delivery failure without restarting pair": "`pair assign <address>: delivery failed`: both agents started but one of them did not get its assignment, and the command stops without waiting for a review. Report the line as printed, check both addresses with `sno reach seats --json` and `sno reach watch`, and do not start the pair again.",
    "reviewer confirms clean after defects": "After a first review that listed defects, report the work as reviewed clean only when the reviewer's own answer says so.",
    "approval prompts off and explicit request": "Both agents run with approval prompts off. Start a pair only when the person asked for one. If you are proposing it yourself, say that the two agents will act without asking and wait for a yes.",
    "self-contained task without conversation": "Write the task as one self-contained string. The two agents are new: they have none of this conversation.",
    "task must not begin with hyphen": "The command takes exactly one nonblank task string, and the string must not begin with `-`: a task copied from a list as `- fix the login` is read as an option and refused. Start it with a word.",
    "leading hyphen prints usage without starting": "The usage line is printed and nothing starts: the task began with `-`. Reword it to start with a word.",
    "pending review is not failure": "`no verified review result` means only that no review reached this command before it returned; the two assignments stay stored. It does not show that the pair failed, and it does not show that both agents are still working.",
    "check agents before reporting": "Check before you report: `sno reach seats --json` for the two addresses, then `sno reach watch <address> --timeout 60 --idle 10` on each. Tell the person what you saw and give the two `view:` lines.",
    "do not restart the pair": "Do not start the pair again.",
    "no additional reviewer during fixes": "Do not start a third reviewer and do not run `peer-review` on the same change while the pair is still exchanging fixes.",
    "disclose single vendor review": "The pair still builds and reviews; tell the person that this review is not a cross-vendor review. The line does not say why, so do not add a reason.",
    "missing sno means install Sno Station": "If the `sno` command itself is missing, Sno Station is not installed: stop and point the person to its install instructions at https://github.com/sno-ai/sno-station.",
    "missing pair means update Reach": "If `sno` runs but `pair` is not a known verb, its Reach program is older than 2.1.7 and `sno setup` updates it.",
    "do not imitate the pair in either case": "In both cases do not imitate the pair by hand.",
    "relay unavailable agent reasons without guessing": "`no usable signed-in agent found; no agents started`: nothing was selected. The lines printed just before it name each agent and why it was passed over (`CLI unavailable`, or `login signed out` or `unknown`). Pass those lines on as printed; do not guess a cause they do not state, and do not retry.",
}


def check(path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        return [f"read SKILL.md: {error}"]
    frontmatter = re.match(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)", text, re.S)
    if frontmatter is None:
        return ["frontmatter delimiters"]
    try:
        header = yaml.safe_load(frontmatter.group(1))
    except yaml.YAMLError as error:
        return [f"parseable frontmatter: {error}"]
    if not isinstance(header, dict):
        return ["frontmatter mapping"]
    requires = header.get("requires")
    if not isinstance(requires, dict):
        return ["requires mapping"]
    programs = requires.get("programs")
    harness = requires.get("harness")
    description = header.get("description")
    body = text[frontmatter.end():]
    normalized = " ".join(body.split())
    bash_blocks = re.findall(r"^```bash[ \t]*\r?\n(.*?)^```[ \t]*\r?$", body, re.M | re.S)
    checks = {
        "name is tag-team": header.get("name") == "tag-team",
        "nonblank description": isinstance(description, str) and bool(description.strip()),
        "reach minimum version 2.1.7": isinstance(programs, list) and any(
            isinstance(item, dict) and item.get("name") == "reach"
            and item.get("min_version") == "2.1.7" for item in programs
        ),
        "required shell slot": isinstance(harness, list) and any(
            isinstance(item, dict) and item.get("slot") == "4.shell"
            and item.get("need") == "required" for item in harness
        ),
        "quoted pair command in bash block": any('sno reach pair "' in block for block in bash_blocks),
        "pair availability check": "`sno reach pair --help`" in normalized,
    }
    checks.update({f"rule: {name}": phrase in normalized for name, phrase in rules.items()})
    return [name for name, passed in checks.items() if not passed]


source = pathlib.Path(sys.argv[1])
failures = check(source)
if failures:
    raise SystemExit(f"failed tag-team checks: {', '.join(failures)}")
print("tag-team text contract passed")

negative = pathlib.Path(sys.argv[2]) / "SKILL.md"
negative.write_text(
    source.read_text(encoding="utf-8").replace(rules["do not restart the pair"], "", 1),
    encoding="utf-8",
)
failures = check(negative)
if failures != ["rule: do not restart the pair"]:
    raise SystemExit(f"failed tag-team check: negative control; expected missing restart rule, got {failures}")
print("tag-team negative control passed: missing restart rule detected")
PY
