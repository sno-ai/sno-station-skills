#!/usr/bin/env bash
# Text contract and PATH lookup for this skill only.
set -Eeuo pipefail

selftest_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill="$(cd -- "$selftest_dir/../.." && pwd)/SKILL.md"

python3 - "$skill" <<'PY'
import pathlib
import sys

text = " ".join(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").split())
rules = {
    "clock times come from the command": "Never write a clock time for the user that the command did not produce.",
    "no human developer anchoring": "Human-coding time anchoring is FORBIDDEN",
    "price the remainder, never subtract": "`remaining = original estimate − elapsed` is FORBIDDEN",
    "bare judgment is the last resort": "This is the LAST step, never the first",
    "pid search must exclude itself": "Do not hunt the pid with a bare `pgrep -f`",
    "a refusal is not a measurement of zero": "Exit 2 never means zero",
}
missing = [name for name, phrase in rules.items() if phrase not in text]
if missing:
    raise SystemExit(f"agentic-time-estimate: missing load-bearing rules: {', '.join(missing)}")
PY

fake_bin="$(mktemp -d)"
wrapper=""
trap 'kill "$wrapper" 2>/dev/null || true; wait "$wrapper" 2>/dev/null || true; rm -rf -- "$fake_bin"' EXIT
printf '#!/usr/bin/env bash\nprintf "09:31 CET (08:31 UTC)\\n"\n' > "$fake_bin/report-time"
chmod +x "$fake_bin/report-time"
timeout 30 sleep 30 &
wrapper=$!
actual="$(PATH="$fake_bin:$PATH" "$selftest_dir/../time-left" --pid "$wrapper")"
[[ "$actual" == 'deadline: 09:31 CET (08:31 UTC)' ]] || {
    printf 'time-left PATH command: got %s\n' "$actual" >&2
    exit 1
}

bash "$selftest_dir/calibration.t"

printf 'agentic-time-estimate text contract passed\n'
