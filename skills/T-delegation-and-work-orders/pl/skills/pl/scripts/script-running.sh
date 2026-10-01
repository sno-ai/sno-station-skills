#!/usr/bin/env bash
# script-running.sh — is a given shell script ACTUALLY running right now?
#
# Why this exists: `pgrep -f <name>` and `ps | grep <name>` match a process whose command
# line merely mentions the name, which gives a confident false "it is already running" in
# two ways:
#
#   1. The checker's own shell. Its command line contains the pattern, so it matches itself.
#   2. A process carrying text that names the script. An executor charter passed as
#      one argument can name a script without running it.
#
# Both come from matching the whole command line when the real question is which script
# this process is. So identify by position, never by substring —
# argv[0] is the script, or argv[0] is an interpreter and argv[1] is the script. Anything
# further right is an argument, and an argument can only NARROW a match, never create one.
#
# Usage:
#   script-running.sh <script-name> [--arg <substring>]...
#
# Exit: 0 running (pids on stdout) · 1 not running · 2 usage.
set -Eeuo pipefail

usage() {
  cat <<'EOF'
usage: script-running.sh <script-name> [--arg <substring>]...

Answers whether a shell script is running, by matching the process's argv position
rather than a substring of its whole command line.

  <script-name>      basename as invoked, e.g. log-watch.sh
  --arg <substring>  repeatable; must appear among that script's own arguments, so two
                     runs of one script can be told apart (e.g. --arg "$spawn_log")

exit 0  running — one line on stdout: RUNNING <pid>...
exit 1  not running
exit 2  usage error
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  printf 'script-running.sh: no script name given; nothing can be checked\n' >&2
  usage >&2
  exit 2
fi
shift

REQUIRED_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --arg)
      [ $# -ge 2 ] || { printf 'script-running.sh: --arg needs a value\n' >&2; exit 2; }
      REQUIRED_ARGS+=("$2")
      shift 2
      ;;
    *)
      printf 'script-running.sh: unknown argument %q\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

live=()
for cmdline in /proc/[0-9]*/cmdline; do
  pid="${cmdline%/cmdline}"
  pid="${pid#/proc/}"
  [ "$pid" = "$$" ] && continue

  # A process can exit between the glob expanding and this read, so the open itself must be
  # inside the silenced group — a redirection failure is reported by the shell, not by
  # mapfile, and an unguarded one prints a spurious error on every busy machine.
  argv=()
  { mapfile -d '' -t argv < "$cmdline"; } 2>/dev/null || continue
  [ "${#argv[@]}" -gt 0 ] || continue

  # Position, not substring: the script is argv[0], or argv[0] is an interpreter and the
  # script is argv[1]. Everything from there rightwards is that script's own arguments.
  if [ "${argv[0]##*/}" = "$TARGET" ]; then
    own_args=("${argv[@]:1}")
  elif [ "${#argv[@]}" -gt 1 ] && [ "${argv[1]##*/}" = "$TARGET" ]; then
    own_args=("${argv[@]:2}")
  else
    continue
  fi

  joined="${own_args[*]:-}"
  matched=1
  for want in "${REQUIRED_ARGS[@]}"; do
    case "$joined" in
      *"$want"*) ;;
      *) matched=0; break ;;
    esac
  done
  [ "$matched" = 1 ] && live+=("$pid")
done

if [ "${#live[@]}" -gt 0 ]; then
  printf 'RUNNING %s\n' "${live[*]}"
  exit 0
fi

printf 'NOT RUNNING — no process is %s' "$TARGET" >&2
if [ "${#REQUIRED_ARGS[@]}" -gt 0 ]; then
  printf ' with argument(s): %s' "${REQUIRED_ARGS[*]}" >&2
fi
printf '\n' >&2
exit 1
