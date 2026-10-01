#!/usr/bin/env bash
# todo.t — behaviour test for todo.sh, the single write path into a repo's TODO.md.
#
# Real filesystem, real flock, real routing ledger, real python3. Nothing is
# stubbed: the only injected value is the clock (TODO_NOW), which is an input to
# the tool, not a stand-in for it. Every assertion reads the artefacts a
# supervisor would read — the rendered file, the detail file, the ledger, the
# exit code — never the tool's own narration.
#
# Run: bash todo.t          (TODO=/path/to/todo.sh to test a deployed copy)
set -Eeuo pipefail

TODO="${TODO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/todo.sh}"
[[ -x "$TODO" ]] || { printf '1..0 # no todo.sh at %s\n' "$TODO"; exit 1; }

root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
export TMPDIR="$root"   # every mktemp -d below lands under $root and is removed with it

tests=0
failures=0

check() { # $1 label, rest: command
    local label="$1"
    shift
    tests=$((tests + 1))
    if "$@"; then
        printf 'ok %d - %s\n' "$tests" "$label"
    else
        printf 'not ok %d - %s\n' "$tests" "$label"
        failures=$((failures + 1))
    fi
}

# A board in the shape every repo's TODO.md starts from: a header, the OPEN
# heading, nothing owed yet.
new_repo() { # $1 name -> prints the repo path
    local repo="$root/$1"
    mkdir -p "$repo"
    printf '# TODO — %s\n\n> North star: ship the thing.\n\n## OPEN\n' "$1" > "$repo/TODO.md"
    printf '%s\n' "$repo"
}

todo() { # run the tool against $repo, quiet unless the caller wants the output
    local verb="$1"
    shift
    "$TODO" "$verb" --repo "$repo" "$@"
}

# The section a supervisor's roll call actually parses: everything after the
# OPEN heading, up to the next heading of the same or shallower depth.
open_section() { # $1 board path
    awk '/^## OPEN$/ {inside=1; next} inside && /^#{1,2} /{inside=0} inside' "$1"
}

rows_of() { # $1 board path — the rendered rows only
    open_section "$1" | grep '^- ' || true
}

# ---------------------------------------------------------------- add + render

repo="$(new_repo add)"
first="$(todo add --name 'Feature A' --prd 'ai-doc/PRD/25-feature-a.md' \
    --state queued --decision high --why-now 'the owner ordered the start' 2>/dev/null)"
second="$(todo add --name 'Feature B' --prd 'ai-doc/PRD/40-feature-b.md' \
    --state not-started --decision low 2>/dev/null)"

check "add mints the first id as b-0001" test "$first" = "b-0001"
check "add mints the next id as b-0002" test "$second" = "b-0002"
check "both rows are on the board" test "$(rows_of "$repo/TODO.md" | wc -l)" -eq 2

one_line_per_row() {
    # Each row occupies exactly one line, so a row can be quoted verbatim in a
    # close and displayed whole at roll call.
    test "$(grep -c '^- \*\*' "$repo/TODO.md")" -eq 2 &&
        test "$(open_section "$repo/TODO.md" | grep -c .)" -eq 2
}
check "a row is exactly one line" one_line_per_row

nothing_but_items_under_open() {
    # cos-roster.sh reports the WHOLE board UNPARSED if any non-blank line under
    # OPEN is not a list item. This is the constraint the renderer must never break.
    local stray
    stray="$(open_section "$repo/TODO.md" | grep -c . || true)"
    test "$stray" -eq "$(rows_of "$repo/TODO.md" | wc -l)"
}
check "under OPEN there are list items and blank lines only" nothing_but_items_under_open

check "the checksum stamp sits above the OPEN heading" bash -c '
    board="'"$repo"'/TODO.md"
    stamp=$(grep -n "board-checksum" "$board" | cut -d: -f1)
    heading=$(grep -n "^## OPEN$" "$board" | cut -d: -f1)
    [ "$stamp" -lt "$heading" ]'

