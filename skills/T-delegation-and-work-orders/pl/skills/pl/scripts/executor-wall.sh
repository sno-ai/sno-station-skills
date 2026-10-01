#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    printf '%s\n' \
        'Usage: executor-wall.sh --spawn-id ID --term-after SECONDS --kill-after SECONDS --events PATH' \
        '       executor-wall.sh --spawn-id ID --cleanup-now'
}

spawn_id=''
term_after=''
kill_after=''
events=''
cleanup_now=0
while (($#)); do
    case "$1" in
        --spawn-id) spawn_id="${2:-}"; shift 2 ;;
        --term-after) term_after="${2:-}"; shift 2 ;;
        --kill-after) kill_after="${2:-}"; shift 2 ;;
        --events) events="${2:-}"; shift 2 ;;
        --cleanup-now) cleanup_now=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'executor-wall: unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

[[ "$spawn_id" =~ ^[A-Za-z0-9._-]+$ ]] || {
    printf 'executor-wall: --spawn-id must be one safe token\n' >&2
    exit 2
}
command -v jq >/dev/null
command -v flock >/dev/null
command -v systemctl >/dev/null

events_lock=''
if ((cleanup_now == 0)); then
    [[ "$term_after" =~ ^[0-9]+$ && "$kill_after" =~ ^[0-9]+$ ]] || {
        printf 'executor-wall: wall times must be whole seconds\n' >&2
        exit 2
    }
    ((term_after > 0 && kill_after > term_after)) || {
        printf 'executor-wall: require 0 < --term-after < --kill-after\n' >&2
        exit 2
    }
    [[ -n "$events" && ! -L "$events" ]] || {
        printf 'executor-wall: --events must be a non-symlink path\n' >&2
        exit 2
    }
    mkdir -p -- "$(dirname -- "$events")"
    touch -- "$events"
    events_lock="$events.lock"
fi
uid="$(id -u)"
user_prefix="/user.slice/user-$uid.slice/user@$uid.service/"
declare -a discovered_units=() discovered_groups=() unsafe_pids=()
declare -a signalled_units=() signalled_groups=() signal_failures=()
started_at=$SECONDS
term_deadline=0
kill_deadline=0
if ((cleanup_now == 0)); then
    term_deadline=$((started_at + term_after))
    kill_deadline=$((started_at + kill_after))
fi

append_event() {
    local event="$1" detail="${2:-}" scopes_json lock_fd
    scopes_json="$(printf '%s\n' "${signalled_groups[@]:-}" | sed '/^$/d' | sort -u | jq -Rsc 'split("\n") | map(select(length > 0))')"
    exec {lock_fd}>>"$events_lock"
    flock -x "$lock_fd"
    jq -nc \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg sid "$spawn_id" \
        --arg event "$event" \
        --arg detail "$detail" \
        --argjson scopes "$scopes_json" \
        '{ts:$ts,spawn_id:$sid,event:$event,scopes:$scopes} +
         (if $detail == "" then {} else {detail:$detail} end)' >>"$events"
    flock -u "$lock_fd"
    exec {lock_fd}>&-
}

