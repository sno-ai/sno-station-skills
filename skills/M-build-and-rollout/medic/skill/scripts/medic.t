#!/usr/bin/env bash
# Behaviour test for medic: a real fake HOME (skills, hook files), real jq/git/tmux/df; only the external
# programs sno, heartbeat, subscription-quota-check, claude and codex are minimal stand-ins.
set -Eeuo pipefail

command_path="$(realpath -- "${1:-$(dirname -- "${BASH_SOURCE[0]}")/medic}")"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
count=0
ok() { count=$((count + 1)); printf 'ok %s - %s\n' "$count" "$1"; }
fail() { printf 'not ok %s - %s\n' "$((count + 1))" "$1"; [[ -s "$root/out" ]] && sed 's/^/# out: /' "$root/out"; [[ -s "$root/err" ]] && sed 's/^/# err: /' "$root/err"; exit 1; }
run() { local status=0; PATH="$root/bin:/usr/bin:/bin" HOME="$root/home" SNO_REACH_ADDR="${SNO_REACH_ADDR-me.main@box}" "$command_path" "$@" >"$root/out" 2>"$root/err" || status=$?; printf '%s' "$status"; }
has() { grep -Eq -- "$1" "$root/out"; }

mkdir -p "$root/bin" "$root/home"
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$root/bin/$1"; chmod +x "$root/bin/$1"; }
make_sno() { stub sno 'case "$1 $2" in
  "doctor --json") cat "$FX/doctor.json" ;;
  "reach seats") cat "$FX/seats.jsonl" ;;
  "reach --version") echo 2.0.4 ;;
  *) exit 64 ;;
esac'
  sed -i "2i FX=$root/fx" "$root/bin/sno"; }
make_sno
stub heartbeat 'if [[ "${1:-}" == --list ]]; then cat '"$root"'/fx/heartbeats; else echo usage; fi'
stub subscription-quota-check 'vendor=""; while (( $# )); do [[ "$1" == --vendor ]] && vendor="$2"; shift; done; cat '"$root"'/fx/quota-"$vendor"; exit "$(cat '"$root"'/fx/quota-"$vendor".exit 2>/dev/null || echo 0)"'
for c in claude codex; do stub "$c" 'exit 0'; done
for c in deliver-proof handoff-checkpoint rotate-agent-resume rem-reflect; do stub "$c" 'exit 0'; done

good_setup() {
    make_sno
    rm -rf "$root/fx" "$root/home"; mkdir -p "$root/fx" "$root/home/.claude/skills" "$root/home/.agents/skills"
    for s in reach heartbeat join-talk handoff deliver charter; do
        for d in .claude .agents; do mkdir -p "$root/home/$d/skills/$s"; printf -- '---\nname: %s\n---\n' "$s" >"$root/home/$d/skills/$s/SKILL.md"; done
    done
    cat >"$root/fx/doctor.json" <<'J'
{"acp":[{"target":"claude","result":"warn","detail":"live handshake unverified"}],
 "hooks":[{"target":"claude configured","result":"ok","detail":""},{"target":"claude execution","result":"warn","detail":"no execution evidence"},{"target":"codex configured","result":"ok","detail":""},{"target":"codex trust","result":"ok","detail":""}],
 "reach":[{"target":"reach","result":"ok","detail":""}],
 "skills":[{"target":"reach/SKILL.md","result":"ok","detail":""},{"target":"handoff/SKILL.md","result":"ok","detail":""}]}
J
    printf '{"address":"me.main@box","channel":"tmux","handle":"x","state":"live"}\n{"address":"old.one@box","channel":"tmux","handle":"y","state":"stale"}\n' >"$root/fx/seats.jsonl"
    printf 'WHO  OWNER LABEL PID LOG\nyou  o1 nightly 123 /tmp/x.log\n' >"$root/fx/heartbeats"
    for v in claude codex; do printf '{"vendors":[{"vendor":"%s","verdict":"go"}]}\n' "$v" >"$root/fx/quota-$v"; done
    for c in deliver-proof handoff-checkpoint rotate-agent-resume rem-reflect claude codex; do stub "$c" 'exit 0'; done
    stub heartbeat 'if [[ "${1:-}" == --list ]]; then cat '"$root"'/fx/heartbeats; else echo usage; fi'
}
tree_hash() { (cd -- "$root/home" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum); }

