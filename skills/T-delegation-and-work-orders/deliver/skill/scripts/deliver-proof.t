#!/usr/bin/env bash
set -Eeuo pipefail

command_path="$(realpath -- "${1:-$(dirname -- "${BASH_SOURCE[0]}")/deliver-proof}")"
root="$(mktemp -d)"
trap 'rm -r -- "$root"' EXIT
count=0

ok() { count=$((count + 1)); printf 'ok %s - %s\n' "$count" "$1"; }
fail() { printf 'not ok %s - %s\n' "$((count + 1))" "$1"; exit 1; }
charter() {
    mkdir -p -- "$root/$1"
    printf '# Work\n\n## Success checks\n1. Run command\n2. Inspect evidence\n\n## Report\nKeep this line.\n' >"$root/$1/work.md"
}
run() {
    local status=0
    "$command_path" "$@" >"$root/out" 2>"$root/err" || status=$?
    printf '%s' "$status"
}

charter collision
mkdir -p -- "$root/bin"
cat >"$root/bin/date" <<'SH'
#!/bin/sh
printf '20260929T120000Z\n'
SH
chmod +x -- "$root/bin/date"
status="$(PATH="$root/bin:$PATH" run run "$root/collision/work.md" 1 -- bash -c 'printf "first output\n"; exit 7')"
[[ "$status" == 7 ]] || fail 'first same-second run status'
status="$(PATH="$root/bin:$PATH" run run "$root/collision/work.md" 1 -- bash -c 'printf "second output\n"')"
[[ "$status" == 0 ]] || fail 'second same-second run status'
[[ "$(cat "$root/collision/work.proof/1-20260929T120000Z.log")" == 'first output' ]] || fail 'first same-second log retained'
[[ "$(cat "$root/collision/work.proof/1-20260929T120000Z-2.log")" == 'second output' ]] || fail 'second same-second log retained'
grep -Eq '^\| 1 \| fail \| .* \| 7 \| work\.proof/1-20260929T120000Z\.log \| 20260929T120000Z \|$' "$root/collision/work.md" || fail 'failed row points at first log'
grep -Eq '^\| 1 \| pass \| .* \| 0 \| work\.proof/1-20260929T120000Z-2\.log \| 20260929T120000Z \|$' "$root/collision/work.md" || fail 'passed row points at second log'
ok 'same-second runs retain their own logs and rows'

mkdir -p -- "$root/empty-repo"
status="$(cd -- "$root/empty-repo" && run)"
[[ "$status" == 0 && "$(cat "$root/out")" == 'usage: deliver-proof run CHARTER N -- COMMAND... | see CHARTER N FILE TEXT | check CHARTER' && ! -s "$root/err" ]] || fail 'no arguments print usage to stdout and succeed'
[[ "$(run unknown)" == 2 ]] || fail 'unknown verb exits 2'
ok 'no arguments and unknown verb have distinct exit contracts'

charter pass
cp -- "$root/pass/work.md" "$root/pass/before"
status="$(run run "$root/pass/work.md" 1 -- bash -c 'printf "visible output\n"')"
[[ "$status" == 0 && "$(cat "$root/out")" == 'check 1: pass (exit 0)' ]] || fail 'successful run status and summary'
log="$(find "$root/pass/work.proof" -name '1-*.log' -print)"
[[ -f "$log" && "$(cat "$log")" == 'visible output' ]] || fail 'real output saved'
rel="${log#"$root/pass/"}"
[[ "$rel" =~ ^work\.proof/1-[0-9]{8}T[0-9]{6}Z\.log$ ]] || fail 'literal UTC log path'
grep -Fq '| 1 | pass | run: bash -c printf "visible output\n" | 0 | work.proof/1-' "$root/pass/work.md" || fail 'literal run row values'
grep -Eq '^\| 1 \| pass \| .* \| 0 \| work\.proof/1-[0-9]{8}T[0-9]{6}Z\.log \| [0-9]{8}T[0-9]{6}Z \|$' "$root/pass/work.md" || fail 'literal run row format'
cmp -s -n "$(wc -c <"$root/pass/before")" -- "$root/pass/before" "$root/pass/work.md" || fail 'all original bytes remain unchanged'
ok 'successful run records only its proof'

