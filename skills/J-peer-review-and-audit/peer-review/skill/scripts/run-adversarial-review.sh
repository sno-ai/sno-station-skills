#!/usr/bin/env bash
# run-adversarial-review.sh — run the peer-review adversarial-review prompt in
# a fresh headless session of `codex exec` or `claude -p`, with the target file
# contents inlined via stdin.
#
# Why this script exists:
#   - Inlining file contents means the reviewer never needs filesystem access,
#     so its sandbox cannot block a read of a path outside its working directory.
#   - One stable command means the calling agent does not have to reconstruct a
#     fragile heredoc inline. A single `bash <script> <files>` call is reproducible.
#   - Reviewer independence: the review runs in its own new session that has
#     none of the caller's conversation. The other vendor's CLI is used when it
#     is installed and logged in; otherwise the caller's own CLI runs the review
#     and the report says so on its first line.
#
# Usage:
#   run-adversarial-review.sh <file1> [<file2> ...]
#
# Environment overrides (all optional):
#   FOCUS              — focus area string to steer the reviewer
#   XDG_CONFIG_HOME    — settings root (default: $HOME/.config); sno/models.toml
#                        selects role reviewer (Codex) or reviewer_claude (Claude).
#                        Unset/empty role: no model flag.
#   REVIEW_CALLER      — codex | claude-code: the harness running this script.
#                        The other vendor's CLI is preferred as reviewer.
#   CODEX_EFFORT       — Codex reasoning effort (default: low)
#   REVIEW_KIND        — prompt selection: code (default) | plan/spec/doc
#                        (plan-specific adversarial prompt: premise attack,
#                        probe-evidence classification, coverage statement)
#   STALL_SECS         — kill+retry after this many seconds with no stdout,
#                        stderr, or final-message activity (default: 600).
#                        Reasoning summaries are streamed so a live codex keeps
#                        this counter reset; only a truly wedged process trips
#                        it. Do not lower this below the longest silent stretch
#                        a healthy review can have.
#   TIMEOUT_SECS       — hard per-attempt wall-clock cap (default: 3600).
#                        Concurrent reviews share one account's rate budget and
#                        run several times slower than a solo review, so this
#                        cap has to clear the slowest parallel wave, not the
#                        solo one.
#   MAX_RETRIES        — retries after a stall/timeout/nonzero-exit/empty
#                        final response, on top of the first attempt (default: 2)
#   POLL_SECS          — watchdog poll interval (default: 5)
#   PROGRESS_SECS      — progress heartbeat interval (default: 30)
#   BACKOFF_BASE_SECS  — retry backoff multiplier (default: 5)
#   PAYLOAD_LIMIT      — inlined-file byte budget before auto-batching kicks
#                        in (default: 92160 = 90KiB)
#   MAX_FILES_PER_WAVE — file-count budget before auto-batching kicks in
#                        (default: 8)
#   MAX_PARALLEL       — how many reviews may run at once across every caller
#                        on this machine (default: 8). Over the cap this exits
#                        9 immediately instead of waiting for a free slot.
#
# Reliability: a reviewer CLI can hang — stderr stops growing right after it
# echoes the inlined prompt, stdout stays at 0 bytes, and the process lingers
# for many minutes before exiting with nothing. The hang can be intermittent.
# This script:
#   (a) watches all output files for growth and kills+retries on a stall or
#       a hard per-attempt timeout;
#   (b) also retries on nonzero exit or empty final response;
#   (c) auto-splits large payloads into waves so no single codex call is
#       enormous, and merges the per-wave reports into one report on stdout.
# In plan/spec/doc review mode, the FIRST target file (the artifact under
# review; evidence files follow) is pinned into every wave so grounding
# never loses sight of it.
#
# Notes:
#   - The script does NOT pass file paths to the reviewer. It sees only the
#     inlined text under "=== FILE: <path> ===" markers in stdin.
#   - --skip-git-repo-check is set so review works from any cwd.
#   - Exit codes: 2 no reviewer CLI installed and logged in / prompt unreadable, 3 no files given,
#     4 a target file is unreadable, 5 unknown REVIEW_KIND, 6 reviewer
#     attempt(s) exhausted retries (single-wave), 7 one or more waves
#     exhausted retries (batched — temp dir kept, path printed to stderr),
#     8 invalid reliability override, 9 concurrency cap reached (nothing ran;
#     safe to retry later — the caller must not block waiting on a slot),
#     10 same-scope review cap reached, 11 journey mode without CHARTER/FENCE.
#
# Accounting. Every invocation writes a `start` line to the ledger
# at dispatch and one terminal line — `end` (it finished, well or badly) or
# `refused` (nothing ran) — when it stops. A start with no terminal line is a
# run that was killed, and is the only trace SIGKILL can leave; the receipt
# script reports exactly those as "not actually covered". Reports are kept under
# REVIEW_ARCHIVE_DIR (default ~/.local/state/codex-reviews/<date>/) rather than
# /tmp, and the end line names the file.
#
#   scripts/review-receipt.sh [--since <date|today|all>] [--journey <id>] [--check]

set -uo pipefail
# Deliberately no `set -e`: this script inspects nonzero exits from codex
# (stall/timeout/failure) to drive its own retry logic, so a nonzero status
# from a single attempt must not abort the whole script.

SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# REVIEW_KIND is validated here but its prompt is resolved AFTER the target list
# is known, because an all-test target set selects `test` on its own (below).
REVIEW_KIND_EXPLICIT=0
[[ -n "${REVIEW_KIND:-}" ]] && REVIEW_KIND_EXPLICIT=1
REVIEW_KIND="${REVIEW_KIND:-code}"
case "$REVIEW_KIND" in
    plan|spec|doc|code|test) : ;;
    *) echo "error: unknown REVIEW_KIND '$REVIEW_KIND' (use code|plan|test)" >&2; exit 5 ;;
esac

REVIEW_CALLER="${REVIEW_CALLER:-}"
if [[ -z "$REVIEW_CALLER" ]]; then
    if [[ -n "${CODEX_THREAD_ID:-}" ]]; then REVIEW_CALLER=codex
    elif [[ -n "${CLAUDECODE:-}" ]]; then REVIEW_CALLER=claude-code
    else REVIEW_CALLER=claude-code
    fi
fi
case "$REVIEW_CALLER" in
    codex) CALLER_CLI=codex; OTHER_CLI=claude ;;
    claude-code) CALLER_CLI=claude; OTHER_CLI=codex ;;
    *) echo "error: REVIEW_CALLER must be codex or claude-code" >&2; exit 5 ;;
esac

# Reviewer independence comes from a fresh, separate headless session. The other
# vendor's CLI is preferred when it is installed and logged in; otherwise the
# caller's own CLI runs the review in a new session, and the report header says
# so. Chosen once, before the first attempt.
cli_ready() { # $1 = codex|claude -> 0 when installed and logged in
    command -v "$1" >/dev/null 2>&1 || return 1
    case "$1" in
        codex) codex login status </dev/null >/dev/null 2>&1 ;;
        claude) claude auth status </dev/null >/dev/null 2>&1 ;;
    esac
}
SAME_VENDOR=0
if cli_ready "$OTHER_CLI"; then
    REVIEWER="$OTHER_CLI"