# usage
good_setup
status="$(run)"; [[ "$status" == 0 && "$(head -n1 "$root/out")" == usage:* ]] || fail 'no arguments print usage and exit 0'
status="$(run --help)"; [[ "$status" == 0 && "$(head -n1 "$root/out")" == usage:* ]] || fail '--help prints usage and exits 0'
status="$(run run --nope)"; [[ "$status" == 2 ]] || fail 'an unknown option exits 2'
status="$(run frobnicate)"; [[ "$status" == 2 ]] || fail 'an unknown word exits 2'
ok 'usage: no arguments and --help exit 0, wrong input exits 2'

# healthy fixture: every line is OK, summary is last, exit 0, and nothing under HOME changed
good_setup; before="$(tree_hash)"
status="$(run run)"
[[ "$status" == 0 ]] || fail "healthy fixture exits 0 (got $status)"
! grep -Eq '^(WARN|FAIL) ' "$root/out" || fail 'healthy fixture has no WARN or FAIL'
for check in tools agent-cli skills commands hooks reach skill-files seat heartbeat quota temp-space; do
    has "^OK $check: " || fail "healthy fixture has an OK line for $check"
done
[[ "$(tail -n1 "$root/out")" =~ ^MEDIC\ ok=[0-9]+\ warn=0\ fail=0$ ]] || fail 'last line is the summary'
[[ "$(tree_hash)" == "$before" ]] || fail 'a run changed a file under HOME'
ok 'healthy fixture: one OK line per check, summary last, exit 0, nothing under HOME changed'

expect_line() { # level check fragment description ; expects a line "LEVEL check: ... fragment ... -> <fix>"
    grep -Eq "^$1 $2: .*$3.* -> .+" "$root/out" || fail "$4"
}

good_setup; rm "$root/bin/heartbeat"
status="$(run run)"; [[ "$status" == 1 ]] && expect_line FAIL tools heartbeat 'a missing required tool is FAIL tools naming it, exit 1' || fail 'missing tool: exit 1 and FAIL tools naming it'
good_setup; rm "$root/bin/sno"
run run >/dev/null
grep -Eq '^WARN seat: not checked, sno is missing' "$root/out" || fail 'a check names only the program that is actually missing'
for c in hooks reach skill-files; do grep -Eq "^WARN $c: not checked, sno is missing" "$root/out" || fail "$c says it was not checked because sno is missing"; done
good_setup; rm "$root/bin/claude" "$root/bin/codex"
status="$(run run)"; [[ "$status" == 1 ]] && expect_line FAIL agent-cli 'neither claude nor codex' 'no agent CLI' || fail 'no agent CLI: exit 1 and FAIL agent-cli'
ok 'FAIL for a missing tool and for having no agent CLI'

good_setup; rm -r "$root/home/.claude/skills/charter" "$root/home/.claude/skills/join-talk" "$root/home/.agents/skills/deliver"
status="$(run run)"; [[ "$status" == 0 ]] || fail 'a missing skill is a WARN, exit 0'
expect_line WARN skills 'join-talk, charter' 'names the skills missing for claude'
expect_line WARN skills 'deliver' 'names the skill missing for codex'
grep -q ',  ' "$root/out" && fail 'a list in a line is joined with one space after each comma'
good_setup; stub rem-reflect 'exit 3'; rm "$root/bin/deliver-proof"
run run >/dev/null; expect_line WARN commands 'deliver-proof' 'names the missing command'; expect_line WARN commands 'rem-reflect' 'names the command that does not run'
ok 'WARN names each missing skill and each command that is missing or fails'

