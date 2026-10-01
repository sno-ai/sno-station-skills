#!/usr/bin/env bash
# Open one owner-supervised PL lane. Prints exactly the appended TSV row.
# Exit 64: invalid input or active lane; 65: unavailable or conflicting state.
set -Eeuo pipefail
lane_resolve="$(dirname -- "$(readlink -f -- "$0")")/lane-resolve.sh"

die() { local code="$1"; shift; printf 'lane-open: %s\n' "$*" >&2; exit "$code"; }

repo=''
lane=all
runtime=claude
while (($# > 0)); do
  case "$1" in
    --repo|--lane|--runtime)
      if (($# < 2)) || [[ -z "$2" || "$2" == --* ]]; then
        die 64 "$1 requires a value; nothing written. See --help."
      fi
      case "$1" in
        --repo) repo="$2" ;;
        --lane) lane="$2" ;;
        --runtime) runtime="$2" ;;
      esac
      shift 2 ;;
    -h|--help)
      printf '%s\n' 'usage: lane-open.sh --repo <path-or-name> [--lane <lane>] [--runtime claude|codex]' \
        'Defaults: lane=all, runtime=claude. An active lane refuses a repeat with exit 64.'
      exit 0 ;;
    *) die 64 "unknown argument: $1; nothing written. See --help." ;;
  esac
done
[[ -n "$repo" ]] || die 64 '--repo is required; nothing written. See --help.'
repo="$(basename -- "$repo")"
[[ "$repo" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] ||
  die 64 "repository is not routable: $repo; use lowercase letters, digits and hyphens."
[[ "$lane" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] ||
  die 64 "lane is not routable: $lane; use lowercase letters, digits and hyphens."
case "$runtime" in claude|codex) ;; *) die 64 "invalid runtime: $runtime; use claude or codex." ;; esac

registry="${PL_REGISTRY:-$HOME/.local/state/pl-registry.tsv}"
mkdir -p -- "$(dirname -- "$registry")" || die 65 "cannot create the registry directory for $registry."
# A first lane on a fresh machine starts the registry; noclobber keeps a racing writer's file.
[[ -e "$registry" ]] || (set -C; printf '%s\n' $'home_repo\tlane\treach_address\theartbeat_name\truntime\towning_cos\tstate\tnote' >"$registry") 2>/dev/null || true
registry="$(readlink -f -- "$registry")" || die 65 'cannot resolve registry; check PL_REGISTRY.'
[[ -f "$registry" ]] || die 65 "registry is missing: $registry; check PL_REGISTRY."
for dependency in flock timeout; do
  command -v "$dependency" >/dev/null || die 65 "missing $dependency; install it before opening a lane."
done

# Resolve the registry symlink before locking, as lane-resolve does for cos-claim.
exec 9>"$registry.lock"
flock -w 10 9 || die 65 "registry lock timed out: $registry; retry after the writer finishes."
header=$'home_repo\tlane\treach_address\theartbeat_name\truntime\towning_cos\tstate\tnote'
[[ "$(awk 'NF && $0 !~ /^[[:space:]]*#/ {print; exit}' "$registry")" == "$header" ]] ||
  die 65 "registry header is malformed: $registry; repair it before retrying."
awk -F '\t' 'NF && $0 !~ /^[[:space:]]*#/ && NF != 8 {exit 1}' "$registry" ||
  die 65 "registry row is malformed: $registry; repair it before retrying."
if awk -F '\t' -v repo="$repo" -v lane="$lane" '
  $1 == repo && $2 == lane && toupper($7) != "RETIRED" {found=1}
  END {exit !found}' "$registry"; then
  die 64 "active lane already exists: $repo/$lane; nothing written. Resolve it with: bash \"$lane_resolve\"."
fi

suffix="$repo"
heartbeat="$repo"
if [[ "$lane" != all ]]; then
  suffix+="-$lane"
  heartbeat+="-$lane"
fi
address="pl.$suffix@$(hostname)"
staging=''
trap '[[ -z "$staging" ]] || rm -f -- "$staging"' EXIT
staging="$(mktemp "${registry}.open.XXXXXXXXXX")"
cat -- "$registry" >"$staging"
chmod --reference="$registry" "$staging"
printf -v row '%s\t%s\t%s\t%s\t%s\tunclaimed\tRUN\tLane opened by a standalone PL.' \
  "$repo" "$lane" "$address" "$heartbeat" "$runtime"
printf '%s\n' "$row" >>"$staging"

# Reach validates the address and preserves an already initialized seat.
timeout 30 sno reach init --as "$address" --name "$suffix" >/dev/null ||
  die 65 "Reach init failed for $address; registry unchanged. Inspect the seat before retrying."
mv -f -- "$staging" "$registry" ||
  die 65 "Reach seat is ready for $address but registry write failed; inspect $registry before retrying."
staging=''
printf '%s\n' "$row"
