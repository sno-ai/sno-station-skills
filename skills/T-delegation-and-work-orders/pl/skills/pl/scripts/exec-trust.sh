#!/usr/bin/env bash
# exec-trust.sh — answer Claude Code's first-run screens before an executor meets them.
#
# Claude Code stops in a directory it has never seen with a question ("Is this a project
# you created or one you trust?"). An unattended executor waits there forever: it looks
# alive, holds its window, and never reads its inbox. There are three first-run screens:
#   1. the folder-trust question, which waits forever;
#   2. the bypass-permissions warning, whose default answer is Exit, so a blind Enter kills
#      the session;
#   3. the onboarding theme picker, which appears once the first two are answered.
#
# WHAT THIS CHANGES ON YOUR MACHINE (read before running). It edits the Claude Code config
# file `<config-dir>/.claude.json` (default: ~/.claude.json, or $CLAUDE_CONFIG_DIR):
#   - sets bypassPermissionsModeAccepted=true and hasCompletedOnboarding=true GLOBALLY, for
#     every project and every future Claude Code session of that user, not only this
#     checkout;
#   - sets hasTrustDialogAccepted and hasCompletedProjectOnboarding for the given repo;
#   - records the installed claude version as lastOnboardingVersion.
# Keys are only added or overwritten, never removed. Executors launched by spawn-exec.sh
# with --runtime claude run `claude --dangerously-skip-permissions` (and codex runs with
# --dangerously-bypass-approvals-and-sandbox): no permission prompts and no sandbox. Use
# --check to see whether a directory is already pre-answered without changing anything.
# Pass --config-dir to use a separate config directory instead of your own.
#
# Run this against the existing checkout selected for the executor; this command
# never creates that checkout:
#
#     bash "${PL_SKILL_DIR}/scripts/exec-trust.sh" --repo "$checkout"
#     bash "${PL_SKILL_DIR}/scripts/spawn-exec.sh" --repo "$checkout" --runtime claude ...
#
# usage: exec-trust.sh --repo <absolute path> [--config-dir <dir>]
#        exec-trust.sh --check --repo <absolute path> [--config-dir <dir>]
# exit: 0 every first-run screen is pre-answered · 1 (--check only) not · 64 usage · 65 refused
set -Eeuo pipefail

repo='' config_dir="${CLAUDE_CONFIG_DIR:-$HOME}" mode=set
while (($# > 0)); do
    case "$1" in
        --repo)       repo="${2:-}"; shift 2 ;;
        --config-dir) config_dir="${2:-}"; shift 2 ;;
        --check)      mode=check; shift ;;
        -h|--help)    sed -n '2,/^# exit:/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'exec-trust: unsupported option: %s\n' "$1" >&2; exit 64 ;;
    esac
done
[[ -n "$repo" ]] || { printf 'exec-trust: --repo <absolute path to the checkout> is required\n' >&2; exit 64; }
# The config keys the runtime on the absolute path it is started in; a relative path
# would write a key nothing matches.
[[ "$repo" == /* ]] || { printf 'exec-trust: --repo must be absolute, got: %s\n' "$repo" >&2; exit 64; }
[[ -d "$repo" ]] || { printf 'exec-trust: no such directory: %s\n' "$repo" >&2; exit 65; }
command -v jq >/dev/null 2>&1 || { printf 'exec-trust: jq is required\n' >&2; exit 69; }

config="$config_dir/.claude.json"

if [[ "$mode" == check ]]; then
    [[ -f "$config" ]] || { printf 'exec-trust: no config at %s — every first-run screen would appear\n' "$config" >&2; exit 1; }
    jq -e --arg p "$repo" \
        '(.bypassPermissionsModeAccepted == true) and (.hasCompletedOnboarding == true)
         and (.projects[$p].hasTrustDialogAccepted == true)' \
        "$config" >/dev/null 2>&1 || {
        printf 'exec-trust: %s is not pre-answered for %s\n' "$config" "$repo" >&2; exit 1; }
    printf 'exec-trust: every first-run screen is pre-answered for %s\n' "$repo"
    exit 0
fi

mkdir -p -- "$config_dir"
lock="$config_dir/.claude.json.exec-trust.lock"
exec 9>>"$lock" || { printf 'exec-trust: cannot take the config lock at %s\n' "$lock" >&2; exit 65; }
flock 9 || { printf 'exec-trust: cannot lock %s\n' "$lock" >&2; exit 65; }

# The runtime writes this file too, so this is a read-modify-write under a lock that only
# adds keys, written to a temporary file and renamed, so concurrent changes are not lost.
current='{}'
if [[ -f "$config" ]]; then
    current="$(cat -- "$config")"
    jq -e . <<<"$current" >/dev/null 2>&1 || {
        printf 'exec-trust: %s is not valid JSON; refusing to touch it\n' "$config" >&2
        exec 9>&-; exit 65; }
fi

# The onboarding version is read from the binary that will run; a stale value makes the
# runtime re-run onboarding (the theme picker returns).
onboarding_version=''
if command -v claude >/dev/null 2>&1; then
    onboarding_version="$(claude --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || true)"
fi

updated="$(jq --arg p "$repo" --arg ver "$onboarding_version" '
    .bypassPermissionsModeAccepted = true
    | .hasCompletedOnboarding = true
    | (if $ver == "" then . else .lastOnboardingVersion = $ver end)
    | .projects = ((.projects // {}) | .[$p] = ((.[$p] // {})
        | .hasTrustDialogAccepted = true
        | .hasCompletedProjectOnboarding = true))
' <<<"$current")" || { printf 'exec-trust: failed to compose the updated config\n' >&2; exec 9>&-; exit 65; }

tmp="$config.exec-trust.$$"
printf '%s\n' "$updated" > "$tmp" && mv -f -- "$tmp" "$config" || {
    rm -f -- "$tmp"; printf 'exec-trust: failed to write %s\n' "$config" >&2; exec 9>&-; exit 65; }
exec 9>&-

printf 'exec-trust: %s is pre-answered for %s — no trust question, no bypass warning, no theme picker\n' "$config" "$repo"
