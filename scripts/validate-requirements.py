#!/usr/bin/env python3
"""Validate copied skill declarations and compute publication content identities."""

import hashlib
import json
import logging
import re
import sys
from collections.abc import Hashable
from pathlib import Path

try:
    import yaml
except ImportError:
    logging.error("gate: Python 3 with PyYAML is required; install the documented dependencies")
    raise SystemExit(1) from None

__all__ = ["artifact_identity", "validate_payload"]
LOG = logging.getLogger(__name__)
CONTRACT_FIELDS = {"schema_version", "program_ids", "slot_ids", "need_values", "version_pattern"}
LEGACY = re.compile(
    r"(?<![\w.-])mbox(?![\w-])|mailbox\.sh|mailbox-doorbell|"
    r"--(?:journey|callsign|message|interval-secs|timeout-secs|idle-secs)(?![\w-])|"
    r"X-Journey|X-Callsign|SNO_MBOX_|sno-agent-mbox"
)


class UniqueLoader(yaml.SafeLoader):
    def construct_mapping(self, node: yaml.MappingNode, deep: bool = False) -> dict[Hashable, object]:
        self.flatten_mapping(node)
        pairs = [(self.construct_object(key, deep=deep), value) for key, value in node.value]
        result: dict[Hashable, object] = {}
        for key, value in pairs:
            if not isinstance(key, str):
                raise ValueError("frontmatter: mapping keys must be strings")
            if key in result:
                raise ValueError(f"{key}: duplicate field")
            result[key] = self.construct_object(value, deep=deep)
        return result


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"{key}: duplicate field")
        result[key] = value
    return result


