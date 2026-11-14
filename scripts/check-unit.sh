#!/usr/bin/env bash
# check-unit.sh — check one skill unit of this repository the way a release does, and print its stamp.
#
# Reads skills/<category>/<unit>/ here and refuses unless the unit passes:
#
#   1. registry.yaml lists the unit with tier candidate or shipped, under the category it is filed in;
#   2. the payload carries no machine-bound path or host and no Chinese/Japanese/Korean characters;
#   3. its requirements declaration is valid (scripts/validate-requirements.py);
#   4. every scripts/selftest/run-selftest.sh it ships is green, run on a copy laid out the way an agent
#      installs it, beside every other unit.
#
# Usage:
#   scripts/check-unit.sh <unit>          run every check
#   scripts/check-unit.sh --json <unit>   stdout = one JSON result line whose .result is the PUBLISHED.json stamp
#   scripts/check-unit.sh --help
#
# It writes nothing in the repository. Exit: 0 passed · 1 refused or a step failed · 2 bad usage.
set -Eeuo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly SRC
readonly SELFTEST_TIMEOUT=300

# Category code -> directory under skills/. Fixed order J M S H T R; do not extend here.
cat_dir() {
  case "$1" in
    J) printf 'J-peer-review-and-audit' ;;
    M) printf 'M-build-and-rollout' ;;
    S) printf 'S-communication-and-handoff' ;;
    H) printf 'H-reporting-and-visibility' ;;
    T) printf 'T-delegation-and-work-orders' ;;
    R) printf 'R-recursive-self-improvement' ;;
    *) return 1 ;;
  esac
}

# Anything matching these must not be published. Each is a fixed string or ERE; the scan
# reports file:line so the fix is a direct edit, not a hunt.
readonly -a PERSONAL_PATTERNS=(
  # paths that only exist on the owner's machine
  '/home/[A-Za-z0-9_-]+'
  '[~]/code/'
  '/mnt/ramdis[k]'
  # where a harness happens to install skills — a skill must locate itself relative to its own file
  '[~]/\.(claude|codex|agents)/skills/'
  # hosts, tailnet
  '[a-z0-9]+-vm\b'
  '\b(10|100|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+\.[0-9]+\b'
  '(localhost|127\.0\.0\.1):[0-9]{2,5}'
  'sno\.ai'
  # this workstation's plumbing
  '[Dd]oppler'
  '[Cc]cproxy'
  # a model named in code: must come from the models file (role), absent file = harness default
  '\b(gpt-[0-9][a-z0-9.-]*|claude-[a-z]+-[0-9][a-z0-9.-]*|o[0-9]-[a-z]+)\b'
)

