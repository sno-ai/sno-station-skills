#!/usr/bin/env bash
# run-selftest.sh — exercise run-adversarial-review.sh's accounting paths.
#
# A review without a report must leave a ledger record so a caller can tell
# "found nothing" from "never ran". Reading the code cannot verify that, because
# the broken path is the one that writes nothing. Every row below drives the real script down a failure path and then
# asserts what landed in the ledger.
#
# No real reviewer calls are spent: a stub `codex` is placed first on PATH and
# told how to misbehave through STUB_MODE.
set -Eeuo pipefail

# Python must not write bytecode here: a generated __pycache__ would leave stray
# files inside the skill directory.
export PYTHONDONTWRITEBYTECODE=1
export REVIEW_CALLER=claude-code

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REVIEW="${REVIEW:-$HERE/../run-adversarial-review.sh}"
[[ -r "$REVIEW" ]] || { printf 'selftest: cannot read %s\n' "$REVIEW" >&2; exit 2; }

ROOT="$(mktemp -d)"
trap 'rm -rf -- "$ROOT"' EXIT

tests=0
failures=0
check() { # $1 label, rest: command
    local label="$1"; shift
    tests=$((tests + 1))
    if "$@"; then
        printf 'ok %d - %s\n' "$tests" "$label"
    else
        printf 'not ok %d - %s\n' "$tests" "$label"
        failures=$((failures + 1))
    fi
}

# ---- stub codex -----------------------------------------------------------
# Honors --output-last-message so the wrapper's "did it produce anything?" check
# is exercised for real rather than simulated.
mkdir -p "$ROOT/bin"
cat > "$ROOT/bin/codex" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == login ]] && exit "${STUB_CODEX_LOGIN_RC:-0}"   # the wrapper's logged-in probe
out=""
[[ -z "${CAPTURE_ARGS:-}" ]] || printf '%s\n' "$@" > "$CAPTURE_ARGS"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-last-message) out="$2"; shift 2 ;;
        *) shift ;;
    esac
done
cat >/dev/null   # drain the piped prompt so the wrapper never blocks on write
case "${STUB_MODE:-ok}" in
    ok)    [[ -n "$out" ]] && printf 'Verdict: approve\n\nFindings:\n- [high] [fix-now] stub finding (src/stub.ts:1-2, confidence 0.90)\n' > "$out"; exit 0 ;;
    clean) [[ -n "$out" ]] && printf 'Verdict: approve\n\nFindings: none\n' > "$out"; exit 0 ;;
    debt)  [[ -n "$out" ]] && printf 'Verdict: approve\n\nFindings:\n- [medium] [debt] old issue (a.ts:3, confidence 0.50)\n' > "$out"; exit 0 ;;
    empty) [[ -n "$out" ]] && : > "$out"; exit 0 ;;          # clean exit, nothing written
    fail)  exit 3 ;;
    hang)  sleep 300 ;;                                       # never writes, never exits
esac
STUB
chmod +x "$ROOT/bin/codex"
# Recording stand-in for `sno observe` (the real tool uploads); first on PATH for every case.
mkdir -p "$ROOT/obsbin"
cat > "$ROOT/obsbin/sno" <<'OBS'
#!/usr/bin/env bash
[[ "${1:-}" == observe ]] || exit 64
shift
printf '%s\n' "$*" >>"$OBSERVE_LOG"
exit "${FAKE_OBSERVE_EXIT:-0}"
OBS
chmod +x "$ROOT/obsbin/sno"
export OBSERVE_LOG="$ROOT/observe.log"; : > "$OBSERVE_LOG"
export PATH="$ROOT/obsbin:$ROOT/bin:$PATH"

# Everything the wrapper writes to is redirected into this test's own directory.
# TMPDIR keeps its concurrency slots from taking or releasing a slot belonging to
# a real review running right now. The other two matter just as much: without
# them the stub's fake report lands in the real archive and its fake finding in
# the real findings ledger.
export TMPDIR="$ROOT/tmp"; mkdir -p "$TMPDIR"
export REVIEW_ARCHIVE_DIR="$ROOT/archive-default"
export FINDINGS_FILE="$ROOT/findings-default.jsonl"
export XDG_CONFIG_HOME="$ROOT/config"
mkdir -p "$XDG_CONFIG_HOME/sno"
printf '[models]\nreviewer = "stub-model"\n' >"$XDG_CONFIG_HOME/sno/models.toml"

TARGET="$ROOT/target.ts"
printf 'export const a = 1;\n' > "$TARGET"
PROMPT="$HERE/../../assets/adversarial-plan-review.prompt.md"
[[ -r "$PROMPT" ]] || { printf 'selftest: cannot read %s\n' "$PROMPT" >&2; exit 2; }