name_state_id_within_the_displayed_width() {
    # Roll call prints the first 150 characters of an item. If the field order let
    # a long name push `state` past that, the supervisor reads a row with no state.
    local long_repo long_row
    long_repo="$(new_repo width)"
    repo="$long_repo"
    todo add --name "$(printf 'A%.0s' {1..80})" --prd 'ai-doc/PRD/x.md' \
        --state blocked-on-owner --decision high >/dev/null 2>&1
    long_row="$(rows_of "$long_repo/TODO.md")"
    [[ "${long_row:0:150}" == *"state: blocked-on-owner"* && "${long_row:0:150}" == *"id: b-0001"* ]]
}
check "name, state and id fit in the 150 characters roll call displays" \
    name_state_id_within_the_displayed_width

# ------------------------------------------------------------------------- set

repo="$(new_repo set)"
todo add --name 'Feature C' --prd 'ai-doc/PRD/50-feature-c.md' --state queued \
    --decision high >/dev/null 2>&1
todo set b-0001 --state running --journey j-feature-c --callsign vega >/dev/null 2>&1

check "set changes the state on the board" bash -c \
    'grep -q "state: running" "'"$repo"'/TODO.md"'
check "set records the journey and callsign" bash -c \
    'grep -q "journey: j-feature-c" "'"$repo"'/TODO.md" && grep -q "callsign: vega" "'"$repo"'/TODO.md"'

verified_is_not_settable() {
    # If `set` could stamp the verification date, editing one word would claim the
    # row was checked against disk, and the staleness signal would be silently
    # false rather than merely old.
    local before after
    before="$(grep -o 'verified: [0-9-]*' "$repo/TODO.md")"
    TODO_NOW=2026-09-09T00:00:00Z todo set b-0001 --verified 2026-09-09 >/dev/null 2>&1 && return 1
    after="$(grep -o 'verified: [0-9-]*' "$repo/TODO.md")"
    test "$before" = "$after"
}
check "set refuses --verified and leaves the stored date untouched" verified_is_not_settable

check "set refuses an unknown state" bash -c \
    '! "'"$TODO"'" --repo "'"$repo"'" set b-0001 --state sort-of-running >/dev/null 2>&1'
check "set on an unknown id fails" bash -c \
    '! "'"$TODO"'" --repo "'"$repo"'" set b-0099 --state queued >/dev/null 2>&1'

separator_is_rejected() {
    # The separator inside a value would split one row into two fields and change
    # what every later reader thinks the row says.
    local before
    before="$(rows_of "$repo/TODO.md")"
    todo set b-0001 --why-now 'first · second' >/dev/null 2>&1 && return 1
    test "$(rows_of "$repo/TODO.md")" = "$before"
}
check "a value carrying the field separator is rejected, board unchanged" separator_is_rejected

over_long_value_is_rejected() {
    local before
    before="$(rows_of "$repo/TODO.md")"
    todo set b-0001 --why-now "$(printf 'x%.0s' {1..300})" >/dev/null 2>&1 && return 1
    test "$(rows_of "$repo/TODO.md")" = "$before"
}
check "an over-long value is rejected instead of widening the row" over_long_value_is_rejected

# -------------------------------------------------------------- verify + note

repo="$(new_repo verify)"
TODO_NOW=2026-07-01T09:00:00Z todo add --name 'Feature D' --prd 'ai-doc/PRD/60-feature-d.md' \
    --state queued --decision low >/dev/null 2>&1

check "a row added with no disk check claims no verification" bash -c \
    'grep -q "verified: never" "'"$repo"'/TODO.md"'
check "check names a never-verified row" bash -c \
    'TODO_NOW=2026-07-01T09:00:00Z "'"$TODO"'" --repo "'"$repo"'" check 2>&1 |
        grep -q "b-0001 has never been verified against disk"'
check "verify without --command fails" bash -c \
    '! "'"$TODO"'" verify b-0001 --repo "'"$repo"'" >/dev/null 2>&1'
check "the refused verify left the row unverified" bash -c \
    'grep -q "verified: never" "'"$repo"'/TODO.md"'

