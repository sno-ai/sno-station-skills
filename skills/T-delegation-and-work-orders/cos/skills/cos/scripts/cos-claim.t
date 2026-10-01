#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
claim="${COS_CLAIM_UNDER_TEST:-$script_dir/cos-claim.sh}"
root="$(mktemp -d)"
host="$(hostname)"
socket="cos-claim-$RANDOM"
signal="cos-claim-done-$RANDOM"
trap 'env -u TMUX tmux -L "$socket" kill-server >/dev/null 2>&1 || true; rm -r -- "$root"' EXIT

export SNO_REACH_ROOT="$root/reach"
export SNO_PL_REGISTRY="$root/registry.tsv"
export COS_CLAIM_HOST="$host"
mkdir -p "$root/example-repo"
cd "$root/example-repo"

printf 'TAP version 13\n'

bash "$claim" open example-repo >"$root/open.out"
if [[ "$(awk -F '\t' '$1 == "example-repo" && $2 == "all" &&
    $3 == "pl.example-repo@" h && $6 == "cos/example-repo" &&
    $7 == "RUN" {n++} END {print n+0}' h="$host" "$SNO_PL_REGISTRY")" == 1 ]] &&
   jq -e --arg address "cos.example-repo@$host" \
      '.address == $address and .role == "cos"' \
      "$SNO_REACH_ROOT/cos.example-repo@$host/seat.json" >/dev/null &&
   jq -e --arg address "pl.example-repo@$host" \
      '.address == $address and .role == "pl"' \
      "$SNO_REACH_ROOT/pl.example-repo@$host/seat.json" >/dev/null; then
    printf 'ok 1 - opening a lane records its COS and initializes both Reach seats\n'
else
    printf 'not ok 1 - opening a lane did not create its Reach seats and registry row\n'
    cat "$root/open.out"
    exit 1
fi

cp -- "$SNO_PL_REGISTRY" "$root/registry.before"
cp -- "$SNO_REACH_ROOT/pl.example-repo@$host/seat.json" "$root/seat.before"
bash "$claim" open example-repo >"$root/reopen.out"
if cmp -s "$SNO_PL_REGISTRY" "$root/registry.before" &&
   cmp -s "$SNO_REACH_ROOT/pl.example-repo@$host/seat.json" "$root/seat.before" &&
   [[ "$(bash "$claim" resolve example-repo)" == "pl.example-repo@$host" ]]; then
    printf 'ok 2 - repeated opening preserves the row and resolves the PL address\n'
else
    printf 'not ok 2 - repeated opening changed state or resolved the wrong seat\n'
    exit 1
fi

set +e
bash "$claim" open 'Bad repo' >"$root/invalid.out" 2>"$root/invalid.err"
invalid_rc=$?
set -e
if [[ "$invalid_rc" == 64 ]] &&
   cmp -s "$SNO_PL_REGISTRY" "$root/registry.before" &&
   grep -Fq 'not a routable token' "$root/invalid.err"; then
    printf 'ok 3 - an invalid address leaves the registry unchanged\n'
else
    printf 'not ok 3 - an invalid address changed the registry\n'
    exit 1
fi

printf 'From: COS <cos.example-repo@%s>\nCc: PL <pl.example-repo@%s>\nSubject: [FYI] Preserved task\nDate: %s\nMessage-ID: <claim-preserve-%s@%s>\nX-Work: example-work\nX-Type: info\n\nKeep this task.\n' \
    "$host" "$host" "$(date -u '+%a, %d %b %Y %H:%M:%S +0000')" \
    "$RANDOM" "$host" | sno reach send --as "cos.example-repo@$host"
jq '.updated = "1970-01-01T00:00:01Z"' \
    "$SNO_REACH_ROOT/pl.example-repo@$host/seat.json" >"$root/old-seat.json"
mv -- "$root/old-seat.json" "$SNO_REACH_ROOT/pl.example-repo@$host/seat.json"
bash "$claim" open example-repo next >"$root/next.out"
cc_card="$(sno reach inbox --as "pl.example-repo@$host" --cc |
    awk -F '\t' '$1 == "INFORMED-NOT-WORK" {print $2; exit}')"
if awk -F '\t' '$1 == "example-repo" && $2 == "all" && $7 == "RETIRED" {old=1}
                   $1 == "example-repo" && $2 == "next" && $7 == "RUN" {new=1}
                   END {exit !(old && new)}' "$SNO_PL_REGISTRY" &&
   [[ "$(bash "$claim" resolve example-repo)" == "pl.example-repo-next@$host" ]] &&
   [[ -f "$cc_card" ]] &&
   grep -Fq 'Subject: [FYI] Preserved task' "$cc_card"; then
    printf 'ok 4 - expired PL lease retires its row while Reach retains its card\n'
else
    printf 'not ok 4 - lease reclaim lost its row or Reach card\n'
    exit 1
fi

printf 'target\talpha\tpl.target-alpha@%s\ttarget-alpha\tcodex\tcos/alpha\tRUN\tAlpha lane.\n' \
    "$host" >>"$SNO_PL_REGISTRY"
printf 'target\tbeta\tpl.target-beta@%s\ttarget-beta\tcodex\tcos/beta\tRUN\tBeta lane.\n' \
    "$host" >>"$SNO_PL_REGISTRY"
cat >"$root/pane.sh" <<'PANE'
#!/usr/bin/env bash
set +e
bash "$CLAIM" register >"$ROOT/register.out" 2>"$ROOT/register.err"
registered=$?
bash "$CLAIM" claim target >"$ROOT/mixed.out" 2>"$ROOT/mixed.err"
mixed=$?
bash "$CLAIM" claim target --handover 'two owners agreed' \
    >"$ROOT/claim.out" 2>"$ROOT/claim.err"
claimed=$?
cp -- "$SNO_PL_REGISTRY" "$ROOT/claimed.tsv"
bash "$CLAIM" release target >"$ROOT/release.out" 2>"$ROOT/release.err"
released=$?
mkdir -p "$ROOT/unsafe"
cp -- "$SNO_PL_REGISTRY" "$ROOT/unsafe/registry-target.tsv"
cp -- "$ROOT/unsafe/registry-target.tsv" "$ROOT/unsafe/registry-before.tsv"
ln -s registry-target.tsv "$ROOT/unsafe/registry.tsv"
SNO_REACH_ROOT="$ROOT/unsafe-reach" \
    SNO_PL_REGISTRY="$ROOT/unsafe/registry.tsv" \
    bash "$CLAIM" register >"$ROOT/unsafe.out" 2>"$ROOT/unsafe.err"
unsafe=$?
printf '%s %s %s %s\n' "$registered" "$mixed" "$claimed" "$released" >"$ROOT/status"
printf '%s\n' "$unsafe" >"$ROOT/unsafe.status"
tmux wait-for -S "$SIGNAL"
sleep 60
PANE
export CLAIM="$claim" ROOT="$root" SIGNAL="$signal"
env -u TMUX tmux -L "$socket" new-session -d -s claim \
    -c "$root/example-repo" "bash '$root/pane.sh'"
env -u TMUX timeout 30 tmux -L "$socket" wait-for "$signal"
if [[ "$(<"$root/status")" == '0 65 0 0' ]] &&
   sno reach seats --json |
       jq -e --arg address "cos.example-repo@$host" \
           'select(.address == $address and .state == "live")' >/dev/null &&
   awk -F '\t' '$1 == "target" && $2 != "-" &&
                   $6 == "cos/example-repo" {n++} END {exit n != 2}' \
       "$root/claimed.tsv" &&
   awk -F '\t' '$1 == "target" && $2 != "-" &&
                   $6 == "unclaimed" {n++} END {exit n != 2}' \
       "$SNO_PL_REGISTRY"; then
    printf 'ok 5 - registered COS can claim mixed lanes with a reason and release them\n'
else
    printf 'not ok 5 - Reach registration or ownership change failed\n'
    cat "$root/register.err" "$root/mixed.err" "$root/claim.err" "$root/release.err"
    exit 1
fi

set +e
env -u TMUX -u TMUX_PANE -u ORCA_TAB_ID -u ORCA_TERMINAL_HANDLE \
    bash "$claim" claim target --handover outside \
    >"$root/outside.out" 2>"$root/outside.err"
outside_rc=$?
set -e
if [[ "$outside_rc" == 0 ]] &&
   awk -F '\t' '$1 == "target" && $2 != "-" && $6 == "cos/example-repo" {n++}
                   END {exit n != 2}' "$SNO_PL_REGISTRY" &&
   grep -Fq 'not reachable' "$root/outside.err"; then
    printf 'ok 6 - a shell without a window still claims and warns about reachability\n'
else
    printf 'not ok 6 - shell without a window failed to claim or warn\n'
    cat "$root/outside.err"
    exit 1
fi

if [[ "$(<"$root/unsafe.status")" == 0 ]] &&
   cmp -s "$root/unsafe/registry-target.tsv" "$root/unsafe/registry-before.tsv" &&
   grep -Fqx "cos-claim: registered address=cos.example-repo@$host owner=cos/example-repo" \
       "$root/unsafe.out" &&
   SNO_REACH_ROOT="$root/unsafe-reach" sno reach seats --json |
       jq -e --arg address "cos.example-repo@$host" \
           'select(.address == $address and .state == "live")' >/dev/null; then
    printf 'ok 7 - registry trouble does not prevent COS Reach registration\n'
else
    printf 'not ok 7 - registry trouble blocked COS Reach registration\n'
    cat "$root/unsafe.err"
    exit 1
fi

flock "$SNO_PL_REGISTRY.lock" bash -c 'touch "$1"; sleep 3' _ \
    "$root/lock-held" & lock_holder=$!
for _ in {1..50}; do
    [[ ! -f "$root/lock-held" ]] || break
    sleep 0.01
done
set +e
timeout 1 bash "$claim" show >"$root/locked-show.out" 2>"$root/locked-show.err"
show_rc=$?
timeout 1 bash "$claim" open example-repo side \
    >"$root/locked-open.out" 2>"$root/locked-open.err"
open_rc=$?
set -e
kill "$lock_holder" 2>/dev/null || true
wait "$lock_holder" 2>/dev/null || true
if [[ "$show_rc" == 0 && "$open_rc" == 65 ]] &&
   grep -Fq 'registry is busy' "$root/locked-open.err"; then
    printf 'ok 8 - registry lock cannot block a read or hold a writer waiting\n'
else
    printf 'not ok 8 - registry lock blocked a read or held a writer waiting\n'
    printf 'show=%s open=%s\n' "$show_rc" "$open_rc"
    cat "$root/locked-show.err" "$root/locked-open.err"
    exit 1
fi
flock -w 4 "$SNO_PL_REGISTRY.lock" true

mkdir -p "$root/bin" "$root/orca-repo" "$root/auto-repo" \
    "$root/collision-repo" "$root/stale-repo"
cat >"$root/bin/orca" <<'ORCA'
#!/usr/bin/env bash
printf '%s\n' '{"result":{"terminals":[{"connected":true,"handle":"term_test","tabId":"11111111-1111-4111-8111-111111111111"},{"connected":true,"handle":"term_other","tabId":"22222222-2222-4222-8222-222222222222"}]}}'
ORCA
chmod +x "$root/bin/orca"
export PATH="$root/bin:$PATH"
unset TMUX TMUX_PANE
export ORCA_TAB_ID=11111111-1111-4111-8111-111111111111
export ORCA_TERMINAL_HANDLE=term_test
printf 'orca-target\tall\tpl.orca-target@%s\torca-target\tcodex\tunclaimed\tRUN\tOrca lane.\n' \
    "$host" >>"$SNO_PL_REGISTRY"
cd "$root/orca-repo"
if ! bash "$claim" register >"$root/orca-register.out" 2>"$root/orca-register.err" ||
   ! bash "$claim" claim orca-target >"$root/orca-claim.out" 2>"$root/orca-claim.err"; then
    printf 'not ok 9 - Orca register or claim failed\n'
    cat "$root/orca-register.err" "$root/orca-claim.err" 2>/dev/null || true
    exit 1
fi
if jq -e '.channel == "orca" and .handle == "term_test" and
          .identity == {"kind":"orca-tab","value":"11111111-1111-4111-8111-111111111111"}' \
    "$SNO_REACH_ROOT/cos.orca-repo@$host/reachable.json" >/dev/null &&
   awk -F '\t' '$1 == "orca-target" && $6 == "cos/orca-repo" {found=1}
                  END {exit !found}' "$SNO_PL_REGISTRY"; then
    bash "$claim" release orca-target >"$root/orca-release.out" 2>"$root/orca-release.err"
    if awk -F '\t' '$1 == "orca-target" && $6 == "unclaimed" {found=1}
                     END {exit !found}' "$SNO_PL_REGISTRY"; then
        printf 'ok 9 - Orca register, claim and release write the expected state\n'
    else
        printf 'not ok 9 - Orca release did not clear ownership\n'
        exit 1
    fi
else
    printf 'not ok 9 - Orca registration or claim wrote the wrong state\n'
    exit 1
fi

printf 'auto-target\tall\tpl.auto-target@%s\tauto-target\tcodex\tunclaimed\tRUN\tAuto lane.\n' \
    "$host" >>"$SNO_PL_REGISTRY"
cd "$root/auto-repo"
bash "$claim" claim auto-target >"$root/auto-claim.out" 2>"$root/auto-claim.err"
if jq -e '.channel == "orca" and .handle == "term_test" and
          .identity == {"kind":"orca-tab","value":"11111111-1111-4111-8111-111111111111"}' \
    "$SNO_REACH_ROOT/cos.auto-repo@$host/reachable.json" >/dev/null &&
   awk -F '\t' '$1 == "auto-target" && $6 == "cos/auto-repo" {found=1}
                  END {exit !found}' "$SNO_PL_REGISTRY" &&
   grep -Fq 'registered' "$root/auto-claim.err"; then
    printf 'ok 10 - claim registers an unregistered Orca window\n'
else
    printf 'not ok 10 - claim failed to register an unregistered Orca window\n'
    exit 1
fi

printf 'collision-target\tall\tpl.collision-target@%s\tcollision-target\tcodex\tunclaimed\tRUN\tCollision lane.\n' \
    "$host" >>"$SNO_PL_REGISTRY"
cd "$root/collision-repo"
sno reach init --as "cos.collision-repo@$host" --name cos.collision-repo >/dev/null
sno reach register --as "cos.collision-repo@$host" --channel orca --handle term_other >/dev/null
cp -- "$SNO_PL_REGISTRY" "$root/collision.before"
set +e
bash "$claim" claim collision-target >"$root/collision.out" 2>"$root/collision.err"
collision_rc=$?
set -e
if [[ "$collision_rc" == 65 ]] &&
   cmp -s "$SNO_PL_REGISTRY" "$root/collision.before" &&
   grep -Fq 'live window' "$root/collision.err"; then
    printf 'ok 11 - a different live Orca window refuses without changing ownership\n'
else
    printf 'not ok 11 - a different live Orca window was not protected\n'
    cat "$root/collision.err"
    exit 1
fi

printf 'stale-target\tall\tpl.stale-target@%s\tstale-target\tcodex\tunclaimed\tRUN\tStale lane.\n' \
    "$host" >>"$SNO_PL_REGISTRY"
cd "$root/stale-repo"
sno reach init --as "cos.stale-repo@$host" --name cos.stale-repo >/dev/null
SNO_REACH_NOW=1000000000 sno reach register --as "cos.stale-repo@$host" \
    --channel orca --handle term_other >/dev/null
bash "$claim" claim stale-target >"$root/stale.out" 2>"$root/stale.err"
if jq -e '.channel == "orca" and .handle == "term_test" and
          .identity == {"kind":"orca-tab","value":"11111111-1111-4111-8111-111111111111"}' \
    "$SNO_REACH_ROOT/cos.stale-repo@$host/reachable.json" >/dev/null &&
   awk -F '\t' '$1 == "stale-target" && $6 == "cos/stale-repo" {found=1}
                  END {exit !found}' "$SNO_PL_REGISTRY" &&
   grep -Fq 'registered' "$root/stale.err"; then
    printf 'ok 12 - claim replaces a stale Orca registration\n'
else
    printf 'not ok 12 - claim did not replace a stale Orca registration\n'
    cat "$root/stale.err"
    exit 1
fi
printf '1..12\n'
