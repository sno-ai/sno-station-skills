#!/usr/bin/env bash
# build.sh — generated files and the release archive of this repository.
#
#   scripts/build.sh --sync            rewrite the generated files in this checkout: the skill lists in
#                                      .claude-plugin/marketplace.json and .codex-plugin/plugin.json, and the
#                                      real copies under plugins/sno-station-standalone/
#   scripts/build.sh --check           fail when --sync would change anything (the pull request check)
#   scripts/build.sh --archive <dir>   check every unit and write <dir>/final-skills.tar.gz, the archive
#                                      `sno setup` installs; needs a clean checkout, and takes committed files only
#
# Plugin versions are not touched here; scripts/release.sh bump sets them.
# Exit: 0 done · 1 a step failed · 2 bad usage. Needs git, jq, python3 (PyYAML), tar.
set -Eeuo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
log() { printf 'build: %s\n' "$*" >&2; }
die() { log "$*"; exit 1; }
usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

for program in git jq python3 tar; do command -v "$program" >/dev/null || die "$program is not installed"; done

# sync <tree> — regenerate the generated files inside <tree> from the skills it holds.
sync() {
  local tree="$1" marketplace skill_dirs claude_dirs codex_dirs codex_manifest standalone wanted dir name
  marketplace="$tree/.claude-plugin/marketplace.json"
  [[ -f "$marketplace" ]] || die "$marketplace is missing"
  # The full plugin lists every skill folder, so a nested skill cannot go missing from it. A unit that ships one
  # copy per agent (overlay/<agent>/) is listed with Claude's copy here and Codex's copy in the Codex manifest.
  skill_dirs="$(cd "$tree" && find skills -name SKILL.md -printf './%h\n' | LC_ALL=C sort)"
  claude_dirs="$(awk '!/\/overlay\// || /\/overlay\/claude$/' <<<"$skill_dirs")"
  jq --arg dirs "$claude_dirs" '(.plugins[] | select(.name == "sno-station")).skills = ($dirs | split("\n"))' \
    "$marketplace" >"$marketplace.tmp"
  mv -f -- "$marketplace.tmp" "$marketplace"
  codex_manifest="$tree/.codex-plugin/plugin.json"
  if [[ -f "$codex_manifest" ]]; then
    codex_dirs="$(awk '!/\/overlay\// || /\/overlay\/codex$/' <<<"$skill_dirs")"
    jq --arg dirs "$codex_dirs" '.skills = ($dirs | split("\n"))' "$codex_manifest" >"$codex_manifest.tmp"
    mv -f -- "$codex_manifest.tmp" "$codex_manifest"
  fi
  # A directory submission ships only its plugin folder, so the standalone folder holds real copies of its skills.
  standalone="$tree/plugins/sno-station-standalone"
  if [[ -d "$standalone" ]]; then
    rm -rf -- "$standalone/skills"
    mkdir -p -- "$standalone/skills"
    wanted="$(jq -r '.plugins[] | select(.name == "sno-station-standalone") | .skills[] | sub("^\\./skills/"; "")' "$marketplace")"
    while IFS= read -r dir; do
      name="$(sed -n 's/^name: *//p' "$tree/$dir/SKILL.md" | head -n 1)"
      if grep -qxF -- "$name" <<<"$wanted"; then cp -a -- "$tree/$dir" "$standalone/skills/$name"; fi
    done <<<"$skill_dirs"
    cp -a -- "$tree/LICENSE" "$standalone/LICENSE"
    cp -a -- "$tree/SECURITY.md" "$standalone/SECURITY.md"
  fi
}

# export_tree <dir> — the committed files of HEAD, never untracked or ignored ones.
export_tree() {
  git -C "$repo" archive --format=tar HEAD | tar -x -C "$1"
}

case "${1:-}" in
  --sync)
    [[ $# -eq 1 ]] || usage
    sync "$repo"
    log "generated files rewritten; review and commit them"
    ;;
  --check)
    [[ $# -eq 1 ]] || usage
    work="$(mktemp -d)"; trap 'rm -rf -- "$work"' EXIT
    export_tree "$work"
    sync "$work"
    if ! diff -r -q "$repo/.claude-plugin" "$work/.claude-plugin" >/dev/null ||
       ! diff -r -q "$repo/.codex-plugin" "$work/.codex-plugin" >/dev/null ||
       ! diff -r -q "$repo/plugins" "$work/plugins" >/dev/null; then
      diff -r -q "$repo/.claude-plugin" "$work/.claude-plugin" >&2 || true
      diff -r -q "$repo/.codex-plugin" "$work/.codex-plugin" >&2 || true
      diff -r -q "$repo/plugins" "$work/plugins" >&2 || true
      die "generated files are stale; run scripts/build.sh --sync and commit the result"
    fi
    log "generated files are current"
    ;;
  --archive)
    [[ $# -eq 2 && -n "$2" ]] || usage
    out="$(realpath -m -- "$2")"
    [[ -d "$out" ]] || die "output directory does not exist: $out"
    [[ -z "$(git -C "$repo" status --porcelain)" ]] ||
      die "the checkout has uncommitted changes; the archive is built from a clean checkout only"
    work="$(mktemp -d)"; trap 'rm -rf -- "$work"' EXIT
    stage="$work/stage"; mkdir -p "$stage"
    tree="$work/tree"; mkdir -p "$tree"
    export_tree "$tree"
    # The same shape the archive had when it was built from the private repository.
    for path in registry.yaml skills/README.md scripts/requirements-contract.json LICENSE NOTICE README.md \
                AGENTS.md SECURITY.md .gitignore .claude-plugin .codex-plugin plugins; do
      [[ -e "$tree/$path" ]] || die "$path is missing from HEAD"
      mkdir -p -- "$stage/$(dirname -- "$path")"
      cp -a -- "$tree/$path" "$stage/$path"
    done
    mapfile -t units < <(python3 -c 'import sys, yaml; print(*yaml.safe_load(open(sys.argv[1]))["units"], sep="\n")' "$tree/registry.yaml")
    total=${#units[@]}; started=$(date +%s)
    for index in "${!units[@]}"; do
      unit="${units[index]}"
      source="$(find "$tree/skills" -mindepth 2 -maxdepth 2 -type d -name "$unit" -print -quit)"
      [[ -n "$source" ]] || die "$unit is in registry.yaml but has no skills/<category>/$unit directory"
      target="$stage/skills/${source#"$tree/skills/"}"
      mkdir -p -- "$target"
      for part in skill skills overlay public-bin .roots; do
        if [[ -e "$source/$part" || -L "$source/$part" ]]; then cp -a -- "$source/$part" "$target/$part"; fi
      done
      gate_json="$(bash "$repo/scripts/check-unit.sh" --json "$unit")" || die "check-unit refused $unit; no archive written"
      jq -e '.result | select(type == "object")' <<<"$gate_json" >"$target/PUBLISHED.json" ||
        die "check-unit returned no stamp for $unit; no archive written"
      completed=$((index + 1)); elapsed=$(($(date +%s) - started))
      log "$unit $completed/$total checked; ETA $(((total - completed) * elapsed / completed))s"
    done
    tar -czf "$out/final-skills.tar.gz.tmp" -C "$stage" .
    mv -f -- "$out/final-skills.tar.gz.tmp" "$out/final-skills.tar.gz"
    log "wrote $out/final-skills.tar.gz ($total units)"
    ;;
  -h|--help) usage ;;
  *) usage ;;
esac
