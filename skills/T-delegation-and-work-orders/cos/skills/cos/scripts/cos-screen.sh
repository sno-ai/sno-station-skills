#!/usr/bin/env bash
# cos-screen.sh — print what a PL's window shows RIGHT NOW, so a status answer to the
# owner comes from the live screen and not from inbox and disk inference.
#
#   cos-screen.sh <seat-address | repo> [--lines N]      (default 40 lines)
#
#   seat-address  e.g. pl.myrepo@host1 — the window that seat registered.
#   repo          a registry home_repo — every live-listed PL seat of that repo;
#                 if none of them can be read, every Orca terminal or tmux pane
#                 whose directory basename equals the repo name.
#
# tmux windows are read with `tmux capture-pane -p` on the default tmux server. Orca
# terminals, if Orca is installed, are read with `orca terminal read --screen` (the
# rendered frame; the default stream mode returns repainted lines as stacked fragments).
# Needs tmux, jq and the sno command.
#
# EXIT: 0 at least one screen printed · 2 usage · 3 no window could be read (a line
# starting NO WINDOW says why — that is a finding, not a failure to retry).
set -Eeuo pipefail

REGISTRY="${SNO_PL_REGISTRY:-$HOME/.local/state/pl-registry.tsv}"
lines=40
target=''
printed=0

die() { printf 'cos-screen: %s\n' "$*" >&2; exit 2; }
for tool in tmux jq sno; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required but not installed"
done

while (($#)); do
    case "$1" in
        --lines) [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--lines needs a number"; lines="$2"; shift 2 ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        -*) die "unknown flag: $1" ;;
        *) [[ -z "$target" ]] || die "one target only"; target="$1"; shift ;;
    esac
done
[[ -n "$target" ]] || die "usage: cos-screen.sh <seat-address | repo> [--lines N]"

# capture-pane and Orca pad the frame with blank rows; keep the last N non-blank rows.
last_lines() {
    awk -v n="$lines" 'NF { last = NR } { l[NR] = $0 }
        END { for (i = (last > n ? last - n + 1 : 1); i <= last; i++) print l[i] }'
}

show() { # header, channel, handle-or-pane
    local header="$1" channel="$2" handle="$3" json
    printf '=== %s [%s]\n' "$header" "$channel"
    case "$channel" in
        orca)
            json="$(orca terminal read --terminal "$handle" --screen --json 2>/dev/null)" || true
            if jq -e '.ok' >/dev/null 2>&1 <<<"$json"; then
                jq -r '.result.terminal.tail[]' <<<"$json" | last_lines
                printed=1
            else
                printf 'NO WINDOW: orca terminal %s not readable (%s)\n' "$handle" \
                    "$(jq -r '.error.code // "no reply"' <<<"$json" 2>/dev/null || echo "no reply")"
            fi ;;
        tmux)
            if json="$(tmux capture-pane -p -t "$handle" 2>/dev/null)"; then
                last_lines <<<"$json"
                printed=1
            else
                printf 'NO WINDOW: tmux target %s not found on the default server\n' "$handle"
            fi ;;
        *) printf 'NO WINDOW: channel %s has no screen to read\n' "$channel" ;;
    esac
}

by_seat() {
    local address="$1" seat channel handle state
    seat="$(sno reach seats --json 2>/dev/null | jq -c --arg a "$address" 'select(.address == $a)' | head -n1)"
    if [[ -z "$seat" ]]; then
        printf '=== %s\nNO WINDOW: no registered seat with this address\n' "$address"
        return
    fi
    channel="$(jq -r '.channel' <<<"$seat")"
    handle="$(jq -r '.handle' <<<"$seat")"
    state="$(jq -r '.state' <<<"$seat")"
    # tmux seat handles read tmux-<server-hash>:<session>; the session is the target.
    [[ "$channel" != tmux ]] || handle="=${handle##*:}:"
    show "$address (seat $state)" "$channel" "$handle"
}

by_directory() {
    local repo="$1" handle title pane path
    printf 'no seat window readable for %s; looking for windows whose directory is named %s\n' "$repo" "$repo"
    if command -v orca >/dev/null 2>&1; then
        while IFS=$'\t' read -r handle title; do
            show "$title" orca "$handle"
        done < <(orca terminal list --json 2>/dev/null |
            jq -r --arg r "$repo" '.result.terminals[]? | select((.worktreePath | split("/") | last) == $r) | [.handle, .title] | @tsv')
    fi
    if command -v tmux >/dev/null 2>&1; then
        while IFS=$'\t' read -r pane path title; do
            if [[ "${path##*/}" == "$repo" ]]; then show "$title" tmux "$pane"; fi
        done < <(tmux list-panes -a -F '#{pane_id}	#{pane_current_path}	#{session_name}: #{pane_title}' 2>/dev/null || true)
    fi
}

if [[ "$target" == *@* ]]; then
    by_seat "$target"
else
    while IFS= read -r address; do
        by_seat "$address"
    done < <(awk -F'\t' -v r="$target" '$1 == r && $3 ~ /^pl\./ && $7 != "RETIRED" { print $3 }' "$REGISTRY" 2>/dev/null || true)
    [[ "$printed" == 1 ]] || by_directory "$target"
fi

if [[ "$printed" == 0 ]]; then
    printf 'NO WINDOW: nothing readable for %s — treat it as having no window\n' "$target"
    exit 3
fi
