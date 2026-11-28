#!/usr/bin/env python3
"""Assert COS supervision rules and cos-screen.sh help behavior."""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

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

script = pathlib.Path(__file__).resolve().parents[1] / "cos-screen.sh"
with tempfile.TemporaryDirectory() as temporary_directory:
    fake_bin = pathlib.Path(temporary_directory) / "bin"
    fake_bin.mkdir()
    bash = shutil.which("bash")
    sed = shutil.which("sed")
    if not bash or not sed:
        raise SystemExit("cos-screen.sh help test requires bash and sed")
    (fake_bin / "sed").symlink_to(sed)

    environment = os.environ.copy()
    environment["PATH"] = str(fake_bin)

    for flag in ("-h", "--help"):
        result = subprocess.run(
            [bash, str(script), flag],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )
        if result.returncode != 0:
            raise SystemExit(f"cos-screen.sh {flag}: expected exit 0, got {result.returncode}: {result.stderr}")
        if result.stderr:
            raise SystemExit(f"cos-screen.sh {flag}: expected empty stderr, got: {result.stderr}")
        lines = result.stdout.splitlines()
        if any(line.startswith("#") for line in lines):
            raise SystemExit(f"cos-screen.sh {flag}: help output contains a comment marker")
        if not lines or not lines[0].startswith("cos-screen.sh — print what a PL's window shows RIGHT NOW"):
            raise SystemExit(f"cos-screen.sh {flag}: help header is missing or malformed")
        if "Needs tmux, jq and the sno command." not in result.stdout or "EXIT:" not in result.stdout:
            raise SystemExit(f"cos-screen.sh {flag}: help output is incomplete")
        if "set -Eeuo pipefail" in result.stdout or "REGISTRY=" in result.stdout:
            raise SystemExit(f"cos-screen.sh {flag}: help output includes executable code")

print("cos-screen.sh help: -h and --help print clean usage and exit 0")
