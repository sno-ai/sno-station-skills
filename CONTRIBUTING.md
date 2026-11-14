# Contributing to Sno Station skills

Thanks for helping. This page is short on purpose.

## Before you start

- **Questions and ideas** go to [Discussions](https://github.com/sno-ai/sno-station-skills/discussions).
- **Bugs and requests** go to [issues](https://github.com/sno-ai/sno-station-skills/issues).
- **Security problems** never go in a public issue. See [SECURITY.md](SECURITY.md).

## How we take your change

Pull requests are welcome, and we answer every one within a day.

- **Documentation** and other non-code files: we review and merge them as you wrote them.
- **Skill code, tests and evaluations:** we keep what your change is for and our agents rewrite it to
  our house standard, to the same result and the same passing check. You stay the commit author: the
  pull request is merged under your name and you appear in GitHub's contributor list and in
  [CONTRIBUTORS.md](CONTRIBUTORS.md).
- **An idea with no code** counts too. Describe it in a pull request or an issue; if we build it, the
  commit is yours.

Every pull request uses the [template](.github/pull_request_template.md). Two sections are required, a
sentence each: what should be different, and how to tell it works.

## Making a change

1. Fork and branch from `main`.
2. Keep one change per pull request.
3. Run the check: `bash scripts/check.sh origin/main` (needs gitleaks, PyYAML and jq). To check one
   unit alone: `bash scripts/check-unit.sh <unit>`.
4. Sign off every commit (DCO). We do not use a CLA.

   ```bash
   git commit -s -m "fix: describe the change"
   ```

## What we will ask you to remove

- Benchmark numbers or vendor comparisons in skill text or docs. Numbers live in `evals/` with a
  receipt.
- Any private host name, absolute home path, credential, or link to a private document.
- Text that names one model vendor as the careful one and the other as the fast one. It flips by
  month and by job; the point is that they differ.
