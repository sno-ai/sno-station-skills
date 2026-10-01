#!/usr/bin/env bash
# The only sanctioned writer for the owning_cos column.
#
# One writer keeps the owning_cos column unambiguous for each PL lane.
#
#   cos-claim.sh whoami [<letter>]     who am I, which address, how many lanes
#   cos-claim.sh show                  every lane, its PL, its COS, reachable?
#   cos-claim.sh reap <repo>           reclaim every repo lease stale >24h
#   cos-claim.sh open <repo> [lane]    reap the repo, then open a lane
#   cos-claim.sh claim <repo> [--seat <letter>] [--handover "<reason>"]
#   cos-claim.sh release <repo> [<seat-letter>]
#   cos-claim.sh register [<letter>]    repair identity and register this window
#   cos-claim.sh resolve <repo> [--lane <lane>]  print the PL address of that repo's active lane
#
# Pairing is never announced to anyone. A PL resolves its own address and its
# final COS authority from this one table at boot.
#
# Refusals are fail-closed and name the exact next command.

set -Eeuo pipefail

for tool in flock jq sno awk; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'cos-claim: %s is required but not installed (this script needs Linux, flock, jq, sno, awk)\n' "$tool" >&2
        exit 69
    }
done

readonly REGISTRY="${SNO_PL_REGISTRY:-$HOME/.local/state/pl-registry.tsv}"
readonly REACH_ROOT="${SNO_REACH_ROOT:-$HOME/.local/state/sno-reach}"
readonly HOST="${COS_CLAIM_HOST:-$(hostname)}"
readonly PL_LEASE_SECONDS=86400

die() {
    printf 'cos-claim: %s\n' "$*" >&2
    exit "${DIE_CODE:-65}"
}

lock_registry() {
    exec 9>"$REGISTRY.lock" || die "cannot open registry lock: $REGISTRY.lock"
    flock -n 9 || die "registry is busy: $REGISTRY. Try again after the current writer finishes."
}

now_epoch() {
    local now="${SNO_COS_CLAIM_NOW:-}"
    if [[ -n "$now" ]]; then
        [[ "$now" =~ ^[0-9]+$ ]] || {
            DIE_CODE=64 die 'SNO_COS_CLAIM_NOW must be a non-negative integer';
        }
        printf '%s\n' "$((10#$now))"
        return
    fi
    date -u +%s || die 'could not read the current time'
}

card_updated_epoch() {
    local card="$1" updated
    [[ -f "$card" && ! -L "$card" ]] || return 1
    updated="$(jq -er '.updated | strings | select(length > 0)' "$card" 2>/dev/null)" ||
        return 1
    date -u -d "$updated" +%s 2>/dev/null
}

seat_last_seen_epoch() {
    local root="$1" address="$2"
    local seat="$root/$address" record="$root/$address/reachable.json"
    local seen=0 value

    if [[ -e "$seat/.lease-opened-at" || -L "$seat/.lease-opened-at" ]]; then
        [[ -f "$seat/.lease-opened-at" && ! -L "$seat/.lease-opened-at" ]] || return 2
        value="$(cat "$seat/.lease-opened-at")"
        [[ "$value" =~ ^[0-9]+$ ]] || return 2
        seen="$value"
    fi

    if [[ -e "$record" || -L "$record" ]]; then
        [[ -f "$record" && ! -L "$record" ]] || return 2
        value="$(jq -er '.refreshed_at | numbers | select(floor == . and . >= 0)' \
            "$record" 2>/dev/null)" || return 2
        ((value <= seen)) || seen="$value"
    fi
    if value="$(card_updated_epoch "$seat/seat.json")"; then
        ((value <= seen)) || seen="$value"
    fi
    ((seen > 0)) || return 1
    printf '%s\n' "$seen"
}

seat_lease_expired() {
    local root="$1" address="$2" now="$3" seen status
    seen="$(seat_last_seen_epoch "$root" "$address")" || {
        status=$?
        ((status == 1)) && return 1
        return 2
    }
    ((now - seen > PL_LEASE_SECONDS))
}

