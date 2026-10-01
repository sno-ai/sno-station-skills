#!/usr/bin/env bash
# Behaviour test for away-brief: real git repos, real charters proved with deliver-proof, real progress
# records written by handoff-checkpoint. Only the external programs sno (Reach inbox), heartbeat and the
# quota reader are stand-ins.
set -Eeuo pipefail

command_path="$(realpath -- "${1:-$(dirname -- "${BASH_SOURCE[0]}")/away-brief}")"
for tool in git jq deliver-proof handoff-checkpoint; do
    command -v "$tool" >/dev/null || { printf 'SKIP: %s is not installed\n' "$tool"; exit 0; }
done
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
count=0
ok() { count=$((count + 1)); printf 'ok %s - %s\n' "$count" "$1"; }
fail() { printf 'not ok %s - %s\n' "$((count + 1))" "$1"; [[ -s "$root/out" ]] && sed 's/^/# out: /' "$root/out"; [[ -s "$root/err" ]] && sed 's/^/# err: /' "$root/err"; exit 1; }
run() { local status=0; PATH="$root/bin:$PATH" XDG_STATE_HOME="$root/state" SNO_REACH_ADDR= "$command_path" "$@" >"$root/out" 2>"$root/err" || status=$?; printf '%s' "$status"; }
has() { grep -Fq -- "$1" "$root/out"; }
section() { awk -v h="## $1" '$0 == h { on = 1; next } /^## / { on = 0 } on' "$root/out"; }

# ---- stand-ins for the three external programs
mkdir -p "$root/bin" "$root/state" "$root/cards"
cat >"$root/bin/sno" <<'SH'
#!/usr/bin/env bash
[[ "$1 $2" == "reach inbox" ]] || exit 64
[[ -e "$FAKE_ROOT/inbox-broken" ]] && { echo 'inbox unreadable' >&2; exit 5; }
cat "$FAKE_ROOT/inbox"
SH
cat >"$root/bin/heartbeat" <<'SH'
#!/usr/bin/env bash
[[ "$1" == --list ]] && cat "$FAKE_ROOT/heartbeats"
SH
cat >"$root/bin/subscription-quota-check" <<'SH'
#!/usr/bin/env bash
cat "$FAKE_ROOT/quota"
exit "$(cat "$FAKE_ROOT/quota.exit" 2>/dev/null || echo 0)"
SH
chmod +x "$root/bin/"*
export FAKE_ROOT="$root"
printf 'WHO  OWNER LABEL PID LOG\nyou  o1 nightly 11 /x.log\n--   o2 other 22 /y.log\n' >"$root/heartbeats"
quota() { printf '{"vendors":[{"vendor":"claude","five_hour":{"used_pct":10},"seven_day":{"used_pct":%s}},{"vendor":"codex","tightest_window":{"used_pct":52,"window_minutes":10080}}]}\n' "$1" >"$root/quota"; }
quota 25

# ---- a real repo: one old commit, two new ones
repo="$root/proj"
mkdir -p "$repo/docs"
git -C "$repo" init -q -b main
gc() { git -C "$repo" -c user.name=Dev -c user.email=dev@example.invalid commit -q --allow-empty -m "$1"; }
old="$(date -d '3 days ago' -R)"
GIT_AUTHOR_DATE="$old" GIT_COMMITTER_DATE="$old" gc 'old work from days ago'
gc 'add login page'
gc 'fix login redirect'

