#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
roster="${COS_ROSTER_UNDER_TEST:-$script_dir/cos-roster.sh}"
root="$(mktemp -d)"
host="$(hostname)"
socket="cos-roster-$RANDOM"
signal="cos-roster-ready-$RANDOM"
agent=''
trap '[[ -z "$agent" ]] || kill "$agent" 2>/dev/null || true; env -u TMUX tmux -L "$socket" kill-server >/dev/null 2>&1 || true; rm -r -- "$root"' EXIT
export SNO_REACH_ROOT="$root/reach"

mkdir -p \
    "$root/cos/skills/cos/scripts" \
    "$root/cos/skills/cos/references" \
    "$root/home/.local/state"
ln -s "$roster" "$root/cos/skills/cos/scripts/cos-roster.sh"
mkdir -p "$root/checkouts/example-repo"
git -C "$root/checkouts/example-repo" init -q
printf '# Tasks\n\n## OPEN\n\n- Read the relocated board.\n' >"$root/checkouts/example-repo/TODO.md"
cat >"$root/home/.local/state/pl-registry.tsv" <<EOF
home_repo	lane	reach_address	heartbeat_name	runtime	owning_cos	state	note
example-repo	-	cos.example-repo@$host	example-repo-cos	codex	cos/example-repo	RUN	COS identity.
example-repo	all	pl.example-repo@$host	example-repo	claw	cos/example-repo	RUN	PL lane.
example-repo	old	pl.example-repo-old@$host	example-repo-old	another-universe	cos/example-repo	RETIRED	Expired PL lane.
EOF
sno reach init --as "pl.example-repo@$host" --name pl.example-repo >/dev/null

printf 'TAP version 13\n'

set +e
cd "$root/checkouts/example-repo"
HOME="$root/home" \
    bash "$root/cos/skills/cos/scripts/cos-roster.sh" \
    --cos cos/example-repo --json >"$root/roster.json" 2>"$root/roster.err"
rc=$?
set -e

if [[ "$rc" == 0 ]] &&
   jq -e --arg board "$root/checkouts/example-repo/TODO.md" --arg address "pl.example-repo@$host" '
       .cos == "cos/example-repo" and
       .capacity.live_owned == 0 and
       (.pls | length) == 1 and
       .pls[0].lane == "all" and
       .pls[0].address == $address and
       .pls[0].state == "NONE" and
       .pls[0].windows == 0 and
       .pls[0].open_board.path == $board and
       .pls[0].open_board.open_count == 1 and
       .pls[0].open_board.items == ["Read the relocated board."]
   ' "$root/roster.json" >/dev/null; then
    printf 'ok 1 - roster ignores runtime labels and excludes COS identity rows\n'
else
    printf 'not ok 1 - runtime-neutral COS identity exclusion from PL roster\n'
    sed 's/^/# stdout: /' "$root/roster.json"
    sed 's/^/# stderr: /' "$root/roster.err"
    exit 1
fi

printf -v pane_command \
    'sno reach register --as %q --channel tmux --handle "$TMUX_PANE" >%q 2>%q; tmux wait-for -S %q; sleep 60' \
    "pl.example-repo@$host" "$root/seat.out" "$root/seat.err" "$signal"
env -u TMUX tmux -L "$socket" new-session -d -s roster "$pane_command"
env -u TMUX timeout 10 tmux -L "$socket" wait-for "$signal"
HOME="$root/home" \
    bash "$root/cos/skills/cos/scripts/cos-roster.sh" \
    --cos cos/example-repo --json >"$root/registered.json" 2>"$root/registered.err"
if jq -e --arg address "pl.example-repo@$host" \
    '.pls[0].state == "CHECK" and .pls[0].watchers[$address] == 1' \
    "$root/registered.json" >/dev/null; then
    printf 'ok 2 - live Reach registration remains reachable outside a Codex turn\n'
else
    printf 'not ok 2 - live Reach seat was treated as unable to receive cards\n'
    cat "$root/seat.err" "$root/registered.err" "$root/registered.json"
    exit 1
fi
env -u TMUX tmux -L "$socket" kill-server
sno reach unregister --as "pl.example-repo@$host" >/dev/null

mkdir -p "$root/home/.local/state/pl-heartbeat"
touch "$root/home/.local/state/pl-heartbeat/example-repo"
(
    cd "$root/checkouts/example-repo"
    exec -a codex sleep 60
) &
agent=$!
HOME="$root/home" \
    bash "$root/cos/skills/cos/scripts/cos-roster.sh" \
    --cos cos/example-repo --json >"$root/unregistered.json" 2>"$root/unregistered.err"
