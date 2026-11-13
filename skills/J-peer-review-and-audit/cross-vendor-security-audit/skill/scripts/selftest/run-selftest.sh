#!/usr/bin/env bash
# Two checks on this payload: the upstream validators' own tests, and the text contract of the
# second-look step this skill adds, including a negative control.
set -Eeuo pipefail
export PYTHONDONTWRITEBYTECODE=1

selftest_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd -- "$selftest_dir/../.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT

command -v node >/dev/null || { printf 'selftest: node is required for the validator tests\n' >&2; exit 1; }
(cd -- "$skill_dir" && node --test validate-findings.test.cjs validate-coverage-ledger.test.cjs)

python3 - "$skill_dir" "$temp_dir" <<'PY'
import pathlib
import re
import shutil
import sys

import yaml

validation_rules = {
    "pile includes hardening notes": "every `hardening` note retained in ledger bookkeeping",
    "pile includes rejected records": "every `rejected` record in `findings.json`",
    "pile includes deferred and blocked units": "every in-scope ledger unit left `deferred` or `blocked`",
    "reviewer from another vendor": "It must come from a different model vendor than the agents that hunted and validated.",
    "pick reviewer through sno": "`sno subscription-quota-check --pick review --from <parent-agent> --json`",
    "same-vendor fallback is disclosed": "`REPORT.md` then says the second look stayed inside one vendor.",
    "reviewer checks the dismissal reason": "Do not accept the audit's reason as given; check it against the source.",
    "codex runs read-only without user config or proxy": "--ignore-user-config --disable apps --sandbox read-only",
    "claude runs with read tools only": "claude -p --strict-mcp-config --tools Read Grep Glob",
    "revived items get fresh validation": "send it through Phase 3 candidate validation with a fresh verifier that did not hunt, validate it before, or run the second look",
    "disagreement is never dropped": "Never drop it silently; the owner decides.",
    "report lists disagreements": 'Under the heading "Reviewers disagree"',
}
skill_rules = {
    "upstream credit and license": "used under its MIT license (`LICENSE-MIT-cloudflare` in this folder)",
    "phase 5 names the second look": "then give everything the run set aside to a reviewer from another model vendor",
    "budget reserves the second look": "plus the one second-look reviewer call",
    "profiles keep the second look": "or the second look at everything set aside.",
}


def check(root):
    failures = []
    skill = (root / "SKILL.md").read_text(encoding="utf-8")
    validation = " ".join((root / "VALIDATION-AND-REPORTING.md").read_text(encoding="utf-8").split())
    frontmatter = re.match(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)", skill, re.S)
    header = yaml.safe_load(frontmatter.group(1)) if frontmatter else None
    if not isinstance(header, dict) or header.get("name") != "cross-vendor-security-audit":
        failures.append("name is cross-vendor-security-audit")
    if not (root / "LICENSE-MIT-cloudflare").read_text(encoding="utf-8").startswith("MIT License"):
        failures.append("MIT license file ships")
    body = " ".join(skill.split())
    failures += [f"skill: {name}" for name, phrase in skill_rules.items() if phrase not in body]
    failures += [f"validation: {name}" for name, phrase in validation_rules.items() if phrase not in validation]
    return failures


source = pathlib.Path(sys.argv[1])
failures = check(source)
if failures:
    raise SystemExit(f"failed second-look checks: {', '.join(failures)}")
print("second-look text contract passed")

negative = pathlib.Path(sys.argv[2]) / "skill"
negative.mkdir()
for name in ("SKILL.md", "LICENSE-MIT-cloudflare"):
    shutil.copy(source / name, negative / name)
original = (source / "VALIDATION-AND-REPORTING.md").read_text(encoding="utf-8")
(negative / "VALIDATION-AND-REPORTING.md").write_text(
    original.replace(validation_rules["disagreement is never dropped"], "", 1), encoding="utf-8"
)
failures = check(negative)
if failures != ["validation: disagreement is never dropped"]:
    raise SystemExit(f"failed second-look check: negative control; expected missing disagreement rule, got {failures}")
print("second-look negative control passed: missing disagreement rule detected")
PY
