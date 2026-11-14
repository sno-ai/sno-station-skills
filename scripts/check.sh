#!/usr/bin/env bash
# check.sh — the check every pull request and every push to main must pass.
#
#   scripts/check.sh <base>   check the commits from <base> to HEAD
#
# 1. No commit adds, modifies or renames into a private path (deleting one is allowed).
# 2. gitleaks finds no secret in those commits (built-in rules only).
# 3. No added line carries an absolute home path.
# 4. Every unit the commits touch passes scripts/check-unit.sh.
# 5. The generated plugin files are current (scripts/build.sh --check).
#
# It blocks merging; it cannot take back an upload. Exit: 0 passed · 1 refused · 2 bad usage.
# Needs git, jq, python3 (PyYAML), gitleaks.
set -Eeuo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
log() { printf 'check: %s\n' "$*" >&2; }
die() { log "$*"; exit 1; }
[[ $# -eq 1 && "$1" != -* ]] || { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }
for program in git jq python3 gitleaks; do command -v "$program" >/dev/null || die "$program is not installed"; done
cd "$repo"
base="$(git rev-parse --verify "$1^{commit}")"
head="$(git rev-parse --verify HEAD)"
git merge-base --is-ancestor "$base" "$head" || die "$1 is not an ancestor of HEAD; update the branch from main"
scratch="$(mktemp -d)"; trap 'rm -rf -- "$scratch"' EXIT

# 1. Private paths. This list is the denylist of .gitignore; keep the two equal.
git log -m --format= --name-only --diff-filter=ACMRT -z "$base..$head" > "$scratch/paths"
refused=0
while IFS= read -r -d '' path; do
  path=${path#$'\n'}
  [[ -n "$path" ]] || continue
  case "$path" in
    .env.example|*/.env.example) continue ;;
    ai-doc|ai-doc/*|openspec|openspec/*|staging|staging/*|dev-scripts|dev-scripts/*|.claude|.claude/*|.codex|.codex/*|\
    CLAUDE.md|TODO.md*|.env|.env.*|*/.env|*/.env.*|*.pem|*.key|*.p12|*.pfx|.npmrc|*/.npmrc|\
    tests|tests/*|deploy.sh|scripts/publish.sh|scripts/e2e/*|scripts/fixtures/*|scripts/selftest/*|\
    skills/*/*/docs/*|skills/*/*/tests/*|skills/*/*/sidecar/*|skills/*/*/PRD*|skills/*/reports/*|skills/*/prd/*|\
    skills/*/PROBE-RESULTS*|skills/*/LESSIONS.md|skills/*.private.*|skills/*.sha256|skills/*/.managed-by-sno-skills)
      log "private path: $path"; refused=1 ;;
  esac
done < "$scratch/paths"
((refused == 0)) || die "these paths never belong in this repository"

# 2. Secrets.
printf '[extend]\nuseDefault = true\n' > "$scratch/gitleaks.toml"
(cd "$scratch"; unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
 gitleaks git "$repo" --config "$scratch/gitleaks.toml" --gitleaks-ignore-path /dev/null --ignore-gitleaks-allow \
   --redact --no-banner --log-opts="-m $base..$head") || die "gitleaks found a secret"

# 3. Absolute home paths, in every file (a unit not yet in registry.yaml gets no check-unit run).
if git diff --no-color --unified=0 "$base" "$head" |
   grep -nE '^\+[^+].*(/home/[A-Za-z0-9_-]+/|/Users/[A-Za-z0-9_-]+/|[A-Za-z]:\\Users\\)' >&2; then
  die "absolute home paths in added lines (above)"
fi

# 4. Units the commits touch, as named in registry.yaml.
mapfile -t touched < <(git diff --name-only "$base" "$head" -- skills/ | awk -F/ 'NF >= 4 {print $3}' | sort -u)
mapfile -t known < <(python3 -c 'import sys, yaml; print(*yaml.safe_load(open(sys.argv[1]))["units"], sep="\n")' registry.yaml)
for unit in "${touched[@]}"; do
  printf '%s\n' "${known[@]}" | grep -qxF -- "$unit" || { log "skipping $unit: not in registry.yaml (removed or new)"; continue; }
  bash scripts/check-unit.sh "$unit" || die "check-unit refused $unit"
done

# 5. Generated files.
bash scripts/build.sh --check
log "passed for ${head:0:12} (${#touched[@]} unit(s) checked)"
