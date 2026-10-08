# AGENTS.md

This repository is the published Sno Station skill library. It is generated from a private
working repository on every release; changes made here directly are overwritten by the next
release. To report a problem or suggest a change, open an issue.

- Install with `sno setup`, which puts each skill into every agent it finds on the machine.
- Each unit lives in `skills/<category>/<unit>/`; `skills/README.md` lists units by category.
- `PUBLISHED.json` in each unit records the publish check result; it is written by the release
  build, never by hand.

## Releasing: always the release script, always automatic

- `sno setup` downloads `final-skills.tar.gz` from the latest GitHub release, never from this
  branch. A change that reached `main` but not a release has not reached any user.
- The private working repository's release script is the only way anything here changes. In one
  run it builds the whole tree, pushes it to `main`, and creates the next GitHub release (patch
  version + 1) with that build's `final-skills.tar.gz` as its only asset.
- An agent that changes a published skill must run that release script after the change is
  committed, every time, without waiting to be asked. Never edit this repository, push to it, or
  create, edit or upload a GitHub release by hand.
- Done means the latest release points at the current `main` commit and its asset digest
  (`gh api repos/sno-ai/sno-station-skills/releases/latest --jq '.assets[0].digest'`) equals
  `sha256sum final-skills.tar.gz` of the downloaded asset.
