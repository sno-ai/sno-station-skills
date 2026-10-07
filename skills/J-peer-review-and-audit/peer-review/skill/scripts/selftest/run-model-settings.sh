#!/usr/bin/env bash
# Check the existing CLI boundary, without importing the settings implementation.
set -Eeuo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
review="${REVIEW:-$here/../run-adversarial-review.sh}"
root="$(mktemp -d)"
trap 'rm -r -- "$root"' EXIT
mkdir -p "$root/bin" "$root/tmp" "$root/config with spaces/sno" "$root/absent"
printf 'export const value = 1;\n' >"$root/target.ts"
cat >"$root/bin/codex" <<'STUB'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == login ]] && exit 0   # the wrapper's logged-in probe
printf '%s\n' "$@" >"$CAPTURE_ARGS"
while [[ $# -gt 0 ]]; do
    if [[ "$1" == --output-last-message ]]; then
        printf 'Verdict: approve\n' >"$2"
        shift
    fi
    shift
done
cat >/dev/null
STUB
chmod +x "$root/bin/codex"
failures=0

for state in configured absent empty missing; do
    config="$root/config with spaces"
    case "$state" in
        configured) printf '[other]\nreviewer = "wrong-section"\n[models] # roles\n coder = "coder-fixture"\n reviewer = "review-fixture" # selected\n eval = "eval-fixture"\n' >"$config/sno/models.toml" ;;
        absent) config="$root/absent" ;;
        empty) printf '[models]\nreviewer = ""\n' >"$config/sno/models.toml" ;;
        missing) printf "[models]\neval = 'eval-fixture'\n[other]\nreviewer = 'wrong-section'\n" >"$config/sno/models.toml" ;;
    esac
    env -u CODEX_EFFORT REVIEW_CALLER=claude-code PATH="$root/bin:$PATH" TMPDIR="$root/tmp" \
        XDG_CONFIG_HOME="$config" CODEX_MODEL=ignored-env-model \
        CAPTURE_ARGS="$root/args" STATS_FILE="$root/$state.jsonl" \
        FINDINGS_FILE="$root/findings.jsonl" REVIEW_ARCHIVE_DIR="$root/archive" \
        MAX_RETRIES=0 POLL_SECS=1 \
        timeout 15 bash "$review" "$root/target.ts" >"$root/out" 2>"$root/err"
    if python3 - "$root/args" "$state" <<'PY'
import pathlib
import sys

args = pathlib.Path(sys.argv[1]).read_text().splitlines()
flags = [arg for arg in args if arg in ('--model', '-m') or arg.startswith(('--model=', '-m='))]
if sys.argv[2] == 'configured':
    assert flags == ['--model'], args
    assert args[args.index('--model') + 1] == 'review-fixture', args
else:
    assert flags == [], args
assert 'ignored-env-model' not in args, args
assert 'model_reasoning_effort=high' in args, args
PY
    then
        printf 'PASS reviewer model settings: %s\n' "$state"
    else
        printf 'FAIL reviewer model settings: %s\n' "$state" >&2
        failures=1
    fi
done

cat >"$root/bin/claude" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == auth ]] && exit 0    # the wrapper's logged-in probe
printf '%s\n' "$@" >"$CAPTURE_ARGS"
cat >/dev/null
case "$CLAUDE_TEST_RESULT" in
    ok) printf 'Verdict: needs-attention\n\n- [high] Wrong total (target.ts:1)\n' ;;
    empty) exit 0 ;;
    fail) printf 'provider unavailable\n' >&2; exit 3 ;;
esac
STUB
chmod +x "$root/bin/claude"
mkdir -p "$root/claude-config/sno"
for result in ok empty fail; do
    status=0
    config="$root/claude-config"
    case "$result" in
        ok) printf '[models]\nreviewer = "codex-fixture"\nreviewer_claude = "review-model-x"\n' >"$config/sno/models.toml" ;;
        empty) printf '[models]\nreviewer_claude = ""\n' >"$config/sno/models.toml" ;;
        fail) config="$root/absent" ;;
    esac
    env REVIEW_CALLER=codex CLAUDECODE=1 CODEX_THREAD_ID=inherited \
        PATH="$root/bin:$PATH" TMPDIR="$root/tmp" XDG_CONFIG_HOME="$config" \
        CLAUDE_TEST_RESULT="$result" CAPTURE_ARGS="$root/args" \
        STATS_FILE="$root/claude-$result.jsonl" FINDINGS_FILE="$root/findings.jsonl" \
        REVIEW_OUTPUT_FILE="$root/report.md" MAX_RETRIES=0 POLL_SECS=1 \
        timeout 15 bash "$review" "$root/target.ts" >"$root/out" 2>"$root/err" || status=$?
    if python3 - "$root" "$result" "$status" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
result = sys.argv[2]
args = (root / 'args').read_text().splitlines()
if result == 'ok':
    assert args[args.index('--model') + 1] == 'review-model-x', args
else:
    assert '--model' not in args, args
assert args[args.index('--effort') + 1] == 'medium', args
assert args[args.index('--tools') + 1] == '', args
rows = [json.loads(line) for line in (root / f'claude-{result}.jsonl').read_text().splitlines()]
end = next(row for row in rows if row['event'] == 'end')
if result == 'ok':
    assert sys.argv[3] == '0', sys.argv
    assert end['outcome'] == 'success', end
    assert 'Wrong total' in (root / 'report.md').read_text()
else:
    assert sys.argv[3] == '6', sys.argv
    assert end['outcome'] == 'failed', end
    assert end['failure'] == ('empty' if result == 'empty' else 'exit:3'), end
PY
    then printf 'PASS Claude review: %s\n' "$result"
    else failures=1
    fi
done
exit "$failures"