# ---- helpers --------------------------------------------------------------
ledger=""            # set per case
run_review() {       # run the wrapper with a fresh ledger unless KEEP=1 is set
    [[ "${KEEP:-0}" -eq 1 ]] || { ledger="$ROOT/ledger-$RANDOM.jsonl"; : > "$ledger"; }
    STATS_FILE="$ledger" \
    CODEX_EFFORT=stub-effort \
    MAX_RETRIES=0 POLL_SECS=1 PROGRESS_SECS=1000 BACKOFF_BASE_SECS=1 \
    STALL_SECS="${STALL_SECS_OVERRIDE:-600}" TIMEOUT_SECS="${TIMEOUT_SECS_OVERRIDE:-3600}" \
    bash "$REVIEW" "$@" >/dev/null 2>"${REVIEW_ERR:-/dev/null}"
}
n_event() { grep -c "\"event\":\"$1\"" "$ledger" 2>/dev/null || true; }
has() { grep -q "$1" "$ledger"; }

# The signal rows must send the signal to the WRAPPER, not to a subshell wrapping
# it — otherwise the wrapper survives, writes no end line, and the SIGKILL row
# passes for the wrong reason. Backgrounding `bash "$REVIEW"` as the last command
# makes $! that process.
BG_PID=""
start_review_bg() {
    ledger="$1"; : > "$ledger"
    STATS_FILE="$ledger" \
    CODEX_EFFORT=stub-effort STUB_MODE=hang \
    MAX_RETRIES=0 POLL_SECS=1 PROGRESS_SECS=1000 BACKOFF_BASE_SECS=1 \
    STALL_SECS=600 TIMEOUT_SECS=3600 \
    bash "$REVIEW" "$TARGET" >/dev/null 2>&1 &
    BG_PID=$!
}
await_start() { # the wrapper must have reached dispatch before we signal it
    local _i
    for _i in $(seq 1 60); do
        grep -q '"event":"start"' "$ledger" 2>/dev/null && return 0
        sleep 0.25
    done
    return 1
}
reap() {
    local pid
    wait "$BG_PID" 2>/dev/null || true
    while IFS= read -r pid; do
        kill -9 "$pid" 2>/dev/null || true
    done < <(pgrep -f "^bash ${ROOT}/bin/codex( |$)" 2>/dev/null || true)
}

# ---- 1. success: exactly one start and one end, and the end says success ----
case_success() {
    local rc=0
    STUB_MODE=ok run_review "$TARGET" || rc=$?
    [[ "$rc" -eq 0 ]] || return 1
    [[ "$(n_event start)" -eq 1 ]] || return 1
    [[ "$(n_event end)" -eq 1 ]] || return 1
    has '"outcome":"success"' || return 1
    has '"targets":\["'"$TARGET"'"\]'          # the receipt needs paths, not just the scope hash
}
check "success writes one start and one end carrying the target paths" case_success

# ---- review.run upload: one event per successful review, nothing otherwise ----
observe_lines() { : > "$OBSERVE_LOG"; "$@" || true; cat "$OBSERVE_LOG"; }
case_event_found() {
    local out; out="$(observe_lines env STUB_MODE=ok bash -c "$(declare -f run_review n_event has); ROOT='$ROOT' REVIEW='$REVIEW' run_review '$TARGET'")"
    [[ "$(grep -c '^append review.run ' <<<"$out")" -eq 1 ]] || return 1
    grep -Eq '^append review.run --agent=claude-code --project=/[^ ]+ --author_harness=claude-code --reviewer_harness=codex --findings_p1=1 --findings_p2=0 --findings_p3=0 --empty=false --duration_ms=[0-9]+$' <<<"$out"
}
check "a successful review uploads one review.run with author, reviewer and counts" case_event_found
case_event_author() {
    local out; out="$(observe_lines env STUB_MODE=ok REVIEW_AUTHOR=codex bash -c "$(declare -f run_review n_event has); ROOT='$ROOT' REVIEW='$REVIEW' run_review '$TARGET'")"
    grep -Eq '^append review.run --agent=claude-code --project=/[^ ]+ --author_harness=codex --reviewer_harness=codex ' <<<"$out"
}
check "REVIEW_AUTHOR names who wrote the work; the caller stays the sender" case_event_author
case_event_clean() {
    : > "$OBSERVE_LOG"; STUB_MODE=clean run_review "$TARGET" || return 1
    grep -Eq -- '--findings_p1=0 --findings_p2=0 --findings_p3=0 --empty=true --duration_ms=[0-9]+$' "$OBSERVE_LOG"
}
check "a review with no findings uploads empty=true" case_event_clean
case_event_debt() {
    : > "$OBSERVE_LOG"; STUB_MODE=debt run_review "$TARGET" || return 1
    grep -Eq -- '--findings_p1=0 --findings_p2=0 --findings_p3=0 --empty=true ' "$OBSERVE_LOG"
}
check "a debt-only report is not counted as a problem" case_event_debt
case_event_failed() {
    : > "$OBSERVE_LOG"; STUB_MODE=fail run_review "$TARGET" || true
    [[ ! -s "$OBSERVE_LOG" ]]
}
check "a failed review uploads nothing" case_event_failed
case_event_missing() {
    local rc=0; : > "$OBSERVE_LOG"; REVIEW_ERR="$ROOT/err.txt"
    PATH="$ROOT/bin:/usr/bin:/bin" STUB_MODE=ok run_review "$TARGET" || rc=$?
    unset REVIEW_ERR
    [[ "$rc" -eq 0 ]] && grep -q '^sno: not found; review.run event not recorded$' "$ROOT/err.txt"
}
check "tool missing: the review still succeeds and one not-recorded line is printed" case_event_missing
case_event_broken() {
    local rc=0; REVIEW_ERR="$ROOT/err.txt"
    FAKE_OBSERVE_EXIT=3 STUB_MODE=ok run_review "$TARGET" || rc=$?
    unset REVIEW_ERR
    [[ "$rc" -eq 0 ]] && grep -q '^sno observe append review.run failed (exit 3); event not recorded$' "$ROOT/err.txt"
}
check "tool failing: the review still succeeds and names the event and exit code" case_event_broken