charter existing
sed -i '/^## Report$/i ## Proof\n\n| check | result | how | exit | log | at (UTC) |\n| --- | --- | --- | --- | --- | --- |\n' "$root/existing/work.md"
sed '/^## Proof$/,/^## Report$/{ /^## Report$/!d; }' "$root/existing/work.md" >"$root/existing/before"
printf 'seen\n' >"$root/existing/evidence.txt"
[[ "$(run see "$root/existing/work.md" 1 "$root/existing/evidence.txt" observed)" == 0 ]] || fail 'existing Proof append'
awk '/^\| --- \|/ { getline; print }' "$root/existing/work.md" | grep -Eq '^\| 1 \| pass \| see: observed \| 0 \| evidence\.txt \| [0-9]{8}T[0-9]{6}Z \|$' || fail 'row separated from existing table'
sed '/^## Proof$/,/^## Report$/{ /^## Report$/!d; }' "$root/existing/work.md" >"$root/existing/after"
cmp -s -- "$root/existing/before" "$root/existing/after" || fail 'bytes outside existing Proof changed'
ok 'existing Proof changes only inside its section'

charter fail
status="$(run run "$root/fail/work.md" 1 -- bash -c 'printf "failure\n" >&2; exit 7')"
[[ "$status" == 7 ]] || fail 'failed command status'
grep -Eq '^\| 1 \| fail \| run: .* \| 7 \| work\.proof/1-[0-9]{8}T[0-9]{6}Z\.log \| [0-9]{8}T[0-9]{6}Z \|$' "$root/fail/work.md" || fail 'failed row'
[[ "$(cat "$root/fail/work.proof"/*.log)" == failure ]] || fail 'stderr logged'
ok 'failed run retains its status and log'

charter invalid
cp -- "$root/invalid/work.md" "$root/invalid/before"
status="$(run run "$root/invalid/work.md" 3 -- printf no)"
[[ "$status" == 2 ]] || fail 'missing check number rejected'
cmp -s -- "$root/invalid/before" "$root/invalid/work.md" || fail 'rejected charter unchanged'
[[ ! -e "$root/invalid/work.proof" ]] || fail 'rejected run made no directory'
ok 'missing check number touches nothing'

charter absent
status="$(run run "$root/absent/work.md" 1 -- command-that-does-not-exist-729)"
[[ "$status" == 127 ]] || fail 'missing command status'
grep -Eq '^\| 1 \| fail \| run: command-that-does-not-exist-729 \| 127 \|' "$root/absent/work.md" || fail 'missing command row'
[[ -s "$(find "$root/absent/work.proof" -name '*.log' -print)" ]] || fail 'missing command error logged'
ok 'missing command records exit 127'

charter context
(
    cd -- "$root/context"
    "$command_path" run work.md 1 -- bash -c 'pwd; if read -r value; then printf "stdin open\n"; else printf "stdin closed\n"; fi' >"$root/context/out" 2>"$root/context/err"
)
context_log="$(find "$root/context/work.proof" -name '1-*.log' -print)"
[[ "$(cat "$context_log")" == "$root/context"$'\nstdin closed' ]] || fail 'command cwd or stdin'
[[ "$(cat "$root/context/out")" == 'check 1: pass (exit 0)' ]] || fail 'command output leaked to stdout'
ok 'run uses caller directory and closed stdin'

charter see
printf 'observed bytes\n' >"$root/see/evidence.txt"
status="$(run see "$root/see/work.md" 2 "$root/see/evidence.txt" $'line one\nline two | checked')"
[[ "$status" == 0 ]] || fail 'see status'
grep -Eq '^\| 2 \| pass \| see: line one line two \\| checked \| 0 \| evidence\.txt \| [0-9]{8}T[0-9]{6}Z \|$' "$root/see/work.md" || fail 'see row and newline/pipe sanitizing'
cp -- "$root/see/work.md" "$root/see/before"
status="$(run see "$root/see/work.md" 2 "$root/see/empty" nope)"
[[ "$status" == 2 ]] || fail 'missing evidence rejected'
cmp -s -- "$root/see/before" "$root/see/work.md" || fail 'missing evidence changed charter'
[[ ! -e "$root/see/empty" ]] || fail 'missing evidence created'
touch "$root/see/empty"
[[ "$(run see "$root/see/work.md" 2 "$root/see/empty" nope)" == 2 ]] || fail 'empty evidence accepted'
cmp -s -- "$root/see/before" "$root/see/work.md" || fail 'empty evidence changed charter'
ok 'see requires nonempty evidence and records its relative path'