good_setup; sed -i 's/"claude configured","result":"ok"/"claude configured","result":"missing"/' "$root/fx/doctor.json"
run run >/dev/null; expect_line WARN hooks 'claude' 'hooks not configured for claude'
good_setup; sed -i 's/"reach","result":"ok","detail":""/"reach","result":"fail","detail":"run: sno update"/' "$root/fx/doctor.json"
status="$(run run)"; [[ "$status" == 1 ]] && grep -Eq '^FAIL reach: .* -> run: sno update$' "$root/out" || fail 'sno doctor reach failure is FAIL reach with its own fix, exit 1'
good_setup; sed -i 's#"handoff/SKILL.md","result":"ok"#"handoff/SKILL.md","result":"fail"#' "$root/fx/doctor.json"
run run >/dev/null; expect_line WARN skill-files 'handoff/SKILL.md' 'names the skill file that failed'
good_setup; sed -i 's/"codex trust","result":"ok"/"codex trust","result":"changed"/' "$root/fx/doctor.json"
run run >/dev/null; expect_line WARN hooks 'codex trust is changed' 'a codex hook whose trust changed is named'
good_setup; rm "$root/bin/codex"; sed -i 's/"codex trust","result":"ok"/"codex trust","result":"changed"/; s/"codex configured","result":"ok"/"codex configured","result":"missing"/' "$root/fx/doctor.json"
status="$(run run)"; ! grep -q 'codex' "$root/out" || fail 'a vendor that is not installed is not checked for hooks, skills or quota'
[[ "$status" == 0 ]] || fail 'with only claude installed and healthy the run exits 0'
good_setup; printf '{"error":"doctor failed halfway"}\n' >"$root/fx/doctor.json"
status="$(run run)"
for c in hooks reach skill-files; do grep -Eq "^WARN $c: sno doctor gave no usable answer" "$root/out" || fail "an answer from sno doctor without the $c results is not read as OK"; done
! grep -Eq '^OK (hooks|reach|skill-files): ' "$root/out" || fail 'an incomplete doctor answer produces no OK line'
good_setup; printf 'not json\n' >"$root/fx/doctor.json"
run run >/dev/null; expect_line WARN hooks 'sno doctor' 'an unreadable sno doctor is reported, not swallowed'
ok 'sno doctor findings become hooks, reach and skill-files lines'

good_setup; printf '{"address":"old.one@box","channel":"tmux","handle":"y","state":"stale"}\n' >"$root/fx/seats.jsonl"
run run >/dev/null; expect_line WARN seat 'me.main@box' 'own seat missing or stale is named'
status="$(SNO_REACH_ADDR='' run run)"; expect_line WARN seat 'no live seat' 'no live seat at all'
good_setup; status="$(SNO_REACH_ADDR='' run run)"; has '^OK seat: 1 live seat\(s\)' || fail 'without a seat address, one live seat is enough'
good_setup; printf 'WHO  OWNER                    LABEL                PID      LOG\n(no heartbeat is running)\n' >"$root/fx/heartbeats"
run run >/dev/null; expect_line WARN heartbeat 'no heartbeat' 'no heartbeat running'
ok 'WARN for a stale or absent seat and for no heartbeat'

good_setup; printf '{"vendors":[{"vendor":"claude","verdict":"wait"}]}\n' >"$root/fx/quota-claude"; printf 'garbage\n' >"$root/fx/quota-codex"
run run >/dev/null; expect_line WARN quota 'claude' 'wait verdict is a WARN naming claude'; expect_line WARN quota 'codex' 'unreadable quota is a WARN naming codex'
good_setup; status="$(run run --min-free-mb 99999999999)"; expect_line WARN temp-space 'free' 'low temp space'
# the quota reader exits 1 when a vendor is blocked but still prints the verdict: that verdict must be read
good_setup; printf '{"vendors":[{"vendor":"claude","verdict":"wait"}]}\n' >"$root/fx/quota-claude"; printf 1 >"$root/fx/quota-claude.exit"
run run >/dev/null; expect_line WARN quota 'claude quota reads wait' 'a blocked vendor (reader exits 1) is reported as wait, not as unreadable'
! grep -q 'unknown' "$root/out" || fail 'the verdict is not polluted by a fallback word'
good_setup; printf '{"vendors":[{"vendor":"claude","verdict":"go"}]}\n' >"$root/fx/quota-claude"; printf 1 >"$root/fx/quota-claude.exit"
run run >/dev/null; has '^OK quota: claude quota reads go' || fail 'a usable verdict is read even when the reader exits non-zero'
ok 'WARN for a refused quota, an unreadable quota and low temp space'

good_setup; rm -r "$root/home/.claude/skills/charter"; before="$(tree_hash)"; run run >/dev/null
[[ "$(tree_hash)" == "$before" ]] || fail 'a run with problems changes no file (checks only)'
ok 'checks only: a run with problems repairs nothing'

printf '1..%s\n' "$count"