check "add --command stamps the date and records what was run" bash -c '
    r="$(mktemp -d)"; printf "# TODO\n\n## OPEN\n" > "$r/TODO.md"
    TODO_NOW=2026-07-01T09:00:00Z "'"$TODO"'" add --repo "$r" --name "Checked block" \
        --prd "ai-doc/PRD/x.md" --state queued --decision low \
        --command "ls ai-doc/PRD/x.md" >/dev/null 2>&1
    grep -q "verified: 2026-07-01" "$r/TODO.md" &&
        grep -q "ls ai-doc/PRD/x.md" "$r/ai-doc/ACTIVE/PL/board/b-0001.md"'

TODO_NOW=2026-07-20T09:00:00Z todo verify b-0001 --command 'git log -1 --oneline -- src/' >/dev/null 2>&1
check "verify stamps the day it ran" bash -c 'grep -q "verified: 2026-07-20" "'"$repo"'/TODO.md"'
check "verify records the command that produced the claim" bash -c \
    'grep -q "git log -1 --oneline -- src/" "'"$repo"'/ai-doc/ACTIVE/PL/board/b-0001.md"'

note_never_lengthens_the_row() {
    local narrative
    narrative='The seat looked dark because the first check read only tmux sessions and the
stale pid in the reachability record. The window itself is alive and connected. Absence
from one inventory is not absence.'
    todo note b-0001 --text "$narrative" >/dev/null 2>&1
    test "$(rows_of "$repo/TODO.md" | wc -l)" -eq 1 &&
        grep -q 'Absence' "$repo/ai-doc/ACTIVE/PL/board/b-0001.md" &&
        ! grep -q 'Absence' "$repo/TODO.md"
}
check "note puts narrative in the detail file, never on the board" note_never_lengthens_the_row
check "the row points at its detail file" bash -c \
    'grep -q "detail: ai-doc/ACTIVE/PL/board/b-0001.md" "'"$repo"'/TODO.md"'

# ----------------------------------------------------------------------- close

repo="$(new_repo close)"
todo add --name 'Feature E closeout' --prd 'ai-doc/PRD/40-feature-e.md' --state running \
    --decision low >/dev/null 2>&1
todo add --name 'Survivor row' --prd 'ai-doc/PRD/41-survivor.md' --state queued \
    --decision low >/dev/null 2>&1

mkdir -p "$repo/ai-doc/JOURNAL"
printf 'the acceptance verdict\n' > "$repo/ai-doc/JOURNAL/verdict.md"
TODO_NOW=2026-08-05T03:17:00Z todo close b-0001 --evidence 'ai-doc/JOURNAL/verdict.md' \
    --outcome 'ACCEPTED — feature E is complete' >/dev/null 2>&1

check "the closed row left the board" bash -c '! grep -q "id: b-0001" "'"$repo"'/TODO.md"'
check "the surviving row stayed" bash -c 'grep -q "id: b-0002" "'"$repo"'/TODO.md"'
check "the close is one line in the routing ledger" bash -c \
    'test "$(grep -c board_closed "'"$repo"'/ai-doc/JOURNAL/routing-ledger.jsonl")" -eq 1'

ledger_event_is_valid_json_carrying_the_proof() {
    python3 - "$repo/ai-doc/JOURNAL/routing-ledger.jsonl" <<'PY'
import json, sys
event = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])
assert event["event"] == "board_closed", event
assert event["id"] == "b-0001", event
assert event["evidence"] == "ai-doc/JOURNAL/verdict.md", event
assert event["outcome"].startswith("ACCEPTED"), event
assert event["ts"] == "2026-08-05T03:17:00Z", event
PY
}
check "the ledger event is valid JSON naming the row, outcome and evidence" \
    ledger_event_is_valid_json_carrying_the_proof

id_is_never_reused_after_a_close() {
    # A reused id silently re-points every close that ever quoted the old one.
    local minted
    minted="$(todo add --name 'Later block' --prd 'ai-doc/PRD/70-later.md' --state queued \
        --decision low 2>/dev/null)"
    test "$minted" = "b-0003"
}
check "an id spent on a closed row is never minted again" id_is_never_reused_after_a_close

