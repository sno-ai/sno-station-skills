#!/usr/bin/env python3
"""Check SKILL.md against the reference the sno binary itself serves (`sno skills get cli`)."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
text = (root / "SKILL.md").read_text(encoding="utf-8")
problems = []

head = re.match(r"---\n(.*?)\n---\n", text, re.S)
if not head:
    sys.exit("sno-cli selftest: SKILL.md has no frontmatter")
front = head.group(1)
if not re.search(r"^name: sno-cli$", front, re.M):
    problems.append("frontmatter name must be sno-cli")
if not re.search(r"^\s+programs: \[\]$", front, re.M):
    problems.append("requires must declare an empty programs list: sno installs this skill, it is not a required program")
if not re.search(r"\{slot: 4\.shell, need: required\}", front):
    problems.append("requires must declare slot 4.shell as required")
for phrase in ["sno", "Sno CLI", "sno setup", "sno update", "sno doctor", "sno uninstall", "sno station",
               "telemetry consent", "rem verdict", "sno account", "sno skills"]:
    if phrase not in front:
        problems.append(f"description lacks trigger phrase: {phrase}")

binary = os.environ.get("SNO_BIN") or shutil.which("sno")
if not binary:
    sys.exit("sno-cli selftest: no sno binary; set SNO_BIN to a binary that serves `sno skills get cli`")
done = subprocess.run([binary, "skills", "get", "cli"], capture_output=True, text=True, timeout=60,
                      stdin=subprocess.DEVNULL)
if done.returncode != 0 or not done.stdout.startswith("# sno "):
    sys.exit(f"sno-cli selftest: `{binary} skills get cli` did not serve a reference "
             f"(exit {done.returncode}); the binary is older than this skill")
sections = {}
current = None
for line in done.stdout.splitlines():
    if line.startswith("## sno"):
        current = line[3:].strip()
        sections[current] = []
    elif current:
        sections[current].append(line)
sections = {path: "\n".join(lines) for path, lines in sections.items()}

def resolve(words):
    """Longest known command path in words[0:], and the words after it."""
    path = "sno"
    index = 1
    while index < len(words) and not words[index].startswith("-") and f"{path} {words[index]}" in sections:
        path = f"{path} {words[index]}"
        index += 1
    return path, words[index:]


def has_subcommands(path):
    return any(other.startswith(path + " ") for other in sections)


def unknown_subcommand(path, rest):
    return has_subcommands(path) and rest and not rest[0].startswith("-") and not rest[0].startswith("<")


checked = 0
for block in re.findall(r"```text\n(.*?)```", text, re.S):
    for line in block.splitlines():
        words = line.split()
        if not words or words[0] != "sno":
            continue
        path, rest = resolve(words)
        if unknown_subcommand(path, rest):
            problems.append(f"unknown command in a command block: {line}")
            continue
        for word in rest:
            if word.startswith("--") and word != "--version":
                flag = word.split("=")[0]
                if flag not in sections[path]:
                    problems.append(f"flag {flag} is not in the reference of `{path}`: {line}")
        checked += 1
for mention in re.findall(r"`(sno [a-z][a-z -]*?)(?: <[^`]*)?`", text):
    path, rest = resolve(mention.split())
    if unknown_subcommand(path, rest):
        problems.append(f"the text names a command that the reference lacks: `{mention}`")
if checked == 0:
    problems.append("no command block was checked")
if problems:
    sys.exit("sno-cli selftest failed:\n- " + "\n- ".join(problems))
print(f"sno-cli selftest ok: {checked} command lines, {len(sections)} reference sections")
