#!/usr/bin/env bash
# The rem-reflect self-test runs the unit suite, then the full fixture journey
# under a PATH that holds only an allowlist of programs — node, git, a named set of coreutils, and the
# fixture claude / codex / sno shims — each a recording wrapper, so every child process exec is
# logged. It asserts the recorded exec list names no program outside the allowlist, and that a program
# spawning python3 (outside the allowlist) fails naming it. It finishes well under 300 seconds.
set -Eeuo pipefail

START=$(date +%s)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(dirname "$HERE")"
BIN_SRC="$HERE/bin"

fail() { printf 'run-selftest: FAIL: %s\n' "$1" >&2; exit 1; }

# On the home disk, not the system temp directory, which may be a RAM disk shared with other work.
mkdir -p "$HOME/.cache/rem-reflect-tests"
WORK="$(mktemp -d "$HOME/.cache/rem-reflect-tests/selftest.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
ALLOW_BIN="$WORK/bin"
mkdir -p "$ALLOW_BIN"
EXEC_LOG="$WORK/exec.log"
: > "$EXEC_LOG"

# The allowlist of real programs the journey may reach. Each becomes a recording wrapper that logs its
# own name to EXEC_LOG and then execs the real binary (resolved now, while the normal PATH still holds).
ALLOW_PROGRAMS=(node git sh bash env cat uname dirname basename mkdir rm cp mv ln chmod mktemp date sort grep sed head tail wc tr cut readlink)
# The wrapper shebang must be the real bash by absolute path: under the allowlist-only PATH a
# `#!/usr/bin/env bash` wrapper would re-resolve `bash` to the wrapper itself and recurse.
REAL_BASH="$(command -v bash)"
[[ -n "$REAL_BASH" ]] || fail "bash not found"
for prog in "${ALLOW_PROGRAMS[@]}"; do
  real="$(command -v "$prog" || true)"
  [[ -n "$real" ]] || continue
  { printf '#!%s\n' "$REAL_BASH"
    printf 'printf "%%s\\n" %q >> %q\n' "$prog" "$EXEC_LOG"
    printf 'exec %q "$@"\n' "$real"
  } > "$ALLOW_BIN/$prog"
  chmod +x "$ALLOW_BIN/$prog"
done
# The fixture CLIs: the real shims, which self-record to EXEC_LOG. They need shim-core.cjs beside them.
for shim in claude codex sno; do
  cp -- "$BIN_SRC/$shim" "$ALLOW_BIN/$shim"
  chmod +x "$ALLOW_BIN/$shim"
done
cp -- "$BIN_SRC/shim-core.cjs" "$ALLOW_BIN/shim-core.cjs"

# The set of names allowed to appear in the exec log (the wrappers plus the three shims).
declare -A ALLOWED=()
for prog in "${ALLOW_PROGRAMS[@]}" claude codex sno; do ALLOWED["$prog"]=1; done

# The unit suite runs under the normal environment because it exercises tools outside the journey's allowlist.
printf 'run-selftest: unit suite...\n'
( cd "$SCRIPTS" && node --test --experimental-strip-types ) >/dev/null 2>&1 || fail "the unit suite did not pass"

# Parse an strace `-e trace=execve` log into the basenames of every program actually exec'd. This
# captures every child exec, including one launched by an absolute path that bypasses PATH.
execd_basenames() {
  sed -n 's/^[0-9 ]*execve("\([^"]*\)".*/\1/p' "$1" | while read -r p; do basename -- "$p"; done | sort -u
}

# The full fixture journey runs under the allowlist-only PATH. When available, strace records
# absolute-path child processes too. REM_SELFTEST keeps the driver from re-adding ambient PATH.
printf 'run-selftest: fixture journey under the allowlist PATH...\n'
EXECVE_LOG="$WORK/execve.log"
if [[ "$(uname -s)" == Linux ]] && command -v strace >/dev/null 2>&1; then
  journey_out="$(strace -f -e trace=execve -o "$EXECVE_LOG" \
    env PATH="$ALLOW_BIN" EXEC_LOG="$EXEC_LOG" REM_SELFTEST=1 \
    node --experimental-strip-types "$HERE/journey.mjs" isolated 2>&1)" \
    || { printf '%s\n' "$journey_out" >&2; fail "the fixture journey did not pass under the allowlist PATH"; }
  [[ -s "$EXECVE_LOG" ]] || fail "strace recorded no execve (the instrument did not run)"
