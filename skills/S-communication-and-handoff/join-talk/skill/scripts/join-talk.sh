#!/usr/bin/env bash
# join-talk.sh — make the agent that runs this command reachable through Reach.
#
# One call registers the seat (`sno reach init` + `sno reach register`, this terminal as the
# wake channel). Every input comes from the environment of the running agent, so a person
# opens an agent by hand, the agent runs this, and from then on it can be listed, sent
# cards, called, rung, and can reply.
#
# Usage: join-talk.sh [<address>] [--name <display>]
#   <address>  explicit address; default <call-name>.agent@<host>
#   --name     display name; default <repo>
# Stdout: exactly one line, `joined <address>`. Everything else is stderr.
# Exit:  0 joined (or already joined from this terminal) · 2 usage · 3 no discoverable
#        terminal identity · 4 `sno`, `jq` or `flock` is missing · the runtime's own status
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

command -v sno >/dev/null || die 4 'sno is missing: Reach registration needs it (installed by sno setup)'
command -v jq >/dev/null || die 4 'jq is missing: join-talk needs it to detect another terminal holding the same address'
command -v flock >/dev/null || die 4 'flock is missing: join-talk needs it so two terminals joining together do not pick the same address (install util-linux flock)'

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
elif [[ -n "${CURSOR_CONVERSATION_ID:-}" && -z "${CURSOR_INVOKED_AS:-}" ]]; then
  # A Cursor IDE chat has no terminal; Reach delivers to it through the chat's conversation id.
  identity="cursor-ide:${CURSOR_CONVERSATION_ID}"
  reach_channel='cursor-ide'
  reach_handle="$CURSOR_CONVERSATION_ID"
else
  terminal_info="$(sno reach terminal-info)" || die 3 'terminal discovery failed; see the Reach diagnostic above'
  reach_handle="$(jq -er '.handle | strings | select(length > 0)' <<<"$terminal_info")" || die 3 'no terminal input endpoint was discovered'
  reach_channel='terminal'
  identity="terminal:$reach_handle"
fi

host="$(hostname | tr '[:upper:]' '[:lower:]')"
[[ -n "$host" ]] || die 4 'hostname printed nothing'

repo="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
repo="$(basename -- "$repo" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-\n' '-')"
repo="${repo#-}"
[[ -n "$repo" ]] || repo='shell'
[[ -n "$name" ]] || name="$repo"
call_name="$(printf '%s' "$name" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cd 'a-z0-9-')"

# Same terminal, same seat: rerunning is a no-op. Another live terminal holding the derived
# address gets out of the way with a numeric suffix.
seat_identity() {
  jq -r '.identity | "\(.kind):\(.value)"' "$STATE_ROOT/$1/reachable.json" 2>/dev/null || true
}

# One call name at a time chooses, initializes and registers, so two terminals joining together
# cannot both pick the same free address.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/sno-join-talk-${call_name}@${host}-$(id -u).lock"
flock -w 60 9 || die 4 "another join for ${name} is still running after 60 s"

if [[ -z "$address" ]]; then
  address="${call_name}.agent@${host}"
  n=1
  while [[ -f "$STATE_ROOT/$address/reachable.json" && "$(seat_identity "$address")" != "$identity" ]]; do
    n=$((n + 1))
    ((n <= 9)) || die 4 "nine seats already hold ${call_name}*.agent@${host}; pass an address"
    address="${call_name}-${n}.agent@${host}"
  done
fi
[[ "$address" =~ $ADDRESS_RE ]] || die 2 "address must look like role.seat@host: $address"

sno reach init --as "$address" --name "$name" >/dev/null
sno reach register --as "$address" --channel "$reach_channel" --handle "$reach_handle" >/dev/null

printf 'joined %s\n' "$address"
printf 'join: others reach you with sno reach send; you answer with sno reach reply --as %s\n' \
  "$address" >&2