check "model settings and default effort reach the Codex CLI" bash "$HERE/run-model-settings.sh"

# ---- reviewer choice: other vendor preferred, same vendor as a labelled fallback
cat > "$ROOT/bin/claude" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == auth ]] && exit 0    # the wrapper's logged-in probe
cat >/dev/null
printf 'Verdict: approve\n\nFindings: none\n\nstub-claude-report\n'
STUB
chmod +x "$ROOT/bin/claude"

sv_run() { # $1 = report path; run the wrapper as a Claude caller, extra env from caller
    ledger="$ROOT/ledger-sv-$RANDOM.jsonl"; : > "$ledger"
    STATS_FILE="$ledger" REVIEW_OUTPUT_FILE="$1" REVIEW_CALLER=claude-code \
    CODEX_EFFORT=stub-effort MAX_RETRIES=0 POLL_SECS=1 PROGRESS_SECS=1000 \
        bash "$REVIEW" "$TARGET" >/dev/null 2>&1
}
case_cross_vendor_no_header() { # other vendor installed and logged in: used, no label
    local rep="$ROOT/sv-cross.md"
    STUB_MODE=ok sv_run "$rep" || return 1
    ! grep -q 'same-vendor' "$rep" && ! grep -q 'stub-claude-report' "$rep"
}
check "an installed, logged-in other-vendor CLI is the reviewer and the report is not labelled same-vendor" case_cross_vendor_no_header

case_same_vendor_not_logged_in() { # other CLI installed but logged out
    local rep="$ROOT/sv-loggedout.md"
    STUB_CODEX_LOGIN_RC=1 sv_run "$rep" || return 1
    [[ "$(head -1 "$rep")" == 'Reviewer: same-vendor review'* ]] || return 1
    grep -q 'stub-claude-report' "$rep" || return 1
    has '"outcome":"success"'
}
check "a logged-out other CLI falls back to a same-vendor review labelled on the first line" case_same_vendor_not_logged_in

path_without_reviewers() { # $PATH minus every directory that holds codex or claude
    local d out="" IFS=:
    for d in $PATH; do [[ -x "$d/codex" || -x "$d/claude" ]] || out+="$d:"; done
    printf '%s' "${out%:}"
}
case_same_vendor_other_missing() { # other CLI not installed at all
    local rep="$ROOT/sv-missing.md" clean_path
    clean_path="$(path_without_reviewers)"
    mkdir -p "$ROOT/bin-claude-only"; cp "$ROOT/bin/claude" "$ROOT/bin-claude-only/claude"
    PATH="$ROOT/bin-claude-only:$clean_path" sv_run "$rep" || return 1
    [[ "$(head -1 "$rep")" == 'Reviewer: same-vendor review'* ]] && grep -q 'stub-claude-report' "$rep"
}
check "a missing other-vendor CLI never refuses: the caller's own CLI reviews and says so" case_same_vendor_other_missing

case_no_cli_at_all() { # neither CLI installed: one clear error, exit 2
    local rc=0 err="$ROOT/nocli.err"
    PATH="$(path_without_reviewers)" REVIEW_CALLER=claude-code STATS_FILE="$ROOT/ledger-nocli.jsonl" \
        bash "$REVIEW" "$TARGET" >/dev/null 2>"$err" || rc=$?
    [[ "$rc" -eq 2 ]] && grep -q 'neither the .codex. nor the .claude. CLI is installed and logged in' "$err"
}
check "with neither CLI installed the wrapper exits 2 with one clear message" case_no_cli_at_all

# ---- 2. empty response is recorded, and named as empty ---------------------
case_empty() {
    local rc=0
    STUB_MODE=empty run_review "$TARGET" || rc=$?
    [[ "$rc" -eq 6 ]] || return 1
    [[ "$(n_event start)" -eq 1 ]] || return 1
    [[ "$(n_event end)" -eq 1 ]] || return 1
    has '"outcome":"failed"' || return 1
    has '"failure":"empty"'
}
check "codex exiting clean with no report is recorded as failure=empty" case_empty

# ---- 3. codex failing is distinguished from producing nothing --------------
case_exit() {
    local rc=0
    STUB_MODE=fail run_review "$TARGET" || rc=$?
    [[ "$rc" -eq 6 ]] || return 1
    has '"failure":"exit:3"'
}
check "codex exiting nonzero is recorded as failure=exit:<n>, not empty" case_exit

