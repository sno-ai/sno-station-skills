#!/usr/bin/env bash
# Behaviour test for handoff-checkpoint: real git work trees, real files, real hashes.
set -Eeuo pipefail

command_path="$(realpath -- "${1:-$(dirname -- "${BASH_SOURCE[0]}")/handoff-checkpoint}")"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
count=0

ok() { count=$((count + 1)); printf 'ok %s - %s\n' "$count" "$1"; }
fail() { printf 'not ok %s - %s\n' "$((count + 1))" "$1"; [[ -s "$root/err" ]] && sed 's/^/# /' "$root/err"; exit 1; }
run() { local status=0; "$command_path" "$@" >"$root/out" 2>"$root/err" || status=$?; printf '%s' "$status"; }
git_() { git -C "$repo" -c user.name=Test -c user.email=test@example.invalid "$@"; }
new_repo() {
    repo="$root/$1"
    mkdir -p -- "$repo"
    git -C "$repo" init -q -b main
    printf 'one\n' >"$repo/tracked.txt"
    git_ add tracked.txt
    git_ commit -q -m 'first commit'
}

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
for heading in 'Objective and authorization' 'Done' 'Next' 'Decisions and assumptions' 'Risks and open questions'; do
    grep -q "^## $heading\$" "$record" || fail "agent section '$heading' exists"
done
ok 'create writes the machine record and the five agent sections'

# refresh keeps every byte outside the record
python3 - "$record" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = t.replace("## Done\n", "## Done\n- step one finished, proof in proof/1.log\n", 1)
t = t.replace("## Next\n", "## Next\n1. write the report\n2. run the checks\n", 1)
p.write_text(t)
PY
outside() { sed '/<!-- machine-record:start -->/,/<!-- machine-record:end -->/d' "$1"; }
outside "$record" >"$root/outside-before"
git_ add -A
git_ commit -q -m 'second commit'
status="$(cd -- "$repo" && run "$record")"
[[ "$status" == 0 ]] || fail "refresh exits 0 (got $status)"
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
[[ "$status" == 2 && "$(wc -l <"$root/err")" == 1 ]] || fail 'a missing record exits 2 with one line'
printf 'no markers here\n' >"$root/plain.md"
status="$(run --verify "$root/plain.md")"
[[ "$status" == 2 && "$(wc -l <"$root/err")" == 1 ]] || fail 'a file without the record markers exits 2 with one line'
status="$(cd -- "$root/empty" && run "$root/nogit.md")"
[[ "$status" == 2 && "$(wc -l <"$root/err")" == 1 && ! -e "$root/nogit.md" ]] || fail 'outside a git work tree it exits 2 and writes nothing'
ok 'unusable input exits 2 with one line'

printf '1..%s\n' "$count"