# ---- real charters, proved with deliver-proof
charter() { # file status title checks
    cat >"$1" <<E
---
name: ${1##*/}
title: $3
status: $2
owner: owner
updated: 2026-09-30
---

## Success checks
$4

## Proof
(Written only by \`deliver-proof\`. Never edited by hand.)

| check | result | how | exit | log | at (UTC) |
|---|---|---|---|---|---|

## Report
E
}
charter "$repo/docs/done.md" delivered 'Ship the login page' $'1. login works\n2. redirect works'
(cd "$repo/docs" && deliver-proof run done.md 1 -- true >/dev/null && deliver-proof run done.md 2 -- true >/dev/null)
charter "$repo/docs/stuck.md" released 'Migrate the billing table' $'1. schema migrated\n2. old rows copied\n3. reports rebuilt'
(cd "$repo/docs" && deliver-proof run stuck.md 1 -- true >/dev/null; deliver-proof run stuck.md 2 -- false >/dev/null || true)
charter "$repo/docs/long.md" delivered 'A very long charter title that goes on and on and on and on and on and on and on and on and on and on' $'1. it worked'
(cd "$repo/docs" && deliver-proof run long.md 1 -- true >/dev/null)
charter "$repo/docs/ancient.md" delivered 'Delivered long ago' $'1. it worked'
(cd "$repo/docs" && deliver-proof run ancient.md 1 -- true >/dev/null)
touch -d '5 days ago' "$repo/docs/ancient.md"

# ---- real progress records
for r in quiet running finished; do (cd "$repo" && handoff-checkpoint "$root/$r.state.md" >/dev/null); done
sed -i 's/^## Next$/## Next\n1. copy the old rows\n2. rebuild the reports/' "$root/quiet.state.md"
sed -i 's/^by: .*/by: worker.one@host/; s/^updated: .*/updated: '"$(date -u -d '5 hours ago' +%Y-%m-%dT%H:%M:%SZ)"'/' "$root/quiet.state.md"
sed -i 's/^## Next$/## Next\n1. write the summary/' "$root/running.state.md"
sed -i 's/^## Next$/## Next\nNone./' "$root/finished.state.md"
mkdir -p "$repo/notes"; cp "$root/"{quiet,running,finished}.state.md "$repo/notes/"

# ---- Reach cards: one question, one decision, one plain status
card() { printf 'From: A <worker.a@host>\nTo: B <me@host>\nSubject: %s\nDate: Wed, 30 Sep 2026 08:00:00 +0000\nMessage-ID: <%s@x>\nX-Work: w-%s\nX-Type: %s\n\nbody\n' "$3" "$1" "$1" "$2" >"$root/cards/$1.eml"; printf '%s\t%s\n' "$root/cards/$1.eml" "$3" >>"$root/inbox"; }
: >"$root/inbox"
card q1 question '[question] Which database for billing?'
card d1 decision '[decision] Approve the rollout on Friday?'
card s1 completed '[completed] Report ready'

# ---- usage
status="$(run)"; [[ "$status" == 0 && "$(head -n1 "$root/out")" == usage:* ]] || fail 'no arguments print usage and exit 0'
status="$(run --help)"; [[ "$status" == 0 && "$(head -n1 "$root/out")" == usage:* ]] || fail '--help prints usage and exits 0'
status="$(run run --nope)"; [[ "$status" == 2 ]] || fail 'an unknown option exits 2'
status="$(run run --since banana --repo "$repo")"; [[ "$status" == 2 ]] || fail 'an unreadable --since exits 2'
ok 'usage: no arguments and --help exit 0, wrong input exits 2'

# ---- the page
status="$(run run --since 12h --repo "$repo" --as me@host)"
[[ "$status" == 0 ]] || fail "run exits 0 (got $status)"
for h in Done Stuck 'Needs you' Spend; do grep -qx "## $h" "$root/out" || fail "section $h is present"; done
(( $(wc -l <"$root/out") <= 60 )) || fail 'the page is at most 60 lines'
ok 'the page has the four sections and at most 60 lines'

done_="$(section Done)"; stuck="$(section Stuck)"; needs="$(section 'Needs you')"; spend="$(section Spend)"
grep -Fq '2 commits' <<<"$done_" || fail 'Done counts the two new commits'
grep -Fq 'add login page' <<<"$done_" && grep -Fq 'fix login redirect' <<<"$done_" || fail 'Done lists the new commit subjects'
! grep -Fq 'old work from days ago' "$root/out" || fail 'a commit older than the cutoff is not listed'
grep -Fq 'Ship the login page' <<<"$done_" && grep -Fq '2/2' <<<"$done_" || fail 'Done lists the delivered charter with 2/2 proven'
! grep -Fq 'Delivered long ago' "$root/out" || fail 'a charter delivered before the cutoff is not listed'
grep -Fq 'finished.state.md' <<<"$done_" || fail 'a progress record with nothing left is listed as finished'
grep -Fq 'running.state.md' <<<"$done_" || fail 'a fresh progress record with tasks left is listed as still going'
grep -F 'A very long charter title' <<<"$done_" | grep -Fq '...' && ! grep -Fq 'on and on and on and on and on and on and on and on and on and on' "$root/out" || fail 'a long charter title is cut with ...'
ok 'Done: new commits, delivered charters with n/m, finished and running records; nothing older than the cutoff'

grep -Fq 'Migrate the billing table' <<<"$stuck" || fail 'Stuck lists the released charter with unproven checks'
grep -Fq '1/3' <<<"$stuck" && grep -Eq 'check 2.*check 3|checks 2, 3' <<<"$stuck" || fail 'Stuck names the unproven check numbers (2 and 3) and 1/3'
grep -Fq 'quiet.state.md' <<<"$stuck" && grep -Fq '2 tasks left' <<<"$stuck" && grep -Fq 'worker.one@host' <<<"$stuck" || fail 'Stuck lists the record with tasks left that has been quiet for hours, with who and how many'
! grep -Fq 'running.state.md' <<<"$stuck" || fail 'a fresh record is not stuck'
ok 'Stuck: unproven checks by number, and records quiet for hours with tasks left'

grep -Fq 'Which database for billing?' <<<"$needs" && grep -Fq 'Approve the rollout on Friday?' <<<"$needs" || fail 'Needs you lists the question and the decision'
! grep -Fq 'Report ready' <<<"$needs" || fail 'a plain status card is not a request'
grep -Fq '1 other card' <<<"$needs" || fail 'other cards are counted'
ok 'Needs you: question and decision cards; other cards only counted'

grep -Fq '1 heartbeat' <<<"$spend" || fail 'Spend (or the page) states how many heartbeats are yours'
grep -Fq 'claude: 5-hour window 10% used, weekly 25% used' <<<"$spend" || fail 'Spend shows the claude 5-hour and weekly usage'
grep -Fq 'codex: weekly 52% used' <<<"$spend" && ! grep -Fq 'codex: 5-hour' <<<"$spend" || fail 'a vendor with only one window is shown as weekly, not shifted into the 5-hour slot'
grep -Fq 'no earlier reading' <<<"$spend" || fail 'the first run says there is no earlier reading'
ok 'Spend: usage now, first run says there is no earlier reading'

# folders that overlap (a repo and a --charters folder inside it, or the same folder twice) list a file once
status="$(cd "$repo" && run run --since 12h --repo "$repo" --charters "$repo/docs" --charters docs --charters ./docs)"
[[ "$(grep -c 'Ship the login page' "$root/out")" == 1 ]] || fail 'a charter found through overlapping folders is listed once'
[[ "$(grep -c 'quiet.state.md' "$root/out")" == 1 ]] || fail 'a progress record found through overlapping folders is listed once'
ok 'overlapping folders do not repeat a file'

# the second run compares with the stored reading
quota 28
status="$(run run --since 12h --repo "$repo" --as me@host)"
grep -Fq '+3' <<<"$(section Spend)" || fail 'the second run shows the change (+3) against the stored reading'
# a reading older than the cutoff is the baseline
printf '{"ts":"2026-09-01T00:00:00Z","vendor":"claude","five_hour":1,"weekly":10}\n' >"$root/state/away-brief/readings.jsonl"
status="$(run run --since 12h --repo "$repo")"
grep -Fq '+18' <<<"$(section Spend)" || fail 'the newest reading before the cutoff is the baseline (28 - 10)'
ok 'quota change is measured against the stored reading nearest before the cutoff'

# unreadable sources are named and the rest still prints
touch "$root/inbox-broken"
status="$(run run --since 12h --repo "$repo" --as me@host)"
[[ "$status" == 0 ]] && grep -Eq '^not read: Reach inbox .* -> ' "$root/out" && grep -qx '## Done' "$root/out" || fail 'a broken Reach inbox is named and the page still prints'
rm "$root/inbox-broken"
status="$(run run --since 12h --repo "$repo")"
grep -Eq '^not read: Reach inbox -> .*seat' "$root/out" || fail 'without a seat address the inbox is not read and says why'
printf 'not json' >"$root/quota"; printf 3 >"$root/quota.exit"
status="$(run run --since 12h --repo "$repo")"
[[ "$status" == 0 ]] && grep -Eq '^not read: quota .* -> ' "$root/out" || fail 'an unreadable quota is named'
rm -f "$root/quota.exit"; quota 25
status="$(run run --since 12h --repo "$root/not-a-repo")"
grep -Eq '^not read: .*not-a-repo' "$root/out" || fail 'a folder that is not a git work tree is named'
ok 'unreadable sources are named and never stop the page'

# reads only: nothing changes except the reading store
before="$( (cd "$repo" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum; git status --short; sha256sum "$root"/*.state.md) | sha256sum)"
run run --since 12h --repo "$repo" --as me@host >/dev/null
after="$( (cd "$repo" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum; git status --short; sha256sum "$root"/*.state.md) | sha256sum)"
[[ "$before" == "$after" ]] || fail 'a run changed a file in the repo or a progress record'
[[ -s "$root/state/away-brief/readings.jsonl" ]] || fail 'the reading store exists'
ok 'a run changes nothing but its own reading store'

# a long Done list must not push Needs you and Spend off the page
for n in $(seq 1 40); do
    (cd "$repo" && handoff-checkpoint "$repo/notes/many$n.state.md" >/dev/null)
    sed -i 's/^## Next$/## Next\nNone./' "$repo/notes/many$n.state.md"
done
quota 25
status="$(run run --since 12h --repo "$repo" --as me@host)"
(( $(wc -l <"$root/out") <= 60 )) || fail 'the page is at most 60 lines even with 40 more finished records'
grep -Fq 'Which database for billing?' <<<"$(section 'Needs you')" || fail 'the question that waits for the owner is still on the page'
grep -Fq 'claude' <<<"$(section Spend)" || fail 'the quota lines are still on the page'
grep -Eq 'and [0-9]+ more' <<<"$(section Done)" || fail 'what was left out of Done is counted in an "and N more" line'
grep -Fq 'Migrate the billing table' <<<"$(section Stuck)" || fail 'the stuck charter is still on the page'
rm -f "$repo"/notes/many*.state.md
ok 'each section has its own line budget, so a long Done list cannot push out Needs you or Spend'

# a quota reading with decimals must not end the page
mkdir -p "$root/state/away-brief"
printf '{"ts":"2026-09-01T00:00:00Z","vendor":"claude","five_hour":1,"weekly":40}\n' >"$root/state/away-brief/readings.jsonl"
quota 42.5
status="$(run run --since 12h --repo "$repo")"
[[ "$status" == 0 ]] && grep -Fq '(weekly +2.5 since' <<<"$(section Spend)" && grep -Fq 'weekly 42.5% used' <<<"$(section Spend)" || fail 'decimal usage is shown and its change is computed (42.5 - 40 = +2.5)'
quota 25
ok 'decimal quota readings are handled'

# seven waiting questions are all shown (the section budget counts, nothing is dropped silently)
cp "$root/inbox" "$root/inbox.keep"
for n in 1 2 3 4 5 6 7; do card "q$n" question "[question] Open question number $n?"; done
status="$(run run --since 12h --repo "$repo" --as me@host)"
[[ "$(grep -c 'Open question number' "$root/out")" == 7 ]] || fail 'all seven waiting questions are on the page'
cp "$root/inbox.keep" "$root/inbox"
ok 'every waiting question is shown within the section budget'

# a released charter whose proofs cannot be read (deliver-proof fails and prints nothing) is named, not dropped
mkdir -p "$root/bin-broken"; printf '#!/usr/bin/env bash\nexit 1\n' >"$root/bin-broken/deliver-proof"; chmod +x "$root/bin-broken/deliver-proof"
status=0; PATH="$root/bin-broken:$root/bin:$PATH" XDG_STATE_HOME="$root/state" SNO_REACH_ADDR= "$command_path" run --since 12h --repo "$repo" >"$root/out" 2>"$root/err" || status=$?
grep -Fq 'proofs could not be read: Migrate the billing table' <<<"$(section Stuck)" || fail 'a released charter whose proofs cannot be read is listed under Stuck, naming the file'
ok 'a charter whose proofs cannot be read is named under Stuck'

# a reading store that cannot be written must not end the page
printf 'a file, not a folder' >"$root/not-a-folder"
status=0; PATH="$root/bin:$PATH" XDG_STATE_HOME="$root/not-a-folder/inner" SNO_REACH_ADDR= "$command_path" run --since 12h --repo "$repo" >"$root/out" 2>"$root/err" || status=$?
[[ "$status" == 0 ]] && grep -qx '## Done' "$root/out" && grep -qx '## Spend' "$root/out" || fail 'the page still prints when the reading store cannot be written'
grep -Eq '^not stored: quota readings -> cannot write ' "$root/out" || fail 'the failure to store the readings is named on the page'
status=0; PATH="$root/bin:$PATH" XDG_STATE_HOME="$root/not-a-folder/inner" "$command_path" mark >"$root/out" 2>"$root/err" || status=$?
[[ "$status" == 1 ]] && grep -Eq '^not stored: quota readings -> cannot write ' "$root/out" || fail 'mark that cannot store anything says so and exits 1'
ok 'a reading store that cannot be written is named and does not end the page'

# a charter marked delivered whose proofs do not check out is not listed as done
charter "$repo/docs/liar.md" delivered 'Claims to be delivered' $'1. first\n2. second'
(cd "$repo/docs" && deliver-proof run liar.md 1 -- true >/dev/null; deliver-proof run liar.md 2 -- false >/dev/null || true)
status="$(run run --since 12h --repo "$repo")"
! grep -Fq 'charter delivered: Claims to be delivered' "$root/out" || fail 'a delivered charter with a failing proof is not listed as delivered'
grep -Fq 'marked delivered but its proofs do not check out: Claims to be delivered' <<<"$(section Stuck)" && grep -Fq '1/2' <<<"$(section Stuck)" || fail 'it is listed under Stuck with how many checks are proven'
rm -f "$repo/docs/liar.md"; rm -rf "$repo/docs/liar.proof"
ok 'a charter marked delivered with a failing proof goes under Stuck, not Done'

# mark stores a reading and prints one line
rm -rf "$root/state/away-brief"
status="$(run mark)"
[[ "$status" == 0 && "$(wc -l <"$root/out")" == 1 && "$(wc -l <"$root/state/away-brief/readings.jsonl")" == 2 ]] || fail 'mark stores one reading per vendor and prints one line'
ok 'mark stores a reading and prints one line'

printf '1..%s\n' "$count"
