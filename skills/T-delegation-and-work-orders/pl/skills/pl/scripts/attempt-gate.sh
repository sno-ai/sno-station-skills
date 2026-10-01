#!/usr/bin/env bash
# attempt-gate.sh — the circuit breaker's pre-send check, as a command that can refuse.
#
# A supervisor can drive one unresolved problem through the same kind of ruling again and
# again; every card is fine on its own, nothing counts attempts, and the loop runs until
# someone outside it notices. The circuit-breaker rule in the pl and cos skills forbids the
# third same-shape attempt; this command counts attempts and refuses deterministically,
# instead of relying on a model to remember to count.
#
# The tag. Every intervention card or ruling line on a recurring problem carries
#     attempt: <problem-slug> #N — success check: <command>
# with the slug chosen on attempt one and reused verbatim. Cards are files, so the count is
# a scan over the Reach inbox directories and exported threads. Counting is by distinct
# attempt number: a later card that quotes "attempt: fix-x #1" adds nothing, because #1 was
# already seen — max(N), not line count, cannot be inflated by quoting.
#
# usage:
#   attempt-gate.sh count --slug <slug> --scan <file-or-dir> [--scan <...>]...
#   attempt-gate.sh check --slug <slug> --scan <file-or-dir> [--scan <...>]...
# stdout (one line, machine-readable):
#   count :  attempts=<highest-N-seen>
#   check :  ok next-attempt=<N+1>            (exit 0 — sending is allowed)
#            REFUSED attempts=<N> slug=<slug> (exit 3 — the third attempt is forbidden;
#                                              matched tag lines are on stderr)
# exit 0 = allowed / counted · 3 = refused · 64 = bad usage · 65 = a scan path missing
set -Eeuo pipefail

usage() {
  sed -n '17,26p' "${BASH_SOURCE[0]}" >&2
}

[[ $# -ge 1 ]] || { usage; exit 64; }
cmd="$1"; shift
case "$cmd" in count|check) ;; *)
  printf 'attempt-gate: unknown subcommand %q (want: count | check)\n' "$cmd" >&2
  exit 64 ;;
esac

slug=""
scans=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug) [[ $# -ge 2 ]] || { printf 'attempt-gate: --slug needs a value\n' >&2; exit 64; }
            slug="$2"; shift 2 ;;
    --scan) [[ $# -ge 2 ]] || { printf 'attempt-gate: --scan needs a value\n' >&2; exit 64; }
            scans+=("$2"); shift 2 ;;
    *) printf 'attempt-gate: unknown argument %q\n' "$1" >&2; exit 64 ;;
  esac
done

[[ -n "$slug" ]] || { printf 'attempt-gate: --slug is required\n' >&2; exit 64; }
[[ "${#scans[@]}" -gt 0 ]] || { printf 'attempt-gate: at least one --scan path is required\n' >&2; exit 64; }
for p in "${scans[@]}"; do
  [[ -e "$p" ]] || {
    printf 'attempt-gate: scan path does not exist: %s — a zero from a missing path looks like a zero from no matches, so this is refused, not counted\n' "$p" >&2
    exit 65
  }
done

# All tag lines for this slug, from every scan path. grep -r covers files and
# directories alike; -F on the slug would lose the "#N" pattern, so the slug is
# escaped into the regex instead.
esc=$(printf '%s' "$slug" | sed -e 's/[][\.*^$/]/\\&/g')
matches=$(grep -rIhoE "attempt: ${esc} #[0-9]+" -- "${scans[@]}" 2>/dev/null || true)

highest=0
if [[ -n "$matches" ]]; then
  highest=$(printf '%s\n' "$matches" | grep -oE '[0-9]+$' | sort -un | tail -1)
fi

case "$cmd" in
  count)
    printf 'attempts=%s\n' "$highest"
    ;;
  check)
    if (( highest >= 2 )); then
      printf 'attempt-gate: REFUSED — %s attempts already recorded for this problem; the third same-shape attempt is forbidden (core §The circuit breaker). Write the loop down, restate the problem from disk, change lanes.\n' "$highest" >&2
      printf '%s\n' "$matches" | sort -u >&2
      printf 'REFUSED attempts=%s slug=%s\n' "$highest" "$slug"
      exit 3
    fi
    printf 'ok next-attempt=%s\n' "$((highest + 1))"
    ;;
esac
