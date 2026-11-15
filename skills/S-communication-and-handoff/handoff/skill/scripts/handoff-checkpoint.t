#!/usr/bin/env bash
# Behaviour test for handoff-checkpoint: real git work trees, real files, real hashes.
set -Eeuo pipefail
unset CLAUDE_SESSION_ID CODEX_THREAD_ID

command_path="$(realpath -- "${1:-$(dirname -- "${BASH_SOURCE[0]}")/handoff-checkpoint}")"
# Physical path: git reports the checkout with symlinks resolved (macOS /var is /private/var).
root="$(cd -- "$(mktemp -d)" && pwd -P)"
trap 'rm -rf -- "$root"' EXIT
count=0

ok() { count=$((count + 1)); printf 'ok %s - %s\n' "$count" "$1"; }
fail() { printf 'not ok %s - %s\n' "$((count + 1))" "$1"; [[ -s "$root/err" ]] && sed 's/^/# /' "$root/err"; exit 1; }
run() { local status=0; "$command_path" "$@" >"$root/out" 2>"$root/err" || status=$?; printf '%s' "$status"; }
file_mode() { stat -c %a -- "$1" 2>/dev/null || stat -f %Lp -- "$1"; }
git_() { git -C "$repo" -c user.name=Test -c user.email=test@example.invalid "$@"; }
new_repo() {
    repo="$root/$1"
    mkdir -p -- "$repo"
    git -C "$repo" init -q -b main
    printf 'one\n' >"$repo/tracked.txt"
    git_ add tracked.txt
    git_ commit -q -m 'first commit'
}

plain_brief() {
    new_repo plain-work
    record="$root/plain-brief.md"
    printf '# Current task\n\n## Next\nCompute the sum from input.txt.\n\n## Known failure\nRead missing.txt: no such file.\n' >"$record"
    cp "$record" "$root/plain-before.md"
    chmod 640 "$record"
    status="$(cd -- "$repo" && run "$record")"
    [[ "$status" == 0 ]] && grep -qx '<!-- machine-record:start -->' "$record" || fail 'readable task without machine markers can be refreshed'
    [[ "$(file_mode "$record")" == 640 ]] || fail 'adding machine information kept the file mode'
    sed '1,/<!-- machine-record:end -->/d' "$record" | tail -n +2 >"$root/plain-after.md"
    cmp -s "$root/plain-before.md" "$root/plain-after.md" || fail 'adding machine information changed the readable task'
    ok 'existing readable brief receives machine information without losing any original byte'
}
if [[ "${2:-}" == plain-brief ]]; then plain_brief; printf '1..%s\n' "$count"; exit 0; fi

non_git() {
    local directory="$root/non-git directory" record="$root/nogit.md" status
    mkdir -p -- "$directory/child"
    status="$(cd -- "$directory" && CLAUDE_SESSION_ID=claude-outside-git run "$record")"
    [[ "$status" == 0 ]] || fail "outside git create exits 0 (got $status)"
    grep -qxF "checkout: $directory" "$record" || fail 'outside git records the resolved directory'
    grep -qx 'branch: none' "$record" && grep -qx 'head: none' "$record" || fail 'outside git records no branch or head'
    [[ "$(sed -n '/^recent:$/,/^session-id:/p' "$record")" == $'recent:\nuncommitted:\nruntime: claude-code\nsession-id: claude-outside-git' ]] || fail 'outside git lists no git state and keeps the Claude identity'
    status="$(run --repo "$directory/child/.." "$record")"
    [[ "$status" == 0 ]] && grep -qx 'checkpoint: 2' "$record" || fail 'outside git refresh increments the checkpoint'
    grep -qxF "checkout: $directory" "$record" && grep -qx 'runtime: claude-code' "$record" && grep -qx 'session-id: claude-outside-git' "$record" || fail 'outside git --repo resolves the directory and refresh preserves identity'
    status="$(run --verify "$record")"
    [[ "$status" == 0 && "$(cat "$root/out")" == 'No git state to compare.' && "$(wc -l <"$root/out")" -eq 1 && ! -s "$root/err" ]] || fail 'outside git verify exits 0 with one explanatory line'
    ok 'outside git create, refresh and verify preserve the directory and session identity'
}

