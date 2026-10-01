#!/bin/bash
# exec-tree-check.sh — is an executor REAL WORK, or a wrapper holding a keepalive sleep?
#
# A pid proves only that a process exists; a `bash---sleep` tree is not evidence
# that an executor is doing work.
#
# SELF-EXCLUSION IS NOT OPTIONAL. A pattern-matching liveness check finds its own command
# line and every ancestor shell that carries the pattern, then reports the lane healthy
# because it found ITSELF. That is the same defect it exists to detect, one level up.
#
# WHAT IT DOES NOT TELL YOU, AND THIS MATTERS: SLEEP-ONLY cannot distinguish an executor
# that FINISHED and exited cleanly from one that never started. Both leave the same
# bash---sleep shell. Read the last commit and the executor's stated wait before
# deciding whether work has stopped.
#
# So SLEEP-ONLY means GO LOOK, never RESTART. The discriminators are the executor's last
# commit and whether it said what it was waiting for. Read those before acting.
#
# usage: exec-tree-check.sh <work-or-executor-pattern>
# exit 0 = real work · 2 = only keepalive shells · 3 = no process at all
set -u
if [ ! -d /proc/$$ ] || ! command -v pgrep >/dev/null 2>&1 || ! command -v pstree >/dev/null 2>&1; then
  echo "exec-tree-check: requires Linux (/proc) with pgrep and pstree installed" >&2; exit 69
fi
pat="${1:?usage: exec-tree-check.sh <pattern>}"

# every ancestor of this script, so neither it nor the shell that launched it can match
declare -A skip=()
p=$$
while [ "$p" -gt 1 ] 2>/dev/null; do
  skip[$p]=1
  p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null) || break
  [ -n "$p" ] || break
done

pids=()
while read -r c; do
  [ -n "${skip[$c]:-}" ] && continue
  cmd=$(tr '\0' ' ' < "/proc/$c/cmdline" 2>/dev/null)
  case "$cmd" in *exec-tree-check*|*exec-sentinel*|*pgrep*) continue ;; esac
  # A SESSION SERVER IS NEVER THE EXECUTOR. A tmux server hosts every session on the
  # machine, so its tree contains OTHER journeys' healthy executors -- and it can match a
  # journey pattern from whatever started it. Reported as WORKING it makes a dead lane read
  # healthy off a live neighbour's children.
  comm=$(cat "/proc/$c/comm" 2>/dev/null)
  case "$comm" in tmux*|systemd|init) continue ;; esac
  pids+=("$c")
done < <(pgrep -f "$pat" 2>/dev/null)

((${#pids[@]})) || { echo "NO-PROCESS  nothing matches: $pat"; exit 3; }

real=0
for c in "${pids[@]}"; do
  tree=$(pstree -p "$c" 2>/dev/null | tr -d '\n')
  et=$(ps -o etime= -p "$c" 2>/dev/null | tr -d ' ')
  if [[ "$tree" =~ ^[^-]*\([0-9]+\)---sleep\([0-9]+\)$ ]]; then
    echo "SLEEP-ONLY  pid=$c elapsed=$et  $tree"
  else
    echo "WORKING     pid=$c elapsed=$et  ${tree:0:100}"
    real=1
  fi
done
((real)) && exit 0 || exit 2