# ---- 4. the watchdog kill is recorded, not silent --------------------------
case_watchdog() {
    local rc=0
    STUB_MODE=hang STALL_SECS_OVERRIDE=3 TIMEOUT_SECS_OVERRIDE=20 \
        run_review "$TARGET" || rc=$?
    [[ "$rc" -eq 6 ]] || return 1
    has '"failure":"watchdog"'
}
check "a stalled codex killed by the watchdog is recorded as failure=watchdog" case_watchdog

# ---- 5. SIGKILL: a start line with no end IS the uncovered row -------------
# This is the case the whole change exists for. A trap cannot run here.
case_sigkill() {
    start_review_bg "$ROOT/ledger-kill.jsonl"
    await_start || return 1
    kill -9 "$BG_PID" 2>/dev/null || return 1
    reap
    kill -0 "$BG_PID" 2>/dev/null && return 1   # prove the wrapper is really gone
    [[ "$(n_event start)" -eq 1 ]] || return 1
    [[ "$(n_event end)" -eq 0 ]]                # unmatched start == "not actually covered"
}
check "SIGKILL leaves a start with no end (the uncovered-run signal)" case_sigkill

# ---- 6. SIGTERM: the trap still closes the record when it can --------------
case_sigterm() {
    start_review_bg "$ROOT/ledger-term.jsonl"
    await_start || return 1
    kill -TERM "$BG_PID" 2>/dev/null || return 1
    reap
    [[ "$(n_event end)" -eq 1 ]] || return 1
    has '"outcome":"interrupted"' || return 1
    has '"failure":"interrupted"'
}
check "SIGTERM closes the record with outcome=interrupted" case_sigterm

# ---- 7. round counting does not double now that start lines exist ----------
# The hard cap keys on this. Two completed reviews of one scope must leave the
# third reporting round 3 — counting every scope hit would say 5 and refuse.
case_rounds() {
    ledger="$ROOT/ledger-rounds.jsonl"; : > "$ledger"
    STUB_MODE=ok KEEP=1 run_review "$TARGET" || return 1
    STUB_MODE=ok KEEP=1 run_review "$TARGET" || return 1
    grep -q '"round":2,' "$ledger" || return 1
    STUB_MODE=ok KEEP=1 run_review "$TARGET" || return 1
    grep -q '"round":3,' "$ledger" || return 1
    ! grep -q '"round":[45],' "$ledger"
}
check "round counter reads completed reviews only (2 done -> next is round 3)" case_rounds

# ---- 8. the cap refusal is itself recorded, and does not count as a round ---
case_cap_refused() {
    ledger="$ROOT/ledger-cap.jsonl"; : > "$ledger"
    local rc=0
    STUB_MODE=ok KEEP=1 run_review "$TARGET" || return 1
    STUB_MODE=ok KEEP=1 run_review "$TARGET" || return 1
    STUB_MODE=ok KEEP=1 run_review "$TARGET" || return 1
    STUB_MODE=ok KEEP=1 run_review "$TARGET" || rc=$?
    [[ "$rc" -eq 10 ]] || return 1
    [[ "$(n_event refused)" -eq 1 ]] || return 1
    has '"reason":"cap"' || return 1
    # a refusal must not inflate the counter: a 5th call still reports cap 3 / round 4
    [[ "$(grep -c '"event":"end"' "$ledger")" -eq 3 ]]
}
check "reaching the cap records a refused line that is not counted as a round" case_cap_refused

# ---- 9. journey mode without its contract is refused AND recorded ----------
case_contract_refused() {
    ledger="$ROOT/ledger-contract.jsonl"; : > "$ledger"
    local rc=0
    STUB_MODE=ok KEEP=1 REVIEW_JOURNEY=j-test STATS_FILE="$ledger" \
        bash "$REVIEW" "$TARGET" >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 11 ]] || return 1
    has '"reason":"contract"'
}
check "journey mode missing charter/fence is recorded as refused" case_contract_refused

# ---- 10. every ledger line is valid JSON ----------------------------------
case_json() {
    ledger="$ROOT/ledger-json.jsonl"; : > "$ledger"
    STUB_MODE=ok KEEP=1 run_review "$TARGET" || return 1
    STUB_MODE=empty KEEP=1 run_review "$TARGET" || true
    python3 -c '
import json,sys
for i, line in enumerate(open(sys.argv[1]), 1):
    line = line.strip()
    if line:
        json.loads(line)
' "$ledger"
}
check "every ledger line parses as JSON" case_json

