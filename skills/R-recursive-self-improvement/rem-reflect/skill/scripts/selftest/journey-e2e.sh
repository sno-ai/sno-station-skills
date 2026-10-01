#!/usr/bin/env bash
# A two-day fixture journey with a planted isolation failure only in the test backend instance.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOURNEY="$HERE/journey.mjs"
[[ -f "$JOURNEY" ]] || { printf 'FAIL: fixture journey not found\n' >&2; exit 1; }

run_journey() { node --experimental-strip-types "$JOURNEY" isolated; }

if ! output="$(run_journey)" || ! grep -q 'JOURNEY OK isolated' <<<"$output"; then
  printf '%s\n' "$output" >&2
  printf 'FAIL: the clean two-day journey did not pass\n' >&2
  exit 1
fi

if output="$(REM_DROP_SPAWN_ENV=1 run_journey 2>&1)"; then
  printf 'FAIL: the planted isolation loss did not make the ordinary journey RED\n' >&2
  exit 1
fi
grep -q 'day two harvested no loop-own session; got [1-9]' <<<"$output" || {
  printf '%s\n' "$output" >&2
  printf 'FAIL: the planted defect did not reach the second harvest\n' >&2
  exit 1
}
grep -q 'cloud cited it: true' <<<"$output" || {
  printf '%s\n' "$output" >&2
  printf 'FAIL: the planted defect did not contaminate the cloud answer\n' >&2
  exit 1
}

if ! output="$(run_journey)" || ! grep -q 'JOURNEY OK isolated' <<<"$output"; then
  printf '%s\n' "$output" >&2
  printf 'FAIL: the journey did not pass after restoring isolation\n' >&2
  exit 1
fi

printf 'Two-day journey GREEN, planted isolation loss RED with a cloud-cited leak, restored GREEN\n'
