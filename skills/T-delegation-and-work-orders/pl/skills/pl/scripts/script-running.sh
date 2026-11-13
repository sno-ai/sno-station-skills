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
# Exit: 0 running (pids on stdout) · 1 not running · 2 usage · 3 processes cannot be read.
# Linux reads /proc; macOS needs python3 for the kernel's argv listing.
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
exit 3  the process table could not be read (macOS without a working python3)
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

# macOS has no /proc. The kernel gives each process's exact argv through sysctl
# KERN_PROCARGS2; this prints, per process, pid NUL argc NUL and then argc arguments each
# followed by NUL. Processes it may not read (another user's, or one that just exited) are
# left out, so on macOS only this user's processes are seen.
readonly MACOS_ARGV_PY='
import ctypes, struct, sys
libc = ctypes.CDLL(None, use_errno=True)
def sysctl(mib, size):
    buf = ctypes.create_string_buffer(size)
    n = ctypes.c_size_t(size)
    if libc.sysctl((ctypes.c_int * len(mib))(*mib), len(mib), buf, ctypes.byref(n), None, 0):
        return None
    return buf.raw[:n.value]
argmax = struct.unpack("i", sysctl([1, 8], 4))[0]            # CTL_KERN, KERN_ARGMAX
count = libc.proc_listallpids(None, 0)
pids = (ctypes.c_int * (count + 64))()
count = libc.proc_listallpids(pids, ctypes.sizeof(pids))
if count <= 0:
    sys.exit("proc_listallpids returned no processes")
out = sys.stdout.buffer
for pid in pids[:count]:
    raw = sysctl([1, 49, pid], argmax)                          # CTL_KERN, KERN_PROCARGS2
    if not raw or len(raw) < 4:
        continue
    argc = struct.unpack("i", raw[:4])[0]
    rest = raw[4:]
    start = rest.find(b"\0")                                    # skip the executable path
    if start < 0:
        continue
    while start < len(rest) and rest[start] == 0:
        start += 1
    args = rest[start:].split(b"\0")[:argc]
    if len(args) < argc:
        continue
    out.write(b"%d\0%d\0" % (pid, argc) + b"".join(a + b"\0" for a in args))
'

live=()
consider() { # pid argv...
  local pid="$1"
  shift
  [ "$pid" = "$$" ] && return 0
  [ "$#" -gt 0 ] || return 0

  # Position, not substring: the script is argv[0], or argv[0] is an interpreter and the
  # script is argv[1]. Everything from there rightwards is that script's own arguments.
  local own_args
  if [ "${1##*/}" = "$TARGET" ]; then
    own_args=("${@:2}")
  elif [ "$#" -gt 1 ] && [ "${2##*/}" = "$TARGET" ]; then
    own_args=("${@:3}")
  else
    return 0
  fi

  local joined="${own_args[*]:-}" want
  for want in ${REQUIRED_ARGS[@]+"${REQUIRED_ARGS[@]}"}; do
    case "$joined" in
      *"$want"*) ;;
      *) return 0 ;;
    esac
  done
  live+=("$pid")
}

if [ -d /proc/self ]; then
  for cmdline in /proc/[0-9]*/cmdline; do
    pid="${cmdline%/cmdline}"
    pid="${pid#/proc/}"

    # A process can exit between the glob expanding and this read, so the open itself must be
    # inside the silenced group — a redirection failure is reported by the shell, not by
    # mapfile, and an unguarded one prints a spurious error on every busy machine.
    argv=()
    { mapfile -d '' -t argv < "$cmdline"; } 2>/dev/null || continue
    consider "$pid" ${argv[@]+"${argv[@]}"}
  done
else
  # The snapshot goes to a file, not a pipe: a pipe would fork a copy of this shell, carrying
  # this script's own argv, while the listing runs.
  snapshot="$(mktemp)"
  trap 'rm -f -- "$snapshot"' EXIT
  if ! python3 -c "$MACOS_ARGV_PY" >"$snapshot"; then
    printf 'script-running.sh: no /proc here and the sysctl process listing failed; cannot tell whether %s is running\n' "$TARGET" >&2
    exit 3
  fi
  while IFS= read -r -d '' pid && IFS= read -r -d '' argc; do
    argv=()
    for ((i = 0; i < argc; i++)); do
      IFS= read -r -d '' arg
      argv+=("$arg")
    done
    consider "$pid" ${argv[@]+"${argv[@]}"}
  done <"$snapshot"
fi

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
