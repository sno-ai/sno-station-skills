#!/usr/bin/env bash
# Check only this packaged skill against the sno binary that serves its reference.
# SNO_BIN picks the binary (default: sno on PATH); a missing binary fails with the reason.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 "$HERE/text-check.py"