locked_write() {
    (
        local record="$root/locked.md" lock_fd writer status=0
        new_repo locked-work
        "$command_path" --repo "$repo" "$record" >/dev/null
        cp -- "$record" "$root/locked-before"
        exec {lock_fd}>"$record.lock"
        flock -x "$lock_fd"
        "$command_path" --repo "$repo" "$record" >"$root/locked-out" 2>"$root/err" {lock_fd}>&- &
        writer=$!
        trap 'kill "$writer" 2>/dev/null || :; wait "$writer" 2>/dev/null || :' EXIT
        sleep 0.5
        kill -0 "$writer" 2>/dev/null && [[ ! -s "$root/locked-out" ]] && cmp -s "$root/locked-before" "$record" || fail 'checkpoint waits without writing while FILE.lock is held'
        cp -- "$record" "$root/runner-update"
        printf '\n## Due\ndo: write the daily report\nlast: 2026-11-15 started, result done\n' >>"$root/runner-update"
        mv -- "$root/runner-update" "$record"
        outside "$record" >"$root/locked-outside"
        flock -u "$lock_fd"
        exec {lock_fd}>&-
        wait "$writer" || status=$?
        [[ "$status" == 0 ]] && grep -qx 'checkpoint: 2' "$record" || fail 'checkpoint finishes after the lock is released'
        cmp -s "$root/locked-outside" <(outside "$record") || fail 'checkpoint keeps all text another writer renamed in while it waited'
    )
    ok 'checkpoint waits for FILE.lock and preserves the other writer update'
}

without_flock() {
    local repo status
    new_repo no-flock-work
    # Without flock, the same write and verification work without a lock file.
    mkdir -- "$root/no-flock-bin"
    for tool in bash git dirname realpath stat sha256sum cut grep sed head date mktemp rm chmod awk cat mv sort; do
        ln -s -- "$(command -v "$tool")" "$root/no-flock-bin/$tool"
    done
    status="$(PATH="$root/no-flock-bin" run --repo "$repo" "$root/no-flock.md")"
    [[ "$status" == 0 && ! -e "$root/no-flock.md.lock" ]] || fail 'without flock a record is written without a lock file'
    status="$(PATH="$root/no-flock-bin" run --verify "$root/no-flock.md")"
    [[ "$status" == 0 ]] && grep -qx MATCH "$root/out" || fail 'without flock the git record verifies normally'
    ok 'write and verify work when flock is absent'
}

outside() { sed '/<!-- machine-record:start -->/,/<!-- machine-record:end -->/d' "$1"; }
if [[ "${2:-}" == non-git ]]; then non_git; printf '1..%s\n' "$count"; exit 0; fi
if [[ "${2:-}" == locked-write ]]; then locked_write; printf '1..%s\n' "$count"; exit 0; fi

if [[ "${2:-}" == no-flock ]]; then without_flock; printf '1..%s\n' "$count"; exit 0; fi

# usage
mkdir -p -- "$root/empty"
status="$(cd -- "$root/empty" && run)"
[[ "$status" == 0 && "$(head -n1 "$root/out")" == usage:* && ! -s "$root/err" ]] || fail 'no arguments print usage and exit 0'
status="$(run --help)"
[[ "$status" == 0 && "$(head -n1 "$root/out")" == usage:* && ! -s "$root/err" ]] || fail '--help prints usage and exits 0'
ok 'usage on no arguments and on --help'

# create
new_repo work
printf 'edited\n' >"$repo/tracked.txt"
printf 'brand new\n' >"$repo/new file.txt"
record="$root/progress.md"
status="$(cd -- "$repo" && run "$record")"
[[ "$status" == 0 ]] || fail "create exits 0 (got $status)"
grep -q '^checkpoint: 1$' "$record" || fail 'first checkpoint is number 1'
grep -q "^checkout: $repo\$" "$record" || fail 'checkout is recorded'
grep -q '^branch: main$' "$record" || fail 'branch is recorded'
grep -Eq '^head: [0-9a-f]{7,} first commit$' "$record" || fail 'head and subject are recorded'
grep -Eq '^- [0-9a-f]{7,} first commit$' "$record" || fail 'recent commits are listed'
want_new="$(sha256sum <"$repo/new file.txt" | cut -d' ' -f1)"
want_mod="$(sha256sum <"$repo/tracked.txt" | cut -d' ' -f1)"
grep -Fq -- "- ?? new file.txt sha256:$want_new" "$record" || fail 'untracked file (with a space) recorded with its hash'
grep -Fq -- "- M tracked.txt sha256:$want_mod" "$record" || fail 'modified file recorded with its hash'
for heading in 'Objective and authorization' 'Done' 'Next' 'Decisions and assumptions' 'Known failure' 'Report destination' 'Reach card' 'Risks and open questions'; do
    grep -q "^## $heading\$" "$record" || fail "agent section '$heading' exists"
done
ok 'create writes the machine record and task, failure, destination and card sections'

