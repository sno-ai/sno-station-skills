#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(mktemp -d)"
session="a1-roster-$$"
trap 'tmux kill-session -t "$session" 2>/dev/null || true; rm -r -- "$root"' EXIT
host="$(hostname)"
export HOME="$root/home" SNO_REACH_ROOT="$root/reach"
mkdir -p "$HOME/.local/state" "$root/repo"
name="$(bash "$script_dir/callsign.sh" claim --journey j-roster --repo "$root/repo" --kind executor)"
jq -nc --arg name "$name" --arg repo "$root/repo" \
    '{callsign:$name,journey:"j-roster",repo:$repo,pid:999999,ack_due:"2020-01-01T00:00:00Z"}' \
    >"$HOME/.local/state/agent-spawns.jsonl"
sno reach init --as "pl.roster@$host" --name Lead >/dev/null
sno reach init --as "executor.roster@$host" --name Worker >/dev/null

bash "$script_dir/roster.sh" >"$root/before.out"
grep -Fq "NO-ACK: $name" "$root/before.out"

tmux new-session -d -s "$session" 'sleep 300'
sno reach register --as "pl.roster@$host" --channel tmux \
    --handle "$(tmux list-panes -t "$session" -F '#{pane_id}')" >/dev/null
cat >"$root/card.eml" <<CARD
From: Worker <executor.roster@$host>
To: Lead <pl.roster@$host>
Subject: [STATUS] on-station: $name
Date: $(date -R)
Message-ID: <roster-$(date +%s%N)@$host>
X-Work: j-roster
X-Type: status

The executor is on station.
CARD
sno reach send --no-ring --as "executor.roster@$host" <"$root/card.eml" >/dev/null
bash "$script_dir/roster.sh" >"$root/after.out"
! grep -Fq "NO-ACK: $name" "$root/after.out"
! grep -Fq 'REACH-READ-FAILED: j-roster' "$root/after.out"
# A card whose Subject holds raw non-ASCII text must not crash the roster.
utf_name="$(bash "$script_dir/callsign.sh" claim --journey j-utf --repo "$root/repo" --kind executor)"
jq -nc --arg name "$utf_name" --arg repo "$root/repo" \
    '{callsign:$name,journey:"j-utf",repo:$repo,pid:999999,ack_due:"2020-01-01T00:00:00Z"}' \
    >>"$HOME/.local/state/agent-spawns.jsonl"
{
  printf 'From: Worker <executor.roster@%s>\nTo: Lead <pl.roster@%s>\n' "$host" "$host"
  printf 'Subject: [STATUS] progress caf\xc3\xa9 \xe2\x80\x94 close-audit requested\n'
  printf 'Date: %s\nMessage-ID: <roster-utf-%s@%s>\nX-Work: j-utf\nX-Type: status\n\nUTF-8 subject.\n' \
    "$(date -R)" "$(date +%s%N)" "$host"
} >"$root/utf.eml"
sno reach send --no-ring --as "executor.roster@$host" <"$root/utf.eml" >/dev/null
bash "$script_dir/roster.sh" >"$root/utf.out" 2>"$root/utf.err"
grep -Fq "NO-ACK: $utf_name" "$root/utf.out"
! grep -Fq 'Traceback' "$root/utf.err"
printf 'not a Reach directory\n' >"$root/bad-store"
SNO_REACH_ROOT="$root/bad-store" bash "$script_dir/roster.sh" >"$root/bad.out"
grep -Fq 'REACH-READ-FAILED: j-roster' "$root/bad.out"
! grep -Fq "NO-ACK: $name" "$root/bad.out"
printf 'ok - Reach on-station card clears the roster acknowledgment alarm\n'
printf 'ok - a raw non-ASCII Subject does not crash the roster\n'
