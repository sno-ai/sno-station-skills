#!/usr/bin/env bash
# callsign.sh — human-speakable agent callsigns + window self-labeling.
# Every spawned agent gets a simple English callsign
# (machine-wide unique while active, ~48 rotating); windows label their own
# state via terminal title; closing agents print a standard close banner.
#
#   claim   [--journey <j-id>] --repo <repo> --kind <executor|monitor|pl|cos> [--session <id>] [--label <text>]
#           -> prints the claimed name on stdout (the ONLY stdout output);
#              PL and COS claims may omit --journey; executor and monitor claims may not.
#              exhausted pool = loud exit 4 (never auto-reclaims; --force repairs)
#   release <name> --journey <j-id>  -> frees the name IF that journey holds it
#           (exit 5 on ownership mismatch); --force = operator repair, logged.
#           Reuse is LRU-delayed ~48 deep.
#   transfer <name> --from <j-id> --to <j-id>
#           -> the SAME agent continues under a NEW journey, keeping its name.
#              Appends a claim for --to only if --from currently holds the name,
#              so the name is never free and cannot be raced or stolen. Use when
#              one executor session takes a continuation charter.
#   list                      -> active callsigns table (name journey repo kind since)
#   title   <run|wait|done|stuck> <name> --journey <j-id> <label...>
#           -> sets the terminal tab title and records the state; without --journey
#              the title is set but nothing is recorded
#   banner  <name> <journey> <log-or-journal-path>  -> prints the close banner
#
# State: single machine-wide ledger (append-only JSONL) shared by all runtimes.
set -euo pipefail

STATE_DIR="$HOME/.local/state"
LEDGER="$STATE_DIR/agent-callsigns.jsonl"
LOCK="$LEDGER.lock"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALLSIGN_DB="$SCRIPT_DIR/../references/callsigns.txt"
mkdir -p "$STATE_DIR"
touch "$LEDGER"

WORDS=()

load_words() {
  local line line_no=0
  local -A seen=()

  [ -r "$CALLSIGN_DB" ] || {
    echo "callsign: database is not readable: $CALLSIGN_DB" >&2
    exit 6
  }

  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue
    [[ "$line" =~ ^[a-z][a-z0-9-]*$ ]] || {
      echo "callsign: invalid name at $CALLSIGN_DB:$line_no: $line" >&2
      exit 6
    }
    [ -z "${seen[$line]+present}" ] || {
      echo "callsign: duplicate name at $CALLSIGN_DB:$line_no: $line" >&2
      exit 6
    }
    seen["$line"]=1
    WORDS+=("$line")
  done < "$CALLSIGN_DB"

  [ "${#WORDS[@]}" -gt 0 ] || {
    echo "callsign: database has no names: $CALLSIGN_DB" >&2
    exit 6
  }
}

load_words

now() { date -Is; }

# JSONL fields are written by naive printf — map ALL control bytes (CR, ESC, BEL,
# LF, TAB, …) to spaces and strip quotes/backslashes. Ledger integrity > fidelity.
sane() { printf '%s' "${1:-}" | tr '[:cntrl:]' ' ' | tr -d '\\"'; }

canonical_repo() {
  local requested="$1" main_root=""
  if [ -d "$requested" ]; then
    main_root="$(git -C "$requested" worktree list --porcelain 2>/dev/null |
      awk '/^worktree / { print substr($0, 10); exit }')"
  fi
  if [ -n "$main_root" ] && [ -d "$main_root" ]; then
    (cd -- "$main_root" && pwd -P)
  else
    printf '%s\n' "$requested"
  fi
}

_lock() { # usage: _lock  (uses FD 9; distinct exit for missing dependency)
  command -v flock >/dev/null 2>&1 || { echo "callsign: missing dependency: flock (util-linux)" >&2; exit 7; }
  exec 9>"$LOCK"
  flock -w 5 9 || { echo "callsign: ledger lock busy" >&2; exit 3; }
}

_active_claim_line() { # $1=name -> latest claim JSON line (empty if none)
  grep -F "\"event\":\"claim\",\"name\":\"$1\"" "$LEDGER" | tail -1
}
_field() { # $1=json-line $2=key -> value
  printf '%s' "$1" | awk -F'"' -v k="$2" '{for(i=1;i<NF;i++) if($i==k){print $(i+2); exit}}'
}

