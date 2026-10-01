#!/usr/bin/env bash
# Structure test for the laws-first cores.
#
# Two properties, both load-bearing and both silent when they rot:
#   1. THE SURVIVAL CAP. Claude-runtime compaction keeps only an invoked skill's first
#      ~5,000 tokens. The unrecoverable laws (identity → end of the decision
#      discipline) must fit that window; the sections after them are the deliberate
#      sacrificial tail (pointer summaries, routing tables scripts also print). The cap
#      here is bytes (~4 bytes/token): 21,500 ≈ 5,375 tokens — headroom for small
#      edits, a hard stop for a new essay creeping into the laws.
#   2. POINTER INTEGRITY. The laws cite section names in their own file and in sibling
#      skills. A renamed heading turns a law's pointer into a dead end with no error.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Repo shape: <root>/pl/skills/pl/scripts → root is four levels up.
# Deployed shape: <skills-root>/pl/scripts → the skills dir is two levels up.
repo_root="$(cd -- "$script_dir/../../../.." && pwd)"
deploy_root="$(cd -- "$script_dir/../.." && pwd)"
if [[ -n "${PL_SKILLS_ROOT:-}" ]]; then
    repo_root="$PL_SKILLS_ROOT"
fi
if [[ -f "$repo_root/pl/skills/pl/SKILL.md" ]]; then
    pl_core="$repo_root/pl/skills/pl/SKILL.md"
    pl_watch="$repo_root/pl/skills/pl-watch/SKILL.md"
    cos_core="$repo_root/cos/skills/cos/SKILL.md"
else
    pl_core="$deploy_root/pl/SKILL.md"
    pl_watch="$deploy_root/pl-watch/SKILL.md"
    cos_core="$deploy_root/cos/SKILL.md"
fi

CAP_BYTES=21500
# Reserve space for an installation header when checking the source copy, so
# the same law-region limit applies after installation.
STAMP_ALLOWANCE=600
if [[ -f "$repo_root/pl/skills/pl/SKILL.md" ]]; then
    CAP_BYTES=$((CAP_BYTES - STAMP_ALLOWANCE))
fi

failures=0
test_no=0

pass() { test_no=$((test_no + 1)); printf 'ok %d - %s\n' "$test_no" "$1"; }
fail() {
    test_no=$((test_no + 1)); failures=$((failures + 1))
    printf 'not ok %d - %s\n' "$test_no" "$1"
    [[ -z "${2:-}" ]] || printf '#   %s\n' "$2"
}

prefix_cap() {
    local label="$1" file="$2" boundary="$3"
    if [[ ! -f "$file" ]]; then fail "$label" "missing file: $file"; return; fi
    local off
    off="$(grep -bF -m1 -- "$boundary" "$file" | cut -d: -f1 || true)"
    if [[ -z "$off" ]]; then
        fail "$label" "boundary heading not found: $boundary"
        return
    fi
    if (( off <= CAP_BYTES )); then
        pass "$label (${off} <= ${CAP_BYTES} bytes)"
    else
        fail "$label" "critical prefix is ${off} bytes, cap ${CAP_BYTES} — a law region this big no longer survives compaction"
    fi
}

heading_present() {
    local label="$1" file="$2" heading="$3"
    if grep -qF -- "$heading" "$file"; then
        pass "$label"
    else
        fail "$label" "not found in $file: $heading"
    fi
}


printf 'TAP version 13\n'

# One section deliberately rides the cut line in both cores: the fast/slow switch,
# because Reach inbox prints its signals and the four-line form under every
# inbound batch — at the decision moment itself. Everything before it, the circuit
# breaker included, exists nowhere else and must survive compaction.
prefix_cap 'pl core unrecoverable laws fit the survival window' "$pl_core" '### Fast thinking, slow thinking'
# The cos skill is a sibling unit; when it is not installed its checks are skipped.
have_cos=1
if [[ ! -f "$cos_core" ]]; then
    have_cos=0
    printf '# SKIP: cos skill not installed; cos core checks skipped\n'
else
    prefix_cap 'cos core unrecoverable laws fit the survival window' "$cos_core" '## The charter-filename law'
fi

# pl core: sections its own laws and sibling files point at.
for h in '## Decision discipline' '### The Triage Predicate' \
         '### Severity & disposition' '### The circuit breaker' \
         '### Fast thinking, slow thinking — the switch' \
         '## Launch ladders' '## Communication — four mechanisms and PL session rituals'; do
    heading_present "pl core carries: $h" "$pl_core" "$h"
done
heading_present 'pl-watch still carries the Take-over section the menu points at' \
    "$pl_watch" '## Take-over & convergence supervision'
heading_present 'pl-watch still carries the Supersede protocol the breaker points at' \
    "$pl_watch" 'Supersede protocol'

# cos core: sections its own laws point at.
if [[ "$have_cos" -eq 1 ]]; then
for h in '## Decision discipline' '### The only six reasons to act' \
         '### The restraint list' '### What may settle a decision' \
         '### The circuit breaker' '## Fast thinking, slow thinking — the switch' \
         '## Where COS may overrule a PL' \
         '### The send protocol' '### When mail must not be sent' \
         '## Card timing' '## Talking to the owner' '## Repairing a board' \
         '## Liveness' '## Boot ritual' '## Acting on the six reasons' '## PART 2'; do
    heading_present "cos core carries: $h" "$cos_core" "$h"
done
fi


# Pocket cards: each core's frontmatter hook cats references/pocket-card.md with a
# masked failure (|| true), so a missing or renamed card silently kills the per-turn
# refresh. The card must exist beside its core, and the core must point at it.
pairs=("pl:$pl_core")
[[ "$have_cos" -eq 1 ]] && pairs+=("cos:$cos_core")
for pair in "${pairs[@]}"; do
    role="${pair%%:*}"; core="${pair#*:}"
    card="$(dirname -- "$core")/references/pocket-card.md"
    if [[ -f "$card" ]]; then
        pass "$role pocket card exists beside its core"
    else
        fail "$role pocket card exists beside its core" "missing: $card"
    fi
    heading_present "$role core frontmatter hook names the pocket card" "$core" 'references/pocket-card.md'
done

printf '1..%d\n' "$test_no"
if [[ "$failures" -eq 0 ]]; then
    printf '# core structure holds\n'
else
    printf '# core structure BROKEN (%d)\n' "$failures"
    exit 1
fi