collect_expired_lanes() {
    local repo="$1" root="$2" now="$3" result_name="$4"
    local row_repo row_lane row_address row_heartbeat row_runtime row_owner row_state row_note extra
    local key status
    local -n result="$result_name"

    while IFS=$'\t' read -r row_repo row_lane row_address row_heartbeat row_runtime row_owner row_state row_note extra; do
        [[ "$row_repo" == "$repo" && "$row_lane" != - && "${row_state^^}" != RETIRED ]] ||
            continue
        if seat_lease_expired "$root" "$row_address" "$now"; then
            key="$row_repo"$'\t'"$row_lane"
            # shellcheck disable=SC2034 # result is the caller's associative array via nameref.
            result["$key"]="$row_address"
        else
            status=$?
            ((status == 1)) ||
                die "PL reachability record is invalid: $root/$row_address/reachable.json. Nothing was changed."
        fi
    done <"$REGISTRY"
}

reclaim_expired_lanes() {
    local root="$1" now="$2" now_iso="$3" expired_name="$4"
    local key address staging expired_serialized=''
    local -n expired="$expired_name"

    ((${#expired[@]} > 0)) || return 0

    # Unregister the stale Reach channel; keep the seat and its cards.
    for key in "${!expired[@]}"; do
        address="${expired[$key]}"
        if [[ -e "$root/$address/reachable.json" ||
              -L "$root/$address/reachable.json" ]]; then
            SNO_REACH_ROOT="$root" sno reach unregister --as "$address" >/dev/null ||
                die "could not reclaim expired PL reachability for $address. Nothing was written to the registry."
        fi
        expired_serialized+="$key"$'\n'
    done

    staging="$(mktemp "${REGISTRY}.reap.XXXXXXXXXX")"
    awk -F '\t' -v OFS='\t' -v expired_rows="$expired_serialized" \
        -v expired_at="$now_iso" '
        BEGIN {
            count = split(expired_rows, rows, "\n")
            for (i = 1; i <= count; i++) if (rows[i] != "") expired[rows[i]] = 1
        }
        ($1 "\t" $2) in expired && toupper($7) != "RETIRED" {
            $7 = "RETIRED"
            $8 = $8 " LEASE: reclaimed after more than 24 hours without renewal at " expired_at "."
        }
        { print }
    ' "$REGISTRY" >"$staging"
    chmod --reference="$REGISTRY" "$staging"
    mv -f -- "$staging" "$REGISTRY"
}

registered_pane_of() {
    local address="$1"
    [[ -f "$REACH_ROOT/$address/reachable.json" ]] || return 0
    jq -r '.identity.value // empty' "$REACH_ROOT/$address/reachable.json"
}

current_window() {
    WINDOW_CHANNEL='' WINDOW_IDENTITY='' WINDOW_HANDLE=''
    if [[ -n "${TMUX_PANE:-}" ]]; then
        WINDOW_CHANNEL=tmux WINDOW_IDENTITY="$TMUX_PANE" WINDOW_HANDLE="$TMUX_PANE"
    elif [[ -n "${ORCA_TAB_ID:-}" ]]; then
        WINDOW_CHANNEL=orca WINDOW_IDENTITY="$ORCA_TAB_ID"
        WINDOW_HANDLE="${ORCA_TERMINAL_HANDLE:-}"
    fi
}

cos_is_live() {
    local address="$1"
    sno reach seats --json | jq -e --arg address "$address" \
        'select(.address == $address and .state == "live")' >/dev/null
}

registered_pane_is_current() {
    local address="$1" pane
    current_window
    pane="$(registered_pane_of "$address")"
    [[ -n "$pane" && "$pane" == "$WINDOW_IDENTITY" ]] || return 1
    cos_is_live "$address"
}

register_reach() {
    local address="$1"
    sno reach init --as "$address" --name "${address%@*}" >/dev/null || return 1
    sno reach register --as "$address" --channel "$WINDOW_CHANNEL" \
        --handle "$WINDOW_HANDLE" >/dev/null
}

ensure_current_registration() {
    local address="$1" holder
    current_window
    if [[ -z "$WINDOW_IDENTITY" ]]; then
        printf 'cos-claim: warning: %s is not reachable; run inside a tmux pane (TMUX_PANE is unset).\n' "$address" >&2
        return
    fi
    if registered_pane_is_current "$address"; then return; fi
    holder="$(registered_pane_of "$address")"
    if [[ -n "$holder" ]] && cos_is_live "$address"; then
        die "$address is held by another live window. Use a lettered COS seat: $0 register b. Nothing was written."
    fi
    if [[ -z "$WINDOW_HANDLE" ]]; then
        printf 'cos-claim: warning: %s is not reachable; ORCA_TERMINAL_HANDLE is missing.\n' "$address" >&2
    elif register_reach "$address"; then
        printf 'cos-claim: registered %s to this window before changing ownership.\n' "$address" >&2
    else
        printf 'cos-claim: warning: Reach registration failed for %s; this seat is not reachable.\n' "$address" >&2
    fi
}

# Default seat is repo-derived, matching how a PL derives its own. A repo may
# occasionally carry a second COS; that one takes an explicit lettered seat
# rather than silently sharing the first one's Reach seat.
seat_address() {
    local repo="$1"
    local letter="${2:-}"
    if [[ -n "$letter" ]]; then
        printf 'cos.%s-%s@%s\n' "$repo" "$letter" "$HOST"
    else
        printf 'cos.%s@%s\n' "$repo" "$HOST"
    fi
}

owner_token() {
    printf 'cos/%s\n' "$1"
}

registry_header() {
    printf '%s\n' $'home_repo\tlane\treach_address\theartbeat_name\truntime\towning_cos\tstate\tnote'
}

require_row() {
    /usr/bin/awk -F '\t' -v r="$1" \
        '$1 == r && $2 != "-" && toupper($7) != "RETIRED" { found = 1 }
         END { exit !found }' \
        "$REGISTRY" ||
        die "no active PL row for repository: $1 — add the lane before changing ownership"
}

current_owners() {
    /usr/bin/awk -F '\t' -v r="$1" '
        $1 == r && $2 != "-" && toupper($7) != "RETIRED" && !seen[$6]++ { print $6 }
    ' "$REGISTRY"
}

owned_count() {
    /usr/bin/awk -F '\t' -v o="$1" '
        NR > 1 && $2 != "-" && toupper($7) != "RETIRED" && $6 == o { n++ }
        END { print n + 0 }
    ' \
        "$REGISTRY"
}

write_owner() {
    local repo="$1"
    local owner="$2"
    local note_suffix="$3"
    local staging

    staging="$(mktemp "${REGISTRY}.XXXXXX")"
    /usr/bin/awk -F '\t' -v OFS='\t' -v r="$repo" -v o="$owner" -v s="$note_suffix" '
        $1 == r && $2 != "-" && toupper($7) != "RETIRED" {
            $6 = o
            if (s != "") $8 = $8 " " s
        }
        { print }
    ' "$REGISTRY" >"$staging"
    /bin/chmod --reference="$REGISTRY" "$staging"
    mv -f -- "$staging" "$REGISTRY"
}

cmd_whoami() {
    local repo
    local letter="${1:-}"
    local address
    local registered_elsewhere=0

    [[ -z "$letter" || "$letter" =~ ^[a-z]$ ]] ||
        { DIE_CODE=64 die 'whoami seat must be one lowercase letter'; }

    repo="$(basename -- "$PWD")"
    address="$(seat_address "$repo" "$letter")"

    # A warning that fires for your own window is a warning nobody reads. The
    # seat is only "taken" when it points at a terminal that is not this one.
    local holder
    holder="$(registered_pane_of "$address")"
    current_window
    if [[ -z "$letter" && -n "$holder" && "$holder" != "$WINDOW_IDENTITY" ]] &&
       cos_is_live "$address"; then
        registered_elsewhere=1
    fi

    local token
    token="$(owner_token "$repo")"
    [[ -n "$letter" ]] && token="$token-$letter"
    printf 'repository   %s\n' "$repo"
    printf 'cos address  %s\n' "$address"
    printf 'owner token  %s\n' "$token"
    printf 'lanes owned  %s\n' "$(owned_count "$token")"
    if ((registered_elsewhere == 1)); then
        printf '\nNOTE: %s already holds a registered window.\n' "$address" >&2
        printf 'If that is not this window, you are the second COS in this repository\n' >&2
        printf 'and must take a lettered seat instead of sharing that one:\n' >&2
        printf '  %s whoami b\n' "$0" >&2
        printf 'Sharing it would silently take the first COS Reach seat.\n' >&2
    fi
}

cmd_register() {
    local letter="${1:-${COS_SEAT:-}}"
    local repo address token runtime holder now staging first_record selected_state=''
    local row_repo row_lane row_address row_heartbeat row_runtime row_owner row_state row_note extra
    local relevant_count=0 compatible_count=0

    (($# <= 1)) || { DIE_CODE=64 die 'register accepts at most one seat letter'; }
    [[ -z "$letter" || "$letter" =~ ^[a-z]$ ]] ||
        { DIE_CODE=64 die 'COS seat must be one lowercase letter'; }
    repo="$(basename -- "$PWD")"
    [[ "$repo" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] ||
        die "working-directory repository is not routable: $repo"
    address="$(seat_address "$repo" "$letter")"
    token="$(owner_token "$repo")"
    [[ -z "$letter" ]] || token="$token-$letter"
    current_window
    [[ -n "$WINDOW_IDENTITY" ]] || die "register must run inside a tmux pane (TMUX_PANE is unset) for $address; an Orca terminal also works if Orca is installed (ORCA_TAB_ID with ORCA_TERMINAL_HANDLE)"
    [[ -n "$WINDOW_HANDLE" ]] || die "register needs ORCA_TERMINAL_HANDLE for $address"
    holder="$(registered_pane_of "$address")"
    if [[ -n "$holder" ]] && ! registered_pane_is_current "$address" &&
       cos_is_live "$address"; then
        die "$address is already held by a live window. Use a lettered COS seat: $0 register b"
    fi
    runtime="${COS_RUNTIME:-unknown}"
    register_reach "$address" ||
        die "could not register COS seat: $address"
    printf 'cos-claim: registered address=%s owner=%s\n' "$address" "$token"

    if ! mkdir -p -- "$(dirname -- "$REGISTRY")" ||
       [[ -L "$REGISTRY" || ( -e "$REGISTRY" && ! -f "$REGISTRY" ) ]]; then
        printf 'cos-claim: warning: Reach registered %s; registry unavailable or unsafe: %s. Registry unchanged.\n' \
            "$address" "$REGISTRY" >&2
        return 0
    fi
    if ! { exec 9>"$REGISTRY.lock" && flock -n 9; }; then
        printf 'cos-claim: warning: Reach registered %s; registry lock unavailable: %s.lock. Registry unchanged.\n' \
            "$address" "$REGISTRY" >&2
        return 0
    fi

    if [[ ! -e "$REGISTRY" ]]; then
        registry_header >"$REGISTRY"
        chmod 600 "$REGISTRY"
    else
        first_record="$(awk 'NF && $0 !~ /^[[:space:]]*#/ { print; exit }' "$REGISTRY")"
        if [[ "$first_record" != "$(registry_header)" ]]; then
            staging="$(mktemp "${REGISTRY}.header.XXXXXXXXXX")"
            registry_header >"$staging"
            cat "$REGISTRY" >>"$staging"
            chmod --reference="$REGISTRY" "$staging"
            mv -f -- "$staging" "$REGISTRY"
        fi
    fi

    while IFS=$'\t' read -r row_repo row_lane row_address row_heartbeat row_runtime row_owner row_state row_note extra; do
        [[ -n "$row_repo" && "$row_repo" != \#* && "$row_repo" != home_repo ]] || continue
        if [[ "$row_repo" == "$repo" && "$row_lane" == - ||
              "$row_address" == "$address" ]]; then
            ((relevant_count += 1))
            if [[ -z "$extra" && "$row_repo" == "$repo" && "$row_lane" == - &&
                  "$row_address" == "$address" && "$row_owner" == "$token" &&
                  -n "$row_runtime" && -n "$row_note" ]]; then
                ((compatible_count += 1))
                selected_state="$row_state"
            fi
        fi
    done <"$REGISTRY"

    if ((relevant_count == 0)); then
        now="$(date -u +%Y-%m-%dT%H:%MZ)"
        staging="$(mktemp "${REGISTRY}.register.XXXXXXXXXX")"
        cat "$REGISTRY" >"$staging"
        chmod --reference="$REGISTRY" "$staging"
        printf '%s\t-\t%s\t%s-cos%s\t%s\t%s\tRUN\tCOS identity registered %s.\n' \
            "$repo" "$address" "$repo" "${letter:+-$letter}" "$runtime" \
            "$token" "$now" >>"$staging"
        mv -f -- "$staging" "$REGISTRY"
    elif ((relevant_count == 1 && compatible_count == 1)); then
        if [[ "$selected_state" != RUN ]]; then
            staging="$(mktemp "${REGISTRY}.register.XXXXXXXXXX")"
            awk -F '\t' -v OFS='\t' -v repo="$repo" -v address="$address" \
                -v owner="$token" '
                $1 == repo && $2 == "-" && $3 == address && $6 == owner { $7 = "RUN" }
                { print }
            ' "$REGISTRY" >"$staging"
            chmod --reference="$REGISTRY" "$staging"
            mv -f -- "$staging" "$REGISTRY"
        fi
    else
        printf 'cos-claim: warning: registry identity conflicts for %s (%s); COS is reachable and can repair it\n' \
            "$repo" "$address" >&2
    fi
}

cmd_show() {
    local owner_address
    printf '%-18s %-24s %-24s %s\n' REPOSITORY PL OWNING_COS REACHABLE
    /usr/bin/awk -F '\t' '
        $1 ~ /^#/ || $1 == "home_repo" || $2 == "-" || toupper($7) == "RETIRED" || NF < 6 { next }
        { print $1 "\t" $3 "\t" $6 }
    ' "$REGISTRY" |
        while IFS=$'\t' read -r repo pl owner; do
            local_state=unclaimed
            if [[ "$owner" != unclaimed && -n "$owner" ]]; then
                owner_address="$(seat_address "${owner#cos/}")"
                if cos_is_live "$owner_address"; then
                    local_state=yes
                else
                    local_state='NO — owner unreachable'
                fi
            fi
            printf '%-18s %-24s %-24s %s\n' "$repo" "$pl" "$owner" "$local_state"
        done
}

cmd_claim() {
    local repo="$1"
    shift
    local letter=''
    local handover=''

    while (($# > 0)); do
        case "$1" in
            --seat) letter="${2:-}"; shift 2 ;;
            --handover) handover="${2:-}"; shift 2 ;;
            *) DIE_CODE=64 die "unknown argument: $1" ;;
        esac
    done

    require_row "$repo"
    local home_repo mine mine_address owner prior
    local -a existing=()
    home_repo="$(basename -- "$PWD")"
    mine="$(owner_token "$home_repo")"
    [[ -n "$letter" ]] && mine="$mine-$letter"
    mine_address="$(seat_address "$home_repo" "$letter")"
    ensure_current_registration "$mine_address"
    mapfile -t existing < <(current_owners "$repo")

    if ((${#existing[@]} == 1)) && [[ "${existing[0]}" == "$mine" ]]; then
        printf 'cos-claim: already yours: %s -> %s\n' "$repo" "$mine"
        return 0
    fi

    if ((${#existing[@]} > 1)) && [[ -z "$handover" ]]; then
        DIE_CODE=65 die "$repo has active lanes with different owners: ${existing[*]}.
  A repository-wide claim needs an explicit handover reason.
  Run: $0 claim $repo --handover \"<reason>\"
  Nothing was written."
    fi
    for owner in "${existing[@]}"; do
        [[ -n "$owner" && "$owner" != unclaimed && "$owner" != "$mine" ]] || continue
        if cos_is_live "$(seat_address "${owner#cos/}")" && [[ -z "$handover" ]]; then
            DIE_CODE=65 die "$repo is owned by $owner, which is reachable right now.
  Taking it silently is the collision this file exists to prevent.
  Ask that COS to release it:      $0 release $repo
  Or record why you are overriding: $0 claim $repo --handover \"<reason>\"
  Nothing was written."
        fi
    done

    local owned additional after
    owned="$(owned_count "$mine")"
    additional="$(awk -F '\t' -v repo="$repo" -v mine="$mine" '
        $1 == repo && $2 != "-" && toupper($7) != "RETIRED" && $6 != mine {n++}
        END {print n+0}
    ' "$REGISTRY")"
    after=$((owned + additional))
    ((after <= 3)) ||
        DIE_CODE=65 die "$mine would own $after lanes after this claim; the cap is 3. Nothing was written."
    if ((after == 3 && additional > 0)) && [[ -z "$handover" ]]; then
        DIE_CODE=65 die "$mine would own 3 lanes; going to 3 requires a written reason.
  $0 claim $repo --handover \"<why a third lane>\"
  Nothing was written."
    fi

    prior="$(IFS=,; printf '%s' "${existing[*]:-unclaimed}")"
    local suffix="OWNERSHIP: claimed by $mine $(date -u +%Y-%m-%dT%H:%MZ)."
    [[ -n "$handover" ]] && suffix="$suffix Override from $prior: $handover"
    write_owner "$repo" "$mine" "$suffix"
    printf 'cos-claim: %s -> %s (was %s)\n' "$repo" "$mine" "$prior"
}

cmd_reap() {
    local repo="$1" reach_root now now_iso
    local -A expired_lanes=()

    [[ "$repo" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] ||
        { DIE_CODE=64 die "repository name is not a routable token: $repo"; }
    [[ -f "$REGISTRY" && ! -L "$REGISTRY" ]] ||
        die "registry is unavailable or unsafe: $REGISTRY. Nothing was written."
    [[ "$(awk 'NF && $0 !~ /^[[:space:]]*#/ { print; exit }' "$REGISTRY")" == "$(registry_header)" ]] ||
        die "registry header is malformed: $REGISTRY. Nothing was written."

    reach_root="$REACH_ROOT"
    now="$(now_epoch)"
    now_iso="$(date -u -d "@$now" +%Y-%m-%dT%H:%M:%SZ)" ||
        die 'could not render the current time. Nothing was written.'
    collect_expired_lanes "$repo" "$reach_root" "$now" expired_lanes
    reclaim_expired_lanes "$reach_root" "$now" "$now_iso" expired_lanes
    printf 'cos-claim: reclaimed %d expired PL lane(s) for %s\n' \
        "${#expired_lanes[@]}" "$repo"
}

# Opening a lane is one command: it adds the registry row and creates the Reach
# seats together, so a lane is never half-built and the two sources cannot disagree.
cmd_open() {
    local repo="$1"
    local lane="${2:-all}"
    local pl_address cos_address reach_root mine lease_now lease_now_iso
    local registry_tmp cos_count=0 pl_count=0
    local cos_exact=0 pl_exact=0
    local owned_after_reap=0 row_active key
    local -A expired_lanes=()

    # Validate before the first write, so a name the address grammar rejects cannot
    # leave a corrupt row behind.
    [[ "$repo" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] ||
        DIE_CODE=64 die "repository name is not a routable token: $repo
  Allowed: lowercase letters, digits and hyphens. Nothing was written."
    [[ "$lane" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] ||
        DIE_CODE=64 die "lane name is not a routable token: $lane
  Allowed: lowercase letters, digits and hyphens. Nothing was written."

    # One repository, one address -- unless it is deliberately split. Two agents on
    # one address race for every card: whoever touches it first owns it. A second
    # window therefore needs a second lane and a second address, not a different name.
    if [[ "$lane" == all ]]; then
        pl_address="pl.$repo@$HOST"
    else
        pl_address="pl.$repo-$lane@$HOST"
    fi
    cos_address="$(seat_address "$repo")"
    mine="$(owner_token "$repo")"
    reach_root="$REACH_ROOT"
    lease_now="$(now_epoch)"
    lease_now_iso="$(date -u -d "@$lease_now" +%Y-%m-%dT%H:%M:%SZ)" ||
        die 'could not render the current time. Nothing was written.'

    # The complete validation pass precedes every registry or seat mutation.
    if [[ -e "$REGISTRY" || -L "$REGISTRY" ]]; then
        [[ -f "$REGISTRY" && ! -L "$REGISTRY" ]] ||
            die "registry is unavailable or unsafe: $REGISTRY. Nothing was written."
        [[ "$(awk 'NF && $0 !~ /^[[:space:]]*#/ { print; exit }' "$REGISTRY")" == "$(registry_header)" ]] ||
            die "registry header is malformed: $REGISTRY. Nothing was written."
        collect_expired_lanes "$repo" "$reach_root" "$lease_now" expired_lanes
        while IFS=$'\t' read -r row_repo row_lane row_address row_heartbeat row_runtime row_owner row_state row_note extra; do
            [[ -n "$row_repo" && "$row_repo" != \#* && "$row_repo" != home_repo ]] || continue
            key="$row_repo"$'\t'"$row_lane"
            row_active=1
            [[ "${row_state^^}" != RETIRED ]] || row_active=0
            if ((row_active == 1)) && [[ -n "${expired_lanes[$key]+present}" ]]; then
                row_active=0
            fi
            if ((row_active == 1)) && [[ "$row_lane" != - && "$row_owner" == "$mine" ]]; then
                ((owned_after_reap += 1))
            fi
            if ((row_active == 1)) &&
               [[ "$row_repo" == "$repo" && "$row_lane" == - || "$row_address" == "$cos_address" ]]; then
                ((cos_count += 1))
                [[ -z "$extra" && "$row_repo" == "$repo" && "$row_lane" == - &&
                   "$row_address" == "$cos_address" && "$row_heartbeat" == "$repo-cos" &&
                   "$row_owner" == "$mine" &&
                   -n "$row_note" ]] && cos_exact=1
            fi
            if ((row_active == 1)) &&
               [[ "$row_repo" == "$repo" && "$row_lane" == "$lane" || "$row_address" == "$pl_address" ]]; then
                ((pl_count += 1))
                [[ -z "$extra" && "$row_repo" == "$repo" && "$row_lane" == "$lane" &&
                   "$row_address" == "$pl_address" && "$row_heartbeat" == "$repo" &&
                   "$row_owner" == "$mine" &&
                   -n "$row_note" ]] && pl_exact=1
            fi
        done <"$REGISTRY"
    fi
    ((cos_count <= 1 && (cos_count == 0 || cos_exact == 1))) ||
        die "COS identity or derived address conflicts for $repo ($cos_address). Nothing was written."
    ((pl_count <= 1 && (pl_count == 0 || pl_exact == 1))) ||
        die "PL lane or derived address conflicts for $repo/$lane ($pl_address). Nothing was written."
    if ((pl_count == 0 && owned_after_reap >= 3)); then
        die "$mine still owns $owned_after_reap reachable PL lanes after the 24-hour lease check; the cap is 3. Nothing was written."
    fi

    reclaim_expired_lanes "$reach_root" "$lease_now" "$lease_now_iso" expired_lanes

    if ((pl_count == 0)) && [[ -f "$reach_root/$pl_address/seat.json" ]]; then
        local lease_tmp
        lease_tmp="$(mktemp "$reach_root/$pl_address/.lease-opened-at.XXXXXXXXXX")"
        printf '%s\n' "$lease_now" >"$lease_tmp"
        mv -f -- "$lease_tmp" "$reach_root/$pl_address/.lease-opened-at"
    fi

    registry_tmp="$(mktemp "${REGISTRY}.open.XXXXXXXXXX")"
    if [[ -f "$REGISTRY" ]]; then
        cat "$REGISTRY" >"$registry_tmp"
        chmod --reference="$REGISTRY" "$registry_tmp"
    else
        registry_header >"$registry_tmp"
        chmod 600 "$registry_tmp"
    fi
    ((cos_count == 1)) || printf '%s\t-\t%s\t%s-cos\t%s\t%s\tRUN\tCOS identity created %s.\n' \
        "$repo" "$cos_address" "$repo" "${COS_RUNTIME:-unknown}" "$mine" "$lease_now_iso" >>"$registry_tmp"
    ((pl_count == 1)) || printf '%s\t%s\t%s\t%s\t%s\t%s\tRUN\tLane opened %s by %s.\n' \
        "$repo" "$lane" "$pl_address" "$repo" "${COS_RUNTIME:-unknown}" "$mine" "$lease_now_iso" "$mine" >>"$registry_tmp"
    if ((cos_count == 0 || pl_count == 0 || ${#expired_lanes[@]} > 0)); then
        mv -f -- "$registry_tmp" "$REGISTRY"
        printf 'cos-claim: registry identity chain ready %s/%s\n' "$repo" "$lane"
    else
        rm -f -- "$registry_tmp"
        printf 'cos-claim: registry identity chain already complete %s/%s\n' "$repo" "$lane"
    fi

    sno reach init --as "$cos_address" --name "${cos_address%@*}" >/dev/null ||
        die "could not create the Reach seat for $cos_address"
    printf 'cos-claim: Reach seat ready %s\n' "$cos_address"

    sno reach init --as "$pl_address" --name "${pl_address%@*}" >/dev/null ||
        die "could not create the Reach seat for $pl_address"
    printf 'cos-claim: Reach seat ready %s\n' "$pl_address"

    printf '\nLane ready. Nobody needs to be told the pairing:\n'
    printf '  the PL resolves both its address and its COS from this one table.\n'
    printf '  Open a window in %s and type /pl.\n' "$repo"
    cmd_show
}

cmd_release() {
    local repo="$1"
    local letter="${2:-}"
    local home_repo mine mine_address owner
    local -a existing=()

    (($# <= 2)) || { DIE_CODE=64 die 'release accepts a repository and optional seat letter'; }
    [[ -z "$letter" || "$letter" =~ ^[a-z]$ ]] ||
        { DIE_CODE=64 die 'release seat must be one lowercase letter'; }
    require_row "$repo"
    home_repo="$(basename -- "$PWD")"
    mine="$(owner_token "$home_repo")"
    [[ -n "$letter" ]] && mine="$mine-$letter"
    mine_address="$(seat_address "$home_repo" "$letter")"
    ensure_current_registration "$mine_address"
    mapfile -t existing < <(current_owners "$repo")
    for owner in "${existing[@]}"; do
        [[ "$owner" == "$mine" ]] ||
            DIE_CODE=65 die "$repo has an active lane owned by $owner, not $mine. Nothing was written."
    done
    write_owner "$repo" unclaimed \
        "OWNERSHIP: released by $mine $(date -u +%Y-%m-%dT%H:%MZ)."
    printf 'cos-claim: %s released (was %s)\n' "$repo" "$mine"
}

cmd_resolve() {
    local repo="$1"
    shift
    local lane=''
    local row
    local -a matches=()
    local -a lanes=()

    while (($# > 0)); do
        case "$1" in
            --lane)
                (($# >= 2)) || { DIE_CODE=64 die '--lane requires a value'; }
                [[ -z "$lane" ]] || { DIE_CODE=64 die '--lane appears more than once'; }
                lane="$2"
                shift 2
                ;;
            *) DIE_CODE=64 die "unknown argument: $1" ;;
        esac
    done

    mapfile -t matches < <(
        /usr/bin/awk -F '\t' -v r="$repo" -v l="$lane" '
            $1 == r && $2 != "-" && (l == "" || $2 == l) && toupper($7) != "RETIRED" {
                print $2 "\t" $3
            }
        ' "$REGISTRY"
    )

    if ((${#matches[@]} == 0)); then
        DIE_CODE=65 die "no active registry row for repository=$repo lane=${lane:-<unspecified>}"
    fi
    if ((${#matches[@]} > 1)); then
        for row in "${matches[@]}"; do
            lanes+=("${row%%$'\t'*}")
        done
        DIE_CODE=65 die "several active registry rows match repository=$repo lane=${lane:-<unspecified>}; found lanes: ${lanes[*]}"
    fi
    printf '%s\n' "${matches[0]#*$'\t'}"
}

verb="${1:-}"
shift || true
case "$verb" in
    resolve)  [[ -f "$REGISTRY" ]] || DIE_CODE=66 die "registry is unavailable: $REGISTRY"
              [[ -n "${1:-}" ]] || { DIE_CODE=64 die 'resolve needs a repository name'; }
              cmd_resolve "$@" ;;
    whoami)  [[ -f "$REGISTRY" ]] || DIE_CODE=66 die "registry is unavailable: $REGISTRY"
              cmd_whoami "${1:-}" ;;
    show)    [[ -f "$REGISTRY" ]] || DIE_CODE=66 die "registry is unavailable: $REGISTRY"
              cmd_show ;;
    reap)    [[ -f "$REGISTRY" ]] || DIE_CODE=66 die "registry is unavailable: $REGISTRY"
             [[ -n "${1:-}" ]] || { DIE_CODE=64 die 'reap needs a repository name'; }
             lock_registry; cmd_reap "$1" ;;
    open)    [[ -n "${1:-}" ]] || { DIE_CODE=64 die "open needs a repository name"; }
             mkdir -p -- "$(dirname -- "$REGISTRY")"
             lock_registry; cmd_open "$1" "${2:-all}" ;;
    claim)   [[ -f "$REGISTRY" ]] || DIE_CODE=66 die "registry is unavailable: $REGISTRY"
             [[ -n "${1:-}" ]] || { DIE_CODE=64 die 'claim needs a repository name'; }
             lock_registry; cmd_claim "$@" ;;
    release) [[ -f "$REGISTRY" ]] || DIE_CODE=66 die "registry is unavailable: $REGISTRY"
             [[ -n "${1:-}" ]] || { DIE_CODE=64 die 'release needs a repository name'; }
             lock_registry; cmd_release "$@" ;;
    register) cmd_register "$@" ;;
    *) DIE_CODE=64 die 'usage: cos-claim.sh <whoami|show|reap <repo>|open <repo>|claim <repo>|release <repo> [seat]|register [seat]|resolve <repo> [--lane <lane>]>' ;;
esac
