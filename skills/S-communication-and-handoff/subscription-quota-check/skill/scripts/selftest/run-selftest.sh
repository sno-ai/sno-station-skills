#!/usr/bin/env bash
# Check only this packaged skill. Runtime tests belong to the core release.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 "$HERE/text-check.py"