_pick_free() { # -> best free name (never-used first, else LRU release), or empty
  local events; events="$(_last_events)"
  local pick="" pick_ts="9999" w ev ts
  for w in "${WORDS[@]}"; do
    ev="$(printf '%s\n' "$events" | awk -F'\t' -v n="$w" '$1==n {print $2}')"
    ts="$(printf '%s\n' "$events" | awk -F'\t' -v n="$w" '$1==n {print $3}')"
    if [ "$ev" = "claim" ]; then continue; fi
    if [ -z "$ev" ]; then pick="$w"; break; fi
    # ISO timestamps sort chronologically as strings.
    # shellcheck disable=SC2071
    if [[ "$ts" < "$pick_ts" ]]; then pick="$w"; pick_ts="$ts"; fi
  done
  printf '%s' "$pick"
}

# last event per name: "claim" or "release", plus ts — from the append-only ledger
_last_events() { # stdout: name<TAB>event<TAB>ts  (latest line per name wins)
  awk -F'"' '
    /"name"/ {
      for (i=1; i<NF; i++) {
        if ($i == "name")  n = $(i+2)
        if ($i == "event") e = $(i+2)
        if ($i == "ts")    t = $(i+2)
      }
      last[n] = e "\t" t
    }
    END { for (n in last) print n "\t" last[n] }
  ' "$LEDGER"
}

cmd_claim() {
  local journey="" repo="" kind="executor" session="" label=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --journey) journey="$2"; shift 2 ;;
      --repo)    repo="$2";    shift 2 ;;
      --kind)    kind="$2";    shift 2 ;;
      --session) session="$2"; shift 2 ;;
      --label)   label="$2";   shift 2 ;;
      *) echo "callsign: unknown claim arg $1" >&2; exit 2 ;;
    esac
  done
  case "$kind" in
    pl|cos)
      [ -n "$repo" ] ||
        { echo "callsign: $kind claim needs --repo" >&2; exit 2; }
      ;;
    executor|monitor)
      if [ -z "$journey" ] || [ -z "$repo" ]; then
        echo "callsign: $kind claim needs --journey and --repo" >&2
        exit 2
      fi
      ;;
    *)
      echo "callsign: claim --kind must be executor|monitor|pl|cos" >&2
      exit 2
      ;;
  esac
  repo="$(canonical_repo "$repo")"
  journey="$(sane "$journey")"; repo="$(sane "$repo")"; kind="$(sane "$kind")"
  session="$(sane "$session")"; label="$(sane "$label")"

  _lock

  # active = last event is claim; free = rest; pick free with oldest release (never-used first)
  local pick; pick="$(_pick_free)"

  # Pool exhausted: NEVER auto-reclaim — an age heuristic could evict a live
  # long-running agent and mint a duplicate identity.
  # Uniqueness outranks convenience: fail loudly; reclaiming a dead owner's name is a
  # manual repair: `release <name> --force`.
  [ -n "$pick" ] || {
    echo "callsign: all ${#WORDS[@]} names active — no free name. Oldest active:" >&2
    _last_events | awk -F'\t' '$2=="claim"' | sort -t$'\t' -k3 | head -3 | awk -F'\t' '{print "  " $1 " since " $3}' >&2
    echo "callsign: verify the holder is dead, then: callsign.sh release <name> --force" >&2
    exit 4; }

  printf '{"event":"claim","name":"%s","ts":"%s","journey":"%s","repo":"%s","kind":"%s","session":"%s","label":"%s"}\n' \
    "$pick" "$(now)" "$journey" "$repo" "$kind" "$session" "$label" >> "$LEDGER"
  echo "$pick"
}

