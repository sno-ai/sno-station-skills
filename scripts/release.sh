#!/usr/bin/env bash
# release.sh — release the skills in three steps, so no user gets a build before it was installed and tested.
#
#   scripts/release.sh bump              set the plugin version to 1.0.<UTC time YYYYmmddHHMM> in the three plugin
#                                        manifests; commit it on the release branch and open its pull request
#   scripts/release.sh candidate         from a clean checkout whose HEAD is on GitHub (the release pull request's
#                                        head), build final-skills.tar.gz and create the next version as a prerelease
#   scripts/release.sh promote <tag>     after that pull request merged: check that main has exactly the tested tree,
#                                        then replace the prerelease with the stable release <tag> on main, same archive
#
# `sno setup` installs the latest stable release unless --skills-tag names another, so a prerelease reaches only
# the machine that asks for it by tag. Exit: 0 done · 1 a step failed · 2 bad usage. Needs git, jq, gh, python3.
set -Eeuo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly GH_REPO=sno-ai/sno-station-skills
readonly MANIFESTS=(.codex-plugin/plugin.json plugins/sno-station-standalone/.claude-plugin/plugin.json
  plugins/sno-station-standalone/.codex-plugin/plugin.json)
log() { printf 'release: %s\n' "$*" >&2; }
die() { log "$*"; exit 1; }
usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }
for program in git jq gh python3; do command -v "$program" >/dev/null || die "$program is not installed"; done
cd "$repo"

# shellcheck disable=SC2016  # the backticks are Markdown, not command substitution
notes() {
  printf '# Sno Station skills %s\n\nThe team skills your agents share: peer review, handoff, delegation, reporting and learning from mistakes. Install them with `sno setup`.\n\nAlready installed? Run `sno update`.\n' "$1"
}

case "${1:-}" in
  bump)
    [[ $# -eq 1 ]] || usage
    version="1.0.$(date -u +%Y%m%d%H%M)"
    for manifest in "${MANIFESTS[@]}"; do
      [[ -f "$manifest" ]] || die "$manifest is missing"
      current="$(jq -r '.version' "$manifest")"
      [[ "$current" < "$version" ]] || die "$manifest already has version $current, not below $version"
      jq --arg v "$version" '.version = $v' "$manifest" >"$manifest.tmp"
      mv -f -- "$manifest.tmp" "$manifest"
    done
    log "plugin version set to $version in ${#MANIFESTS[@]} manifests; commit them on the release branch"
    ;;
  candidate)
    [[ $# -eq 1 ]] || usage
    [[ -z "$(git status --porcelain)" ]] || die "the checkout has uncommitted changes"
    sha="$(git rev-parse HEAD)"
    gh api "repos/$GH_REPO/commits/$sha" --jq .sha >/dev/null 2>&1 || die "HEAD ${sha:0:12} is not on GitHub; push the release branch first"
    latest="$(gh release view --repo "$GH_REPO" --json tagName,isPrerelease)" || die "could not read the latest release of $GH_REPO"
    [[ "$(jq -r .isPrerelease <<<"$latest")" == false ]] || die "the latest release is a prerelease; promote or delete it first"
    old_tag="$(jq -r .tagName <<<"$latest")"
    [[ "$old_tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "the latest release tag '$old_tag' is not vMAJOR.MINOR.PATCH"
    version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
    tag="v$version"
    ! gh release view "$tag" --repo "$GH_REPO" >/dev/null 2>&1 || die "release $tag already exists"
    out="$(mktemp -d)"; trap 'rm -rf -- "$out"' EXIT
    bash scripts/build.sh --archive "$out"
    gh release create "$tag" "$out/final-skills.tar.gz" --repo "$GH_REPO" --target "$sha" --prerelease \
      --title "Sno Station skills $version (candidate)" --notes "$(notes "$version")" >/dev/null ||
      die "creating prerelease $tag failed"
    log "prerelease $tag created from ${sha:0:12}; test it with: sno setup --skills-tag $tag"
    printf '%s\n' "$tag"
    ;;
  promote)
    [[ $# -eq 2 && "$2" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
    tag="$2"
    info="$(gh release view "$tag" --repo "$GH_REPO" --json isPrerelease,assets)" || die "release $tag does not exist"
    [[ "$(jq -r .isPrerelease <<<"$info")" == true ]] || die "$tag is not a prerelease"
    git fetch -q origin main "refs/tags/$tag:refs/tags/$tag"
    main_sha="$(git rev-parse origin/main)"
    [[ "$(git rev-parse "origin/main^{tree}")" == "$(git rev-parse "$tag^{commit}^{tree}")" ]] ||
      die "main ${main_sha:0:12} does not hold the tree tested as $tag; build a new candidate from main instead"
    out="$(mktemp -d)"   # kept if a later step fails, so the tested archive is not lost
    gh release download "$tag" --repo "$GH_REPO" --pattern final-skills.tar.gz --dir "$out" ||
      die "downloading the $tag archive failed"
    digest="$(jq -r '.assets[] | select(.name == "final-skills.tar.gz") | .digest' <<<"$info")"
    [[ "$digest" == "sha256:$(sha256sum "$out/final-skills.tar.gz" | cut -d ' ' -f1)" ]] ||
      die "the downloaded $tag archive does not match its recorded digest"
    version="${tag#v}"
    gh release delete "$tag" --repo "$GH_REPO" --cleanup-tag --yes || die "deleting prerelease $tag failed"
    gh release create "$tag" "$out/final-skills.tar.gz" --repo "$GH_REPO" --target "$main_sha" --latest \
      --title "Sno Station skills $version" --notes "$(notes "$version")" >/dev/null ||
      die "creating release $tag on main failed after the prerelease was deleted; users still get the previous release. The tested archive is kept at $out/final-skills.tar.gz: gh release create $tag $out/final-skills.tar.gz --repo $GH_REPO --target $main_sha --latest"
    rm -rf -- "$out"
    log "released $tag on main ${main_sha:0:12}"
    ;;
  -h|--help) usage ;;
  *) usage ;;
esac