def mapping(value: object, keys: set[str], field: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise ValueError(f"{field}: expected an object")
    missing = keys - value.keys()
    if missing:
        raise ValueError(f"{field}.{sorted(missing)[0]}: missing field")
    extra = value.keys() - keys
    if extra:
        raise ValueError(f"{field}.{sorted(extra)[0]}: unknown field")
    return value


def string_list(value: object, field: str) -> list[str]:
    if not isinstance(value, list) or not value:
        raise ValueError(f"{field}: expected a nonempty string list")
    result: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item.strip() or item in result:
            raise ValueError(f"{field}: invalid or duplicate value")
        result.append(item)
    return result


def read_contract(path: Path) -> dict[str, object]:
    contract = mapping(json.loads(path.read_text(), object_pairs_hook=unique_object), CONTRACT_FIELDS, "contract")
    if type(contract["schema_version"]) is not int or contract["schema_version"] != 1:
        raise ValueError("contract.schema_version: unsupported schema")
    for field in ("program_ids", "slot_ids", "need_values"):
        string_list(contract[field], f"contract.{field}")
    if contract["need_values"] != ["required", "preferred", "optional"]:
        raise ValueError("contract.need_values: unsupported values")
    if contract["version_pattern"] != "^[0-9]+[.][0-9]+([.][0-9]+)?$":
        raise ValueError("contract.version_pattern: unsupported version rule")
    return contract


def frontmatter(path: Path) -> dict[str, object]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "---":
        raise ValueError("requires: SKILL.md needs YAML frontmatter")
    try:
        end = lines.index("---", 1)
    except ValueError:
        raise ValueError("requires: YAML frontmatter has no closing delimiter") from None
    try:
        data = yaml.load("\n".join(lines[1:end]), Loader=UniqueLoader)
    except yaml.YAMLError:
        raise ValueError("requires: invalid YAML frontmatter") from None
    if not isinstance(data, dict) or "requires" not in data:
        raise ValueError("requires: missing field")
    return mapping(data["requires"], {"programs", "harness"}, "requires")


def validate_entries(value: object, group: str, contract: dict[str, object]) -> None:
    if not isinstance(value, list):
        raise ValueError(f"requires.{group}: expected a list")
    identity, second, known = ("name", "min_version", "program_ids") if group == "programs" else ("slot", "need", "slot_ids")
    seen: set[str] = set()
    for index, raw in enumerate(value):
        field = f"requires.{group}[{index}]"
        row = mapping(raw, {identity, second}, field)
        key = row[identity]
        if not isinstance(key, str) or key not in string_list(contract[known], known):
            raise ValueError(f"{field}.{identity}: unknown identifier")
        if key in seen:
            raise ValueError(f"{field}.{identity}: duplicate entry")
        seen.add(key)
        setting = row[second]
        if not isinstance(setting, str) or not setting.strip():
            raise ValueError(f"{field}.{second}: expected a nonempty string")
        if group == "programs":
            if re.fullmatch(str(contract["version_pattern"]), setting) is None:
                raise ValueError(f"{field}.min_version: malformed version")
        elif setting not in string_list(contract["need_values"], "need_values"):
            raise ValueError(f"{field}.need: expected required, preferred or optional")


def artifact_identity(root: Path) -> str:
    if not root.is_dir():
        raise ValueError(f"artifact: directory does not exist: {root}")
    entries = []
    for path in sorted(root.rglob("*"), key=lambda p: p.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            entries.append({"path": relative, "type": "symlink", "target": str(path.readlink())})
        elif path.is_file():
            content = path.read_bytes()
            if path.name == "PUBLISHED.json":
                stamp = json.loads(content, object_pairs_hook=unique_object)
                if not isinstance(stamp, dict):
                    raise ValueError(f"{relative}: stamp is not an object")
                stamp.pop("published_at", None)
                content = json.dumps(stamp, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
            entries.append({"path": relative, "type": "file", "mode": path.stat().st_mode & 0o7777,
                            "sha256": hashlib.sha256(content).hexdigest()})
    manifest = json.dumps(entries, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(manifest).hexdigest()


def validate_payload(contract_path: Path, root: Path, category: str) -> dict[str, str]:
    contract = read_contract(contract_path)
    skills = sorted(root.rglob("SKILL.md"))
    if not skills:
        raise ValueError("SKILL.md: no skill declarations in payload")
    primary = [root / "skill"] if (root / "skill" / "SKILL.md").is_file() else []
    primary.extend(path.parent for path in sorted((root / "skills").glob("*/SKILL.md")))
    if not primary:
        # An overlay-only unit is a supported shape: publish.sh copies overlay/ as the payload
        # when a unit has no shared skill/ and no family, because the two harnesses cannot use
        # the same text. Those per-harness overlays are then the primaries, and each owes a
        # self-test like any other. Without this the gate refused a shape its own copy step
        # accepts, and said "no self-test" about a payload it had not looked for.
        primary.extend(path.parent for path in sorted((root / "overlay").glob("*/SKILL.md")))
    if not primary:
        raise ValueError("SKILL.md: no primary skill payload")
    for skill in skills:
        try:
            declaration = frontmatter(skill)
            for group in ("programs", "harness"):
                validate_entries(declaration[group], group, contract)
        except ValueError as error:
            raise ValueError(f"{skill.relative_to(root)}: {error}") from None
    for base in primary:
        test = base / "scripts/selftest/run-selftest.sh"
        if not test.is_file():
            raise ValueError(f"{test.relative_to(root)}: missing self-test")
    if category == "S":
        for path in sorted(root.rglob("*.md")):
            relative = path.relative_to(root).as_posix()
            if "/scripts/selftest/" in f"/{relative}":
                continue
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                match = LEGACY.search(line)
                if match:
                    raise ValueError(f"{relative}:{number}:{match.group()}: legacy communication vocabulary")
    return {"contract_sha256": hashlib.sha256(contract_path.read_bytes()).hexdigest(),
            "payload_sha256": artifact_identity(root)}


def main() -> int:
    target = "arguments"
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "identity":
            target = sys.argv[2]
            result = {"artifact_sha256": artifact_identity(Path(target))}
        elif len(sys.argv) == 5 and sys.argv[1] == "validate":
            target = sys.argv[3]
            result = validate_payload(Path(sys.argv[2]), Path(target), sys.argv[4])
        else:
            LOG.error("usage: validate-requirements.py validate CONTRACT PAYLOAD CATEGORY | identity DISTRIBUTION")
            return 2
    except (OSError, UnicodeError, ValueError) as error:
        LOG.error("gate: %s: %s; fix the source or contract before publishing", target, error)
        return 1
    sys.stdout.write(json.dumps(result, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
