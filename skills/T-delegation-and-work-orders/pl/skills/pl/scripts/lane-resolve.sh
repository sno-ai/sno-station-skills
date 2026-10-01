#!/usr/bin/env bash
# lane-resolve.sh — resolve ONE registry row, and take every field from that same row.
#
# The registry is keyed on (repository, lane), and a repository may carry several lanes.
# A lookup that matches on repository alone and takes the first row would hand lane B
# lane A's Reach address and lane A's owning COS, with no error. So this script resolves the
# row once, fails closed when it is not exactly one, and reads every field from that row.
# A lookup that cannot say which lane it means is refused rather than guessed.
#
# usage: lane-resolve.sh [--repo <path-or-name>] [--lane <lane>] [--field <name>]
#   --repo    path or bare name; defaults to the current directory
#   --lane    required only when the repository carries more than one; defaults to $PL_LANE
#   --field   lane | addr | cos_token | cos_addr | state | all   (default: all)
# prints  lane<TAB>pl_addr<TAB>owning_cos<TAB>cos_addr<TAB>state
# exit 0 = resolved · 64 = no row, ambiguous lane, or a malformed address · 65 = no registry
#
# For a lane that no COS has claimed, cos_addr is $SNO_OWNER_ADDR: the Reach address of the
# owner's own seat (the person or agent who supervises unclaimed lanes). Export it before
# running the PL, for example: export SNO_OWNER_ADDR=owner.me@host1
# Needs the cos skill's cos-claim.sh (override with $PL_COS_CLAIM).
set -Eeuo pipefail

skill_dir="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)"
cos_dir="$skill_dir/../cos"
if [[ -d "$skill_dir/../../../cos/skills/cos" ]]; then
  cos_dir="$skill_dir/../../../cos/skills/cos"
fi

REGISTRY="${PL_REGISTRY:-$HOME/.local/state/pl-registry.tsv}"
COS_CLAIM="${PL_COS_CLAIM:-$cos_dir/scripts/cos-claim.sh}"

repo=""
lane="${PL_LANE:-}"
field="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  repo="${2:-}"; shift 2 ;;
    --lane)  lane="${2:-}"; shift 2 ;;
    --field) field="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '/^# usage:/,/^# Needs the cos skill/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'lane-resolve: unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done

case "$field" in
  lane|addr|cos_token|cos_addr|state|all) ;;
  *) printf 'lane-resolve: --field takes lane|addr|cos_token|cos_addr|state|all, got: %s\n' \
       "$field" >&2; exit 64 ;;
esac

[[ -f "$REGISTRY" ]] || {
  printf 'lane-resolve: no registry at %s\n' "$REGISTRY" >&2; exit 65; }

[[ -n "$repo" ]] || repo="$PWD"
repo="$(basename -- "$repo")"

[[ -x "$COS_CLAIM" ]] || {
  printf 'lane-resolve: cos-claim.sh not found or not executable: %s (install the cos skill or set PL_COS_CLAIM)\n' "$COS_CLAIM" >&2; exit 65; }
registry_target="$(readlink -f -- "$REGISTRY")" || {
  printf 'lane-resolve: cannot resolve registry target: %s\n' "$REGISTRY" >&2; exit 65; }
if ! SNO_PL_REGISTRY="$registry_target" "$COS_CLAIM" reap "$repo" >/dev/null; then
  printf 'lane-resolve: could not reclaim expired lanes for %s\n' "$repo" >&2
  exit 65
fi

# Retired rows are not candidates: a closed lane must never resolve as the live one.
rows="$(awk -F '\t' -v r="$repo" -v l="$lane" '
  NR > 1 && $1 == r && $2 != "-" && toupper($7) != "RETIRED" &&
      (l == "" || $2 == l) {
    print $2 "\t" $3 "\t" $6 "\t" $7
  }' "$REGISTRY")"

count="$(printf '%s' "$rows" | grep -c . || true)"

if [[ "$count" -eq 0 ]]; then
  if [[ -n "$lane" ]]; then
    printf 'lane-resolve: no active row for repository %s lane %s\n' "$repo" "$lane" >&2
  else
    printf 'lane-resolve: no active row for repository %s\n' "$repo" >&2
  fi
  exit 64
fi

if [[ "$count" -gt 1 ]]; then
  printf 'lane-resolve: %s carries %s active lanes; name one with --lane or $PL_LANE:\n' \
    "$repo" "$count" >&2
  printf '%s\n' "$rows" | cut -f1 | sed 's/^/  /' >&2
  exit 64
fi

IFS=$'\t' read -r r_lane r_addr r_cos r_state <<< "$rows"

# The address shape is checked here rather than at each call site: a placeholder in the
# registry would otherwise look like a real address until something tries to send.
case "$r_addr" in
  pl.*@*) ;;
  *) printf 'lane-resolve: %s lane %s has no strict PL address (%s)\n' \
       "$repo" "$r_lane" "${r_addr:-<empty>}" >&2; exit 64 ;;
esac

# An unclaimed lane is not an error — it means the owner supervises it until a COS claims it.
case "$r_cos" in
  cos/*) cos_addr="cos.${r_cos#cos/}@$(hostname)" ;;
  *)
    # Only the fields that print the supervisor address need the owner's address.
    [[ "$field" != cos_addr && "$field" != all ]] || [[ -n "${SNO_OWNER_ADDR:-}" ]] || {
      printf 'lane-resolve: %s lane %s is not claimed by a COS, so cards go to the owner'"'"'s own Reach seat, but SNO_OWNER_ADDR is not set. Export it (for example: export SNO_OWNER_ADDR=owner.me@host1) and retry\n' \
        "$repo" "$r_lane" >&2; exit 64; }
    cos_addr="${SNO_OWNER_ADDR:-}" ;;
esac

case "$field" in
  lane)      printf '%s\n' "$r_lane" ;;
  addr)      printf '%s\n' "$r_addr" ;;
  cos_token) printf '%s\n' "$r_cos" ;;
  cos_addr)  printf '%s\n' "$cos_addr" ;;
  state)     printf '%s\n' "$r_state" ;;
  all)       printf '%s\t%s\t%s\t%s\t%s\n' "$r_lane" "$r_addr" "$r_cos" "$cos_addr" "$r_state" ;;
esac