log()   { printf '%s\n' "check-unit: $*" >&2; }
die()   { log "$*"; exit 1; }
usage() { sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

TMPDIRS=()
cleanup() {
  local st=$? d
  for d in "${TMPDIRS[@]:-}"; do [[ -n "$d" && -e "$d" ]] && rm -rf -- "$d"; done
  exit "$st"
}
trap cleanup EXIT

# registry_row <unit> -> "cat tier split" (split may be empty). registry.yaml keeps one unit
# per line in the shape  name: {cat: X, tier: Y[, split: {...}]}.
registry_row() {
  local unit="$1" reg="$SRC/registry.yaml" line cat tier split
  [[ -f "$reg" ]] || die "registry: $reg not found"
  line="$(grep -E "^[[:space:]]+${unit}:[[:space:]]*\{" -- "$reg" || true)"
  [[ -n "$line" ]] || die "registry: unit '$unit' is not in $reg — add a row before publishing"
  cat="$(sed -nE 's/.*\{[^}]*cat:[[:space:]]*([A-Z]).*/\1/p' <<<"$line")"
  tier="$(sed -nE 's/.*[{,][[:space:]]*tier:[[:space:]]*([a-z]+).*/\1/p' <<<"$line")"
  split="$(sed -nE 's/.*split:[[:space:]]*\{([^}]*)\}.*/\1/p' <<<"$line" | tr -d ' ')"
  [[ -n "$cat" && -n "$tier" ]] || die "registry: malformed row for '$unit': $line"
  printf '%s %s %s\n' "$cat" "$tier" "$split"
}

# payload_parts <unit-dir> -> the top-level entries of a unit that are published, one per line.
payload_parts() {
  local base="$1" part found=1
  for part in skill skills overlay public-bin .roots; do
    if [[ -e "$base/$part" || -L "$base/$part" ]]; then printf '%s\n' "$part"; found=0; fi
  done
  return "$found"
}

# scan_personal <dir> -> prints file:line:match for every hit; returns 1 if any.
scan_personal() {
  local dir="$1" pat hits=0 out
  for pat in "${PERSONAL_PATTERNS[@]}"; do
    out="$(grep -rnoE -- "$pat" "$dir" 2>/dev/null | sed "s|^$dir/||" || true)"
    if [[ -n "$out" ]]; then printf '%s\n' "$out"; hits=1; fi
  done
  [[ "$hits" -eq 0 ]]
}

# Every unit directory in this repo: skills/<category>/<unit>/.
unit_dirs() {
  local d
  for d in "$SRC"/skills/*/*/; do printf '%s\n' "${d%/}"; done
}

# stage_skill <name> <origin> <from> <stage> — copy one skill flat into the stage, refusing a
# name that two units both provide, since the later copy would silently replace the earlier.
declare -A STAGED_FROM=()
stage_skill() {
  local name="$1" origin="$2" from="$3" stage="$4"
  if [[ -n "${STAGED_FROM[$name]:-}" ]]; then
    log "stage: duplicate skill '$name': ${STAGED_FROM[$name]} and $origin"; return 1
  fi
  STAGED_FROM[$name]="$origin"
  cp -a -- "$from" "$stage/$name"
}

# stage_deployed <copy-dir> <unit> <stage-dir> — lay the stripped copy out the way a harness
# root does (flat: <stage>/<skill-name>/SKILL.md) with every OTHER unit of this repo beside
# it, so a self-test that reads a sibling skill finds it as it would after install. Prints the
# staged names of the unit under test, one per line.
stage_deployed() {
  local copy="$1" unit="$2" stage="$3" u base d
  STAGED_FROM=()
  while IFS= read -r u; do
    base="${u##*/}"
    [[ "$base" == "$unit" ]] && u="$copy"
    if [[ -f "$u/skill/SKILL.md" ]]; then
      stage_skill "$base" "$base/skill" "$u/skill" "$stage" || return 1
      [[ "$base" == "$unit" ]] && printf '%s\n' "$base"
    fi
    for d in "$u"/skills/*/; do
      d="${d%/}"; [[ -f "$d/SKILL.md" ]] || continue
      stage_skill "${d##*/}" "$base/skills/${d##*/}" "$d" "$stage" || return 1
      [[ "$base" == "$unit" ]] && printf '%s\n' "${d##*/}"
    done
    # An overlay-only unit has no shared payload: its per-harness overlays ARE the skill.
    # Each is staged as <unit>@<harness> because they install under one name on different
    # harnesses and would collide.
    if [[ ! -f "$u/skill/SKILL.md" && ! -d "$u/skills" ]]; then
      for d in "$u"/overlay/*/; do
        d="${d%/}"; [[ -f "$d/SKILL.md" ]] || continue
        stage_skill "$base@${d##*/}" "$base/overlay/${d##*/}" "$d" "$stage" || return 1
        [[ "$base" == "$unit" ]] && printf '%s\n' "$base@${d##*/}"
      done
    fi
  done < <(unit_dirs)
  return 0
}

# run_selftests <copy-dir> <unit> <stage-dir> — every scripts/selftest/run-selftest.sh the unit
# ships, run on the staged copy under a time limit. Sets NTESTS to the number run. It is called
# directly, not inside $( ), so a refusal reaches the exit trap and the temp dirs are removed.
NTESTS=0
run_selftests() {
  local copy="$1" unit="$2" stage="$3" names name st
  NTESTS=0
  names="$(stage_deployed "$copy" "$unit" "$stage")" ||
    die "stage: '$unit' cannot be tested unambiguously; nothing published"
  while IFS= read -r name; do
    st="$stage/$name/scripts/selftest/run-selftest.sh"
    [[ -f "$st" ]] || continue
    NTESTS=$((NTESTS + 1))
    log "selftest $NTESTS: $name/scripts/selftest/run-selftest.sh"
    timeout "$SELFTEST_TIMEOUT" bash "$st" >&2 ||
      die "selftest FAILED: $name/scripts/selftest/run-selftest.sh — the copy does not prove its own gates; fix the unit, do not publish"
  done <<<"$names"
}

check_unit() {
  local unit="$1" json="$2"
  [[ "$unit" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "unit name '$unit' is not a valid unit id"
  local src="" d
  while IFS= read -r d; do
    if [[ "${d##*/}" == "$unit" ]]; then src="$d"; break; fi
  done < <(unit_dirs)
  [[ -d "$src" ]] || die "no skills/<category>/$unit under $SRC"

  local cat tier split cdir
  read -r cat tier split <<<"$(registry_row "$unit")"
  case "$tier" in
    candidate|shipped) ;;
    *) die "gate: '$unit' has tier '$tier' in registry.yaml — only candidate or shipped units publish" ;;
  esac
  cdir="$(cat_dir "$cat")" || die "gate: '$unit' has unknown category '$cat'"
  [[ "$src" == "$SRC/skills/$cdir/$unit" ]] ||
    die "gate: '$unit' is filed under ${src#"$SRC"/skills/} but registry.yaml says category $cat ($cdir)"

  local parts part notice
  parts="$(payload_parts "$src")" || die "'$unit' has none of skill/, skills/, overlay/, public-bin/ — nothing to publish"
  for notice in LICENSE NOTICE; do
    [[ -f "$SRC/$notice" ]] || die "gate: '$unit' requires root $notice before publishing"
  done

  local tmp; tmp="$(mktemp -d)"; TMPDIRS+=("$tmp")
  while IFS= read -r part; do cp -a -- "$src/$part" "$tmp/$part"; done <<<"$parts"
  # What stays private never crosses: deploy markers, sealed hashes, PRD and report material
  # that some units keep inside their tree, build leftovers.
  find "$tmp" -type d \( -name prd -o -name reports -o -name node_modules -o -name __pycache__ \) \
    -prune -exec rm -rf -- {} +
  find "$tmp" -type f \( -name '.managed-by-sno-skills' -o -name '*.sha256' -o \
    -name 'PROBE-RESULTS*' -o -name '*.pyc' -o -name '*.private.*' \) -delete

  local hits
  if ! hits="$(scan_personal "$tmp")"; then
    printf '%s\n' "$hits" | sed 's/^/  /' >&2
    die "gate: personal bindings in '$unit' (above, file:line:match) — remove them here, then publish again"
  fi
  # Published skills are English only: any CJK character (or fullwidth form) refuses the unit.
  if hits="$(LC_ALL=C.UTF-8 grep -rnaoP '[\x{2e80}-\x{9fff}\x{3000}-\x{303f}\x{ff00}-\x{ffef}]' "$tmp" 2>/dev/null | sed "s|^$tmp/||")" && [[ -n "$hits" ]]; then
    printf '%s\n' "$hits" | head -20 | sed 's/^/  /' >&2
    die "gate: non-English characters in '$unit' (above, file:line:match) — published skills are English only"
  fi

  local validation contract_sha payload_sha ntests stage
  validation="$(python3 "$SRC/scripts/validate-requirements.py" validate \
    "$SRC/scripts/requirements-contract.json" "$tmp" "$cat")" ||
    die "gate: declaration or self-test requirements refused '$unit'"
  contract_sha="$(jq -r '.contract_sha256' <<<"$validation")"
  payload_sha="$(jq -r '.payload_sha256' <<<"$validation")"
  log "requirements-contract: sha256=$contract_sha"
  stage="$(mktemp -d)"; TMPDIRS+=("$stage")
  run_selftests "$tmp" "$unit" "$stage"
  ntests="$NTESTS"
  [[ "$ntests" -gt 0 ]] || die "gate: '$unit' has no scripts/selftest/run-selftest.sh"

  local commit clean split_json='{}' stamp
  # published_at is the time of the core commit being published, never the clock: the same commit always
  # gives the same stamp, so a release of an unchanged core changes nothing.
  commit="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  if git -C "$SRC" diff --quiet -- "${src#"$SRC"/}" 2>/dev/null; then clean=true; else clean=false; fi
  if [[ -n "$split" ]]; then
    split_json="$(tr ',' '\n' <<<"$split" | jq -Rn '[inputs | select(length>0) | split(":") | {(.[0]): .[1]}] | add // {}')"
  fi
  stamp="$(jq -n --arg unit "$unit" --arg cat "$cat" --arg tier "$tier" --arg commit "$commit" \
              --argjson clean "$clean" --argjson split "$split_json" --argjson tests "$ntests" \
              --arg contract "$contract_sha" --arg payload "$payload_sha" \
              --arg when "$(date -u -d "$(git -C "$SRC" log -1 --format=%cI HEAD 2>/dev/null || printf '1970-01-01T00:00:00Z')" +%Y-%m-%dT%H:%M:%SZ)" \
              '{unit:$unit, category:$cat, tier:$tier, split:$split,
                source:{commit:$commit, unit_tree_clean:$clean},
                selftests_run:$tests, contract_sha256:$contract, payload_sha256:$payload, published_at:$when}')"

  log "'$unit' passes ($ntests self-test(s) green)"
  if [[ "$json" == true ]]; then
    jq -nc --argjson r "$stamp" --arg dest "skills/$cdir/$unit" '{ok:true, operation:"check-unit", target:$dest, result:$r}'
  fi
}

main() {
  local json=false unit="" dependency
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json=true ;;
      -h|--help) usage ;;
      --*) log "unknown flag: $1"; usage ;;
      *) [[ -z "$unit" ]] || { log "only one unit per run"; usage; }; unit="$1" ;;
    esac
    shift
  done
  [[ -n "$unit" ]] || usage
  for dependency in jq python3 timeout git; do
    command -v "$dependency" >/dev/null || die "$dependency is required"
  done
  python3 -c 'import yaml' 2>/dev/null || die "Python 3 with PyYAML is required"
  [[ -f "$SRC/scripts/requirements-contract.json" ]] || die "scripts/requirements-contract.json is required"
  check_unit "$unit" "$json"
}

main "$@"
