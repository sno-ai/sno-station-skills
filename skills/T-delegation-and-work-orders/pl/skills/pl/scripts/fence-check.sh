#!/usr/bin/env bash
# fence-check.sh — verify that a commit only touches paths inside a scope fence.
# Every checkpoint or close commit is checked against the journey's fence file; out-of-fence
# paths are a VIOLATION (the PL rejects or reverts that commit — commit-level, so other
# sessions' uncommitted files in a shared worktree are never touched).
#
#   fence-check.sh --repo <path> --commit <sha> --fence <fence-file>
#   fence-check.sh --repo <path> --worktree    --fence <fence-file>   # report-only
#
# Fence file: one entry per line. Blank lines and #comments ignored.
#   dir/            -> allows everything under dir/
#   path/to/file    -> exact file
#   glob (e.g. apps/x/**/*.py or *.md) -> bash extended glob match
# Exit: 0 PASS · 3 VIOLATION (paths listed) · 2 usage/missing input.
set -euo pipefail
case "${1:-}" in
  -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
shopt -s extglob globstar nullglob

repo="" commit="" fence="" worktree=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)     repo="$2"; shift 2 ;;
    --commit)   commit="$2"; shift 2 ;;
    --fence)    fence="$2"; shift 2 ;;
    --worktree) worktree=1; shift ;;
    *) echo "fence-check: unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] && [ -n "$fence" ] || { echo "fence-check: need --repo and --fence" >&2; exit 2; }
[ -f "$fence" ] || { echo "fence-check: fence file not found: $fence" >&2; exit 2; }
[ -n "$commit" ] || [ "$worktree" = 1 ] || { echo "fence-check: need --commit <sha> or --worktree" >&2; exit 2; }

# load fence patterns
patterns=()
while IFS= read -r line; do
  line="${line%%#*}"; line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
  [ -n "$line" ] && patterns+=("$line")
done < "$fence"
[ "${#patterns[@]}" -gt 0 ] || { echo "fence-check: fence file has no patterns" >&2; exit 2; }

# Component-aware glob→regex: `*` and `?` must not cross `/` (bash [[ == ]] lets * match
# slashes, so `apps/x/*.py` would approve nested out-of-scope files); `**` explicitly
# crosses directories.
glob_to_regex() { # $1=glob -> anchored ERE on stdout
  local g="$1" out="" c i
  for (( i=0; i<${#g}; i++ )); do
    c="${g:$i:1}"
    case "$c" in
      \*) if [ "${g:$((i+1)):1}" = "*" ]; then
            # `**/` = optional directory run (must also match zero dirs:
            # apps/x/**/*.py has to accept apps/x/foo.py); bare `**` = anything
            if [ "${g:$((i+2)):1}" = "/" ]; then out+="(.*/)?"; i=$((i+2)); else out+=".*"; i=$((i+1)); fi
          else out+="[^/]*"; fi ;;
      \?) out+="[^/]" ;;
      [.^\$+\(\)\[\]\{\}\|\\]) out+="\\$c" ;;
      *) out+="$c" ;;
    esac
  done
  printf '^%s$' "$out"
}

in_fence() { # $1 = repo-relative path
  local f="$1" p re
  for p in "${patterns[@]}"; do
    case "$p" in
      */) [[ "$f" == "$p"* ]] && return 0 ;;             # directory prefix
      *)  re="$(glob_to_regex "$p")"
          [[ "$f" =~ $re ]] && return 0 ;;               # exact or component-aware glob
    esac
  done
  return 1
}

if [ "$worktree" = 1 ]; then
  files="$(git -C "$repo" status --porcelain | cut -c4- | sed 's/^"\(.*\)"$/\1/')"
  label="worktree (report-only; other sessions' files may be listed)"
else
  git -C "$repo" rev-parse --verify --quiet "${commit}^{commit}" >/dev/null || {
    echo "fence-check: commit not found: $commit" >&2; exit 2; }
  # Merge commits are rejected outright: their diff-trees can be empty (an empty file list
  # would read as PASS) and an executor has no business merging.
  nparents=$(git -C "$repo" rev-list --parents -n1 "$commit" | wc -w)
  if [ "$nparents" -gt 2 ]; then
    echo "VIOLATION: commit $commit is a merge commit — executors may not merge; unchecked paths could ride in"
    exit 3
  fi
  # --root: root commits enumerate their files (else empty list = false PASS)
  # --no-renames: a rename INTO the fence must surface the out-of-fence source
  files="$(git -C "$repo" diff-tree --root --no-renames --no-commit-id --name-only -r "$commit")"
  label="commit $commit"
fi

violations=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  in_fence "$f" || violations+=("$f")
done <<< "$files"

if [ "${#violations[@]}" -eq 0 ]; then
  echo "PASS: all paths in $label are inside the fence"
  exit 0
fi
echo "VIOLATION: $label touches ${#violations[@]} out-of-fence path(s):"
printf '  %s\n' "${violations[@]}"
[ "$worktree" = 1 ] || echo "action: reject/revert this commit (it is the executor's own; a revert cannot harm parallel sessions)"
exit 3
