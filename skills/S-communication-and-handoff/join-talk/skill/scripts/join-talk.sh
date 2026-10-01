#!/usr/bin/env bash
# join-talk.sh — make the agent that runs this command reachable through Reach.
#
# One call registers the seat (`sno reach init` + `sno reach register`, this terminal as the
# wake channel). Every input comes from the environment of the running agent, so a person
# opens an agent by hand, the agent runs this, and from then on it can be listed, sent
# cards, called, rung, and can reply.
#
# Usage: join-talk.sh [<address>] [--name <display>]
#   <address>  role.seat@host; default hand.<repo>@<host>, <repo> from the git top-level
#   --name     display name; default <repo>
# Stdout: exactly one line, `joined <address>`. Everything else is stderr.
# Exit:  0 joined (or already joined from this terminal) · 2 usage · 3 no terminal
#        identity (not under tmux or Orca) · 4 `sno`, `jq` or `flock` is missing · the runtime's own status
#        when init or register refuse.
set -Eeuo pipefail

readonly ADDRESS_RE='^[a-z][a-z0-9-]{0,31}\.[a-z0-9][a-z0-9-]{0,63}@[a-z0-9][a-z0-9.-]{0,252}$'
readonly STATE_ROOT="${SNO_REACH_ROOT:-$HOME/.local/state/sno-reach}"

die() {
  local status="$1"
  shift
  printf 'join: %s\n' "$*" >&2
  exit "$status"
}

address=''
name=''
while (($# > 0)); do
  case "$1" in
    --name)
      [[ $# -ge 2 && -n "$2" ]] || die 2 '--name needs a value'
      name="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
      exit 0
      ;;
    -*)
      die 2 "unknown option: $1"
      ;;
    *)
      [[ -z "$address" ]] || die 2 'only one address is accepted'
      address="$1"
      shift
      ;;
  esac
done

# The wake channel is whatever terminal this agent's shell inherited.
if [[ -n "${TMUX_PANE:-}" ]]; then
  identity="tmux-pane:${TMUX_PANE}"
  reach_channel='tmux'
  reach_handle="$TMUX_PANE"
elif [[ -z "${TMUX:-}" && -n "${ORCA_TAB_ID:-}" ]]; then
  identity="orca-tab:${ORCA_TAB_ID}"
  reach_channel='orca'
  reach_handle="${ORCA_TERMINAL_HANDLE:-}"
  [[ -n "$reach_handle" ]] || die 3 'under Orca but ORCA_TERMINAL_HANDLE is empty: Reach cannot address this terminal'
else
  die 3 'no terminal to be reached at: this shell is under neither tmux nor Orca'
fi

command -v sno >/dev/null || die 4 'sno is missing: Reach registration needs it (installed by sno setup)'
command -v jq >/dev/null || die 4 'jq is missing: join-talk needs it to detect another terminal holding the same address'
command -v flock >/dev/null || die 4 'flock is missing: join-talk needs it so two terminals joining together do not pick the same address (install util-linux flock)'

host="$(hostname | tr '[:upper:]' '[:lower:]')"
[[ -n "$host" ]] || die 4 'hostname printed nothing'

repo="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
repo="$(basename -- "$repo" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-\n' '-')"
repo="${repo#-}"
[[ -n "$repo" ]] || repo='shell'

# Same terminal, same seat: rerunning is a no-op. Another live terminal holding the derived
# address gets out of the way with a numeric suffix.
seat_identity() {
  jq -r '.identity | "\(.kind):\(.value)"' "$STATE_ROOT/$1/reachable.json" 2>/dev/null || true
}

# One repo at a time chooses, initializes and registers, so two terminals joining together
# cannot both pick the same free address.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/sno-join-talk-${repo}-$(id -u).lock"
flock -w 60 9 || die 4 "another join for ${repo} is still running after 60 s"

if [[ -z "$address" ]]; then
  address="hand.${repo}@${host}"
  n=1
  while [[ -f "$STATE_ROOT/$address/reachable.json" && "$(seat_identity "$address")" != "$identity" ]]; do
    n=$((n + 1))
    ((n <= 9)) || die 4 "nine seats already hold hand.${repo}*@${host}; pass an address"
    address="hand.${repo}-${n}@${host}"
  done
fi
[[ "$address" =~ $ADDRESS_RE ]] || die 2 "address must look like role.seat@host: $address"
[[ -n "$name" ]] || name="$repo"

sno reach init --as "$address" --name "$name" >/dev/null
sno reach register --as "$address" --channel "$reach_channel" --handle "$reach_handle" >/dev/null

printf 'joined %s\n' "$address"
printf 'join: others reach you with sno reach send or sno reach call %s; you answer with sno reach reply --as %s\n' \
  "$address" "$address" >&2
