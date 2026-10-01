# CLAUDE.md

This repository is the published Sno Station skill library. It is generated from a private
working repository on every release; changes made here directly are overwritten by the next
release. To report a problem or suggest a change, open an issue.

- Install with `sno setup`, which puts each skill into every agent it finds on the machine.
- Each unit lives in `skills/<category>/<unit>/`; `skills/README.md` lists units by category.
- `PUBLISHED.json` in each unit records the publish check result; it is written by the release
  build, never by hand.