unreadable_ledger_fails_closed() {
    # Without the ledger a fresh id cannot be proven fresh, so recording must stop
    # rather than guess.
    [[ "$(id -u)" -eq 0 ]] && return 0   # root reads anything; the case cannot be staged
    chmod 000 "$repo/ai-doc/JOURNAL/routing-ledger.jsonl"
    local rc=0
    todo add --name 'Blind add' --prd 'ai-doc/PRD/80-blind.md' --state queued \
        --decision low >/dev/null 2>&1 || rc=$?
    chmod 644 "$repo/ai-doc/JOURNAL/routing-ledger.jsonl"
    test "$rc" -ne 0 && ! grep -q 'Blind add' "$repo/TODO.md"
}
check "an unreadable ledger stops the add instead of risking a reused id" \
    unreadable_ledger_fails_closed

# ----------------------------------------------------------------------- check

repo="$(new_repo check)"
# check opens every cited artifact, so a row that names one needs the file to exist.
mkdir -p "$repo/ai-doc/PRD" && : > "$repo/ai-doc/PRD/90-old.md"
TODO_NOW=2026-07-01T09:00:00Z todo add --name 'Old block' --prd 'ai-doc/PRD/90-old.md' \
    --state queued --decision low --command 'ls ai-doc/PRD/90-old.md' >/dev/null 2>&1

check "a fresh board passes check" bash -c \
    'TODO_NOW=2026-07-02T09:00:00Z "'"$TODO"'" --repo "'"$repo"'" check >/dev/null'

stale_row_is_named_not_removed() {
    # Age marks an open row; it never evicts one. Work that is still owed and has
    # gone quiet is exactly the work that must stay visible.
    local out rc=0
    out="$(TODO_NOW=2026-08-01T09:00:00Z todo check 2>&1)" || rc=$?
    test "$rc" -eq 65 && [[ "$out" == *"b-0001 last verified 2026-07-01"* ]] &&
        grep -q 'id: b-0001' "$repo/TODO.md"
}
check "check names a stale row and leaves it on the board" stale_row_is_named_not_removed

check "check reports a row with no source artifact" bash -c '
    r="'"$repo"'"
    TODO_NOW=2026-07-02T09:00:00Z "'"$TODO"'" add --repo "$r" --name "No PRD yet" --prd none \
        --state queued --decision low --command "there is no artifact to check" >/dev/null 2>&1
    TODO_NOW=2026-07-02T09:00:00Z "'"$TODO"'" check --repo "$r" 2>&1 |
        grep -q "b-0002 names no source artifact"'

check "set refuses to move a row to running without journey and callsign" bash -c '
    r="'"$repo"'"
    before="$(grep "id: b-0002" "$r/TODO.md")"
    ! "'"$TODO"'" set b-0002 --repo "$r" --state running >/dev/null 2>&1 &&
        [ "$(grep "id: b-0002" "$r/TODO.md")" = "$before" ]'

check "set refuses blocked-on-owner without the decision written out" bash -c '
    r="'"$repo"'"
    ! "'"$TODO"'" set b-0002 --repo "$r" --state blocked-on-owner >/dev/null 2>&1 &&
        ! grep -q "state: blocked-on-owner" "$r/TODO.md"'

check "check still reports a running row that arrived incomplete through add" bash -c '
    r="$(mktemp -d)"; printf "# TODO\n\n## OPEN\n" > "$r/TODO.md"
    "'"$TODO"'" add --repo "$r" --name "Bare running row" --prd "p.md" --state running \
        --decision low --command "ls" >/dev/null 2>&1
    "'"$TODO"'" check --repo "$r" 2>&1 | grep -q "b-0001 is running with no journey and callsign"'

check "check still reports a blocked row that arrived incomplete through add" bash -c '
    r="$(mktemp -d)"; printf "# TODO\n\n## OPEN\n" > "$r/TODO.md"
    "'"$TODO"'" add --repo "$r" --name "Bare blocked row" --prd "p.md" \
        --state blocked-on-owner --decision low --command "ls" >/dev/null 2>&1
    "'"$TODO"'" check --repo "$r" 2>&1 | grep -q "b-0001 is blocked on the owner with no --awaiting"'

# ------------------------------------------------------------- order is the priority

