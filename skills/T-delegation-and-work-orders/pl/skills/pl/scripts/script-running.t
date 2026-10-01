#!/usr/bin/env bash
# script-running.sh — a process is what it IS, never what its command line mentions.
#
# A checker can match itself, and an executor charter can name a script without
# running it. Both are false positives when matching the whole command line.
set -Eeuo pipefail

CHECK="${CHECK:-$(dirname "$0")/script-running.sh}"

root="$(mktemp -d)"
pids=()
cleanup() {
  for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null || true; done
  rm -rf -- "$root"
}
trap cleanup EXIT

tests=0
failures=0
check() { # $1 label, rest: command
  local label="$1"; shift
  tests=$((tests + 1))
  if "$@"; then printf 'ok %d - %s\n' "$tests" "$label"
  else printf 'not ok %d - %s\n' "$tests" "$label"; failures=$((failures + 1)); fi
}

run_check() { bash "$CHECK" "$@" >/dev/null 2>&1; }
not_running() { ! bash "$CHECK" "$@" >/dev/null 2>&1; }
exits_with() { # $1 expected code, rest: args to the checker
  local want="$1"; shift
  local got=0
  bash "$CHECK" "$@" >/dev/null 2>&1 || got=$?
  [ "$got" = "$want" ]
}
pid_absent() { # $1 pid, rest: args to the checker
  local pid="$1"; shift
  local out
  out="$(bash "$CHECK" "$@" 2>/dev/null || true)"
  case " $out " in
    *" $pid "*) return 1 ;;
    *) return 0 ;;
  esac
}

# Two scripts: the one we look for, and an unrelated one used to carry contaminating text.
victim="$root/victim.sh"
other="$root/other.sh"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$victim"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$other"
chmod +x "$victim" "$other"

# 1. an honest negative first, before anything exists that could produce a false positive
check "reports not running when nothing is" not_running victim.sh
check "not running is exit 1" exits_with 1 victim.sh

# 2-4. interpreter form: `bash /path/victim.sh --log X` — argv[0]=bash, argv[1]=the script
bash "$victim" --log "$root/a.log" &
pids+=($!)
sleep 0.3
check "finds it when launched through an interpreter" run_check victim.sh
check "--arg narrows to the right run" run_check victim.sh --arg "$root/a.log"
check "--arg rejects a run with a different argument" not_running victim.sh --arg /nowhere/b.log

# 5. Self-mention: a shell whose own command line mentions the script name.
#    `pgrep -f victim.sh` matches this process. Position-matching must not.
bash -c 'sleep 30 # victim.sh --log /tmp/x' &
mention_pid=$!
pids+=("$mention_pid")
sleep 0.3
check "a shell that merely mentions the name is not counted" \
  pid_absent "$mention_pid" victim.sh

# 6. Charter text: a different script carrying the name inside one of its arguments,
#    the exact shape of an executor charter naming the command it chartered.
bash "$other" "mission: run the gate · command: $victim --log $root/a.log" &
charter_pid=$!
pids+=("$charter_pid")
sleep 0.3
check "a different script carrying the name in an argument is not counted" \
  pid_absent "$charter_pid" victim.sh
check "and it is still not counted when --arg matches the carried text" \
  pid_absent "$charter_pid" victim.sh --arg "$root/a.log"

# 7. direct form: argv[0] IS the script, because it was run through its shebang
"$victim" --log "$root/c.log" &
pids+=($!)
sleep 0.3
check "finds it when run directly through its shebang" run_check victim.sh --arg "$root/c.log"

# 8. usage
check "no script name is a usage error" exits_with 2
check "an unknown flag is a usage error" exits_with 2 victim.sh --nope
check "--arg with no value is a usage error" exits_with 2 victim.sh --arg
check "--help exits 0" run_check --help

# 9. the checker never counts itself, even when it is the script being asked about
check "the checker does not match its own process" exits_with 1 script-running.sh

printf '1..%d\n' "$tests"
if [ "$failures" -gt 0 ]; then
  printf '# %d of %d failed\n' "$failures" "$tests" >&2
  exit 1
fi
printf '# all %d passed\n' "$tests"
