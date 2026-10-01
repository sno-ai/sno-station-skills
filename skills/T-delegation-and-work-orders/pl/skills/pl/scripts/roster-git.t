#!/usr/bin/env bash
# roster.sh --git: the repo half of the wake sweep.
#
# The output must be stable so consecutive sweeps can be diffed when a repository
# stops moving.
# The remaining rows keep one failing repository from aborting the roster.
set -Eeuo pipefail

ROSTER="${ROSTER:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/roster.sh}"

root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
# roster.sh reads ~/.local/state; keep the test off the real one.
export HOME="$root/home"
mkdir -p "$HOME"

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

# a repo with a watch config, one commit, one dirty src file, one dirty protected file
repo="$root/withconf"
mkdir -p "$repo/src" "$repo/.pl"
git init -q "$repo"
printf 'src: src\nprotected: BASELINE\n' > "$repo/.pl/watch.paths"
printf 'v1\n' > "$repo/BASELINE"
git -C "$repo" add -A
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m "seed BASELINE"
printf 'work\n' > "$repo/src/a.txt"
printf 'v2\n' > "$repo/BASELINE"

block() { bash "$ROSTER" --git "$1" 2>/dev/null | sed -n '/^=== GIT/,$p'; }

# 1. byte-stable for unchanged repo state — the whole reason this exists
same_twice() {
  local a b
  a="$(block "$repo")"; b="$(block "$repo")"
  [[ "$a" == "$b" && -n "$a" ]]
}
check "identical output across two runs (diffable sweeps)" same_twice

# 1b. --git-only is what a PL actually diffs: the fleet table carries relative
#     ages that change every run, so leaving it in makes every sweep differ and
#     buries the repo block the diff exists to expose.
git_only_is_whole_stdout() {
  local a b
  a="$(bash "$ROSTER" --git-only --git "$repo" 2>/dev/null)"
  b="$(bash "$ROSTER" --git-only --git "$repo" 2>/dev/null)"
  [[ -n "$a" && "$a" == "$b" ]] || return 1
  [[ "$a" == "=== GIT "* ]] || return 1          # no fleet table above it
  [[ "$a" != *"last heartbeat"* ]]               # no heartbeat ages inside it
}
check "--git-only: stdout is the git blocks alone, identical twice" git_only_is_whole_stdout

# 2. src and protected are read from .pl/watch.paths, not from the script
reads_config() {
  local out; out="$(block "$repo")"
  [[ "$out" == *"DIRTY    M BASELINE"* ]] && return 1   # BASELINE is not under src:
  # untracked dirs stay collapsed (git's default) — same view the sweep had before
  [[ "$out" == *"DIRTY   ?? src/"*      ]] || return 1
  [[ "$out" == *"PROT     M BASELINE"*  ]] || return 1
  [[ "$out" == *"PROTLOG"*              ]] || return 1
}
check "src/protected come from .pl/watch.paths" reads_config

# 3. no config: src degrades to the whole tree, protected says so instead of
#    silently reporting every file as protected
plain="$root/plain"
git init -q "$plain"
git -C "$plain" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
printf 'x\n' > "$plain/loose.txt"
no_config() {
  local out; out="$(block "$plain")"
  [[ "$out" == *"DIRTY   ?? loose.txt"* ]] || return 1
  [[ "$out" == *"PROT    (undefined"*   ]] || return 1
}
check "no watch.paths: DIRTY covers the tree, PROT reports undefined" no_config

# 4. a non-repo path degrades to one stderr line and MUST NOT abort the roster
#    (the fleet table above it is what the PL actually wakes for)
notgit="$root/notgit"; mkdir -p "$notgit"
survives_nonrepo() {
  local rc=0
  bash "$ROSTER" --git "$notgit" >/dev/null 2>"$root/err" || rc=$?
  [[ "$rc" -eq 0 ]] || return 1
  grep -q 'not a git repository' "$root/err"
}
check "non-repo path: stderr warning, exit still 0" survives_nonrepo

# 5. malformed input is rejected before any output
rejects() { # $@ = args that must exit 2
  local rc=0
  bash "$ROSTER" "$@" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]]
}
check "--git with no value exits 2"        rejects --git
check "--git with a missing path exits 2"  rejects --git "$root/does-not-exist"
check "--git-only without --git exits 2"   rejects --git-only

printf '1..%d\n' "$tests"
[[ "$failures" -eq 0 ]] || { printf '%d failure(s)\n' "$failures" >&2; exit 1; }