else
  journey_out="$(env PATH="$ALLOW_BIN" EXEC_LOG="$EXEC_LOG" REM_SELFTEST=1 \
    node --experimental-strip-types "$HERE/journey.mjs" isolated 2>&1)" \
    || { printf '%s\n' "$journey_out" >&2; fail "the fixture journey did not pass under the allowlist PATH"; }
  printf 'run-selftest: SKIP socket and absolute-path exec traces: strace is unavailable on this machine\n'
fi
grep -q 'JOURNEY OK isolated' <<<"$journey_out" || { printf '%s\n' "$journey_out" >&2; fail "the journey did not report success"; }

# 3. Every program actually exec'd (from the execve trace) is within the allowlist; the shims also
#    self-recorded to EXEC_LOG (recorded by the shims).
[[ -s "$EXEC_LOG" ]] || fail "the shims recorded no exec (the instrument did not run)"
if [[ -s "$EXECVE_LOG" ]]; then
  mapfile -t RAN < <(execd_basenames "$EXECVE_LOG")
else
  mapfile -t RAN < <(sort -u "$EXEC_LOG")
fi
for prog in "${RAN[@]}"; do
  [[ -n "${ALLOWED[$prog]:-}" ]] || fail "a program outside the allowlist was executed: $prog"
done
printf 'run-selftest: %s distinct programs exec'\''d, all within the allowlist\n' "${#RAN[@]}"

# 4a. Negative control by name: a program that spawns python3 by name fails under the allowlist, naming it.
printf 'run-selftest: python3 negative control (by name)...\n'
if neg_out="$(PATH="$ALLOW_BIN" EXEC_LOG="$EXEC_LOG" REM_SELFTEST=1 \
  node --experimental-strip-types "$HERE/spawn-python.mjs" 2>&1)"; then
  fail "a program spawning python3 by name was allowed to succeed under the allowlist"
fi
grep -q 'python3' <<<"$neg_out" || fail "the python3 failure did not name python3"

# 4b. Negative control by absolute path: python3 launched by absolute path bypasses the PATH allowlist
#     and runs, but the execve recorder must still catch it, proving the allowlist check has no blind spot.
PY_ABS="$(command -v python3 || true)"
if [[ -n "$PY_ABS" && -s "$EXECVE_LOG" ]]; then
  printf 'run-selftest: python3 negative control (absolute path bypass)...\n'
  BYPASS_LOG="$WORK/bypass.log"
  strace -f -e trace=execve -o "$BYPASS_LOG" \
    env PATH="$ALLOW_BIN" PY_ABS="$PY_ABS" REM_SELFTEST=1 \
    node --experimental-strip-types "$HERE/spawn-python.mjs" >/dev/null 2>&1 || true
  execd_basenames "$BYPASS_LOG" | grep -qx 'python3' \
    || fail "the execve recorder failed to catch an absolute-path python3 (allowlist check has a blind spot)"
fi

# The usage-statistics rows go through the real CLI, first with the recording `sno` shim and
#    then with no `sno` on PATH at all (the journey builds both PATHs itself).
printf 'run-selftest: observe rows journey...\n'
observe_out="$(node --experimental-strip-types "$HERE/observe-journey.mjs" 2>&1)" \
  || { printf '%s\n' "$observe_out" >&2; fail "the observe rows journey did not pass"; }

ELAPSED=$(( $(date +%s) - START ))
(( ELAPSED < 300 )) || fail "the self-test took ${ELAPSED}s, over the 300s budget"
printf 'Self-test OK: unit suite passed, journey passed under the allowlist (%ss), python3 was refused by name\n' "$ELAPSED"