cmd_release() {
  # release <name> --journey <j-id>   (ownership check: only the claiming
  # journey may release — a delayed/duplicate release from a PREVIOUS holder
  # must never free the name's CURRENT holder)
  # release <name> --force            (operator repair only; logged as forced)
  local name="${1:-}"; shift || true
  local journey="" force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --journey) journey="$(sane "$2")"; shift 2 ;;
      --force)   force=1; shift ;;
      *) echo "callsign: unknown release arg $1" >&2; exit 2 ;;
    esac
  done
  [ -n "$name" ] || { echo "callsign: release needs a name" >&2; exit 2; }
  [ -n "$journey" ] || [ "$force" = 1 ] || { echo "callsign: release needs --journey <j-id> (or --force for operator repair)" >&2; exit 2; }
  _lock
  local ev; ev="$(_last_events | awk -F'\t' -v n="$name" '$1==n {print $2}')"
  [ "$ev" = "claim" ] || { echo "callsign: '$name' is not active" >&2; exit 4; }
  if [ "$force" != 1 ]; then
    local cur; cur="$(_field "$(_active_claim_line "$name")" journey)"
    [ "$cur" = "$journey" ] || { echo "callsign: '$name' is held by journey '$cur', not '$journey' — refusing" >&2; exit 5; }
  fi
  printf '{"event":"release","name":"%s","ts":"%s","journey":"%s"%s}\n' \
    "$name" "$(now)" "$journey" "$([ "$force" = 1 ] && printf ',"reason":"forced"')" >> "$LEDGER"
}

cmd_transfer() {
  # transfer <name> --from <old-j-id> --to <new-j-id>
  # One agent, one identity, successive journeys. A live session routinely outlives the
  # journey it was claimed for; release+claim would auto-pick a different name and rename
  # a live agent that people address by name.
  #
  # Safety: this appends a claim under --to WITHOUT an intervening release, so the
  # name is never free. No concurrent claim can pick it mid-transfer, and no second
  # identity can exist. Ownership is checked exactly as release checks it: only the
  # journey that currently holds the name may hand it on.
  local name="${1:-}"; shift || true
  local from="" to=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from="$(sane "$2")"; shift 2 ;;
      --to)   to="$(sane "$2")";   shift 2 ;;
      *) echo "callsign: unknown transfer arg $1" >&2; exit 2 ;;
    esac
  done
  [ -n "$name" ] || { echo "callsign: transfer needs a name" >&2; exit 2; }
  [ -n "$from" ] && [ -n "$to" ] || { echo "callsign: transfer needs --from <j-id> --to <j-id>" >&2; exit 2; }
  [ "$from" != "$to" ] || { echo "callsign: transfer --from and --to are the same journey ('$from') — nothing to do" >&2; exit 2; }

  _lock
  # Must be ACTIVE. A released name is NOT transferable: resurrecting it would
  # bypass the LRU delay and could mint a duplicate identity — the same reason
  # claim refuses to auto-reclaim on pool exhaustion.
  local ev; ev="$(_last_events | awk -F'\t' -v n="$name" '$1==n {print $2}')"
  [ "$ev" = "claim" ] || { echo "callsign: '$name' is not active — a released name cannot be transferred (claim a fresh one)" >&2; exit 4; }

  local cl; cl="$(_active_claim_line "$name")"
  local cur; cur="$(_field "$cl" journey)"
  [ "$cur" = "$from" ] || { echo "callsign: '$name' is held by journey '$cur', not '$from' — refusing" >&2; exit 5; }

  # Carry the identity's context forward unchanged; only the journey moves.
  local repo kind session label
  repo="$(_field "$cl" repo)"; kind="$(_field "$cl" kind)"
  session="$(_field "$cl" session)"; label="$(_field "$cl" label)"

  printf '{"event":"claim","name":"%s","ts":"%s","journey":"%s","repo":"%s","kind":"%s","session":"%s","label":"%s","transferred_from":"%s"}\n' \
    "$name" "$(now)" "$to" "$repo" "$kind" "$session" "$label" "$from" >> "$LEDGER"
  echo "$name"
}

cmd_list() {
  # join active names back to their claim line for context
  local events; events="$(_last_events)"
  printf '%-8s %-12s %-18s %-9s %s\n' "NAME" "JOURNEY" "REPO" "KIND" "SINCE"
  local n
  while IFS=$'\t' read -r n ev _; do
    [ "$ev" = "claim" ] || continue
    grep -F "\"event\":\"claim\",\"name\":\"$n\"" "$LEDGER" | tail -1 | awk -F'"' '
      { for (i=1;i<NF;i++) { if ($i=="journey") j=$(i+2); if ($i=="repo") r=$(i+2)
                             if ($i=="kind") k=$(i+2);    if ($i=="ts") t=$(i+2) }
        printf "%-8s %-12s %-18s %-9s %s\n", "'"$n"'", j, r, k, t }'
  done <<< "$events"
}

