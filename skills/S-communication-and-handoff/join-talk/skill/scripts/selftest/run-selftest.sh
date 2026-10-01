#!/usr/bin/env bash
# run-selftest.sh — prove join-talk.sh derives the seat from its environment and refuses cleanly.
#
# Runs against the script beside this directory with a fake HOME and a stub `sno` that
# records what it was called with. Nothing outside TMPDIR is touched, so a deployed copy
# can test itself without registering a real seat.
#
# Usage: bash run-selftest.sh
# Exit:  0 every case passed · 1 a case failed · 2 the suite could not run.
set -Eeuo pipefail
export LC_ALL=C

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JOIN="$HERE/../join-talk.sh"
[[ -f "$JOIN" ]] || { printf 'selftest: join-talk.sh is missing: %s\n' "$JOIN" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/join-talk-selftest.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

FAKE_HOME="$WORK/home"
LOG="$WORK/calls.log"
mkdir -p "$FAKE_HOME/.local/state/sno-reach" "$FAKE_HOME/bin"

# A stub `sno` ahead of the real one: it records the argv and succeeds. The real runtime
# validates flags itself; the point here is what join-talk.sh decided to pass.
cat >"$FAKE_HOME/bin/sno" <<'EOF'
#!/usr/bin/env bash
printf 'sno %s\n' "$*" >>"$JOIN_SELFTEST_LOG"
EOF
chmod +x "$FAKE_HOME/bin/sno"
export JOIN_SELFTEST_LOG="$LOG"

REPO="$WORK/My_Repo.v2"
mkdir -p "$REPO/sub"
git -C "$REPO" init -q

host="$(hostname | tr '[:upper:]' '[:lower:]')"
failures=0
fail() { printf 'FAIL %s\n' "$*" >&2; failures=$((failures + 1)); }
pass() { printf 'ok   %s\n' "$*"; }

run_join() {
  # run_join <label> [args...] — runs from the repo's subdirectory under the fake HOME.
  local label="$1"
  shift
  : >"$LOG"
  set +e
  out="$(cd "$REPO/sub" && env -i HOME="$FAKE_HOME" PATH="$FAKE_HOME/bin:$PATH" TMUX_PANE='%7' \
    JOIN_SELFTEST_LOG="$LOG" bash "$JOIN" "$@" 2>"$WORK/$label.err")"
  rc=$?
  set -e
}

# 1. Derived address and name; init then register; one stdout line.
run_join derive
[[ $rc -eq 0 ]] || fail "derive: exit $rc: $(cat "$WORK/derive.err")"
[[ "$out" == "joined hand.my-repo-v2@$host" ]] || fail "derive: stdout was: $out"
grep -q -- "^sno reach init --as hand.my-repo-v2@$host --name my-repo-v2\$" "$LOG" ||
  fail "derive: reach init call was: $(grep '^sno reach init' "$LOG" || true)"
grep -q -- "^sno reach register --as hand.my-repo-v2@$host --channel tmux --handle %7\$" "$LOG" ||
  fail "derive: reach register call was: $(grep '^sno reach register' "$LOG" || true)"
[[ $failures -eq 0 ]] && pass "derived seat from repo and terminal"

# 2. Chosen address and name pass through untouched.
run_join chosen review.example-repo@host1 --name Fjord
[[ $rc -eq 0 && "$out" == 'joined review.example-repo@host1' ]] || fail "chosen: rc=$rc out=$out"
grep -q -- '^sno reach init --as review.example-repo@host1 --name Fjord$' "$LOG" || fail "chosen: init call was: $(grep '^sno reach init' "$LOG" || true)"
pass "chosen address and name"

# 3. A live seat held by another terminal steps aside with a suffix; the same terminal reuses it.
seat="$FAKE_HOME/.local/state/sno-reach/hand.my-repo-v2@$host"
mkdir -p "$seat"
printf '{"identity":{"kind":"tmux-pane","value":"%%9"}}\n' >"$seat/reachable.json"
run_join suffix
[[ "$out" == "joined hand.my-repo-v2-2@$host" ]] || fail "suffix: stdout was: $out"
printf '{"identity":{"kind":"tmux-pane","value":"%%7"}}\n' >"$seat/reachable.json"
run_join same
[[ "$out" == "joined hand.my-repo-v2@$host" ]] || fail "same terminal: stdout was: $out"
pass "suffix on collision, reuse on the same terminal"

# 4. Refusals: no terminal (exit 3), bad address (exit 2), unknown option (exit 2).
: >"$LOG"
set +e
(cd "$REPO" && env -i HOME="$FAKE_HOME" PATH="$FAKE_HOME/bin:$PATH" JOIN_SELFTEST_LOG="$LOG" bash "$JOIN" 2>"$WORK/noterm.err")
rc=$?
set -e
if [[ $rc -ne 3 ]] || ! grep -q 'no terminal' "$WORK/noterm.err"; then
  fail "no terminal: rc=$rc $(cat "$WORK/noterm.err")"
fi
[[ ! -s "$LOG" ]] || fail "no terminal: runtime was still called: $(cat "$LOG")"
run_join badaddr 'Team Lead.x@host1'
[[ $rc -eq 2 ]] || fail "bad address: rc=$rc"
run_join badopt --bogus
[[ $rc -eq 2 ]] || fail "unknown option: rc=$rc"
pass "refusals exit 2/3 before any runtime call"

# 5. Under Orca the Reach handle is the terminal handle; without it, refuse before any call.
: >"$LOG"
set +e
out="$(cd "$REPO" && env -i HOME="$FAKE_HOME" PATH="$FAKE_HOME/bin:$PATH" JOIN_SELFTEST_LOG="$LOG" \
  ORCA_TAB_ID=tab-1 ORCA_TERMINAL_HANDLE=term_abc bash "$JOIN" orca.seat@host1 2>"$WORK/orca.err")"
rc=$?
set -e
[[ $rc -eq 0 && "$out" == 'joined orca.seat@host1' ]] || fail "orca: rc=$rc out=$out $(cat "$WORK/orca.err")"
grep -q -- '^sno reach register --as orca.seat@host1 --channel orca --handle term_abc$' "$LOG" ||
  fail "orca: reach register call was: $(grep '^sno reach register' "$LOG" || true)"
: >"$LOG"
set +e
(cd "$REPO" && env -i HOME="$FAKE_HOME" PATH="$FAKE_HOME/bin:$PATH" JOIN_SELFTEST_LOG="$LOG" \
  ORCA_TAB_ID=tab-1 bash "$JOIN" orca.seat@host1 2>"$WORK/orca-nohandle.err")
rc=$?
set -e
[[ $rc -eq 3 && ! -s "$LOG" ]] || fail "orca without handle: rc=$rc log=$(cat "$LOG")"
pass "orca handle comes from ORCA_TERMINAL_HANDLE"

# 6. A mixed-case hostname (a Windows or macOS default) is lowercased into a valid address.
mkdir -p "$WORK/hostbin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "Team-MacBook.local"\n' >"$WORK/hostbin/hostname"
chmod +x "$WORK/hostbin/hostname"
: >"$LOG"
set +e
out="$(cd "$REPO" && env -i HOME="$FAKE_HOME" PATH="$WORK/hostbin:$FAKE_HOME/bin:$PATH" TMUX_PANE='%7' \
  JOIN_SELFTEST_LOG="$LOG" bash "$JOIN" 2>"$WORK/mixedhost.err")"
rc=$?
set -e
[[ $rc -eq 0 && "$out" == 'joined hand.my-repo-v2@team-macbook.local' ]] || fail "mixed-case host: rc=$rc out=$out $(cat "$WORK/mixedhost.err")"
pass "mixed-case hostname is lowercased"

if [[ $failures -eq 0 ]]; then
  printf 'join-talk selftest: all cases passed\n'
  exit 0
fi
printf 'join-talk selftest: %d failure(s)\n' "$failures" >&2
exit 1
