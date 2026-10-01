#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
python3 "$HERE/text-check.py"
bash "$HERE/../handoff-checkpoint.t"