elif command -v "$CALLER_CLI" >/dev/null 2>&1; then
    REVIEWER="$CALLER_CLI"
    SAME_VENDOR=1
else
    echo "error: neither the 'codex' nor the 'claude' CLI is installed and logged in" >&2
    exit 2
fi

if [[ $# -eq 0 ]]; then
    echo "usage: $(basename "$0") <file1> [<file2> ...]" >&2
    exit 3
fi

FILES=("$@")
N=${#FILES[@]}

for f in "${FILES[@]}"; do
    if [[ ! -r "$f" ]]; then
        echo "error: target file not readable: $f" >&2
        exit 4
    fi
done

# ---------------------------------------------------------------------------
# Test files are a different review, not a smaller one.
#
# The code prompt hunts data loss, security holes and silently wrong results.
# Pointed at a test file it produces findings about the TEST's own robustness
# and edge cases — work nobody asked for on an artifact that exists only to
# prove one thing about something else. The same-scope cap keys on the whole
# target set, so re-batching can bypass it.
#
# So `test` gets its own prompt, a cap of one, and a per-FILE counter that
# re-batching cannot reset.
# ---------------------------------------------------------------------------
is_test_file() { # $1 = path -> 0 when it is test material
    local p="$1"
    [[ "$p" == */tests/* || "$p" == tests/* ]] && return 0
    [[ "$p" == */test/*  || "$p" == test/*  ]] && return 0
    [[ "$p" == */spec/*  || "$p" == spec/*  ]] && return 0
    [[ "$p" == */__tests__/* ]] && return 0
    case "${p##*/}" in
        *.t|*.test.*|*.spec.*|test_*.py|*_test.py|*-e2e.sh|*-e2e.*.sh) return 0 ;;
    esac
    return 1
}

TEST_FILES=() PROD_FILES=()
for f in "${FILES[@]}"; do
    if is_test_file "$f"; then TEST_FILES+=("$f"); else PROD_FILES+=("$f"); fi
done

# Auto-select. A caller who never sets REVIEW_KIND still gets the right review;
# one who sets it explicitly keeps what they asked for, and the deliberate
# override is logged so it stays visible in the ledger rather than silent.
# `log` is defined further down, so this early block writes to stderr directly.
if [[ ${#TEST_FILES[@]} -eq $N && "$REVIEW_KIND" == "code" ]]; then
    if [[ "$REVIEW_KIND_EXPLICIT" -eq 1 ]]; then
        printf '%s\n' "[run-adversarial-review] every target is a test file, but REVIEW_KIND=code was set explicitly — honouring it." >&2
    else
        REVIEW_KIND="test"
        printf '%s\n' "[run-adversarial-review] every target is a test file -> REVIEW_KIND=test (purpose-only, cap 1)." >&2
    fi
fi

# A mixed batch is the quiet version of the same waste: the test files inherit
# the production prompt AND ride the production scope cap, so they get reviewed
# up to three times with the wrong questions. They are moved out of this review
# and named, with the exact command for their own single pass. They are NOT run
# automatically — doing that from an exit handler would start a fresh review on
# a Ctrl-C — and the deferral is written to the ledger.
DEFERRED_TEST_FILES=()
if [[ "$REVIEW_KIND" == "code" && ${#TEST_FILES[@]} -gt 0 && ${#PROD_FILES[@]} -gt 0 ]]; then
    DEFERRED_TEST_FILES=("${TEST_FILES[@]}")
    FILES=("${PROD_FILES[@]}")
    N=${#FILES[@]}
    printf '%s\n' "[run-adversarial-review] mixed batch: ${#DEFERRED_TEST_FILES[@]} test file(s) moved OUT of this code review." >&2
    printf '%s\n' "  A test file needs one purpose-only pass, not up to three production rounds. Run:" >&2
    printf '%s\n' "    REVIEW_KIND=test bash $0 ${DEFERRED_TEST_FILES[*]}" >&2
    printf '%s\n' "  Recorded as deferred in the ledger." >&2
fi

DOC_MODE=0
case "$REVIEW_KIND" in
    plan|spec|doc) PROMPT_FILE="$SKILL_DIR/assets/adversarial-plan-review.prompt.md"; DOC_MODE=1 ;;
    test)          PROMPT_FILE="$SKILL_DIR/assets/adversarial-test-review.prompt.md" ;;
    code)          PROMPT_FILE="$SKILL_DIR/assets/adversarial-review.prompt.md" ;;
esac

if [[ ! -r "$PROMPT_FILE" ]]; then
    echo "error: prompt template not readable at $PROMPT_FILE" >&2
    exit 2
fi

source "$SKILL_DIR/scripts/lib/sno-model.sh" || exit 2
CODEX_MODEL="$(sno_model reviewer)" || exit 2
CLAUDE_MODEL="$(sno_model reviewer_claude)" || exit 2
CODEX_EFFORT="${CODEX_EFFORT:-low}"
FOCUS_TEXT="${FOCUS:-none}"

STALL_SECS="${STALL_SECS:-600}"
TIMEOUT_SECS="${TIMEOUT_SECS:-3600}"
MAX_RETRIES="${MAX_RETRIES:-2}"
PAYLOAD_LIMIT="${PAYLOAD_LIMIT:-92160}"
WAVE_SIZE_CHOSEN=0
[[ -n "${MAX_FILES_PER_WAVE:-}" ]] && WAVE_SIZE_CHOSEN=1
MAX_FILES_PER_WAVE="${MAX_FILES_PER_WAVE:-8}"
POLL_SECS="${POLL_SECS:-5}"
PROGRESS_SECS="${PROGRESS_SECS:-30}"
BACKOFF_BASE_SECS="${BACKOFF_BASE_SECS:-5}"
MAX_PARALLEL="${MAX_PARALLEL:-8}"

log() { printf '%s\n' "$*" >&2; }

bytesize() { wc -c < "$1" 2>/dev/null | tr -d ' '; }

require_uint() {
    local name="$1" value="$2" allow_zero="${3:-0}"
    if [[ ! "$value" =~ ^[0-9]+$ ]] || { [[ "$allow_zero" -eq 0 ]] && [[ "$value" -eq 0 ]]; }; then
        log "error: $name must be $([[ "$allow_zero" -eq 1 ]] && printf 'a non-negative' || printf 'a positive') integer"
        exit 8
    fi
}

require_uint STALL_SECS "$STALL_SECS"
require_uint TIMEOUT_SECS "$TIMEOUT_SECS"
require_uint MAX_RETRIES "$MAX_RETRIES" 1
require_uint PAYLOAD_LIMIT "$PAYLOAD_LIMIT"
require_uint MAX_FILES_PER_WAVE "$MAX_FILES_PER_WAVE"
require_uint POLL_SECS "$POLL_SECS"
require_uint PROGRESS_SECS "$PROGRESS_SECS"
require_uint BACKOFF_BASE_SECS "$BACKOFF_BASE_SECS" 1
require_uint MAX_PARALLEL "$MAX_PARALLEL"

# Probe evidence — plan/spec/doc reviews only. The prompt forbids the reviewer
# shell tools, so with no PROBE-RESULTS file it is sitting a closed-book exam:
# internal contradictions and unenforced guarantees it catches, but "the document
# claims A, the code actually does B" is structurally invisible to it. The channel
# already exists and is documented as authoritative ground truth; being optional
# is precisely why it gets skipped. Warn, and record it — a review conducted
# without evidence has to stay identifiable after the fact.
PROBE_PRESENT=false
if [[ "$DOC_MODE" -eq 1 ]]; then
    for f in "${FILES[@]}"; do
        case "$(basename -- "$f")" in
            *PROBE-RESULTS*) PROBE_PRESENT=true; break ;;
        esac
    done
    if [[ "$PROBE_PRESENT" != true ]]; then
        log "[run-adversarial-review] WARNING: no PROBE-RESULTS file among the targets."
        log "  This ${REVIEW_KIND} review can check the document against itself but NOT against"
        log "  reality — every empirical claim in it will come back unverified, not refuted."
        log "  Run the checks the review depends on, write the raw output to a PROBE-RESULTS"
        log "  file, and pass it as an extra target. Recorded as probe=false."
    fi
fi

# ---------------------------------------------------------------------------
# HARD CAP + invocation stats.
# Same-scope review invocations are capped regardless of what they return:
# code=3 (2 fix rounds + 1 confirmation), plan/spec/doc=5. At the cap:
# findings that are NOT verified blockers of the current deliverable go to tech
# debt (recorded, later); verified blockers are reported to the user.
# REVIEW_CAP_OVERRIDE=<reason> lifts a cap; the reason is recorded on the stats line.
#
# Caps count only passes inside REVIEW_CAP_WINDOW_HOURS (default 24).
# Counting all history would eventually prevent reviews of changed artifacts.
# REVIEW_CAP_WINDOW_HOURS=0 counts all history.
STATS_FILE="${STATS_FILE:-$HOME/.local/state/codex-review-stats.jsonl}"
mkdir -p "$(dirname "$STATS_FILE")"; touch "$STATS_FILE"
REVIEW_JOURNEY="${REVIEW_JOURNEY:-adhoc}"
case "$REVIEW_KIND" in
    code) _default_cap=3 ;;
    test) _default_cap=1 ;;   # one pass, never a round loop
    *)    _default_cap=5 ;;   # plan/spec/doc: five judgment passes per window
esac
REVIEW_CAP="${REVIEW_CAP:-$_default_cap}"
require_uint REVIEW_CAP "$REVIEW_CAP"
SCOPE_KEY="$(printf '%s\n' "${FILES[@]}" | LC_ALL=C sort | sha1sum | cut -c1-12)"
SCOPE_ID="${REVIEW_JOURNEY}:${SCOPE_KEY}"

REVIEW_CAP_WINDOW_HOURS="${REVIEW_CAP_WINDOW_HOURS:-24}"
require_uint REVIEW_CAP_WINDOW_HOURS "$REVIEW_CAP_WINDOW_HOURS" 1  # 0 = count all history
CAP_WINDOW_CUTOFF=0
CAP_WINDOW_ACTIVE=0
if (( REVIEW_CAP_WINDOW_HOURS > 0 )); then
    # `date -d <iso8601>` is GNU-only. Without it the filter would drop every
    # line and no cap would ever trip, so prove it works before relying on it
    # and otherwise fall back to counting all history — fail closed, not open.
    if date -d "2026-01-01T00:00:00+00:00" +%s >/dev/null 2>&1; then
        CAP_WINDOW_ACTIVE=1
        CAP_WINDOW_CUTOFF=$(( $(date +%s) - REVIEW_CAP_WINDOW_HOURS * 3600 ))
    else
        log "[run-adversarial-review] no GNU date -d; cap window disabled, counting all history"
    fi
fi

# Keeps only ledger lines stamped inside the cap window. Fed pre-filtered lines
# (one scope, one journey, or one file), so the per-line `date` call runs a
# handful of times, not once per ledger row. A line with no `ts` predates the
# stamp and cannot be shown to be recent, so it is treated as outside.
within_cap_window() {
    local line ts epoch
    if (( CAP_WINDOW_ACTIVE == 0 )); then cat; return 0; fi
    while IFS= read -r line; do
        [[ "$line" == *'"ts":"'* ]] || continue
        ts="${line#*\"ts\":\"}"
        ts="${ts%%\"*}"
        epoch="$(date -d "$ts" +%s 2>/dev/null)" || continue
        (( epoch >= CAP_WINDOW_CUTOFF )) && printf '%s\n' "$line"
    done
    return 0
}

# ---------------------------------------------------------------------------
# Ledger: a start line at dispatch, one terminal line at the end.
#
# Without a start line, a killed review could leave neither a report nor a
# record. The caller could not distinguish "found nothing" from "never ran".
#
# The fix is a start line, not a better exit trap: SIGKILL cannot be trapped, so
# a trap-only fix would miss killed runs. A start with no
# matching terminal line IS the "not actually covered" row, computable after the
# fact and immune to how the process died.
#
# Line shapes (one JSON object per line, appended with a single printf so that
# parallel reviewers cannot interleave a partial write):
#   event=start    dispatch happened. No `outcome` key.
#   event=refused  nothing ran: cap reached, journey contract unmet, no slot.
#                  No `outcome` key.
#   event=end      the review finished, well or badly. Carries `outcome`.
# Only `end` lines carry `outcome`, which is
# what the round counter above keys on.
# ---------------------------------------------------------------------------
LEDGER_TERMINAL_WRITTEN=0
LAST_FAILURE_KIND=""
# One id per invocation, carried by all three line shapes. Pairing on scope+round
# is ambiguous exactly where it matters: a killed round-3 run writes no end line,
# so the next attempt is round 3 again and a receipt cannot tell the two apart.
RUN_ID="$(date +%s)-$$"

json_str() { # $1 -> a JSON string literal, quotes and backslashes escaped
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

json_arr() { # $@ -> a JSON array of strings
    local out="[" first=1 v
    for v in "$@"; do
        [[ "$first" -eq 1 ]] || out+=","
        out+="$(json_str "$v")"
        first=0
    done
    printf '%s]' "$out"
}

ledger_write() { # $1 = the complete JSON object, minus the trailing newline
    printf '%s\n' "$1" >> "$STATS_FILE"
}

# Reports are kept in durable storage, named so a
# ledger line and its report can be paired without searching.
# An explicit REVIEW_OUTPUT_FILE from the caller still wins; existing callers
# pass one and must keep getting exactly that path.
REVIEW_ARCHIVE_DIR="${REVIEW_ARCHIVE_DIR:-$HOME/.local/state/codex-reviews}"
archive_path() {
    local day; day="$(date +%F)"
    if mkdir -p "$REVIEW_ARCHIVE_DIR/$day" 2>/dev/null; then
        printf '%s/%s/%s-%s-%s.md' "$REVIEW_ARCHIVE_DIR" "$day" "$RUN_ID" "$SCOPE_KEY" "$REVIEW_KIND"
    else
        # An unwritable archive must not cost the review; fall back and say so.
        log "[run-adversarial-review] cannot write ${REVIEW_ARCHIVE_DIR} — this report will NOT be kept"
        mktemp -t codex-review.XXXXXX.md
    fi
}

record_start() {
    ledger_write "$(printf '{"ts":%s,"event":"start","run":%s,"scope":%s,"journey":%s,"kind":%s,"round":%d,"cap":%d,"files":%d,"targets":%s,"probe":%s,"model":%s,"effort":%s,"pid":%d}' \
        "$(json_str "$(date -Is)")" "$(json_str "$RUN_ID")" "$(json_str "$SCOPE_ID")" "$(json_str "$REVIEW_JOURNEY")" \
        "$(json_str "$REVIEW_KIND")" "$ROUND_N" "$REVIEW_CAP" "$N" "$(json_arr "${FILES[@]}")" "$PROBE_PRESENT" \
        "$(json_str "$CODEX_MODEL")" "$(json_str "$CODEX_EFFORT")" "$$")"
}

record_refused() { # $1 = reason tag, $2 = human detail
    LEDGER_TERMINAL_WRITTEN=1
    ledger_write "$(printf '{"ts":%s,"event":"refused","run":%s,"scope":%s,"journey":%s,"kind":%s,"round":%d,"cap":%d,"files":%d,"targets":%s,"reason":%s,"detail":%s}' \
        "$(json_str "$(date -Is)")" "$(json_str "$RUN_ID")" "$(json_str "$SCOPE_ID")" "$(json_str "$REVIEW_JOURNEY")" \
        "$(json_str "$REVIEW_KIND")" "${ROUND_N:-0}" "$REVIEW_CAP" "$N" "$(json_arr "${FILES[@]}")" \
        "$(json_str "$1")" "$(json_str "$2")")"
}
# Round counting must see COMPLETED reviews only. Each invocation now writes a
# `start` line as well as an end line, and a refused invocation writes a
# `refused` line — counting raw scope hits would make every round count double
# and trip the cap during what is really round 2. Only end lines carry an
# `outcome` key, so `"outcome":"` counts completed reviews.
PRIOR_ROUNDS=$( { grep -F "\"scope\":\"${SCOPE_ID}\"" "$STATS_FILE" 2>/dev/null || true; } \
    | grep -F '"outcome":"' | within_cap_window | grep -c . || true )
ROUND_N=$(( PRIOR_ROUNDS + 1 ))
if (( ROUND_N > REVIEW_CAP )) && [[ -z "${REVIEW_CAP_OVERRIDE:-}" ]]; then
    log "[run-adversarial-review] HARD CAP: scope ${SCOPE_ID} already reviewed ${PRIOR_ROUNDS}x (cap ${REVIEW_CAP} for ${REVIEW_KIND})."
    log "Continue the authorized task: diagnose and fix in-scope defects, then run affected checks."
    log "This limit ends repeated review, not repair work; no new approval is needed for routine fixes."
    record_refused cap "already reviewed ${PRIOR_ROUNDS}x, cap ${REVIEW_CAP}"
    exit 10
fi
if [[ -n "${REVIEW_CAP_OVERRIDE:-}" ]]; then
    log "[run-adversarial-review] cap override reason: ${REVIEW_CAP_OVERRIDE}"
fi

# Plan/spec/doc are one judgment family. The same artifact must not escape the
# planning cap by changing either the review alias or one companion target.
# Count completed reviews by journey and by file across all three aliases, up to
# REVIEW_CAP passes per window. Beyond that the
# legal next step is deterministic validation and implementation, unless an
# override reason is supplied through REVIEW_CAP_OVERRIDE.
if [[ "$REVIEW_KIND" == "plan" || "$REVIEW_KIND" == "spec" || "$REVIEW_KIND" == "doc" ]] && [[ -z "${REVIEW_CAP_OVERRIDE:-}" ]]; then
    plan_kinds=$( { grep -E '"kind":"(plan|spec|doc)"' "$STATS_FILE" 2>/dev/null || true; } \
        | grep -F '"outcome":"' | within_cap_window || true )

    if [[ "$REVIEW_JOURNEY" != "adhoc" ]]; then
        journey_seen=$(printf '%s\n' "$plan_kinds" \
            | grep -F "\"journey\":\"${REVIEW_JOURNEY}\"" | grep -c . || true)
        if (( journey_seen >= REVIEW_CAP )); then
            log "[run-adversarial-review] PLANNING JOURNEY CAP: ${REVIEW_JOURNEY} already used ${journey_seen} judgment passes (cap ${REVIEW_CAP})."
            log "  Fix only current-slice blockers, run deterministic validation once, then implement."
            record_refused plan-journey-cap "journey already used ${journey_seen} plan/spec/doc passes"
            exit 10
        fi
    fi

    already=()
    for f in "${FILES[@]}"; do
        seen=$(printf '%s\n' "$plan_kinds" | grep -cF "$(json_str "$f")" || true)
        (( seen >= REVIEW_CAP )) && already+=("$f")
    done
    if (( ${#already[@]} > 0 )); then
        log "[run-adversarial-review] PLAN FILE CAP: these artifacts already used ${REVIEW_CAP} judgment passes in the window:"
        for f in "${already[@]}"; do log "    $f"; done
        log "  Changing REVIEW_KIND or the companion target set does not create a new round."
        log "  Fix current-slice defects and verify them directly, then continue implementation; do not park the task."
        record_refused plan-file-cap "already reviewed ${REVIEW_CAP}x: ${already[*]}"
        exit 10
    fi
fi

# Per-FILE cap for test material. The scope cap above keys on the whole target
# set, so dropping or adding one unrelated file mints a fresh scope and restarts
# the counter, which would let one test file be reviewed without limit. This
# counter keys on the path, so re-batching cannot reset it. Production files are deliberately untouched: their scope cap
# works and re-reviewing a source file after a fix is the intended loop.
if [[ "$REVIEW_KIND" == "test" && -z "${REVIEW_CAP_OVERRIDE:-}" ]]; then
    already=()
    for f in "${FILES[@]}"; do
        seen=$( { grep -F "\"kind\":\"test\"" "$STATS_FILE" 2>/dev/null || true; } \
            | grep -F '"outcome":"' | grep -F "$(json_str "$f")" | within_cap_window \
            | grep -c . || true )
        (( seen > 0 )) && already+=("$f")
    done
    if (( ${#already[@]} > 0 )); then
        log "[run-adversarial-review] TEST FILE ALREADY REVIEWED — one purpose pass per test file, and these have had theirs:"
        for f in "${already[@]}"; do log "    $f"; done
        log "  A test file is proof of one thing about something else; re-reviewing it"
        log "  polishes the proof instead of the product. If the test's PURPOSE genuinely"
        log "  changed, repair and verify that test directly; a review refusal does not end the task."
        record_refused test-file-cap "already reviewed: ${already[*]}"
        exit 10
    fi
fi
REVIEW_START_EPOCH=$(date +%s)
TOTAL_LINES=$(cat -- "${FILES[@]}" 2>/dev/null | wc -l | tr -d ' ')

# Context contract (advisory injection; enforced only when REVIEW_JOURNEY is set):
# REVIEW_JOURNEY = a label grouping the reviews of one piece of work;
# CHARTER = one-line task statement or a file path saying what the change is for;
# FENCE = path of a file listing the paths the change may touch;
# CONTEXT_FILE = a file describing the deployment context (trust model, platform,
# format invariants) that severity is judged against.
# A labelled (journey) review without CHARTER and FENCE is refused; ad-hoc calls
# proceed without them (the cap still applies).
CHARTER="${CHARTER:-}"; FENCE="${FENCE:-}"; CONTEXT_FILE="${CONTEXT_FILE:-}"
if [[ "$REVIEW_JOURNEY" != "adhoc" ]] && { [[ -z "$CHARTER" ]] || [[ -z "$FENCE" ]]; }; then
    log "error: journey-mode review (REVIEW_JOURNEY=${REVIEW_JOURNEY}) requires CHARTER and FENCE"
    record_refused contract "journey mode without CHARTER and FENCE"
    exit 11
fi

record_stats() { # $1=outcome $2=report-file(optional)
    local outcome="$1" report="${2:-}" dur verdict="" nFix="" nDebt="" nCtx="" nH="" nM=""
        # Written-once: the interrupt handler and the four success/failure paths can
    # both reach here, and a second end line would inflate the round counter that
    # keys on `"outcome":"` and trip the hard cap a round early.
    [[ "$LEDGER_TERMINAL_WRITTEN" -eq 1 ]] && return 0
    LEDGER_TERMINAL_WRITTEN=1
    dur=$(( $(date +%s) - REVIEW_START_EPOCH ))
    if [[ -n "$report" && -r "$report" ]]; then
        verdict="$(grep -m1 -oE 'Verdict: [a-z-]+' "$report" | cut -d' ' -f2)"
        nFix=$(grep -cE '\[fix-now\]' "$report" || true)
        nDebt=$(grep -cE '\[debt\]' "$report" || true)
        nCtx=$(grep -cE '\[out-of-context\]' "$report" || true)
        nH=$(grep -cE '^\- \[(high|critical)' "$report" || true)
        nM=$(grep -cE '^\- \[medium' "$report" || true)
    fi
    # `failure` names WHY a run ended badly, which the outcome alone never did:
    # empty (codex exited clean and wrote nothing), watchdog (stalled or hit the
    # hard timeout and was killed), exit:<n> (codex itself failed), interrupted
    # (this wrapper was signalled). Empty on success.
    ledger_write "$(printf '{"ts":%s,"event":"end","run":%s,"scope":%s,"journey":%s,"kind":%s,"round":%d,"cap":%d,"files":%d,"targets":%s,"lines":%s,"probe":%s,"duration_s":%d,"waves":%s,"report":%s,"outcome":%s,"failure":%s,"verdict":%s,"fix_now":%s,"debt":%s,"out_of_context":%s,"high":%s,"medium":%s,"override":%s}' \
        "$(json_str "$(date -Is)")" "$(json_str "$RUN_ID")" "$(json_str "$SCOPE_ID")" "$(json_str "$REVIEW_JOURNEY")" \
        "$(json_str "$REVIEW_KIND")" "$ROUND_N" "$REVIEW_CAP" "$N" "$(json_arr "${FILES[@]}")" \
        "${TOTAL_LINES:-0}" "$PROBE_PRESENT" "$dur" "${NUM_WAVES:-1}" "$(json_str "$report")" "$(json_str "$outcome")" \
        "$(json_str "${LAST_FAILURE_KIND:-}")" "$(json_str "${verdict:-unknown}")" \
        "${nFix:-null}" "${nDebt:-null}" "${nCtx:-null}" "${nH:-null}" "${nM:-null}" \
        "$(json_str "${REVIEW_CAP_OVERRIDE:-}")")"
    # Findings go somewhere durable, keyed by reviewed file, with a status column.
    # Never allowed to fail the review: the
    # report is already written and on stdout by this point.
    if [[ "$outcome" == "success" && -n "$report" && -r "$report" ]]; then
        local rf="$SKILL_DIR/scripts/review-findings.sh"
        if [[ -r "$rf" ]]; then
            bash "$rf" record "$report" --run "$RUN_ID" --scope "$SCOPE_ID" \
                --kind "$REVIEW_KIND" 2>&1 >/dev/null | head -3 >&2 || true
        fi
    fi
}

# ---------------------------------------------------------------------------
# Concurrency slot — fail fast, never queue.
#
# Concurrent reviews share one account's token-rate budget, so past a handful
# of them every request slows down and none of them finish sooner. This claims
# one of MAX_PARALLEL advisory locks and gives up IMMEDIATELY if they are all
# held: blocking here would pin a caller's process doing nothing, which is the
# exact failure this cap exists to prevent. The caller decides when to retry.
#
# A slot is a directory: mkdir is atomic on every filesystem this runs on, so
# two reviewers racing for the last slot cannot both win. flock is not used —
# it needs bash 4's `exec {fd}>` and a flock(1) binary, neither of which exists
# on macOS, where the cap would then silently do nothing.
#
# A reviewer killed with SIGKILL cannot clean up after itself, so each slot
# records its owner's pid and any slot whose owner is gone is reclaimed on the
# next scan. That keeps a crashed run from permanently burning a slot.
# ---------------------------------------------------------------------------
SLOT_DIR="${TMPDIR:-/tmp}/codex-review-slots"
SLOT_HELD=""

release_slot() {
    if [[ -n "$SLOT_HELD" ]]; then
        rm -rf "$SLOT_HELD"
        SLOT_HELD=""
    fi
}

take_slot() {
    local slot="$1" label="$2"
    mkdir "$slot" 2>/dev/null || return 1
    printf '%s' "$$" > "$slot/pid"
    SLOT_HELD="$slot"
    log "[run-adversarial-review] claimed concurrency slot ${label}"
    return 0
}

claim_slot() {
    mkdir -p "$SLOT_DIR" 2>/dev/null || return 0
    local i slot owner
    for (( i=1; i<=MAX_PARALLEL; i++ )); do
        slot="$SLOT_DIR/slot-$i"
        take_slot "$slot" "${i}/${MAX_PARALLEL}" && return 0

        owner=$(cat "$slot/pid" 2>/dev/null)
        if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
            rm -rf "$slot"
            take_slot "$slot" "${i}/${MAX_PARALLEL} (reclaimed from dead pid ${owner})" && return 0
        fi
    done
    return 1
}

if ! claim_slot; then
    log "error: all ${MAX_PARALLEL} concurrent review slots are busy — refusing to queue."
    log "       Retry this file later, or raise MAX_PARALLEL if the account can take the load."
    record_refused no_slot "all ${MAX_PARALLEL} concurrency slots held"
    exit 9
fi
trap release_slot EXIT

# From here on a codex process may actually be dispatched, so the run becomes
# something that has to be accounted for. Written after the slot is claimed:
# a run that never got a slot ran nothing and is recorded as `refused` above.
record_start

# Deferred test files are recorded as their own ledger row. It is written here
# rather than at the split so that a run refused before dispatch does not leave
# a deferral nobody caused.
if (( ${#DEFERRED_TEST_FILES[@]} > 0 )); then
    ledger_write "$(printf '{"ts":%s,"event":"deferred","run":%s,"scope":%s,"journey":%s,"kind":%s,"files":%d,"targets":%s,"reason":%s}' \
        "$(json_str "$(date -Is)")" "$(json_str "$RUN_ID")" "$(json_str "$SCOPE_ID")" \
        "$(json_str "$REVIEW_JOURNEY")" "$(json_str "test")" "${#DEFERRED_TEST_FILES[@]}" \
        "$(json_arr "${DEFERRED_TEST_FILES[@]}")" "$(json_str "moved out of a code review; needs one REVIEW_KIND=test pass")")"
fi

terminate_tree() {
    local pid="$1" signal="$2" child
    while read -r child; do
        [[ -n "$child" ]] && terminate_tree "$child" "$signal"
    done < <(pgrep -P "$pid" 2>/dev/null)
    kill "-$signal" "$pid" 2>/dev/null || true
}

kill_tree() {
    local pid="$1" i
    terminate_tree "$pid" TERM
    for i in 1 2 3; do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 1
    done
    terminate_tree "$pid" KILL
}

ACTIVE_PID=""
stop_active() {
    if [[ -n "$ACTIVE_PID" ]] && kill -0 "$ACTIVE_PID" 2>/dev/null; then
        log "[run-adversarial-review] interrupted — killing codex process tree (pid $ACTIVE_PID)"
        kill_tree "$ACTIVE_PID"
    fi
}
# Best-effort terminal line when this wrapper is signalled — a caller's deadline
# or a Ctrl-C. It is deliberately NOT the mechanism the accounting relies on:
# SIGKILL cannot be trapped, so the start line above is what makes an
# unaccounted-for run detectable no matter how the process died.
trap 'stop_active; LAST_FAILURE_KIND=interrupted; record_stats interrupted ""; exit 130' INT TERM HUP

activity_size() {
    local total=0 size file
    for file in "$@"; do
        size=$(bytesize "$file"); size=${size:-0}
        total=$(( total + size ))
    done
    printf '%s' "$total"
}

# run_codex_once PROMPT_FILE STDOUT_FILE STDERR_FILE OUTPUT_LAST_MSG_FILE
# Runs one codex attempt with a liveness watchdog on all output growth plus a
# hard overall timeout. Returns codex's exit status, or 124 if the watchdog
# killed it (stall or timeout).
run_codex_once() {
    local prompt_file="$1" stdout_file="$2" stderr_file="$3" last_msg_file="$4"
    : > "$stdout_file"
    : > "$stderr_file"
    : > "$last_msg_file"

    # Built as one array (rather than splicing the possibly-empty MODEL_ARGS
    # into the middle of the command) because expanding an empty array under
    # `set -u` throws "unbound variable" on bash 3.2 (macOS's default /bin/bash).
    local codex_args=(exec --skip-git-repo-check --sandbox read-only)
    if [[ -n "$CODEX_MODEL" ]]; then
        codex_args+=(--model "$CODEX_MODEL")
    fi
    # Streaming reasoning summaries are the ONLY liveness signal this watchdog
    # has: without them codex writes its header, then nothing at all until the
    # final message lands. A growth-based stall check against a silent process kills
    # healthy runs.
    codex_args+=(
        -c "model_reasoning_effort=$CODEX_EFFORT"
        -c "model_reasoning_summary=detailed"
        --output-last-message "$last_msg_file" -
    )

    local claude_args=(-p)
    if [[ -n "$CLAUDE_MODEL" ]]; then
        claude_args+=(--model "$CLAUDE_MODEL")
    fi
    claude_args+=(
        --effort medium --tools ''
        --disable-slash-commands --strict-mcp-config --no-session-persistence
        --output-format text
    )

    log "[run-adversarial-review] caller=$REVIEW_CALLER reviewer=$REVIEWER same_vendor=$SAME_VENDOR"
    # env -u: the reviewer starts a new session and never inherits the caller's.
    if [[ "$REVIEWER" == claude ]]; then
        env -u CLAUDECODE -u CODEX_THREAD_ID claude "${claude_args[@]}" \
            < "$prompt_file" > "$last_msg_file" 2> "$stderr_file" &
    else
        env -u CLAUDECODE -u CODEX_THREAD_ID codex "${codex_args[@]}" \
            < "$prompt_file" > "$stdout_file" 2> "$stderr_file" &
    fi
    ACTIVE_PID=$!
    local start now elapsed quiet last_size cur_size last_growth next_progress status
    start=$(date +%s); last_growth=$start; last_size=0; next_progress=$PROGRESS_SECS

    while kill -0 "$ACTIVE_PID" 2>/dev/null; do
        sleep "$POLL_SECS"
        now=$(date +%s)
        cur_size=$(activity_size "$stdout_file" "$stderr_file" "$last_msg_file")
        if [[ "$cur_size" -gt "$last_size" ]]; then
            last_size=$cur_size
            last_growth=$now
        fi
        elapsed=$(( now - start ))
        quiet=$(( now - last_growth ))
        if (( elapsed >= next_progress )); then
            log "[run-adversarial-review] running ${elapsed}s, quiet ${quiet}s, output ${cur_size} bytes"
            next_progress=$(( next_progress + PROGRESS_SECS ))
        fi
        if (( elapsed >= TIMEOUT_SECS )); then
            log "[run-adversarial-review] hard timeout after ${elapsed}s — killing codex (pid $ACTIVE_PID)"
            kill_tree "$ACTIVE_PID"
            wait "$ACTIVE_PID" 2>/dev/null
            ACTIVE_PID=""
            return 124
        fi
        if (( quiet >= STALL_SECS )); then
            log "[run-adversarial-review] stalled ${quiet}s with no output activity — killing codex (pid $ACTIVE_PID)"
            kill_tree "$ACTIVE_PID"
            wait "$ACTIVE_PID" 2>/dev/null
            ACTIVE_PID=""
            return 124
        fi
    done

    wait "$ACTIVE_PID"
    status=$?
    ACTIVE_PID=""
    return "$status"
}

# run_with_retries PROMPT_FILE STDOUT_FILE STDERR_FILE OUTPUT_LAST_MSG_FILE LABEL
# Retries run_codex_once up to MAX_RETRIES times on stall/timeout/nonzero
# exit/empty final response. Returns 0 on success.
run_with_retries() {
    local prompt_file="$1" stdout_file="$2" stderr_file="$3" last_msg_file="$4" label="$5"
    local attempt=1 max_attempts=$(( MAX_RETRIES + 1 )) status

    while (( attempt <= max_attempts )); do
        log "[run-adversarial-review] ${label}: attempt ${attempt}/${max_attempts}…"
        run_codex_once "$prompt_file" "$stdout_file" "$stderr_file" "$last_msg_file"
        status=$?
        if [[ $status -eq 0 && -s "$last_msg_file" ]]; then
            log "[run-adversarial-review] ${label}: attempt ${attempt}/${max_attempts} succeeded"
            LAST_FAILURE_KIND=""
            return 0
        fi
        # Name the failure so the ledger can distinguish the three that look
        # identical from outside: codex exited clean and wrote nothing, the
        # watchdog killed a stalled or overlong run, or codex itself failed.
        if [[ $status -eq 124 ]]; then
            LAST_FAILURE_KIND="watchdog"
        elif [[ $status -eq 0 ]]; then
            LAST_FAILURE_KIND="empty"
        else
            LAST_FAILURE_KIND="exit:${status}"
        fi
        log "[run-adversarial-review] ${label}: attempt ${attempt}/${max_attempts} failed (${LAST_FAILURE_KIND}, exit=${status}, final_bytes=$(bytesize "$last_msg_file"))"
        if (( attempt < max_attempts )); then
            local backoff=$(( attempt * BACKOFF_BASE_SECS ))
            log "[run-adversarial-review] ${label}: retrying after ${backoff}s backoff…"
            sleep "$backoff"
        fi
        attempt=$(( attempt + 1 ))
    done
    return 1
}

# A same-vendor review is labelled on the first line of the saved report, so a
# reader never mistakes it for an independent-vendor review.
SAME_VENDOR_HEADER="Reviewer: same-vendor review (${REVIEWER} in a fresh session; the ${OTHER_CLI} CLI was not installed or not logged in)."
stamp_same_vendor() { # $1 = report file
    [[ "$SAME_VENDOR" -eq 1 && -s "$1" ]] || return 0
    { printf '%s\n\n' "$SAME_VENDOR_HEADER"; cat -- "$1"; } > "$1.stamped" && mv -- "$1.stamped" "$1"
}

# build_prompt PROMPT_OUT_FILE WAVE_NOTE FILE_INDICES...
# Assembles the prompt template + inlined target files + focus line into
# PROMPT_OUT_FILE, mirroring the original single-shot inlining format.
build_prompt() {
    local out_file="$1" wave_note="$2"; shift 2
    local idx f
    {
        sed 's/You are Codex performing/You are performing/; s/# Codex Adversarial/# Adversarial/' "$PROMPT_FILE"
        # Context contract: severity must be judged
        # against this; a severity cap is legal ONLY when it cites an entry here.
        if [[ -n "$CHARTER" || -n "$FENCE" || -n "$CONTEXT_FILE" ]]; then
            printf '\n<context_contract>\n'
            if [[ -n "$CHARTER" ]]; then
                if [[ -r "$CHARTER" ]]; then printf 'Charter (what this change is FOR):\n'; cat -- "$CHARTER";
                else printf 'Charter (what this change is FOR): %s\n' "$CHARTER"; fi
            fi
            if [[ -n "$FENCE" && -r "$FENCE" ]]; then
                printf '\nScope fence (paths this change may touch):\n'; cat -- "$FENCE"
            fi
            if [[ -n "$CONTEXT_FILE" && -r "$CONTEXT_FILE" ]]; then
                printf '\nDeployment context (trust model / platform / format invariants):\n'
                cat -- "$CONTEXT_FILE"
            fi
            printf '</context_contract>\n'
        fi
        if [[ -n "$wave_note" ]]; then
            printf '\n%s\n' "$wave_note"
        fi
        printf '\n'
        for idx in "$@"; do
            f="${FILES[$idx]}"
            printf '\n=== FILE: %s ===\n' "$f"
            cat -- "$f"
        done
        printf '\nUser focus: %s\n' "$FOCUS_TEXT"
    } > "$out_file"
}

# ---------------------------------------------------------------------------
# Decide single-wave vs batched, based on total payload size / file count.
# ---------------------------------------------------------------------------

TOTAL_BYTES=0
declare -a SIZES
for f in "${FILES[@]}"; do
    sz=$(bytesize "$f"); sz=${sz:-0}
    SIZES+=("$sz")
    TOTAL_BYTES=$(( TOTAL_BYTES + sz ))
done

# Wave size is a judgement, so it is announced rather than applied silently.
# The trade is real in both directions and only the caller knows which side it
# needs: a LARGER wave puts more files in front of one reviewer at once, which
# is the only way cross-file contradictions become visible. A SMALLER wave buys
# depth per file and less dilution, which is what a
# security or correctness pass over dense source wants. The 8 here is a default,
# not a finding; set MAX_FILES_PER_WAVE deliberately when either side matters.
if (( WAVE_SIZE_CHOSEN == 1 )); then
    log "[run-adversarial-review] wave size ${MAX_FILES_PER_WAVE} file(s) — chosen by the caller."
else
    log "[run-adversarial-review] wave size ${MAX_FILES_PER_WAVE} file(s) — DEFAULT, nobody chose it."
    log "  Larger keeps cross-file contradictions visible in one pass; smaller buys depth."
    log "  Set MAX_FILES_PER_WAVE when either matters."
fi

BATCH=0
if (( TOTAL_BYTES > PAYLOAD_LIMIT || N > MAX_FILES_PER_WAVE )); then
    BATCH=1
fi

if [[ "$BATCH" -eq 0 ]]; then
    # ---- Single-wave path (backward compatible shape) ----------------------
    PROMPT_TMP="$(mktemp -t codex-review-prompt.XXXXXX)"
    STDOUT_TMP="$(mktemp -t codex-review-stdout.XXXXXX)"
    STDERR_TMP="$(mktemp -t codex-review-stderr.XXXXXX)"
    REVIEW_OUTPUT_FILE="${REVIEW_OUTPUT_FILE:-$(archive_path)}"

    all_idx=()
    for (( i=0; i<N; i++ )); do all_idx+=("$i"); done
    build_prompt "$PROMPT_TMP" "" "${all_idx[@]}"

    if run_with_retries "$PROMPT_TMP" "$STDOUT_TMP" "$STDERR_TMP" "$REVIEW_OUTPUT_FILE" "review"; then
        stamp_same_vendor "$REVIEW_OUTPUT_FILE"
        cat -- "$REVIEW_OUTPUT_FILE"
        printf '\n[run-adversarial-review] final review also written to: %s\n' "$REVIEW_OUTPUT_FILE" >&2
        record_stats success "$REVIEW_OUTPUT_FILE"
        rm -f "$PROMPT_TMP" "$STDOUT_TMP" "$STDERR_TMP"
        exit 0
    else
        record_stats failed ""
        log "[run-adversarial-review] review failed after ${MAX_RETRIES} retries — see stdout/stderr captures for the last attempt:"
        log "  stdout: $STDOUT_TMP"
        log "  stderr: $STDERR_TMP"
        log "  final: $REVIEW_OUTPUT_FILE"
        log "  prompt: $PROMPT_TMP"
        exit 6
    fi
fi

# ---- Batched path --------------------------------------------------------

TARGET_IDX=-1
if [[ "$DOC_MODE" -eq 1 && "$N" -gt 1 ]]; then
    TARGET_IDX=0
fi

if [[ "$TARGET_IDX" -ge 0 ]]; then
    BUDGET_BYTES=$(( PAYLOAD_LIMIT - SIZES[TARGET_IDX] ))
    BUDGET_FILES=$(( MAX_FILES_PER_WAVE - 1 ))
    POOL=()
    for (( i=0; i<N; i++ )); do
        [[ "$i" -eq "$TARGET_IDX" ]] && continue
        POOL+=("$i")
    done
else
    BUDGET_BYTES=$PAYLOAD_LIMIT
    BUDGET_FILES=$MAX_FILES_PER_WAVE
    POOL=()
    for (( i=0; i<N; i++ )); do POOL+=("$i"); done
fi
(( BUDGET_BYTES <= 0 )) && BUDGET_BYTES=$PAYLOAD_LIMIT
(( BUDGET_FILES <= 0 )) && BUDGET_FILES=1

# WAVES: each element is a space-separated list of file indices for that
# wave (pinned target index already included when applicable).
declare -a WAVES
CUR=() ; CUR_BYTES=0 ; CUR_COUNT=0
flush_wave() {
    [[ "$CUR_COUNT" -eq 0 ]] && return 0
    local wave_idx=("${CUR[@]}")
    if [[ "$TARGET_IDX" -ge 0 ]]; then
        wave_idx=("$TARGET_IDX" "${CUR[@]}")
    fi
    WAVES+=("${wave_idx[*]}")
    CUR=() ; CUR_BYTES=0 ; CUR_COUNT=0
}
for idx in "${POOL[@]}"; do
    fsize=${SIZES[$idx]}
    if [[ "$CUR_COUNT" -gt 0 ]] && (( CUR_BYTES + fsize > BUDGET_BYTES || CUR_COUNT + 1 > BUDGET_FILES )); then
        flush_wave
    fi
    CUR+=("$idx")
    CUR_BYTES=$(( CUR_BYTES + fsize ))
    CUR_COUNT=$(( CUR_COUNT + 1 ))
done
flush_wave

if [[ ${#WAVES[@]} -eq 0 && "$TARGET_IDX" -ge 0 ]]; then
    # Pool was empty (a single, oversized target file) — the target still
    # needs its own wave.
    WAVES+=("$TARGET_IDX")
fi

NUM_WAVES=${#WAVES[@]}
log "[run-adversarial-review] payload ${TOTAL_BYTES} bytes / ${N} files exceeds batching threshold — splitting into ${NUM_WAVES} wave(s)"

WORKDIR="$(mktemp -d -t codex-review-batch.XXXXXX)"
WAVE_REPORTS=()
ANY_FAILED=0

for (( w=0; w<NUM_WAVES; w++ )); do
    wave_num=$(( w + 1 ))
    # shellcheck disable=SC2206 # WAVES[w] is a deliberately word-split index list
    wave_idx=(${WAVES[$w]})
    wave_files=()
    for idx in "${wave_idx[@]}"; do wave_files+=("${FILES[$idx]}"); done

    prompt_tmp="$WORKDIR/wave-${wave_num}.prompt"
    stdout_tmp="$WORKDIR/wave-${wave_num}.stdout"
    stderr_tmp="$WORKDIR/wave-${wave_num}.stderr"
    lastmsg_tmp="$WORKDIR/wave-${wave_num}.lastmsg.md"

    wave_note=""
    if [[ "$NUM_WAVES" -gt 1 ]]; then
        wave_note="This is wave ${wave_num}/${NUM_WAVES} of a batched review; the same target may repeat across waves for grounding, and findings will be merged with the other waves after this one."
    fi
    build_prompt "$prompt_tmp" "$wave_note" "${wave_idx[@]}"

    if run_with_retries "$prompt_tmp" "$stdout_tmp" "$stderr_tmp" "$lastmsg_tmp" "wave ${wave_num}/${NUM_WAVES} (${wave_files[*]})"; then
        WAVE_REPORTS+=("$lastmsg_tmp")
    else
        log "[run-adversarial-review] wave ${wave_num}/${NUM_WAVES} failed after ${MAX_RETRIES} retries — files: ${wave_files[*]}"
        ANY_FAILED=1
        break
    fi
done

if [[ "$ANY_FAILED" -eq 1 ]]; then
    record_stats failed ""
    log "[run-adversarial-review] batched review aborted — intermediate files kept at: $WORKDIR"
    exit 7
fi

[[ "$SAME_VENDOR" -eq 1 ]] && printf '%s\n\n' "$SAME_VENDOR_HEADER"
for (( w=0; w<NUM_WAVES; w++ )); do
    wave_num=$(( w + 1 ))
    printf '## Wave %d/%d\n\n' "$wave_num" "$NUM_WAVES"
    cat -- "${WAVE_REPORTS[$w]}"
    printf '\n'
done

MERGED_REPORT="${REVIEW_OUTPUT_FILE:-$(archive_path)}"
cat -- "${WAVE_REPORTS[@]}" > "$MERGED_REPORT" 2>/dev/null || true
stamp_same_vendor "$MERGED_REPORT"
# Every wave produced a report, but if the merge itself could not be written the
# findings are gone — recording that as success is exactly the silent pass this
# accounting exists to stop.
if [[ ! -s "$MERGED_REPORT" ]]; then
    LAST_FAILURE_KIND="report-not-written"
    record_stats failed ""
    log "[run-adversarial-review] ${NUM_WAVES} wave(s) succeeded but the merged report could not be"
    log "  written to ${MERGED_REPORT} — the findings are NOT recorded. Wave captures: ${WORKDIR}"
    exit 7
fi
record_stats success "$MERGED_REPORT"
printf '[run-adversarial-review] merged review written to: %s\n' "$MERGED_REPORT" >&2
rm -rf "$WORKDIR"
printf '[run-adversarial-review] batched review complete (%d waves merged)\n' "$NUM_WAVES" >&2
exit 0