status="$(run check "$root/pass/work.md")"
[[ "$status" == 1 && "$(cat "$root/out")" == *'check 2: NOT proven'* ]] || fail 'one failed check'
status="$(run check "$root/fail/work.md")"
[[ "$status" == 1 && "$(cat "$root/out")" == *'check 1: NOT proven'* ]] || fail 'last fail row'
status="$(run check "$root/invalid/work.md")"
[[ "$status" == 1 && "$(cat "$root/out")" == *'check 1: NOT proven'* ]] || fail 'no Proof table'
ok 'check reports failed and missing proof'

printf 'first pass\n' >"$root/see/first.txt"
status="$(run see "$root/see/work.md" 1 "$root/see/first.txt" checked)"
[[ "$status" == 0 ]] || fail 'second see status'
status="$(run check "$root/see/work.md")"
[[ "$status" == 0 && "$(cat "$root/out")" == $'check 1: proven\ncheck 2: proven\n2/2 checks proven' ]] || fail 'all proven output'
status="$(run see "$root/fail/work.md" 1 "$root/see/first.txt" later)"
[[ "$status" == 0 ]] || fail 'later pass append'
[[ "$(run check "$root/fail/work.md")" == 1 ]] || fail 'other missing check still fails'
grep -Fxq 'check 1: proven' "$root/out" || fail 'later pass overrides fail'
rm -- "$root/see/first.txt"
[[ "$(run check "$root/see/work.md")" == 1 ]] || fail 'deleted evidence accepted'
grep -Fq 'check 1: NOT proven' "$root/out" || fail 'deleted evidence reason'
ok 'latest row wins and deleted evidence fails'

printf 'second check\n' >"$root/pass/second.txt"
[[ "$(run see "$root/pass/work.md" 2 "$root/pass/second.txt" observed)" == 0 ]] || fail 'pass fixture second check'
[[ "$(run check "$root/pass/work.md")" == 0 ]] || fail 'run log not accepted'
rm -- "$log"
[[ "$(run check "$root/pass/work.md")" == 1 ]] || fail 'deleted run log accepted'
grep -Fq 'check 1: NOT proven (log or evidence missing)' "$root/out" || fail 'deleted run log reason'
ok 'deleted command log loses proof'

charter no_checks
sed -i '/^1\. Run command$/d; /^2\. Inspect evidence$/d' "$root/no_checks/work.md"
cp -- "$root/no_checks/work.md" "$root/no_checks/before"
[[ "$(run check "$root/no_checks/work.md")" == 2 ]] || fail 'no checks check status'
[[ "$(run run "$root/no_checks/work.md" 1 -- true)" == 2 ]] || fail 'no checks run status'
cmp -s -- "$root/no_checks/before" "$root/no_checks/work.md" || fail 'no checks mutated charter'
ok 'no success checks cannot run or check'

charter emptylog
[[ "$(run run "$root/emptylog/work.md" 1 -- true)" == 0 ]] || fail 'silent passing command status'
[[ "$(run see "$root/emptylog/work.md" 2 "$root/pass/second.txt" observed)" == 0 ]] || fail 'emptylog second check'
[[ "$(run check "$root/emptylog/work.md")" == 0 ]] || fail 'silent passing command must be proven'
[[ "$(cat "$root/out")" == $'check 1: proven\ncheck 2: proven\n2/2 checks proven' ]] || fail 'silent passing command output'
ok 'a passing command that prints nothing is proven'

