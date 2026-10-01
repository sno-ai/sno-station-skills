#!/usr/bin/env bash
# E2E suite for `callsign.sh transfer` — one agent keeping its name across
# successive journeys.
# Every test: arrange → act → assert, explicit PASS/FAIL, summary at end.
#
# Isolation: callsign.sh derives its ledger from $HOME, so each test runs under a
# throwaway HOME. Nothing touches the real machine-wide ledger.
set -u
REAL_HOME="$HOME"
CS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/callsign.sh"
BASE="${TMPDIR:-/tmp}/callsign-transfer-e2e-$$"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL  $1  -- $2"; }
fresh() { export HOME="$BASE/$1"; rm -rf "$HOME"; mkdir -p "$HOME/.local/state"; }
ledger() { echo "$HOME/.local/state/agent-callsigns.jsonl"; }
active_journey() { # active_journey <name>
  grep -F "\"name\":\"$1\"" "$(ledger)" | tail -1 |
    sed -n 's/.*"journey":"\([^"]*\)".*/\1/p'
}
last_event() { grep -F "\"name\":\"$1\"" "$(ledger)" | tail -1 |
    sed -n 's/.*"event":"\([^"]*\)".*/\1/p'; }

# ---------- T1 happy path: the name survives, the journey moves ----------
fresh t1
N=$($CS claim --journey j-one --repo /r/demo --kind executor --label first)
$CS transfer "$N" --from j-one --to j-two >/dev/null 2>&1; RC=$?
[ $RC -eq 0 ] && ok "T1a transfer exits 0" || bad "T1a" "rc=$RC"
[ "$(active_journey "$N")" = "j-two" ] && ok "T1b journey moved to j-two" \
  || bad "T1b" "journey=$(active_journey "$N")"
[ "$(last_event "$N")" = "claim" ] && ok "T1c still active (last event is claim)" \
  || bad "T1c" "last=$(last_event "$N")"
$CS list | grep -q "$N .*j-two" && ok "T1d list shows the new journey" \
  || bad "T1d" "$($CS list | grep "$N")"

# ---------- T2 the name is NEVER free mid-transfer (no release event) ----------
grep -F "\"name\":\"$N\"" "$(ledger)" | grep -q '"event":"release"' \
  && bad "T2 no release during transfer" "a release event was written" \
  || ok "T2 no release event — the name is never free, so it cannot be raced"

# ---------- T3 context carried forward, provenance recorded ----------
LINE=$(grep -F "\"name\":\"$N\"" "$(ledger)" | tail -1)
echo "$LINE" | grep -q '"repo":"/r/demo"' && ok "T3a repo carried forward" || bad "T3a" "$LINE"
echo "$LINE" | grep -q '"kind":"executor"' && ok "T3b kind carried forward" || bad "T3b" "$LINE"
echo "$LINE" | grep -q '"label":"first"'   && ok "T3c label carried forward" || bad "T3c" "$LINE"
echo "$LINE" | grep -q '"transferred_from":"j-one"' && ok "T3d provenance recorded" || bad "T3d" "$LINE"

# ---------- T4 theft prevention: a non-holder cannot hand the name on ----------
BEFORE=$(wc -l < "$(ledger)")
OUT=$($CS transfer "$N" --from j-one --to j-evil 2>&1); RC=$?
AFTER=$(wc -l < "$(ledger)")
[ $RC -eq 5 ] && ok "T4a stale holder refused with exit 5" || bad "T4a" "rc=$RC out=$OUT"
[ "$BEFORE" = "$AFTER" ] && ok "T4b refused transfer did not mutate the ledger" \
  || bad "T4b" "$BEFORE -> $AFTER"
[ "$(active_journey "$N")" = "j-two" ] && ok "T4c holder unchanged after refusal" \
  || bad "T4c" "journey=$(active_journey "$N")"

# ---------- T5 a released name is NOT transferable (no identity resurrection) ----------
fresh t5
M=$($CS claim --journey j-a --repo /r/demo --kind executor)
$CS release "$M" --journey j-a
OUT=$($CS transfer "$M" --from j-a --to j-b 2>&1); RC=$?
[ $RC -eq 4 ] && ok "T5a released name refused with exit 4" || bad "T5a" "rc=$RC out=$OUT"
[ "$(last_event "$M")" = "release" ] && ok "T5b name stays released" \
  || bad "T5b" "last=$(last_event "$M")"

# ---------- T6 release ownership follows the transfer ----------
fresh t6
K=$($CS claim --journey j-p --repo /r/demo --kind executor)
$CS transfer "$K" --from j-p --to j-q >/dev/null
OUT=$($CS release "$K" --journey j-p 2>&1); RC=$?
[ $RC -eq 5 ] && ok "T6a the OLD journey can no longer release it (exit 5)" || bad "T6a" "rc=$RC out=$OUT"
$CS release "$K" --journey j-q >/dev/null 2>&1; RC=$?
[ $RC -eq 0 ] && ok "T6b the NEW journey can release it" || bad "T6b" "rc=$RC"

# ---------- T7 argument validation ----------
fresh t7
Z=$($CS claim --journey j-x --repo /r/demo --kind executor)
$CS transfer "$Z" --from j-x --to j-x >/dev/null 2>&1; RC=$?
[ $RC -eq 2 ] && ok "T7a same --from/--to refused (exit 2)" || bad "T7a" "rc=$RC"
$CS transfer "$Z" --from j-x >/dev/null 2>&1; RC=$?
[ $RC -eq 2 ] && ok "T7b missing --to refused (exit 2)" || bad "T7b" "rc=$RC"
$CS transfer --from j-x --to j-y >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && ok "T7c missing name refused" || bad "T7c" "rc=$RC"