check "rows keep the order they were given, not id order" bash -c '
    r="$(mktemp -d)"; printf "# TODO\n\n## OPEN\n" > "$r/TODO.md"
    for n in 1 2 3; do
        "'"$TODO"'" add --repo "$r" --name "Block $n" --prd "$n.md" --state queued \
            --decision low --command "ls" >/dev/null 2>&1
    done
    "'"$TODO"'" move b-0003 --repo "$r" --top yes >/dev/null 2>&1
    [ "$(grep -o "id: b-000[0-9]" "$r/TODO.md" | head -1)" = "id: b-0003" ]'

move_puts_a_row_where_it_was_asked() {
    local order_repo order
    order_repo="$(mktemp -d)"
    printf '# TODO\n\n## OPEN\n' > "$order_repo/TODO.md"
    repo="$order_repo"
    local n
    for n in 1 2 3 4; do
        todo add --name "Block $n" --prd "$n.md" --state queued --decision low \
            --command 'ls' >/dev/null 2>&1
    done
    order="$(todo move b-0004 --before b-0002 2>/dev/null)"
    [[ "$order" == "b-0001 b-0004 b-0002 b-0003" ]] || return 1
    order="$(todo move b-0001 --after b-0003 2>/dev/null)"
    [[ "$order" == "b-0004 b-0002 b-0003 b-0001" ]] || return 1
    # every row survives a reorder
    test "$(rows_of "$order_repo/TODO.md" | wc -l)" -eq 4
}
check "move places a row before or after another and keeps them all" \
    move_puts_a_row_where_it_was_asked

check "move refuses an unknown target and changes nothing" bash -c '
    r="$(mktemp -d)"; printf "# TODO\n\n## OPEN\n" > "$r/TODO.md"
    "'"$TODO"'" add --repo "$r" --name "Only" --prd "p.md" --state queued --decision low \
        --command "ls" >/dev/null 2>&1
    before="$(cat "$r/TODO.md")"
    ! "'"$TODO"'" move b-0001 --repo "$r" --before b-0099 >/dev/null 2>&1 &&
        [ "$(cat "$r/TODO.md")" = "$before" ]'

check "one row can report several violations at once" bash -c '
    r="$(mktemp -d)"; printf "# TODO\n\n## OPEN\n" > "$r/TODO.md"
    "'"$TODO"'" add --repo "$r" --name "Bare row" --prd none --state running \
        --decision low >/dev/null 2>&1
    out="$("'"$TODO"'" check --repo "$r" 2>&1 || true)"
    [[ "$out" == *"b-0001 has never been verified"* ]] &&
        [[ "$out" == *"b-0001 names no source artifact"* ]] &&
        [[ "$out" == *"b-0001 is running with no journey and callsign"* ]]'

check "check reports two high-decision rows running at once" bash -c '
    r="$(mktemp -d)"; printf "# TODO\n\n## OPEN\n" > "$r/TODO.md"
    for n in 1 2; do
        "'"$TODO"'" add --repo "$r" --name "High block $n" --prd "ai-doc/PRD/$n.md" \
            --state running --decision high --journey "j-$n" --callsign "c$n" \
            --command "ls" >/dev/null 2>&1
    done
    "'"$TODO"'" check --repo "$r" 2>&1 | grep -q "2 high-decision rows are running at once"'

over_cap_records_the_work_and_warns() {
    # Refusing to record real work is how work becomes invisible — the failure the
    # cap exists to warn about. So: recorded, and loudly reported.
    local cap_repo out
    cap_repo="$(new_repo cap)"
    repo="$cap_repo"
    local i
    for i in $(seq 1 26); do
        todo add --name "Block $i" --prd "ai-doc/PRD/$i.md" --state queued \
            --decision low >/dev/null 2>&1 || return 1
    done
    test "$(rows_of "$cap_repo/TODO.md" | wc -l)" -eq 26 || return 1
    out="$(todo check 2>&1)" && return 1
    [[ "$out" == *"26 rows, over the 25"* ]]
}
check "the 26th row is still recorded, and check reports the overflow" \
    over_cap_records_the_work_and_warns

# ------------------------------------------------------- hand edits and repair