mkdir -p -- "$root/dropped"
printf '# Work\n\n## Success checks\n1. Run command\n2. Inspect evidence\n3. ~~Old check~~ dropped\n' >"$root/dropped/work.md"
[[ "$(run run "$root/dropped/work.md" 1 -- true)" == 0 ]] || fail 'dropped fixture check 1'
[[ "$(run see "$root/dropped/work.md" 2 "$root/pass/second.txt" observed)" == 0 ]] || fail 'dropped fixture check 2'
[[ "$(run check "$root/dropped/work.md")" == 0 ]] || fail 'dropped check must not block close'
[[ "$(cat "$root/out")" == $'check 1: proven\ncheck 2: proven\n2/2 checks proven' ]] || fail 'dropped check output'
cp -- "$root/dropped/work.md" "$root/dropped/before"
[[ "$(run run "$root/dropped/work.md" 3 -- true)" == 2 ]] || fail 'dropped check cannot be run'
cmp -s -- "$root/dropped/before" "$root/dropped/work.md" || fail 'dropped check run changed charter'
ok 'a dropped check is neither required nor provable'

mkdir -p -- "$root/slices"
printf '# Work\n\n## Success checks\n### Slice A\n1. A one\n2. A two\n### Slice B\n1. B one\n2. B two\n\n## Report\nx\n' >"$root/slices/work.md"
cp -- "$root/slices/work.md" "$root/slices/before"
[[ "$(run run "$root/slices/work.md" 1 -- true)" == 2 ]] || fail 'repeated numbers accepted by run'
grep -Fq 'more than once' "$root/err" || fail 'repeated numbers message'
[[ "$(run check "$root/slices/work.md")" == 2 ]] || fail 'repeated numbers accepted by check'
cmp -s -- "$root/slices/before" "$root/slices/work.md" || fail 'repeated numbers changed charter'
[[ ! -e "$root/slices/work.proof" ]] || fail 'repeated numbers made a directory'
printf '# Work\n\n## Success checks\n### Slice A\n1. A one\n2. A two\n### Slice B\n3. B one\n4. B two\n' >"$root/slices/work.md"
[[ "$(run run "$root/slices/work.md" 1 -- true)" == 0 ]] || fail 'unique slice numbers run'
[[ "$(run check "$root/slices/work.md")" == 1 ]] || fail 'proof of slice A must not prove slice B'
[[ "$(cat "$root/out")" == $'check 1: proven\ncheck 2: NOT proven (no proof row)\ncheck 3: NOT proven (no proof row)\ncheck 4: NOT proven (no proof row)\n1/4 checks proven' ]] || fail 'slice output'
ok 'check numbers must be unique across slices'

charter mode
chmod 640 -- "$root/mode/work.md"
[[ "$(run run "$root/mode/work.md" 1 -- true)" == 0 ]] || fail 'mode run'
[[ "$(stat -c %a -- "$root/mode/work.md")" == 640 ]] || fail 'run changed charter mode'
[[ "$(run see "$root/mode/work.md" 2 "$root/pass/second.txt" observed)" == 0 ]] || fail 'mode see'
[[ "$(stat -c %a -- "$root/mode/work.md")" == 640 ]] || fail 'see changed charter mode'
ok 'charter file mode survives a proof row'

charter relative
printf 'relative evidence\n' >"$root/relative/evidence.txt"
(cd -- "$root" && "$command_path" see relative/work.md 2 relative/evidence.txt observed >"$root/out" 2>"$root/err")
grep -Eq '^\| 2 \| pass \| see: observed \| 0 \| evidence\.txt \|' "$root/relative/work.md" || fail 'evidence path read from cwd, recorded relative to charter'
ok 'see reads the evidence path from the caller directory'

mkdir -p -- "$root/notgnu"
printf '#!/bin/sh\necho "realpath: illegal option -- -" >&2\nexit 1\n' >"$root/notgnu/realpath"
chmod +x -- "$root/notgnu/realpath"
charter needgnu
cp -- "$root/needgnu/work.md" "$root/needgnu/before"
status="$(PATH="$root/notgnu:$PATH" run run "$root/needgnu/work.md" 1 -- true)"
[[ "$status" == 2 ]] || fail 'non-GNU tools status'
grep -Fq 'GNU coreutils' "$root/err" || fail 'non-GNU tools message'
[[ ! -e "$root/needgnu/work.proof" ]] || fail 'non-GNU tools made a directory'
ok 'non-GNU tools stop with one clear message'

printf '1..%s\n' "$count"
