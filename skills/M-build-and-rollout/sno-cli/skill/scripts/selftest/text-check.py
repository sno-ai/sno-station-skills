#!/usr/bin/env python3
"""Check SKILL.md against the help the sno binary itself prints (`sno <command> --help`)."""
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
    sys.exit("sno-cli selftest: no sno binary; set SNO_BIN to the sno binary to check against")
helps = {}


def help_of(path):
    """Help text of `sno <path> --help`, or None when `path` is not a command (the usage line then names the parent)."""
    if path not in helps:
        done = subprocess.run([binary, *path.split(), "--help"], capture_output=True, text=True, timeout=60,
                              stdin=subprocess.DEVNULL)
        usage = re.search(r"^Usage: (.*)$", done.stdout, re.M)
        words = usage.group(1).split() if usage else []
        named = [word for word in words[1:] if not word.startswith(("[", "<", "-"))]
        helps[path] = done.stdout if named == path.split() else None
    return helps[path]


def resolve(words):
    """Longest command path in words[1:], and the words after it."""
    path = ""
    index = 1
    while index < len(words) and not words[index].startswith(("-", "<", "[")):
        candidate = f"{path} {words[index]}".strip()
        if help_of(candidate) is None:
            break
        path = candidate
        index += 1
    return path, words[index:]


def unknown_subcommand(path, rest):
    text_of_path = help_of(path) if path else subprocess.run([binary, "--help"], capture_output=True, text=True,
                                                          timeout=60, stdin=subprocess.DEVNULL).stdout
    usage = re.search(r"^Usage: (.*)$", text_of_path, re.M)
    takes_command = bool(usage) and re.search(r"[\[<]COMMAND[\]>]", usage.group(1)) is not None
    return takes_command and bool(rest) and not rest[0].startswith(("-", "<", "["))


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
                if flag not in (help_of(path) if path else ""):
                    problems.append(f"flag {flag} is not in `sno {path} --help`: {line}")
        checked += 1
for mention in re.findall(r"`(sno [a-z][a-z -]*?)(?: <[^`]*)?`", text):
    path, rest = resolve(mention.split())
    if unknown_subcommand(path, rest):
        problems.append(f"the text names a command the binary lacks: `{mention}`")
if checked == 0:
    problems.append("no command block was checked")
if problems:
    sys.exit("sno-cli selftest failed:\n- " + "\n- ".join(problems))
print(f"sno-cli selftest ok: {checked} command lines, {sum(1 for h in helps.values() if h)} commands read")
