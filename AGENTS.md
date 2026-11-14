# AGENTS.md

This repository is the source of the Sno Station skills. Pull requests are welcome;
[CONTRIBUTING.md](CONTRIBUTING.md) says how we take them.

- Install with `sno setup`, which puts each skill into every agent it finds on the machine.
- Each unit lives in `skills/<category>/<unit>/`; `skills/README.md` lists units by category and
  `registry.yaml` lists every unit that ships.
- **Before you hand back a change**, run `bash scripts/check.sh origin/main` (needs gitleaks, PyYAML and
  jq). It refuses private paths, secrets and absolute home paths, runs `scripts/check-unit.sh` on every
  unit you touched, and checks the generated plugin files. The same check runs on every pull request.
- After adding, moving or renaming a skill folder, run `bash scripts/build.sh --sync` and commit what
  it changes (the plugin skill lists and the standalone plugin copies).
- **Never add** machine-bound paths, private host names, credentials or links to private documents.
  Skills are English only. Never name one model vendor as the careful one and the other as the fast
  one.
- Private working rules for this checkout, when present, are in `CLAUDE.md` beside this file. Read it too.

## Releasing

- `sno setup` downloads `final-skills.tar.gz` from the latest stable GitHub release, never from this
  branch. A change on `main` reaches `sno setup` users only with the next release.
- Release with `scripts/release.sh`, in order: `bump` on a release branch and open its pull request;
  `candidate` on that branch's head (a prerelease, which `sno setup` installs only when asked with
  `--skills-version`); install it on a fresh profile with `sno setup --skills-version <tag>`; merge the pull
  request; `promote <tag>`. Never create, edit or upload a GitHub release by hand.
- Done means the latest release points at a `main` commit and its asset digest
  (`gh api repos/sno-ai/sno-station-skills/releases/latest --jq '.assets[0].digest'`) equals
  `sha256sum` of the downloaded `final-skills.tar.gz`.