repo="$(new_repo handedit)"
todo add --name 'Hand edited block' --prd 'ai-doc/PRD/x.md' --state queued \
    --decision low --why-now 'first pass' --command 'ls' >/dev/null 2>&1

legal_hand_edit_is_adopted() {
    # A hand edit is not an offence; leaving it unreconciled is. A row that still
    # parses is adopted and re-stamped rather than destroyed.
    sed -i 's/why-now: first pass/why-now: second pass/' "$repo/TODO.md"
    todo set b-0001 --callsign onyx >/dev/null 2>&1 || return 1
    grep -q 'why-now: second pass' "$repo/TODO.md" && grep -q 'callsign: onyx' "$repo/TODO.md"
}
check "a legal hand edit survives the next write and is re-stamped" legal_hand_edit_is_adopted

check "check reports a hand edit before the next write" bash -c '
    r="'"$repo"'"
    sed -i "s/why-now: second pass/why-now: third pass/" "$r/TODO.md"
    "'"$TODO"'" check --repo "$r" 2>&1 | grep -q "hand-edited since the last write"'

unparseable_row_blocks_the_write() {
    # Re-rendering around a line nobody can parse means dropping it or guessing at
    # it. Dropping an owed item silently is the failure this tool exists to stop.
    local before
    printf -- '- an owed thing someone typed as prose\n' >> "$repo/TODO.md"
    before="$(cat "$repo/TODO.md")"
    todo set b-0001 --callsign raven >/dev/null 2>&1 && return 1
    test "$(cat "$repo/TODO.md")" = "$before"
}
check "an unparseable row stops the write and the file is untouched" unparseable_row_blocks_the_write

check "check names the unparseable line" bash -c \
    '"'"$TODO"'" --repo "'"$repo"'" check 2>&1 | grep -q "not a legal row"'

# ---------------------------------------------------------------- archive-tail

repo="$(new_repo tail)"
mkdir -p "$repo/ai-doc/PRD" && : > "$repo/ai-doc/PRD/x.md"
todo add --name 'Live block' --prd 'ai-doc/PRD/x.md' --state queued --decision low \
    --command 'ls ai-doc/PRD/x.md' >/dev/null 2>&1
cat >> "$repo/TODO.md" <<'TAIL'

## 2 · COMPLETED WORK

**Completed feature.**
- Work completed and reviewed.

## 4 · BACKLOG

- Feature A remains owed
TAIL

tail_with_list_items_is_refused() {
    # Archiving a second list of work below OPEN silently and then passing `check`
    # is the failure this tool exists to prevent,
    # and no rule can tell an owed bullet from a historical one — so the operator is
    # shown them and has to say so in the command.
    local out
    out="$(TODO_NOW=2026-08-05T10:00:00Z todo archive-tail 2>&1)" && return 1
    [[ "$out" == *"Feature A remains owed"* ]] &&
        [[ ! -e "$repo/ai-doc/JOURNAL/board-tail-2026-08-05.md" ]] &&
        grep -q 'BACKLOG' "$repo/TODO.md"
}
check "archive-tail refuses while the tail holds list items, and shows them" \
    tail_with_list_items_is_refused

tail_moves_out_whole() {
    local before after dest
    before="$(rows_of "$repo/TODO.md")"
    TODO_NOW=2026-08-05T10:00:00Z todo archive-tail --confirm-no-owed-work yes \
        >/dev/null 2>&1 || return 1
    dest="$repo/ai-doc/JOURNAL/board-tail-2026-08-05.md"
    [[ -f "$dest" ]] || return 1
    after="$(rows_of "$repo/TODO.md")"
    # Moved, not summarised — and every open row survives byte for byte, because
    # "everything below OPEN" must never be read as including the rows themselves.
    test "$before" = "$after" &&
        grep -q 'BACKLOG' "$dest" &&
        grep -q 'Work completed and reviewed' "$dest" &&
        grep -q 'Feature A remains owed' "$dest" &&
        ! grep -q 'BACKLOG' "$repo/TODO.md"
}
check "confirmed archive-tail moves the tail out whole and keeps every row byte for byte" \
    tail_moves_out_whole