# refresh keeps every byte outside the record
python3 - "$record" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = t.replace("## Done\n", "## Done\n- step one finished, proof in proof/1.log\n", 1)
t = t.replace("## Next\n", "## Next\n1. write the report\n2. run the checks\n", 1)
p.write_text(t)
PY
outside "$record" >"$root/outside-before"
git_ add -A
git_ commit -q -m 'second commit'
chmod 640 "$record"
status="$(cd -- "$repo" && run "$record")"
[[ "$status" == 0 ]] || fail "refresh exits 0 (got $status)"
[[ "$(file_mode "$record")" == 640 ]] || fail 'refresh keeps the file mode'
grep -q '^checkpoint: 2$' "$record" || fail 'checkpoint number goes up by one'
grep -Eq '^head: [0-9a-f]{7,} second commit$' "$record" || fail 'refresh records the new head'
cmp -s "$root/outside-before" <(outside "$record") || fail 'text outside the record is unchanged byte for byte'
grep -q 'step one finished' "$record" || fail 'agent-written text survives'
ok 'refresh rewrites only the machine record'

# the record file may live inside the checkout without disturbing verify
inside="$repo/progress-inside.md"
(cd -- "$repo" && "$command_path" "$inside" >/dev/null 2>&1)
status="$(run --verify "$inside")"
[[ "$status" == 0 ]] && grep -qx 'MATCH' "$root/out" || fail 'a record inside the checkout does not cause drift'
rm -f -- "$inside"
rm -f -- "$inside.lock"
ok 'record inside the checkout is not counted as uncommitted work'

# verify: MATCH, then each kind of drift
status="$(run --verify "$record")"
[[ "$status" == 0 ]] && grep -qx 'MATCH' "$root/out" || fail 'verify matches right after a checkpoint'
ok 'verify prints MATCH when nothing moved'

git_ commit -q --allow-empty -m 'work after the checkpoint'
status="$(run --verify "$record")"
[[ "$status" == 1 ]] && grep -Eq '^DRIFT head moved [0-9a-f]+\.\.[0-9a-f]+ \(1 commit' "$root/out" || fail 'a new commit is reported as head moved'
(cd -- "$repo" && "$command_path" "$record" >/dev/null 2>&1)

printf 'changed again\n' >"$repo/tracked.txt"
status="$(run --verify "$record")"
[[ "$status" == 1 ]] && grep -qx 'DRIFT new: tracked.txt' "$root/out" || fail 'an edit of a committed file is reported as new drift'
(cd -- "$repo" && "$command_path" "$record" >/dev/null 2>&1)
printf 'changed a third time\n' >"$repo/tracked.txt"
status="$(run --verify "$record")"
[[ "$status" == 1 ]] && grep -qx 'DRIFT changed: tracked.txt' "$root/out" || fail 'an edit of an already-uncommitted file is reported as changed'
(cd -- "$repo" && "$command_path" "$record" >/dev/null 2>&1)

printf 'more\n' >"$repo/late.txt"
status="$(run --verify "$record")"
[[ "$status" == 1 ]] && grep -qx 'DRIFT new: late.txt' "$root/out" || fail 'a new untracked file is reported as new'
(cd -- "$repo" && "$command_path" "$record" >/dev/null 2>&1)

rm -- "$repo/late.txt"
status="$(run --verify "$record")"
[[ "$status" == 1 ]] && grep -qx 'DRIFT gone: late.txt' "$root/out" || fail 'a deleted file is reported as gone'
ok 'verify names a new commit, an edit, a new file and a deleted file'

# unusable input
status="$(run --verify "$root/missing.md")"
[[ "$status" == 2 && "$(wc -l <"$root/err")" -eq 1 ]] || fail 'a missing record exits 2 with one line'
printf 'no markers here\n' >"$root/plain.md"
status="$(run --verify "$root/plain.md")"
[[ "$status" == 2 && "$(wc -l <"$root/err")" -eq 1 ]] || fail 'a file without the record markers exits 2 with one line'
ok 'unusable input exits 2 with one line'
non_git
locked_write

without_flock

# Default session location and exact vendor identity share the existing record format.
profile="$root/profile"
status="$(cd -- "$repo" && SNO_PROFILE_DIR="$profile" CLAUDE_SESSION_ID=claude-test run)"
default="$profile/station/handoff/claude-test.md"
[[ "$status" == 0 && -f "$default" ]] || fail 'known session with no file writes its default record'
grep -qx 'runtime: claude-code' "$default" && grep -qx 'session-id: claude-test' "$default" || fail 'default record has the exact Claude identity'
status="$(cd -- "$repo" && run "$default")"
[[ "$status" == 0 ]] && grep -qx 'session-id: claude-test' "$default" || fail 'refresh without optional metadata preserves the exact identity'
status="$(cd -- "$repo" && CODEX_THREAD_ID=codex-test run "$root/codex.md")"
[[ "$status" == 0 ]] && grep -qx 'runtime: codex' "$root/codex.md" && grep -qx 'session-id: codex-test' "$root/codex.md" || fail 'explicit record records the exact Codex identity'
ok 'default session record and explicit record preserve exact native session identities'
plain_brief

printf '1..%s\n' "$count"
