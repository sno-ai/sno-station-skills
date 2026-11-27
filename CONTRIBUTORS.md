# Contributors

People whose pull requests or ideas changed the Sno Station skills. We rewrite accepted code changes
ourselves and keep the contributor as the commit author (see [CONTRIBUTING.md](CONTRIBUTING.md)); this
list records whose change it was.

| Contributor | What was adopted |
|---|---|
| [@anhaoXie](https://github.com/anhaoXie) | README: the standalone plugin holds 12 skills, not 7 ([#28](https://github.com/sno-ai/sno-station-skills/pull/28)); `catch-report` SKILL.md states the self-check default of 30 excerpts ([#44](https://github.com/sno-ai/sno-station-skills/pull/44)); `log-watch.sh` help, NEVER-STARTED message and comments say any output counts as started ([#50](https://github.com/sno-ai/sno-station-skills/pull/50)) |
| [@bfs2021](https://github.com/bfs2021) | `fence-check.sh --help` prints only its comment header, and the help test checks every script for leaked code ([#27](https://github.com/sno-ai/sno-station-skills/pull/27)); `rotate-agent-watch` and `rotate-agent-preflight` treat an option with no value as a usage error, exit 2, with a selftest per option ([#43](https://github.com/sno-ai/sno-station-skills/pull/43)); the Claude Code `codex-coder` arms its wait with `sno heartbeat` ([#45](https://github.com/sno-ai/sno-station-skills/pull/45)); `review-findings.sh --help` prints its header without `#` markers, with a selftest for `-h` and `--help` ([#57](https://github.com/sno-ai/sno-station-skills/pull/57)) |
| [@lnyuyu](https://github.com/lnyuyu) | `review-receipt.sh` and `review-backfill.sh` `--help` print only their comment header, with a selftest for `-h` and `--help` ([#36](https://github.com/sno-ai/sno-station-skills/pull/36)) |
| [@ginisha2006](https://github.com/ginisha2006) | `rotate-agent-watch --help` and `rotate-agent-preflight --help` print usage to stdout and exit 0, with a selftest for it ([#41](https://github.com/sno-ai/sno-station-skills/pull/41)) |
| [@nabeelbaghoor](https://github.com/nabeelbaghoor) | `rem-reflect` asks the local writer only about sessions with a verdict a lesson can cite, leaving out commits and pushes, with a test for it ([#49](https://github.com/sno-ai/sno-station-skills/pull/49)); `rem-reflect` counts tests behind pnpm's `--filter` selector and `typecheck`, `lint` and `test:*` scripts as verdicts ([#51](https://github.com/sno-ai/sno-station-skills/pull/51)) |
| [@Bersha-del](https://github.com/Bersha-del) | README: the `requires:` example uses the `programs` form the validator accepts, and says what `min_version` means ([#54](https://github.com/sno-ai/sno-station-skills/pull/54)) |
| [@MaxonT](https://github.com/MaxonT) | The eight README translations: the `requires:` example uses the `programs` form the validator accepts, and says what `min_version` means ([#59](https://github.com/sno-ai/sno-station-skills/pull/59)) |