check "the board passes check once the tail is gone" bash -c \
    'TODO_NOW=2026-08-05T10:00:00Z "'"$TODO"'" --repo "'"$repo"'" check >/dev/null'

check "archive-tail never overwrites an existing archive" bash -c '
    r="'"$repo"'"
    printf "\n## 9 · new tail\n\n- something\n" >> "$r/TODO.md"
    ! TODO_NOW=2026-08-05T10:00:00Z "'"$TODO"'" archive-tail --repo "$r" \
        --confirm-no-owed-work yes >/dev/null 2>&1'

# --------------------------------------------------- a hand deletion is not a hand edit

repo="$(new_repo deletion)"
todo add --name 'Row that gets deleted' --prd 'ai-doc/PRD/a.md' --state queued \
    --decision low --command 'ls' >/dev/null 2>&1
todo add --name 'Row that stays' --prd 'ai-doc/PRD/b.md' --state queued \
    --decision low --command 'ls' >/dev/null 2>&1

hand_deletion_stops_the_next_write() {
    # A checksum alone cannot tell an edited row from a deleted one, and only one of
    # those loses owed work. Without the id list, deleting a row by hand and running
    # any ordinary command made the deletion permanent with every later check green.
    local before out
    sed -i '/Row that gets deleted/d' "$repo/TODO.md"
    before="$(cat "$repo/TODO.md")"
    out="$(todo set b-0002 --callsign vega 2>&1)" && return 1
    [[ "$out" == *"b-0001"* ]] && test "$(cat "$repo/TODO.md")" = "$before"
}
check "a row deleted by hand stops the next write and is named" hand_deletion_stops_the_next_write
check "check reports the hand deletion too" bash -c \
    '"'"$TODO"'" check --repo "'"$repo"'" 2>&1 | grep -q "rows deleted by hand"'

# ------------------------------------------------- an interrupted close, and the ledger

repo="$(new_repo interrupted)"
mkdir -p "$repo/ai-doc/JOURNAL"
# Both event shapes the live ledger really carries, seeded before anything is added:
# a legacy line and a current-schema line, neither of them this tool's.
{
    printf '%s\n' '{"ts": "2026-07-01T00:00:00Z", "journey": "j-old", "event": "closed", "outcome": "legacy shape"}'
    printf '%s\n' '{"schema":1,"ts":"2026-07-02T00:00:00Z","event":"closed","tier_final":"quick","journey_id":"j-x"}'
    printf '%s\n' 'not json at all'
} > "$repo/ai-doc/JOURNAL/routing-ledger.jsonl"
printf 'evidence\n' > "$repo/ai-doc/JOURNAL/verdict.md"

check "a ledger of foreign and unparseable lines does not stop a board write" bash -c \
    '"'"$TODO"'" add --repo "'"$repo"'" --name "Mixed ledger block" --prd "ai-doc/PRD/a.md" \
        --state queued --decision low --command "ls" >/dev/null 2>&1 &&
     grep -q "id: b-0001" "'"$repo"'/TODO.md"'

interrupted_close_completes_without_a_duplicate() {
    # Simulate the real crash window: the close event is in the ledger, the row is
    # still on the board. Rerunning close must finish the job, not record it twice.
    printf '%s\n' '{"schema":1,"ts":"2026-08-05T03:00:00Z","event":"board_closed","repo":"interrupted","id":"b-0001","name":"Mixed ledger block","prd":"ai-doc/PRD/a.md","outcome":"first attempt","evidence":"ai-doc/JOURNAL/verdict.md"}' \
        >> "$repo/ai-doc/JOURNAL/routing-ledger.jsonl"
    local report
    report="$(todo check 2>&1 || true)"
    [[ "$report" == *"b-0001 has a close event in the routing ledger"* ]] || return 1
    todo close b-0001 --evidence 'ai-doc/JOURNAL/verdict.md' --outcome 'retry' >/dev/null 2>&1 || return 1
    ! grep -q 'id: b-0001' "$repo/TODO.md" &&
        test "$(grep -c board_closed "$repo/ai-doc/JOURNAL/routing-ledger.jsonl")" -eq 1
}
check "an interrupted close is finished by a retry, with no duplicate ledger event" \
    interrupted_close_completes_without_a_duplicate