kill "$agent"
wait "$agent" 2>/dev/null || true
agent=''
if jq -e '.pls[0].state == "UNREACHABLE" and .pls[0].windows >= 1 and
          .pls[0].watchers == {}' "$root/unregistered.json" >/dev/null; then
    printf 'ok 3 - a fresh heartbeat cannot hide a missing Reach registration\n'
else
    printf 'not ok 3 - heartbeat hid a missing Reach registration\n'
    cat "$root/unregistered.err" "$root/unregistered.json"
    exit 1
fi
rm -- "$root/home/.local/state/pl-heartbeat/example-repo"

mkdir -p "$root/checkouts/example-repo/nested/ai-doc/JOURNAL"
printf '{"ts":"%s"}\n' "$(date -u -d '+1 hour' '+%Y-%m-%dT%H:%M:%SZ')" \
    >"$root/checkouts/example-repo/nested/ai-doc/JOURNAL/routing-ledger.jsonl"
HOME="$root/home" \
    bash "$root/cos/skills/cos/scripts/cos-roster.sh" \
    --cos cos/example-repo --json >"$root/nested-ledger.json" 2>"$root/nested-ledger.err"
if jq -e '.pls[0].board_stale == null' "$root/nested-ledger.json" >/dev/null; then
    printf 'ok 4 - nested ai-doc path is ignored\n'
else
    printf 'not ok 4 - nested ai-doc path changed board status\n'
    cat "$root/nested-ledger.json" "$root/nested-ledger.err"
    exit 1
fi

mkdir -p "$root/checkouts/example-repo/ai-doc/JOURNAL"
cp -- "$root/checkouts/example-repo/nested/ai-doc/JOURNAL/routing-ledger.jsonl" \
    "$root/checkouts/example-repo/ai-doc/JOURNAL/routing-ledger.jsonl"
HOME="$root/home" \
    bash "$root/cos/skills/cos/scripts/cos-roster.sh" \
    --cos cos/example-repo --json >"$root/root-ledger.json" 2>"$root/root-ledger.err"
if jq -e '.pls[0].board_stale == ["TODO.md"]' "$root/root-ledger.json" >/dev/null; then
    printf 'ok 5 - repo-root ai-doc path marks the older board stale\n'
else
    printf 'not ok 5 - repo-root ai-doc path was ignored\n'
    cat "$root/root-ledger.json" "$root/root-ledger.err"
    exit 1
fi

set +e
SNO_OWNER_ADDR="owner.primary@$host" HOME="$root/home" \
    bash "$root/cos/skills/cos/scripts/cos-roster.sh" \
    --cos cos/example-repo --json >"$root/owner-unavailable.json" 2>"$root/owner-unavailable.err"
rc=$?
set -e
if [[ "$rc" == 3 ]] &&
   jq -e '.observation_complete == false and .pls[0].state == "UNKNOWN" and
          (.anomalies | any(startswith("MAILBOX OBSERVATION FAILED")))' \
      "$root/owner-unavailable.json" >/dev/null; then
    printf 'ok 6 - configured owner seat failure is visible in the roll call\n'
else
    printf 'not ok 6 - configured owner seat was ignored\n'
    cat "$root/owner-unavailable.json" "$root/owner-unavailable.err"
    exit 1
fi

for lane in second third fourth; do
    printf 'example-repo\t%s\tpl.example-repo-%s@'"$host"'\texample-repo-%s\tcodex\tcos/example-repo\tRUN\t\n' \
        "$lane" "$lane" "$lane" >>"$root/home/.local/state/pl-registry.tsv"
    sno reach init --as "pl.example-repo-$lane@$host" \
        --name "pl.example-repo-$lane" >/dev/null
done
set +e
HOME="$root/home" \
    bash "$root/cos/skills/cos/scripts/cos-roster.sh" \
    --cos cos/example-repo --json >"$root/over-cap.json" 2>"$root/over-cap.err"
rc=$?
set -e
if [[ "$rc" == 0 ]] && jq -e '(.pls | length) == 4' "$root/over-cap.json" >/dev/null; then
    printf 'ok 7 - excess capacity and missing rationale do not hide the roster\n'
else
    printf 'not ok 7 - excess capacity hid the roster\n'
    printf "exit=%s\n" "$rc"
    cat "$root/over-cap.json" "$root/over-cap.err"
    exit 1
fi
printf '1..7\n'
