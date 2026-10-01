#!/usr/bin/env bash
# Text contract for the medic skill plus the behaviour test of its command.
set -Eeuo pipefail

selftest_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd -- "$selftest_dir/../.." && pwd)"

python3 - "$skill_dir" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
text = " ".join((root / "SKILL.md").read_text(encoding="utf-8").split())
rules = {
    "output shape": "WARN <check>: <what is wrong> -> <the command that fixes it>",
    "summary line": "MEDIC ok=N warn=N fail=N",
    "checks only": "it never installs, repairs, starts, stops or spends anything",
    "fix only on request": "Run a fix only when the owner asks for it",
    "re-run after a fix": "run `medic run` again",
    "skipped checks are shown": "not checked, <program> is missing",
    "points to the live receiver test": "`rotate-agent-preflight`",
}
missing = [name for name, phrase in rules.items() if phrase not in text]
if missing:
    raise SystemExit(f"missing medic rules: {', '.join(missing)}")
for check in ("tools", "agent-cli", "skills", "commands", "hooks", "reach", "skill-files", "seat", "heartbeat", "quota", "temp-space"):
    if f"| `{check}` |" not in text:
        raise SystemExit(f"the checks table lacks: {check}")
PY

bash "$skill_dir/scripts/medic.t"
printf 'medic text contract and behaviour test passed\n'