# ---- 11. the receipt names every run that produced no review ---------------
# A receipt that only lists what succeeded is the failure it exists to prevent.
RECEIPT="$HERE/../review-receipt.sh"
case_receipt() {
    ledger="$ROOT/ledger-receipt.jsonl"; : > "$ledger"
    STUB_MODE=ok    KEEP=1 run_review "$TARGET" || return 1      # covered
    STUB_MODE=empty KEEP=1 run_review "$TARGET" || true          # failed: empty
    start_review_bg "$ROOT/ledger-receipt-kill.jsonl"            # killed: start, no end
    await_start || return 1
    kill -9 "$BG_PID" 2>/dev/null || return 1
    reap
    # start_review_bg repointed `ledger` at its own file; fold that run's lines
    # back into the receipt ledger and repoint before reading.
    cat "$ROOT/ledger-receipt-kill.jsonl" >> "$ROOT/ledger-receipt.jsonl"
    ledger="$ROOT/ledger-receipt.jsonl"

    local out
    out="$(STATS_FILE="$ledger" bash "$RECEIPT" --since all 2>&1)" || return 1
    grep -q 'NOT ACTUALLY COVERED (2)' <<<"$out" || return 1
    grep -q 'killed before it finished'  <<<"$out" || return 1
    grep -q 'review failed: empty'       <<<"$out" || return 1
    grep -q '^KILLED'                    <<<"$out" || return 1
    grep -q '^done'                      <<<"$out"
}
check "receipt lists killed and failed runs under 'not actually covered'" case_receipt

# ---- 12. --check turns the receipt into a gate; a clean ledger passes -------
case_receipt_check() {
    local rc=0
    ledger="$ROOT/ledger-receipt.jsonl"
    STATS_FILE="$ledger" bash "$RECEIPT" --since all --check >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 1 ]] || return 1
    ledger="$ROOT/ledger-clean.jsonl"; : > "$ledger"
    STUB_MODE=ok KEEP=1 run_review "$TARGET" || return 1
    rc=0
    STATS_FILE="$ledger" bash "$RECEIPT" --since all --check >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 0 ]]
}
check "--check exits 1 with uncovered runs and 0 without" case_receipt_check