# ---------- T8 title state persists under the new journey ----------
fresh t8
T=$($CS claim --journey j-old --repo /r/demo --kind executor)
$CS transfer "$T" --from j-old --to j-new >/dev/null
OUT=$($CS title run "$T" --journey j-new "working" 2>&1); RC=$?
[ $RC -eq 0 ] && ok "T8a title persists under the new journey" || bad "T8a" "rc=$RC out=$OUT"
OUT=$($CS title run "$T" --journey j-old "stale" 2>&1); RC=$?
[ $RC -ne 0 ] && ok "T8b title from the OLD journey is refused" || bad "T8b" "rc=$RC out=$OUT"

# ---------- T9 the pool comes from the shared database beside the skill ----------
fixture="$BASE/t9/skill"
mkdir -p "$fixture/scripts" "$fixture/references" "$BASE/t9/home/.local/state"
cp "$CS" "$fixture/scripts/callsign.sh"
printf 'meteor\ncedar\n' > "$fixture/references/callsigns.txt"
OUT=$(HOME="$BASE/t9/home" bash "$fixture/scripts/callsign.sh" claim \
  --journey j-db --repo /r/demo --kind executor 2>&1); RC=$?
if [ $RC -eq 0 ] && [ "$OUT" = meteor ]; then
  ok "T9 shared database supplies the first callsign"
else
  bad "T9" "rc=$RC out=$OUT"
fi

# ---------- T10 an invalid database fails closed before recording a claim ----------
fixture="$BASE/t10/skill"
mkdir -p "$fixture/scripts" "$fixture/references" "$BASE/t10/home/.local/state"
cp "$CS" "$fixture/scripts/callsign.sh"
printf 'valid\nbad name\n' > "$fixture/references/callsigns.txt"
OUT=$(HOME="$BASE/t10/home" bash "$fixture/scripts/callsign.sh" claim \
  --journey j-invalid --repo /r/demo --kind executor 2>&1); RC=$?
if [ $RC -ne 0 ] && [ ! -s "$BASE/t10/home/.local/state/agent-callsigns.jsonl" ]; then
  ok "T10 invalid database is refused before a claim is recorded"
else
  bad "T10" "rc=$RC out=$OUT"
fi

# ---------- T11 COS and PL lease distinct names from one pool and ledger ----------
fresh t11
PL_NAME=$($CS claim --repo /r/demo --kind pl --label "demo PL" 2>&1); PL_RC=$?
COS_NAME=$($CS claim --repo /r/demo --kind cos --label "demo COS" 2>&1); COS_RC=$?
if [ $PL_RC -eq 0 ] && [ $COS_RC -eq 0 ] && [ "$PL_NAME" != "$COS_NAME" ]; then
  ok "T11a COS and PL receive distinct callsigns"
else
  bad "T11a" "pl_rc=$PL_RC pl=$PL_NAME cos_rc=$COS_RC cos=$COS_NAME"
fi
PL_RECORDS=$(grep -c '"kind":"pl"' "$(ledger)" || true)
COS_RECORDS=$(grep -c '"kind":"cos"' "$(ledger)" || true)
if [ "$PL_RECORDS" -eq 1 ] && [ "$COS_RECORDS" -eq 1 ]; then
  ok "T11b both claims share one machine-wide ledger"
else
  bad "T11b" "pl_records=$PL_RECORDS cos_records=$COS_RECORDS"
fi

# ---------- T12 concurrent COS and PL claims cannot receive the same name ----------
fresh t12
$CS claim --repo /r/demo --kind pl --label "demo PL" > "$HOME/pl.out" 2> "$HOME/pl.err" &
PL_PID=$!
$CS claim --repo /r/demo --kind cos --label "demo COS" > "$HOME/cos.out" 2> "$HOME/cos.err" &
COS_PID=$!
wait "$PL_PID"; PL_RC=$?
wait "$COS_PID"; COS_RC=$?
PL_NAME=$(<"$HOME/pl.out")
COS_NAME=$(<"$HOME/cos.out")
if [ $PL_RC -eq 0 ] && [ $COS_RC -eq 0 ] \
  && [ -n "$PL_NAME" ] && [ -n "$COS_NAME" ] && [ "$PL_NAME" != "$COS_NAME" ]; then
  ok "T12a concurrent COS and PL claims receive distinct callsigns"
else
  bad "T12a" "pl_rc=$PL_RC pl=$PL_NAME cos_rc=$COS_RC cos=$COS_NAME"
fi
ACTIVE_NAMES=$(awk -F'"' '/"event":"claim"/ { for (i=1; i<NF; i++) if ($i == "name") print $(i+2) }' \
  "$(ledger)" | sort -u | wc -l)
if [ "$ACTIVE_NAMES" -eq 2 ]; then
  ok "T12b concurrent claims leave two unique active names in the shared ledger"
else
  bad "T12b" "unique_active_names=$ACTIVE_NAMES"
fi

export HOME="$REAL_HOME"
rm -rf "$BASE"
echo
echo "----- callsign transfer e2e: $PASS passed, $FAIL failed -----"
[ "$FAIL" -eq 0 ]