check "an id spent by a foreign-format ledger neighbour is still not reused" bash -c \
    'out="$("'"$TODO"'" add --repo "'"$repo"'" --name "Next block" --prd "ai-doc/PRD/b.md" \
        --state queued --decision low --command "ls" 2>/dev/null)"; [ "$out" = "b-0002" ]'

# ------------------------------------------------------------------------------ init

check "init writes a board the script can immediately use" bash -c '
    r="$(mktemp -d)"
    "'"$TODO"'" init --repo "$r" --north-star "ship the thing" >/dev/null 2>&1 &&
    grep -q "^## OPEN$" "$r/TODO.md" &&
    "'"$TODO"'" add --repo "$r" --name "First" --prd "p.md" --state queued --decision low \
        --command "ls" >/dev/null 2>&1 &&
    grep -q "id: b-0001" "$r/TODO.md"'

check "init never overwrites an existing board" bash -c '
    r="$(mktemp -d)"; printf "# keep me\n\n## OPEN\n" > "$r/TODO.md"
    ! "'"$TODO"'" init --repo "$r" >/dev/null 2>&1 && grep -q "keep me" "$r/TODO.md"'

# ------------------------------------------------- concurrency and atomic write

repo="$(new_repo concurrent)"
a_writer_waits_for_the_board_lock() {
    # Deterministic, because racing two writers and hoping they collide is not a
    # test — with the lock removed entirely, a two-process race still passes most
    # of the time. So the lock is held from outside and the writer must be seen
    # WAITING: still alive well after it would otherwise have finished.
    local held="$repo/TODO.md.lock"
    : > "$held"
    flock "$held" -c 'sleep 1' &
    local holder=$!
    sleep 0.2
    todo add --name 'Blocked writer' --prd 'ai-doc/PRD/a.md' --state queued \
        --decision low >/dev/null 2>&1 &
    local writer=$!
    sleep 0.3
    if ! kill -0 "$writer" 2>/dev/null; then   # it finished while the lock was held
        wait "$holder" 2>/dev/null || true
        return 1
    fi
    wait "$holder" 2>/dev/null || true
    wait "$writer" || return 1
    grep -q 'Blocked writer' "$repo/TODO.md"
}
check "a writer waits while another holds the board lock" a_writer_waits_for_the_board_lock

six_writers_all_land() {
    # Every row survives and every id is distinct: a lost read-modify-write would
    # drop a row with no error anywhere.
    local pids=() i
    for i in 1 2 3 4 5 6; do
        todo add --name "Writer $i" --prd "ai-doc/PRD/$i.md" --state queued \
            --decision low >/dev/null 2>&1 &
        pids+=("$!")
    done
    for i in "${pids[@]}"; do wait "$i" || return 1; done
    test "$(rows_of "$repo/TODO.md" | wc -l)" -eq 7 &&
        test "$(grep -o 'id: b-[0-9]*' "$repo/TODO.md" | sort -u | wc -l)" -eq 7
}
check "six concurrent writers all land, with distinct ids" six_writers_all_land

check "no partial write is left behind" bash -c \
    'test "$(find "'"$repo"'" -maxdepth 1 -name ".TODO.md.*" | wc -l)" -eq 0'

# --------------------------------------------------------------- missing board

repo="$root/noboard"
mkdir -p "$repo"
check "a repo with no TODO.md is reported, not created silently" bash -c \
    '! "'"$TODO"'" --repo "'"$repo"'" add --name x --prd p --state queued --decision low \
        >/dev/null 2>&1 && [ ! -e "'"$repo"'/TODO.md" ]'

printf '# TODO\n\nno heading here\n' > "$repo/TODO.md"
check "a board with no OPEN heading is refused with its own message" bash -c \
    '"'"$TODO"'" --repo "'"$repo"'" check 2>&1 | grep -q "no heading named OPEN"'

printf '1..%d\n' "$tests"
if ((failures)); then
    printf '# %d of %d failed\n' "$failures" "$tests"
    exit 1
fi
printf '# all %d passed\n' "$tests"