discover() {
    local proc_dir pid status_uid env_file cgroup unit shown_group
    local -a marked_env_files=()
    discovered_units=()
    discovered_groups=()
    unsafe_pids=()
    mapfile -t marked_env_files < <(
        grep -l -z -x -F -- "SNO_EXEC_SPAWN_ID=$spawn_id" /proc/[0-9]*/environ 2>/dev/null || true
    )
    for env_file in "${marked_env_files[@]:-}"; do
        [[ -n "$env_file" ]] || continue
        proc_dir="${env_file%/environ}"
        pid="${proc_dir##*/}"
        status_uid="$(awk '/^Uid:/ { print $2; exit }' "$proc_dir/status" 2>/dev/null || true)"
        [[ "$status_uid" == "$uid" ]] || continue
        cgroup="$(awk -F: '$1 == "0" { print $3; exit }' "$proc_dir/cgroup" 2>/dev/null || true)"
        unit="${cgroup##*/}"
        if [[ "$cgroup" != "$user_prefix"* || ! "$unit" =~ \.(scope|service)$ ]]; then
            unsafe_pids+=("$pid:$cgroup")
            continue
        fi
        shown_group="$(systemctl --user show "$unit" -p ControlGroup --value 2>/dev/null || true)"
        if [[ "$shown_group" != "$cgroup" ]]; then
            unsafe_pids+=("$pid:$cgroup")
            continue
        fi
        discovered_units+=("$unit")
        discovered_groups+=("$cgroup")
    done
    if ((${#discovered_units[@]})); then
        mapfile -t discovered_units < <(printf '%s\n' "${discovered_units[@]}" | sort -u)
        mapfile -t discovered_groups < <(printf '%s\n' "${discovered_groups[@]}" | sort -u)
    fi
}

remember_discovery() {
    signalled_units+=("${discovered_units[@]:-}")
    signalled_groups+=("${discovered_groups[@]:-}")
    if ((${#signalled_units[@]})); then
        mapfile -t signalled_units < <(printf '%s\n' "${signalled_units[@]}" | sed '/^$/d' | sort -u)
        mapfile -t signalled_groups < <(printf '%s\n' "${signalled_groups[@]}" | sed '/^$/d' | sort -u)
    fi
}

signal_discovered() {
    local signal="$1" unit
    for unit in "${discovered_units[@]:-}"; do
        [[ -n "$unit" ]] || continue
        if ! systemctl --user kill --kill-whom=all --signal="$signal" "$unit" 2>/dev/null; then
            if systemctl --user is-active --quiet "$unit"; then
                signal_failures+=("$signal:$unit")
            fi
        fi
    done
}

containers_empty() {
    local group procs
    discover
    ((${#unsafe_pids[@]} == 0 && ${#discovered_units[@]} == 0)) || return 1
    for group in "${signalled_groups[@]:-}"; do
        [[ -n "$group" ]] || continue
        if [[ -r "/sys/fs/cgroup$group/cgroup.procs" ]]; then
            procs="$(<"/sys/fs/cgroup$group/cgroup.procs")"
            [[ -z "$procs" ]] || return 1
        fi
    done
}

cleanup_marked_now() {
    discover
    remember_discovery
    if ((${#unsafe_pids[@]})); then
        printf 'executor-wall: marked process entered an unsafe cgroup during startup cleanup: %s\n' \
            "${unsafe_pids[*]}" >&2
        return 1
    fi
    signal_discovered KILL
    for _ in {1..50}; do
        containers_empty && break
        sleep 0.1
    done
    if ((${#signal_failures[@]} == 0)) && containers_empty; then
        return 0
    fi
    printf 'executor-wall: startup cleanup could not prove zero marked processes; signal-failures=%s\n' \
        "${signal_failures[*]:-none}" >&2
    return 1
}

if ((cleanup_now == 1)); then
    cleanup_marked_now
    exit $?
fi

sleep "$((term_deadline - SECONDS))"
discover
remember_discovery
append_event expiry-intent
if ((${#unsafe_pids[@]})); then
    signal_failures+=("unsafe:${unsafe_pids[*]}")
fi
signal_discovered TERM

remaining=$((kill_deadline - SECONDS))
((remaining <= 0)) || sleep "$remaining"
discover
remember_discovery
if ((${#unsafe_pids[@]})); then
    signal_failures+=("unsafe:${unsafe_pids[*]}")
fi
signal_discovered KILL

for _ in {1..20}; do
    containers_empty && break
    sleep 0.1
done

if ((${#unsafe_pids[@]} == 0 && ${#signal_failures[@]} == 0)) && containers_empty; then
    append_event kill-confirmed
    exit 0
fi

detail='termination could not be proven'
((${#unsafe_pids[@]} == 0)) || detail="$detail; unsafe=${unsafe_pids[*]}"
((${#signal_failures[@]} == 0)) || detail="$detail; signal-failures=${signal_failures[*]}"
append_event termination-failed "$detail"
exit 1
