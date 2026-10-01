#!/usr/bin/env bash
# Contract under test: a Claude executor started in a directory nobody has ever opened
# reaches a working prompt with NO dialog — and the proof is the runtime itself doing it,
# not the shape of a config file.
#
#   1-2. both keys land, for the exact absolute path given
#   3.   an existing config keeps everything it already had
#   4.   running it twice changes nothing (dispatch is repeated constantly)
#   5.   the check verb reports an unprepared directory as unprepared
#   6.   and a prepared one as prepared
#   7.   a relative path is REFUSED — the runtime keys on the absolute path, so a relative
#        one writes a key nothing matches
#   8.   the real runtime, in a real directory it has never seen, reaches a prompt and
#        executes a command with no dialog in the way
#
# Row 8 runs only when SNO_PL_E2E_LIVE=1 and working credentials exist; otherwise it is
# reported as skipped and says so rather than passing quietly. When it runs, it copies the
# user's Claude login into the temporary config directory and starts a real claude session
# (a small amount of agent usage).
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${TARGET:-$SCRIPT_DIR/exec-trust.sh}"

root="$(mktemp -d)"
session="walk-trust-$$"
cleanup() {
    # The runtime can still be writing under $root as it dies, so the first rm can
    # lose that race. Under set -e a failed rm aborts the trap and becomes the
    # script's exit status, reporting a green run as red. Retry once, and never let
    # cleanup change the result the assertions produced.
    local rc=$?
    tmux kill-session -t "$session" 2>/dev/null || true
    rm -rf -- "$root" 2>/dev/null || { sleep 1; rm -rf -- "$root" 2>/dev/null || true; }
    return "$rc"
}
trap cleanup EXIT

cfg="$root/config"
mkdir -p "$cfg"
work="$root/never-opened"
mkdir -p "$work"

n=0; fail=0
check() { n=$((n+1)); if [[ "$2" == skip ]]; then printf 'ok %d - %s # SKIP\n' "$n" "$1"
    elif [[ "$2" == pass ]]; then printf 'ok %d - %s\n' "$n" "$1"
    else printf 'not ok %d - %s\n' "$n" "$1"; [[ -z "${3:-}" ]] || printf '#   %s\n' "$3"; fail=$((fail+1)); fi; }

printf 'TAP version 13\n'

# --- an existing config with unrelated content, to prove nothing is lost ----------------
printf '{"numStartups":41,"userID":"someone","projects":{"/other/place":{"hasTrustDialogAccepted":true}}}\n' \
    > "$cfg/.claude.json"

bash "$TARGET" --repo "$work" --config-dir "$cfg" >/dev/null 2>&1
check 'the bypass-mode dialog is pre-answered at the top level' \
    "$(jq -e '.bypassPermissionsModeAccepted == true' "$cfg/.claude.json" >/dev/null 2>&1 && echo pass || echo fail)" \
    "$(jq -c 'del(.projects)' "$cfg/.claude.json")"
check 'the trust dialog is pre-answered for the exact directory given' \
    "$(jq -e --arg p "$work" '.projects[$p].hasTrustDialogAccepted == true' "$cfg/.claude.json" >/dev/null 2>&1 && echo pass || echo fail)" \
    "$(jq -c '.projects' "$cfg/.claude.json")"
check 'everything the config already held is still there' \
    "$(jq -e '.numStartups == 41 and .userID == "someone" and .projects["/other/place"].hasTrustDialogAccepted == true' \
        "$cfg/.claude.json" >/dev/null 2>&1 && echo pass || echo fail)" \
    "$(jq -c . "$cfg/.claude.json" | head -c 200)"

before="$(sha256sum "$cfg/.claude.json" | cut -d' ' -f1)"
bash "$TARGET" --repo "$work" --config-dir "$cfg" >/dev/null 2>&1
check 'running it again changes nothing' \
    "$([[ "$before" == "$(sha256sum "$cfg/.claude.json" | cut -d' ' -f1)" ]] && echo pass || echo fail)"

# --- the check verb -----------------------------------------------------------------
set +e
bash "$TARGET" --check --repo "$root/some-other-dir-entirely" --config-dir "$cfg" >/dev/null 2>&1
unprepared_rc=$?
bash "$TARGET" --check --repo "$work" --config-dir "$cfg" >/dev/null 2>&1
prepared_rc=$?
bash "$TARGET" --repo "relative/path" --config-dir "$cfg" >/dev/null 2>&1
relative_rc=$?
set -e
check 'an unprepared directory is reported as unprepared' \
    "$([[ "$unprepared_rc" -ne 0 ]] && echo pass || echo fail)" "rc=$unprepared_rc"
check 'a prepared directory is reported as prepared' \
    "$([[ "$prepared_rc" -eq 0 ]] && echo pass || echo fail)" "rc=$prepared_rc"
check 'a relative path is REFUSED rather than silently writing a key nothing matches' \
    "$([[ "$relative_rc" -ne 0 ]] && echo pass || echo fail)" "rc=$relative_rc"

# --- row 8: the runtime itself, in a directory it has never seen ----------------------
creds="$HOME/.claude/.credentials.json"
if [[ "${SNO_PL_E2E_LIVE:-}" != 1 ]]; then
    check 'the real runtime reaches a prompt with no dialog (SKIPPED: set SNO_PL_E2E_LIVE=1 to spend agent usage)' skip
elif ! command -v claude >/dev/null 2>&1; then
    check 'the real runtime reaches a prompt with no dialog (SKIPPED: no claude binary)' skip
elif [[ ! -f "$creds" ]]; then
    check 'the real runtime reaches a prompt with no dialog (SKIPPED: no credentials)' skip
else
    cp -- "$creds" "$cfg/.credentials.json"
    marker="TRUST-ROUTE-WORKS-$$"
    tmux new-session -d -s "$session" -x 200 -y 50 \
        "cd $(printf '%q' "$work") && CLAUDE_CONFIG_DIR=$(printf '%q' "$cfg") claude --dangerously-skip-permissions"
    for _ in $(seq 1 40); do
        sleep 2
        screen="$(tmux capture-pane -pt "$session" -S -60 2>/dev/null || true)"
        grep -qE 'trust|Bypass Permissions' <<<"$screen" && break
        grep -qE '│|╰|>' <<<"$screen" && break
    done
    screen="$(tmux capture-pane -pt "$session" -S -60 2>/dev/null || true)"
    dialog=no
    grep -qiE 'is this a project you created|no, exit|i accept' <<<"$screen" && dialog=yes
    if [[ "$dialog" == no ]]; then
        tmux send-keys -t "$session" "run the command: echo $marker"
        sleep 1
        tmux send-keys -t "$session" Enter
        executed=fail
        for _ in $(seq 1 45); do
            sleep 2
            out="$(tmux capture-pane -pt "$session" -S -200 2>/dev/null || true)"
            if grep -F "$marker" <<<"$out" | grep -qv 'run the command'; then executed=pass; break; fi
        done
    else
        executed=fail
    fi
    tmux kill-session -t "$session" 2>/dev/null || true
    check 'the real runtime, in a directory it has never seen, reaches a prompt with NO dialog and executes' \
        "$executed" "dialog-present=$dialog; last screen:
$(sed 's/^/#     /' <<<"$screen" | tail -12)"
fi

printf '1..%d\n' "$n"
((fail == 0)) || { printf '# %d of %d failed\n' "$fail" "$n" >&2; exit 1; }
