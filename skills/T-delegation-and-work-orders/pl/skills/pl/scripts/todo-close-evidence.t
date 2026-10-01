#!/usr/bin/env bash
# Missing evidence cannot block closure; unreadable history must prevent id reuse.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo="$(mktemp -d)"
trap 'rm -rf -- "$repo"' EXIT
printf '# TODO\n\n## OPEN\n' > "$repo/TODO.md"

"$script_dir/todo.sh" add --repo "$repo" --name 'Completed task' --prd none \
  --state queued --decision low > /dev/null

output="$("$script_dir/todo.sh" close --repo "$repo" b-0001 \
  --outcome 'requested behavior works' --evidence 'missing-result.md' 2>&1)"
[[ "$output" == *'missing-result.md'* ]]
[[ "$output" == *'closed b-0001'* ]]
! grep -q 'id: b-0001' "$repo/TODO.md"

"$script_dir/todo.sh" add --repo "$repo" --name 'Second completed task' \
  --prd none --state queued --decision low > /dev/null
chmod 0400 "$repo/ai-doc/JOURNAL/routing-ledger.jsonl"
if output="$("$script_dir/todo.sh" close --repo "$repo" b-0002 \
  --outcome 'second behavior works' 2>&1)"; then
  exit 1
fi
chmod 0600 "$repo/ai-doc/JOURNAL/routing-ledger.jsonl"
[[ "$output" == *'cannot append the close'* ]]
grep -q 'id: b-0002' "$repo/TODO.md"

printf 'todo close: missing evidence did not block; unwritable identity history stayed loud\n'
