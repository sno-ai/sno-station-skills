#!/usr/bin/env bash
# Text contract for the pl skill: the load-bearing rules must still be stated.
# Reads only this payload's own SKILL.md, so a deployed copy tests itself.
set -Eeuo pipefail

selftest_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill="$(cd -- "$selftest_dir/../.." && pwd)/SKILL.md"

python3 - "$skill" <<'PY'
import pathlib
import sys

text = " ".join(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").split())
rules = {
    "manual activation only": "MANUAL-ONLY — load solely when the human owner types",
    "charter reader is an executor": "you are an EXECUTOR, not the PL",
    "never writes product code": "Never write product code.",
    "disk outranks prose": "Never trust report prose",
    "owner-only interrupts": "The owner is interrupted for exactly the items under \"Owner only\" in that file, nothing else",
    "circuit breaker": "the third same-shape attempt is FORBIDDEN, reworded or not",
    "one charter one agent": "One charter, one agent — replacing is forbidden by default",
}
missing = [name for name, phrase in rules.items() if phrase not in text]
if missing:
    raise SystemExit(f"missing pl rules: {', '.join(missing)}")
PY

# callsign.sh -h and --help print the comment header without # markers and exit 0;
# no command and an unknown command stay usage errors (exit 2).
help_home="$(mktemp -d)"
trap 'rm -rf -- "$help_home"' EXIT
callsign="$selftest_dir/../callsign.sh"
for flag in -h --help; do
    rc=0
    out="$(HOME="$help_home" bash "$callsign" "$flag" 2>"$help_home/err")" || rc=$?
    if [[ "$rc" -ne 0 ]] || [[ -s "$help_home/err" ]] || grep -Eq '^#|^set -' <<<"$out" ||
        ! grep -Fxq -- '  list                      -> active callsigns table (name journey repo kind since)' <<<"$out" ||
        ! grep -Fxq -- 'State: single machine-wide ledger (append-only JSONL) shared by all runtimes.' <<<"$out"; then
        printf 'callsign.sh %s: expected exit 0, empty stderr, and the clean header on stdout (rc=%s)\n' "$flag" "$rc" >&2
        exit 1
    fi
done
for args in "" "bogus"; do
    rc=0
    # shellcheck disable=SC2086
    HOME="$help_home" bash "$callsign" $args >/dev/null 2>&1 || rc=$?
    if [[ "$rc" -ne 2 ]]; then
        printf "callsign.sh '%s': expected usage exit 2, got %s\n" "$args" "$rc" >&2
        exit 1
    fi
done

printf 'pl rule contract passed\n'