# ---- 13. the report is kept somewhere durable, and the ledger points at it --
# A finding written to /tmp can be lost.
case_archive() {
    local arch="$ROOT/archive" out
    ledger="$ROOT/ledger-archive.jsonl"; : > "$ledger"
    STATS_FILE="$ledger" REVIEW_ARCHIVE_DIR="$arch" \
    CODEX_EFFORT=stub-effort STUB_MODE=ok \
    MAX_RETRIES=0 POLL_SECS=1 PROGRESS_SECS=1000 \
        bash "$REVIEW" "$TARGET" >/dev/null 2>&1 || return 1
    [[ -n "$(find "$arch" -name '*.md' -print -quit)" ]] || return 1
    out="$(python3 -c '
import json,sys
for l in open(sys.argv[1]):
    r=json.loads(l)
    if r.get("event")=="end": print(r.get("report",""))
' "$ledger")"
    [[ "$out" == "$arch"/* ]] || return 1
    [[ -s "$out" ]]
}
check "the report is written under the archive dir and named in the ledger" case_archive

# ---- 14. an explicit REVIEW_OUTPUT_FILE still wins (existing callers pass one) --
case_explicit_output() {
    local want="$ROOT/explicit-report.md"
    ledger="$ROOT/ledger-explicit.jsonl"; : > "$ledger"
    STATS_FILE="$ledger" REVIEW_ARCHIVE_DIR="$ROOT/archive2" REVIEW_OUTPUT_FILE="$want" \
    CODEX_EFFORT=stub-effort STUB_MODE=ok \
    MAX_RETRIES=0 POLL_SECS=1 PROGRESS_SECS=1000 \
        bash "$REVIEW" "$TARGET" >/dev/null 2>&1 || return 1
    [[ -s "$want" ]]
}
check "an explicit REVIEW_OUTPUT_FILE is still honoured exactly" case_explicit_output

# ---- 15. a plan review with no evidence file warns and is recorded as such ---
case_probe() {
    local plan="$ROOT/plan.md" probe="$ROOT/PROBE-RESULTS-x.md" err
    printf '# Plan\n\nThe table has 40 rows.\n' > "$plan"
    printf '# Probe\n\n$ wc -l table\n40\n' > "$probe"

    ledger="$ROOT/ledger-noprobe.jsonl"; : > "$ledger"; err="$ROOT/noprobe.err"
    STATS_FILE="$ledger" REVIEW_KIND=plan REVIEW_ARCHIVE_DIR="$ROOT/archive3" \
    CODEX_EFFORT=stub-effort STUB_MODE=ok \
    MAX_RETRIES=0 POLL_SECS=1 PROGRESS_SECS=1000 \
        bash "$REVIEW" "$plan" >/dev/null 2>"$err" || return 1
    grep -q 'no PROBE-RESULTS file among the targets' "$err" || return 1
    grep -q '"probe":false' "$ledger" || return 1

    ledger="$ROOT/ledger-probe.jsonl"; : > "$ledger"; err="$ROOT/probe.err"
    STATS_FILE="$ledger" REVIEW_KIND=plan REVIEW_ARCHIVE_DIR="$ROOT/archive4" \
    CODEX_EFFORT=stub-effort STUB_MODE=ok \
    MAX_RETRIES=0 POLL_SECS=1 PROGRESS_SECS=1000 \
        bash "$REVIEW" "$plan" "$probe" >/dev/null 2>"$err" || return 1
    ! grep -q 'no PROBE-RESULTS file' "$err" || return 1
    grep -q '"probe":true' "$ledger"
}
check "plan review without PROBE-RESULTS warns and records probe=false" case_probe

# ---- 16. findings land in the findings ledger, and repeats update in place --
FINDINGS="$HERE/../review-findings.sh"
case_findings() {
    local store="$ROOT/findings.jsonl" rep="$ROOT/report-a.md" out
    : > "$store"
    # A code finding with a class tag, a plan finding
    # without one, and a path containing parentheses of its own
    cat > "$rep" <<'REP'
# Codex Adversarial Review

Verdict: needs-attention

Findings:
- [critical] [fix-now] Token is logged in plaintext (src/auth.ts:41-48, confidence 0.94)
  Trigger: any login
- [high] Reorder drops archived rows (app/[lang]/(shop)/list.tsx:61-66, confidence 0.87)
- [medium] Retry replays the write (src/queue.ts:12-20, confidence 0.70)
REP
    FINDINGS_FILE="$store" bash "$FINDINGS" record "$rep" --run r1 --kind code >/dev/null 2>&1 || return 1
    [[ "$(wc -l < "$store")" -eq 3 ]] || return 1
    grep -q '"file": "app/\[lang\]/(shop)/list.tsx"' "$store" || return 1   # parens survived
    grep -q '"status": "undecided"' "$store" || return 1

    # the same finding raised again must update the row, not add a fourth
    FINDINGS_FILE="$store" bash "$FINDINGS" record "$rep" --run r2 --kind code >/dev/null 2>&1 || return 1
    [[ "$(wc -l < "$store")" -eq 3 ]] || return 1
    grep -q '"times_seen": 2' "$store" || return 1

    out="$(FINDINGS_FILE="$store" bash "$FINDINGS" list 2>&1)"
    grep -q 'Token is logged in plaintext' <<<"$out" || return 1
    grep -q '3 finding(s) still undecided' <<<"$out"
}
check "findings are recorded per file; a repeat updates the row, not a new one" case_findings

# ---- 17. a ruling sticks, and only settled rulings are replayed, bounded ----
case_findings_status() {
    local store="$ROOT/findings.jsonl" id out
    id="$(python3 -c '
import json,sys
for l in open(sys.argv[1]):
    r=json.loads(l)
    if "plaintext" in r["title"]: print(r["id"]); break
' "$store")"
    [[ -n "$id" ]] || return 1
    FINDINGS_FILE="$store" bash "$FINDINGS" set "$id" rejected "guarded upstream" >/dev/null 2>&1 || return 1
    grep -q '"status": "rejected"' "$store" || return 1

    out="$(FINDINGS_FILE="$store" bash "$FINDINGS" prior src/auth.ts 2>&1)"
    grep -q 'previously rejected: guarded upstream' <<<"$out" || return 1
    grep -q 'Do not report them again as new' <<<"$out" || return 1
    # undecided findings must NOT be replayed — only settled rulings are
    ! grep -q 'Retry replays the write' <<<"$out" || return 1
    # and nothing is replayed for a file with no settled history
    [[ -z "$(FINDINGS_FILE="$store" bash "$FINDINGS" prior src/queue.ts 2>&1)" ]]
}
check "a ruling sticks and only settled rulings are replayed to a later review" case_findings_status

# ---- 18. a successful review files its own findings, unprompted -------------
case_findings_wired() {
    local store="$ROOT/findings-wired.jsonl"
    : > "$store"
    ledger="$ROOT/ledger-wired.jsonl"; : > "$ledger"
    STATS_FILE="$ledger" FINDINGS_FILE="$store" REVIEW_ARCHIVE_DIR="$ROOT/archive5" \
    CODEX_EFFORT=stub-effort STUB_MODE=ok \
    MAX_RETRIES=0 POLL_SECS=1 PROGRESS_SECS=1000 \
        bash "$REVIEW" "$TARGET" >/dev/null 2>&1 || return 1
    [[ -s "$store" ]] || return 1
    grep -q '"status": "undecided"' "$store"
}
check "a review files its findings without being asked" case_findings_wired

# ---- 19. concurrent reviews must not overwrite each other's findings --------
# Up to MAX_PARALLEL reviews finish at once and each rewrites this ledger whole.
case_findings_concurrent() {
    local store="$ROOT/findings-conc.jsonl" i
    : > "$store"
    for i in 1 2 3 4 5 6; do
        printf 'Findings:\n- [high] finding number %d (src/f%d.ts:1-2, confidence 0.9)\n' "$i" "$i" \
            > "$ROOT/conc-$i.md"
    done
    for i in 1 2 3 4 5 6; do
        FINDINGS_FILE="$store" bash "$FINDINGS" record "$ROOT/conc-$i.md" >/dev/null 2>&1 &
    done
    wait
    [[ "$(wc -l < "$store")" -eq 6 ]]
}
check "six concurrent record calls keep all six findings" case_findings_concurrent

# ---- 20. test-plan review is exhaustive and bound to the current plan hash --
validate_test_scope_prompt() {
    local prompt="$1" text
    text="$(tr '\n' ' ' < "$prompt" | sed 's/[[:space:]][[:space:]]*/ /g')"
    grep -Fq 'When the primary target is a TEST OR EVAL PLAN, run a row-by-row scope admission before any other detailed finding.' <<<"$text" || return 1
    grep -Fq 'Review EVERY final-plan row, not a sample.' <<<"$text" || return 1
    grep -Fq 'Reviewed plan SHA-256: <copy the command-produced hash from the inlined plan-hash receipt; if absent, reject the plan>' <<<"$text" || return 1
    grep -Fq 'Every plan row must appear exactly once. A missing row, a sampled review, or a hash that does not identify the final plan makes the verdict `needs-attention`.' <<<"$text"
}
case_test_scope_prompt() {
    local sampled="$ROOT/prompt-sampled.md" stale="$ROOT/prompt-stale-hash.md"
    validate_test_scope_prompt "$PROMPT" || return 1
    sed 's/Review EVERY final-plan row, not a sample\./Review a sample of final-plan rows./' \
        "$PROMPT" > "$sampled"
    ! validate_test_scope_prompt "$sampled" || return 1
    sed 's/if absent, reject the plan/if absent, continue without it/' \
        "$PROMPT" > "$stale"
    ! validate_test_scope_prompt "$stale"
}
check "test-plan admission reviews every row and rejects a missing current-plan hash" case_test_scope_prompt

# ---- test-material routing -----------------------------------
# These rows assert the
# three behaviours that close that: an all-test set picks the test prompt on its
# own, a test file gets exactly one pass no matter how it is re-batched, and a
# mixed batch reviews only the production files.
TEST_TARGET="$ROOT/tests/thing.test.ts"
mkdir -p "$ROOT/tests"
printf 'it("proves a thing", () => {});\n' > "$TEST_TARGET"
OTHER="$ROOT/other.ts"
printf 'export const b = 2;\n' > "$OTHER"

case_auto_test_kind() { # all targets are test material -> kind=test, cap 1
    run_review "$TEST_TARGET" || return 1
    has '"kind":"test"' || return 1
    has '"cap":1'
}
check "an all-test target set selects the test prompt and a cap of one" case_auto_test_kind

case_explicit_code_wins() { # an explicit REVIEW_KIND is never overridden
    REVIEW_KIND=code run_review "$TEST_TARGET" || return 1
    has '"kind":"code"'
}
check "an explicit REVIEW_KIND=code on test material is honoured, not overridden" case_explicit_code_wins

case_per_file_cap() { # re-batching must not reset the counter
    ledger="$ROOT/ledger-perfile.jsonl"; : > "$ledger"
    KEEP=1 run_review "$TEST_TARGET" || return 1
    # A DIFFERENT target set containing the same file mints a fresh scope key,
    # so only a per-file counter can refuse this.
    local second="$ROOT/tests/second.test.ts"
    printf 'it("another", () => {});\n' > "$second"
    KEEP=1 run_review "$TEST_TARGET" "$second" && return 1
    has '"reason":"test-file-cap"'
}
check "a test file reviewed once is refused under a different target set" case_per_file_cap

case_mixed_batch_defers() { # production reviewed, test material moved out
    ledger="$ROOT/ledger-mixed.jsonl"; : > "$ledger"
    local fresh="$ROOT/tests/mixed.test.ts"
    printf 'it("mixed", () => {});\n' > "$fresh"
    KEEP=1 run_review "$OTHER" "$fresh" || return 1
    has '"event":"deferred"' || return 1
    # the code review that ran must carry ONLY the production file
    grep '"event":"start"' "$ledger" | grep -q 'mixed.test.ts' && return 1
    grep '"event":"start"' "$ledger" | grep -q 'other.ts'
}
check "a mixed batch reviews the production file and defers the test file" case_mixed_batch_defers

case_test_prompt_scope() { # the prompt must forbid the production questions
    local p="$HERE/../../assets/adversarial-test-review.prompt.md"
    [[ -r "$p" ]] || return 1
    grep -Fq 'Does this test actually prove the thing it claims to prove?' "$p" || return 1
    grep -Fq 'Explicitly OUT OF SCOPE' "$p" || return 1
    grep -Fq 'This is one pass.' "$p"
}
check "the test prompt asks only about purpose and names what is out of scope" case_test_prompt_scope

# ---- plan-material cap --------
# The limit is five passes per window; the sixth is refused across aliases and
# companion sets unless REVIEW_CAP_OVERRIDE gives a reason.
seed_plan_rows() {   # $1 ledger, $2 count, $3 target file, $4 journey, $5 ts
    local i
    for (( i = 0; i < $2; i++ )); do
        printf '{"ts":"%s","event":"end","scope":"seed:%d","journey":"%s","kind":"plan","targets":["%s"],"outcome":"success"}\n' \
            "$5" "$i" "$4" "$3" >> "$1"
    done
}
case_plan_per_file_cap() {
    local plan_a="$ROOT/plan-a.md" plan_b="$ROOT/plan-b.md" plan_c="$ROOT/plan-c.md" rc=0
    printf '# Plan A\n' > "$plan_a"
    printf '# Plan B\n' > "$plan_b"
    printf '# Plan C\n' > "$plan_c"
    ledger="$ROOT/ledger-plan-perfile.jsonl"; : > "$ledger"
    seed_plan_rows "$ledger" 3 "$plan_a" adhoc "$(date -Is)"

    REVIEW_KIND=plan KEEP=1 run_review "$plan_a" || return 1                 # 4th pass runs
    REVIEW_KIND=doc KEEP=1 run_review "$plan_a" "$plan_b" || return 1        # 5th pass runs
    REVIEW_KIND=spec KEEP=1 run_review "$plan_a" "$plan_c" || rc=$?          # 6th is refused

    [[ "$rc" -eq 10 ]] || return 1
    has '"reason":"plan-file-cap"' || return 1
    [[ "$(grep -c '"event":"end"' "$ledger")" -eq 5 ]] || return 1
    # a stated reason lifts the file cap and the run is recorded with the reason
    REVIEW_KIND=spec KEEP=1 REVIEW_CAP_OVERRIDE=manual-override-1 run_review "$plan_a" "$plan_c" || return 1
    has '"override":"manual-override-1"'
}
check "a plan file gets five passes across aliases and target sets; the sixth is refused unless a reason overrides" case_plan_per_file_cap

# The cap is a same-session loop-breaker, not a permanent retirement. Two passes
# from weeks ago must not refuse a third today; the same two must still refuse
# when the window is switched off. Without this case the cap could silently
# revert to counting all history and every other cap test would still pass.
case_plan_cap_window() {
    local plan="$ROOT/window-plan.md" rc=0 old_a old_b
    printf '# Windowed plan\n' > "$plan"
    old_a="$(date -Is -d '20 days ago')"
    old_b="$(date -Is -d '19 days ago')"
    ledger="$ROOT/ledger-plan-window.jsonl"; : > "$ledger"
    seed_plan_rows "$ledger" 3 "$plan" adhoc "$old_a"
    seed_plan_rows "$ledger" 2 "$plan" adhoc "$old_b"

    # Aged out of the default 24h window: the sixth pass runs.
    REVIEW_KIND=plan KEEP=1 run_review "$plan" || return 1
    has '"reason":"plan-file-cap"' && return 1

    # Same five rows, window switched off: they count again and refuse.
    : > "$ledger"
    seed_plan_rows "$ledger" 3 "$plan" adhoc "$old_a"
    seed_plan_rows "$ledger" 2 "$plan" adhoc "$old_b"
    REVIEW_CAP_WINDOW_HOURS=0 REVIEW_KIND=plan KEEP=1 run_review "$plan" || rc=$?
    [[ "$rc" -eq 10 ]] || return 1
    has '"reason":"plan-file-cap"'
}
check "planning passes older than the cap window do not refuse a fresh one" case_plan_cap_window

case_plan_journey_cap() {
    local plan_a="$ROOT/journey-plan-a.md" plan_b="$ROOT/journey-plan-b.md"
    local plan_c="$ROOT/journey-plan-c.md" fence="$ROOT/fence.txt" rc=0
    printf '# Journey plan A\n' > "$plan_a"
    printf '# Journey plan B\n' > "$plan_b"
    printf '# Journey plan C\n' > "$plan_c"
    printf '%s\n' "$ROOT" > "$fence"
    ledger="$ROOT/ledger-plan-journey.jsonl"; : > "$ledger"
    seed_plan_rows "$ledger" 3 "$ROOT/journey-seed.md" j-plan "$(date -Is)"

    REVIEW_JOURNEY=j-plan CHARTER=plan FENCE="$fence" REVIEW_KIND=plan KEEP=1 \
        run_review "$plan_a" || return 1                                     # 4th
    REVIEW_JOURNEY=j-plan CHARTER=plan FENCE="$fence" REVIEW_KIND=doc KEEP=1 \
        run_review "$plan_b" || return 1                                     # 5th
    REVIEW_JOURNEY=j-plan CHARTER=plan FENCE="$fence" REVIEW_KIND=spec KEEP=1 \
        run_review "$plan_c" || rc=$?                                        # 6th refused

    [[ "$rc" -eq 10 ]] || return 1
    has '"reason":"plan-journey-cap"' || return 1
    [[ "$(grep -c '"event":"end"' "$ledger")" -eq 5 ]] || return 1
    # a stated reason lifts the journey cap too
    REVIEW_JOURNEY=j-plan CHARTER=plan FENCE="$fence" REVIEW_KIND=spec KEEP=1 \
        REVIEW_CAP_OVERRIDE=manual-override-2 run_review "$plan_c" || return 1
    has '"override":"manual-override-2"'
}
check "a journey gets five planning judgments total; the sixth is refused unless a reason overrides" case_plan_journey_cap

printf '1..%d\n' "$tests"
[[ "$failures" -eq 0 ]] || { printf '%d failure(s)\n' "$failures" >&2; exit 1; }