cmd_title() {
  # title <state> <name> [--journey <j-id>] [label...]
  # With --journey: the state event is appended ONLY if it matches the active
  # claim (a released former holder's delayed `title done` must
  # never forge the CURRENT holder's terminal state). Without --journey nothing is
  # recorded; only the terminal title is set.
  local state="${1:-}" name="${2:-}"; shift 2 || true
  local caller_journey="" _args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --journey) caller_journey="$(sane "$2")"; shift 2 ;;
      *) _args+=("$1"); shift ;;
    esac
  done
  local label="${_args[*]:-}"
  # OSC payload hardening: any control byte (ESC/BEL/CR/…) in name or label could
  # terminate the sequence and inject terminal commands — strip them all.
  name="$(printf '%s' "$name" | tr -d '[:cntrl:]')"
  label="$(printf '%s' "$label" | tr -d '[:cntrl:]')"
  local icon
  case "$state" in
    run)  icon="🟢" ;;
    wait) icon="🟡" ;;
    done) icon="✅" ;;
    stuck) icon="🔴" ;;
    *) echo "callsign: title state must be run|wait|done|stuck" >&2; exit 2 ;;
  esac
  local text="$icon $name"; [ -n "$label" ] && text="$text · $label"
  # "done" means the executor finished — sealing (and "window closable") is announced
  # only by the PL after the close audit passes.
  [ "$state" = "done" ] && text="$text · audit-pending"
  # State goes to DISK too (separate file — the claim/release ledger's
  # last-event-per-name logic must never see these lines). Terminal titles are
  # for human eyes only; roster.sh and the PL read states from here. A title alone
  # cannot be queried by another agent.
  # Persisted state REQUIRES an authenticated journey:
  # any unauthenticated path lets a former holder forge the current holder's
  # completion. No journey = the
  # terminal title still renders (visual courtesy) but NOTHING is recorded.
  if [ -z "$caller_journey" ]; then
    echo "callsign: state NOT persisted — pass --journey <j-id> (unauthenticated titles are visual-only)" >&2
  else
    _lock
    local claim_line cur=""
    claim_line="$(_active_claim_line "$name")"
    [ -n "$claim_line" ] && cur="$(_field "$claim_line" journey)"
    if [ "$cur" != "$caller_journey" ]; then
      echo "callsign: state REFUSED — '$name' is held by journey '${cur:-<none>}', not '$caller_journey' (stale holder?)" >&2
      exit 5
    fi
    printf '{"event":"state","name":"%s","state":"%s","ts":"%s","journey":"%s","label":"%s"}\n' \
      "$(sane "$name")" "$state" "$(now)" "$caller_journey" "$(sane "$label")" >> "$STATE_DIR/agent-states.jsonl"
  fi
  # OSC 0 sets the tab title. Prefer the controlling terminal so it works even
  # when stdout is piped to a log; headless (no tty) = silent no-op by design.
  if (exec 3>/dev/tty) 2>/dev/null; then
    { printf '\033]0;%s\007' "$text" > /dev/tty; } 2>/dev/null || true
  elif [ -t 1 ]; then
    printf '\033]0;%s\007' "$text"
  fi
}

cmd_banner() {
  local name="${1:-}" journey="${2:-}" record="${3:-}"
  [ -n "$name" ] && [ -n "$journey" ] && [ -n "$record" ] || {
    echo "callsign: banner <name> <journey> <log-or-journal-path>" >&2; exit 2; }
  # banner authenticates with its journey: a stale ex-holder's banner is
  # REFUSED by the title validation (exit 5) instead of forging done-state —
  # and the refusal aborts the banner too
  cmd_title "done" "$name" --journey "$journey"
  printf '\n══════════════════════════════════════════════════════════\n'
  printf '  ✅ CASE CLOSED · awaiting close-audit — PL announces when sealed\n'
  printf '  callsign %s · journey %s\n' "$name" "$journey"
  printf '  record: %s\n' "$record"
  printf '══════════════════════════════════════════════════════════\n'
}

case "${1:-}" in
  claim)    shift; cmd_claim "$@" ;;
  release)  shift; cmd_release "$@" ;;
  transfer) shift; cmd_transfer "$@" ;;
  list)     shift; cmd_list "$@" ;;
  title)    shift; cmd_title "$@" ;;
  banner)   shift; cmd_banner "$@" ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
