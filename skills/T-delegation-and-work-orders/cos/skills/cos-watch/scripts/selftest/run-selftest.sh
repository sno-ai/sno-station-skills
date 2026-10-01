#!/usr/bin/env bash
# Check only this packaged skill. It reads no sibling skill and no network.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 "$HERE/text-check.py"
