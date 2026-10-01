#!/usr/bin/env bash
# Behaviour test for catch-report on real record files with hand-computed totals.
set -Eeuo pipefail

command_path="$(realpath -- "${1:-$(dirname -- "${BASH_SOURCE[0]}")/catch-report}")"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
count=0
ok() { count=$((count + 1)); printf 'ok %s - %s\n' "$count" "$1"; }
fail() { printf 'not ok %s - %s\n' "$((count + 1))" "$1"; [[ -s "$root/out" ]] && sed 's/^/# out: /' "$root/out"; [[ -s "$root/err" ]] && sed 's/^/# err: /' "$root/err"; exit 1; }
run() { local status=0; PATH="$root/bin:$PATH" "$command_path" "$@" >"$root/out" 2>"$root/err" || status=$?; printf '%s' "$status"; }
has() { grep -Fq -- "$1" "$root/out"; }

# Review invocation records: two reviewers, one run that never finished, one refused, one older-format
# line without a run id, one run before the window, one torn line.
cat >"$root/stats.jsonl" <<'J'
{"ts":"2026-09-01T10:00:00+00:00","event":"start","run":"r0","model":"model-a","kind":"code"}
{"ts":"2026-09-01T10:05:00+00:00","event":"end","run":"r0","kind":"code","targets":["old.ts"],"report":"/r/old.md","verdict":"needs-attention","fix_now":9,"debt":9,"high":9,"medium":9}
{"ts":"2026-09-25T10:00:00+00:00","event":"start","run":"r1","model":"model-a","kind":"code"}
{"ts":"2026-09-25T10:05:00+00:00","event":"end","run":"r1","kind":"code","targets":["a.ts"],"report":"/r/a.md","verdict":"needs-attention","fix_now":2,"debt":1,"high":2,"medium":1}
{"ts":"2026-09-26T10:00:00+00:00","event":"start","run":"r2","model":"model-a","kind":"code"}
{"ts":"2026-09-26T10:05:00+00:00","event":"end","run":"r2","kind":"code","targets":["c.ts"],"report":"/r/c.md","verdict":"approve","fix_now":0,"debt":0,"high":0,"medium":0}
{"ts":"2026-09-27T10:00:00+00:00","event":"start","run":"r3","model":"model-b","kind":"plan"}
{"ts":"2026-09-27T10:05:00+00:00","event":"end","run":"r3","kind":"plan","targets":["b.ts","b2.ts"],"report":"/r/b.md","verdict":"needs-attention","fix_now":3,"debt":0,"high":3,"medium":0}
{"ts":"2026-09-28T10:00:00+00:00","event":"start","run":"r4","model":"model-b","kind":"code"}
{"ts":"2026-09-29T10:00:00+00:00","event":"start","run":"r5","model":"model-a","kind":"code"}
{"ts":"2026-09-29T10:00:05+00:00","event":"refused","run":"r5","reason":"cap"}
{"ts":"2026-09-26T12:00:00+00:00","kind":"code","verdict":"needs-attention","high":1,"medium":0,"binA":1}
{"ts":"2026-09-2
J
# Findings ledger: five first seen in the window (one accepted, one rejected, one superseded, two
# undecided) and one older undecided.
cat >"$root/findings.jsonl" <<'J'
{"id":"f0","first_seen":"2026-09-01","status":"undecided","severity":"high","file":"old.ts","title":"old"}
{"id":"f1","first_seen":"2026-09-25","status":"accepted","severity":"high","file":"a.ts","title":"one"}
{"id":"f2","first_seen":"2026-09-25","status":"rejected","severity":"medium","file":"a.ts","title":"two"}
{"id":"f3","first_seen":"2026-09-27","status":"undecided","severity":"high","file":"b.ts","title":"Retry loop never gives up","report":"/r/b.md"}
{"id":"f4","first_seen":"2026-09-27","status":"undecided","severity":"critical","file":"b.ts","title":"Token is written to the log","report":"/r/b.md"}
{"id":"f9","first_seen":"2026-09-27","status":"undecided","severity":"medium","file":"b.ts","title":"A medium finding is not quoted","report":"/r/b.md"}
{"id":"f5","first_seen":"2026-09-28","status":"superseded","severity":"high","file":"c.ts","title":"five"}
J

# usage
status="$(run)"; [[ "$status" == 0 && "$(head -n1 "$root/out")" == usage:* ]] || fail 'no arguments print usage and exit 0'
status="$(run --help)"; [[ "$status" == 0 && "$(head -n1 "$root/out")" == usage:* ]] || fail '--help prints usage and exits 0'
status="$(run run --nope)"; [[ "$status" == 2 ]] || fail 'an unknown option exits 2'
status="$(run run --since banana --stats "$root/stats.jsonl" --findings "$root/findings.jsonl")"; [[ "$status" == 2 ]] || fail 'an unreadable --since exits 2'
ok 'usage: no arguments and --help exit 0, wrong input exits 2'

status="$(run run --since 2026-09-20 --stats "$root/stats.jsonl" --findings "$root/findings.jsonl")"
[[ "$status" == 0 ]] || fail "report exits 0 (got $status)"
has 'Reviews started: 5, finished: 4, refused: 1, never finished: 1' || fail 'counts of started, finished, refused and never finished'
has '  model-a: runs 2, high 2, medium 1, fix-now 2, debt 1' || fail 'model-a totals (old run and refused run excluded)'
has '  model-b: runs 1, high 3, medium 0, fix-now 3, debt 0' || fail 'model-b totals (the run that never finished is not counted)'
has '  unknown (older records): runs 1, high 1, medium 0, fix-now 0, debt 0' || fail 'an older-format line is counted under its own name'
has 'Verdicts: needs-attention 3, approve 1' || fail 'verdict counts'
has 'Two brains (who found the problems):' || fail 'the two-brains block exists'
has '  Mutual review (the other model checks the work; all peer-review records): reviews 4, fix-now 5, high 6, medium 1' || fail 'mutual review totals: every review in the window'
has '  Self-check (an agent finds its own error in its own conversation): not measured by run; use: catch-report self' || fail 'the self-check line points at catch-report self'
has 'Mutual review found 5 problems that had to be fixed now and 6 high-severity findings.' || fail 'the headline sentence'
[[ "$(sed -n 2p "$root/out")" == 'Two brains (who found the problems):' ]] || fail 'the two-brains block comes first, right after the title'
ok 'review counts, per-model totals and verdicts equal the hand-computed values'

has 'Findings first seen since 2026-09-20: 6 (ruled on 3: accepted 1, rejected 1, superseded 1; undecided 3)' || fail 'ledger counts of ruled and undecided findings'
has 'Most fix-now:' || fail 'a most fix-now list exists'
[[ "$(grep -A1 '^Most fix-now:' "$root/out" | tail -n1)" == '  3  2026-09-27  b.ts, b2.ts  /r/b.md' ]] || fail 'the top review is the one with fix-now 3, with its targets and report'
[[ "$(grep -A2 '^Most fix-now:' "$root/out" | tail -n1)" == '  2  2026-09-25  a.ts  /r/a.md' ]] || fail 'second is fix-now 2'
! grep -q 'old.ts' "$root/out" || fail 'a review before the window is not listed'
has 'These records do not say' || fail 'the limits line is printed'
ok 'findings ledger counts, top reviews and the limits line'

# a narrower window
status="$(run run --since 2026-09-27 --stats "$root/stats.jsonl" --findings "$root/findings.jsonl")"
has 'Reviews started: 3, finished: 1, refused: 1, never finished: 1' || fail 'a narrower window changes the counts'
has 'Findings first seen since 2026-09-27: 4 (ruled on 1: accepted 0, rejected 0, superseded 1; undecided 3)' || fail 'a narrower window changes the ledger counts'
ok 'a narrower --since gives the hand-computed narrower totals'

# unreadable sources are named, the rest still prints
status="$(run run --since 2026-09-20 --stats "$root/none.jsonl" --findings "$root/findings.jsonl")"
[[ "$status" == 0 ]] && grep -Eq '^not read: .*none.jsonl -> ' "$root/out" && has 'Findings first seen since' || fail 'a missing stats file is named and the ledger part still prints'
status="$(run run --stats "$root/none.jsonl" --findings "$root/none2.jsonl")"
[[ "$status" == 1 ]] || fail 'with both sources unreadable it exits 1'
ok 'an unreadable source is named; both unreadable exits 1'

# reads only
before="$(cd "$root" && sha256sum stats.jsonl findings.jsonl | sha256sum)"
run run --since 2026-09-20 --stats "$root/stats.jsonl" --findings "$root/findings.jsonl" >/dev/null
[[ "$(cd "$root" && sha256sum stats.jsonl findings.jsonl | sha256sum)" == "$before" ]] || fail 'the record files were changed'
ok 'the record files are not changed'

# ================= self-check: the agent's own model reads its own conversations =================
# Stand-ins for the two model command lines (external programs): they answer PROMPTED when the excerpt
# carries the marker USER-POINTED, SELF otherwise, and record how they were called.
mkdir -p "$root/bin"
cat >"$root/bin/claude" <<'SH'
#!/usr/bin/env bash
[[ -z "${FAKE_MODEL_FAIL:-}" ]] || exit 1
# Like the real command line: --tools takes every following word as a tool name, so the prompt must
# arrive on standard input; with no prompt it stops with an error.
printf 'CALL %s\n' "$(printf '%s' "$*" | head -c 200 | tr '\n' ' ')" >>"$FAKE_ROOT/claude-calls"
prompt="$(cat)"
[[ -n "$prompt" ]] || { echo 'Error: Input must be provided either through stdin or as a prompt argument when using --print' >&2; exit 1; }
printf '%s' "$prompt" >"$FAKE_ROOT/last-claude-prompt"
if [[ "$prompt" == *USER-POINTED* ]]; then echo PROMPTED; else echo SELF; fi
SH
cat >"$root/bin/codex" <<'SH'
#!/usr/bin/env bash
[[ -z "${FAKE_MODEL_FAIL:-}" ]] || exit 1
printf 'CALL %s\n' "$(printf '%s' "$*" | head -c 200 | tr '\n' ' ')" >>"$FAKE_ROOT/codex-calls"
out=""; prev=""; for a in "$@"; do [[ "$prev" == -o ]] && out="$a"; prev="$a"; done
if [[ "${*: -1}" == *USER-POINTED* ]]; then v=PROMPTED; else v=SELF; fi
printf '%s\n' "$v" >"$out"
echo "noise from the codex tool"
SH
chmod +x "$root/bin/claude" "$root/bin/codex"; export FAKE_ROOT="$root"

mkdir -p "$root/claude/proj" "$root/codex/2026/09/30"
cl() { jq -cn --arg role "$1" --arg kind "$2" --arg text "$3" --arg ts "${4:-}" '{type: $role, message: {role: $role, content: [ {type: $kind, ($kind | if . == "tool_result" then "content" elif . == "thinking" then "thinking" else "text" end): $text} ]}} + (if $ts != "" then {timestamp: $ts} else {} end)'; }
{
  cl user text 'please fix the parser'
  cl assistant text 'Fixed it, the tests should pass.'
  cl user tool_result 'FAILED test_parser: expected 3 got 4'
  cl assistant text 'My mistake: I introduced a bug in the parser when I changed the loop bound. Fixing it now.'
  cl user tool_result 'FAILED test_loop: expected 7 got 8'
  cl assistant text 'Der Test ist rot, weil ich die Schleife falsch begrenzt habe. Ich korrigiere das.'
  cl user text 'next step please'
  cl user tool_result 'ok 12 tests passed'
  cl assistant text 'Looks good now, moving on to the next step.'
  cl user tool_result 'Error: cannot open config.yaml'
  cl user tool_result 'listing: a.txt b.txt'
  cl user tool_result 'listing: c.txt'
  cl assistant text 'Indiqué mal el nombre del archivo, así que lo leo de nuevo con el nombre correcto.'
  cl user text 'USER-POINTED: that is wrong, you broke the login page'
  cl assistant text 'You are right, I was wrong about the login redirect. Correcting.'
  cl assistant thinking 'I was wrong here, my mistake, but this is only thinking'
} >"$root/claude/proj/s1.jsonl"
cx() { jq -cn --arg role "$1" --arg kind "$2" --arg text "$3" '{type: "response_item", payload: {type: "message", role: $role, content: [{type: $kind, text: $text}]}}'; }
{
  cx user input_text 'run the tests'
  cx assistant output_text 'Tests ran. All good.'
  jq -cn '{type: "response_item", payload: {type: "function_call_output", output: "Process exited with code 1: test_empty FAIL"}}'
  cx assistant output_text 'I missed the empty case in my earlier fix; found it while running the test just now.'
  cx user input_text 'continue'
  # an admission in Chinese, written with escapes because shipped files hold no CJK characters
  jq -cn '{type: "response_item", payload: {type: "message", role: "assistant", content: [{type: "output_text", text: "\u6211\u628a\u6bd4\u8f83\u5199\u53cd\u4e86\uff0c\u73b0\u5728\u6539\u56de\u6765\u3002"}]}}'
  # the agent ran eight more commands after a failure before it spoke
  jq -cn '{type: "response_item", payload: {type: "function_call_output", output: "Process exited with code 2: no such file"}}'
  for i in 1 2 3 4 5 6 7 8; do jq -cn --arg i "$i" '{type: "response_item", payload: {type: "function_call_output", output: ("listing " + $i)}}'; done
  cx assistant output_text 'Switching to the other file name now.'
} >"$root/codex/2026/09/30/rollout-s2.jsonl"
mkdir -p "$root/claude/old"; cl assistant text 'My mistake, I broke the build long ago.' >"$root/claude/old/ancient.jsonl"; touch -d '2026-09-01' "$root/claude/old/ancient.jsonl"

srun() { run self --since 2026-09-20 --claude-dir "$root/claude" --codex-dir "$root/codex" --stats "$root/stats.jsonl" "$@"; }

status="$(run self --agent nobody)"; [[ "$status" == 2 ]] || fail 'an unknown --agent exits 2'
status="$(run self --limit abc)"; [[ "$status" == 2 ]] || fail 'a --limit that is not a number exits 2'
before="$(find "$root/claude" "$root/codex" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)"
status="$(srun)"
[[ "$status" == 0 ]] || fail "self exits 0 (got $status)"
has 'Looked at: 2 sessions (claude 1, codex 1)' || fail 'two sessions since the cutoff, the old one is not read'
has 'Candidate moments (an agent reacting to a failure or admitting an error): 7; judged: 7' || fail 'seven candidate moments: four in claude, three in codex (an English admission, a Chinese admission, and a reaction ten steps after a failure); thinking blocks and passing outputs give none'
has '  found by the agent itself: 6' || fail 'three were found by the agent itself, one of them in German with no admission phrase'
has '  pointed out by the user or a reviewer: 1' || fail 'one was pointed out by the user'
has '  not an error, or could not be judged: 0' || fail 'nothing is left unjudged'
has 'Side by side: mutual review found 5 problems that had to be fixed now; agents caught their own mistake in at least 6 moments (judged 7 of 7 candidate moments).' || fail 'the side-by-side sentence counts moments, not errors'
[[ "$(find "$root/claude" "$root/codex" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)" == "$before" ]] || fail 'the conversations were changed'
ok 'self counts what the model judged: 6 found by the agent, 1 pointed out, side by side with mutual review'

grep -q -- '--no-session-persistence' "$root/claude-calls" && grep -q -- '--ephemeral' "$root/codex-calls" || fail 'the model calls leave no session behind (--no-session-persistence, --ephemeral)'
[[ "$(wc -l <"$root/claude-calls")" == 4 && "$(wc -l <"$root/codex-calls")" == 3 ]] || fail 'claude moments go to claude, codex moments to codex, once each'
grep -q 'routine progress' "$root/last-claude-prompt" && grep -q 'and is now fixing or redoing it' "$root/last-claude-prompt" || fail 'the prompt says SELF needs an earlier mistake being corrected, and that routine progress is NONE'
ok 'each agent judges its own conversations, without saving a new session'

status="$(srun --limit 2)"
has 'Candidate moments (an agent reacting to a failure or admitting an error): 7; judged: 2 (limit 2)' || fail 'the limit caps how many are judged'
has 'Estimate for all 7 candidate moments: about' || fail 'a sample prints an estimate for all candidates'
status="$(srun --limit 4)"
has 'judged: 4 (limit 4)' || fail 'the limit is used in full: 7 candidates with limit 4 judges 4, not fewer'
status="$(srun --agent codex)"
has 'Looked at: 1 sessions (claude 0, codex 1)' && has 'judged: 3' || fail '--agent codex reads only codex conversations'
status="$(srun --list)"
grep -Eq '^  SELF  claude  s1.jsonl: .*introduced a bug in the parser' "$root/out" && grep -Eq '^  PROMPTED  claude  s1.jsonl: .*login redirect' "$root/out" && grep -Eq '^  SELF  codex  rollout-s2.jsonl: .*empty case' "$root/out" && grep -Eq '^  SELF  claude  s1.jsonl: Der Test ist rot' "$root/out" || fail '--list shows each moment with the model verdict, the agent and the conversation'
ok '--limit and --agent bound the work'

# many candidates (far more than a pipe buffer) with a small limit: the report must still print
mkdir -p "$root/big/proj"
long="My mistake: I introduced a bug in the handler here. $(printf 'detail %.0s' $(seq 1 60))"
for n in $(seq 1 90); do
    for k in 1 2 3 4 5; do cl assistant text "$long $n $k"; done >"$root/big/proj/s$n.jsonl"
done
status="$(run self --since 2026-09-20 --claude-dir "$root/big" --codex-dir "$root/none" --agent claude --limit 200 --stats "$root/stats.jsonl")"
[[ "$status" == 0 ]] && has 'judged: 200 (limit 200)' && has 'Candidate moments (an agent reacting to a failure or admitting an error): 450' || fail 'with 450 candidates and --limit 200 (225 sampled) the report still prints (no silent exit from a closed pipe)'
ok 'a large number of candidates with a small limit still prints the report'
status="$(FAKE_MODEL_FAIL=1 srun)"
has 'No moment could be judged, so nothing is counted.' && has 'the self-check number is not available' && ! has 'Estimate' || fail 'when nothing could be judged the report says so instead of printing zero estimates'
[[ "$status" == 0 ]] && has '  not an error, or could not be judged: 7' && has 'could not be judged:' || fail 'a model that fails leaves the moments unjudged, counted, and the report still prints'
rm "$root/bin/claude"
status="$(PATH="/usr/bin:/bin:$root/bin" srun)"
grep -Eq '^not judged: claude -> ' "$root/out" && has '  found by the agent itself: 3' || fail 'a missing claude command is named; the codex moment is still judged'
ok 'a failing or missing model is named and never stops the report'

# a conversation file touched recently can hold old messages: only moments inside the window count
mkdir -p "$root/ts/proj"
{
  cl assistant text 'My mistake: I introduced a bug in the old handler.' 2026-09-01T10:00:00.000Z
  cl assistant text 'My mistake: I introduced a bug in the new handler.' 2026-09-28T10:00:00.000Z
} >"$root/ts/proj/s.jsonl"
status="$(run self --since 2026-09-20 --claude-dir "$root/ts" --codex-dir "$root/none" --agent claude --limit 10 --list --stats "$root/stats.jsonl")"
has 'Candidate moments (an agent reacting to a failure or admitting an error): 1; judged: 1' && has 'new handler' && ! has 'old handler' || fail 'a moment older than the cutoff in a recently touched file is not counted'
ok 'self: moments older than the cutoff are not counted even in a recently touched conversation'

# sampling spreads over the whole candidate list, including the source that comes last
rm -rf "$root/spread"; mkdir -p "$root/spread/claude/p" "$root/spread/codex"
for n in $(seq 1 40); do cl assistant text "My mistake: I introduced a bug in claude handler $n." >"$root/spread/claude/p/c$n.jsonl"; done
for n in $(seq 1 19); do cx assistant output_text "My mistake: I introduced a bug in codex handler $n." >"$root/spread/codex/rollout-$n.jsonl"; done
status="$(run self --since 2026-09-20 --claude-dir "$root/spread/claude" --codex-dir "$root/spread/codex" --limit 30 --list --stats "$root/stats.jsonl")"
has 'Candidate moments (an agent reacting to a failure or admitting an error): 59; judged: 30 (limit 30)' || fail '59 candidates with limit 30 judges exactly 30'
(( $(grep -c '^  [A-Z]*  codex ' "$root/out") >= 6 )) || fail 'the sample reaches the codex candidates that come after the claude ones (at least 6 of 30)'
ok 'self: a sample is spread over all candidates, not cut from the front'

# an admission long after the user's correction: the model must still see the user's message
mkdir -p "$root/attr/p"
{
  cl user text 'USER-POINTED: that function is wrong'
  for k in 1 2 3 4 5 6; do cl user tool_result "listing ok $k"; done
  cl assistant text 'I was wrong about the function, my mistake.'
} >"$root/attr/p/s.jsonl"
status="$(run self --since 2026-09-20 --claude-dir "$root/attr" --codex-dir "$root/none" --agent claude --limit 5 --list --stats "$root/stats.jsonl")"
grep -Eq '^  PROMPTED  claude  s.jsonl' "$root/out" && ! grep -Eq '^  SELF  claude  s.jsonl' "$root/out" || fail 'a correction by the user several rows before the admission reaches the model, so it is not counted as self-found'
ok 'self: the most recent user message is shown to the model even when it is several rows before the admission'

# ================= brief: the page an agent hands to the user =================
brun() { run brief --since 2026-09-20 --claude-dir "$root/claude" --codex-dir "$root/codex" --stats "$root/stats.jsonl" --findings "$root/findings.jsonl" "$@"; }
rm -f "$root/bin/claude"; cat >"$root/bin/claude" <<'SH'
#!/usr/bin/env bash
[[ -z "${FAKE_MODEL_FAIL:-}" ]] || exit 1
prompt="$(cat)"
if [[ "$prompt" == *USER-POINTED* ]]; then echo PROMPTED; else echo SELF; fi
SH
chmod +x "$root/bin/claude"
status="$(brun)"
[[ "$status" == 0 ]] || fail "brief exits 0 (got $status)"
[[ "$(sed -n 1p "$root/out")" == '# Two brains, since 2026-09-20' ]] || fail 'the page opens with a title naming the period'
[[ "$(sed -n 3p "$root/out")" == '**The two brains together: a second model reviewing the work caught 5 problems that had to be fixed, and the agents caught their own mistakes in 6 moments.**' ]] || fail 'the headline keeps problems (second brain) apart from moments (self-check) and never adds them'
has '## The second brain: a different model checks the work' || fail 'the second-brain section'
has '- 4 reviews by a different model: 3 raised findings, 2 (50%) found something that had to be fixed now, 1 approved clean' || fail 'how many reviews raised findings, how many found something that had to be fixed now, how many approved clean'
has '- 5 must-fix problems and 6 high-severity findings in all' || fail 'must-fix and high-severity totals'
has '  1. 2026-09-27, b.ts (and 1 more file): 3 must-fix' || fail 'the biggest catch names the date, target and count'
has '     - "Token is written to the log"' && has '     - "Retry loop never gives up"' || fail 'the biggest catch quotes the critical and high findings of that review by title'
! has 'A medium finding is not quoted' || fail 'medium findings are not quoted'
ok 'brief: title, headline, second-brain numbers and the quoted biggest catch'

has '## The first brain catching itself' || fail 'the self-check section'
has '- In 7 moments an agent hit a failing command or admitted a mistake, its own model read all 7: 6 were the agent finding its own error, 1 was someone else pointing it out' || fail 'the self-check counts in plain words'
[[ "$(grep -c '^  - "' "$root/out")" == 2 ]] || fail 'one sentence per conversation is quoted as an example (two conversations here)'
prev=0; while IFS= read -r q; do len=${#q}; (( len >= prev )) || fail 'the quotes are ordered shortest first'; prev=$len; done < <(grep '^  - "' "$root/out")
has '## How to read this' || fail 'the how-to-read section'
has 'Must-fix means' && has 'counts moments, not distinct bugs' && has 'Check any number with: catch-report self' || fail 'the reading notes define must-fix and say how to check a number'
(( $(wc -l <"$root/out") <= 45 )) || fail 'the page stays within 45 lines'
ok 'brief: the self-check section with quotes, and how to read the numbers'

status="$(brun --limit 2)"
grep -Eq '^- In 7 moments .*its own model read 2 of them' "$root/out" && grep -Eq 'about [0-9]+ \(plausible range [0-9]+ to [0-9]+\)' "$root/out" || fail 'a sample says how many were read and gives a plausible range'
grep -Eq '^\*\*The two brains together: a second model reviewing the work caught 5 problems that had to be fixed, and the agents caught their own mistakes in an estimated [0-9]+ moments \(plausibly [0-9]+ to [0-9]+\)\.\*\*$' "$root/out" || fail 'a sampled headline keeps the exact number apart from the estimate and gives the range'
# a sample that covers almost every candidate leaves almost no room for error: 6 of 7 read, range at most 2 wide
status="$(brun --limit 6)"
range_line="$(grep -E 'plausible range [0-9]+ to [0-9]+' "$root/out" | head -n1)"
lo="$(sed -E 's/.*plausible range ([0-9]+) to ([0-9]+).*/\1/' <<<"$range_line")"; hi="$(sed -E 's/.*plausible range ([0-9]+) to ([0-9]+).*/\2/' <<<"$range_line")"
[[ -n "$lo" && -n "$hi" ]] && (( hi - lo <= 2 )) || fail "reading 6 of 7 candidates leaves a range at most 2 wide (got $lo to $hi)"
ok 'brief: a sample gives an estimate with a plausible range'

status="$(run brief --since 2026-09-20 --claude-dir "$root/big" --codex-dir "$root/none" --agent claude --limit 6 --stats "$root/stats.jsonl" --findings "$root/findings.jsonl")"
grep -q '^  - ".*\.\.\."$' "$root/out" || fail 'a quote longer than 160 characters is cut with an ellipsis'
ok 'brief: long quotes are cut with an ellipsis'

status="$(FAKE_MODEL_FAIL=1 brun)"
[[ "$(sed -n 3p "$root/out")" == '**A second model reviewing the work caught 5 problems that had to be fixed now.**' ]] && has 'The self-check could not be measured' || fail 'when the self-check cannot be measured the headline is the second brain alone and says so'
ok 'brief: without a self-check number the headline is honest about it'

# the period before: same-length window, dates relative to today
rel() { date -u -d "$1 days ago" +%Y-%m-%dT%H:%M:%S+00:00; }
{
  printf '{"ts":"%s","event":"end","run":"a1","targets":["x.ts"],"report":"/r/x.md","verdict":"needs-attention","fix_now":1,"high":1,"medium":0}\n' "$(rel 3)"
  printf '{"ts":"%s","event":"end","run":"a2","targets":["y.ts"],"report":"/r/y.md","verdict":"needs-attention","fix_now":2,"high":1,"medium":0}\n' "$(rel 5)"
  printf '{"ts":"%s","event":"end","run":"a3","targets":["z.ts"],"report":"/r/z.md","verdict":"needs-attention","fix_now":4,"high":2,"medium":0}\n' "$(rel 14)"
} >"$root/rel.jsonl"
status="$(run brief --since 10d --claude-dir "$root/none" --codex-dir "$root/none" --stats "$root/rel.jsonl" --findings "$root/findings.jsonl")"
has '# Two brains, last 10 days' && has '3 must-fix problems and 2 high-severity findings in all (down from 4 in the 10 days before)' || fail 'the period is named in days and compared with the period of the same length before it'
ok 'brief: names the period and compares it with the period before'

# records of the period before without a fix_now field (older format) are not compared
{
  printf '{"ts":"%s","event":"end","run":"b1","targets":["x.ts"],"report":"/r/x.md","verdict":"needs-attention","fix_now":2,"high":1,"medium":0}\n' "$(rel 3)"
  printf '{"ts":"%s","event":"end","run":"b2","targets":["y.ts"],"report":"/r/y.md","verdict":"needs-attention","high":1,"medium":0}\n' "$(rel 14)"
} >"$root/old.jsonl"
status="$(run brief --since 10d --claude-dir "$root/none" --codex-dir "$root/none" --stats "$root/old.jsonl" --findings "$root/findings.jsonl")"
has '- 2 must-fix problems and 1 high-severity findings in all' && ! has 'up from' && ! has 'down from' || fail 'an older period with no must-fix field is not used for a comparison'
ok 'brief: no comparison against records that never counted must-fix'

# a review with no ledger rows: the titles come from the headings of its report file
printf '# Review\n\n#### [C1] Null pointer in the parser\n- detail\n\n#### [C2] Retry never stops\n' >"$root/report-c.md"
printf '{"ts":"%s","event":"end","run":"c1","targets":["p.ts"],"report":"%s","verdict":"needs-attention","fix_now":2,"high":2,"medium":0}\n' "$(rel 2)" "$root/report-c.md" >"$root/rep.jsonl"
status="$(run brief --since 10d --claude-dir "$root/none" --codex-dir "$root/none" --stats "$root/rep.jsonl" --findings "$root/findings.jsonl")"
has '     - "Null pointer in the parser"' && has '     - "Retry never stops"' || fail 'without ledger rows the titles are read from the report file headings'
ok 'brief: titles fall back to the headings of the report file'

# a report that can be read but has no headings must not end the page (found on a real run)
printf 'A plain review with no headings at all.\n' >"$root/report-plain.md"
printf '{"ts":"%s","event":"end","run":"d1","targets":["q.ts"],"report":"%s","verdict":"needs-attention","fix_now":2,"high":1,"medium":0}\n' "$(rel 2)" "$root/report-plain.md" >"$root/plain.jsonl"
status="$(run brief --since 10d --claude-dir "$root/none" --codex-dir "$root/none" --stats "$root/plain.jsonl" --findings "$root/findings.jsonl")"
[[ "$status" == 0 ]] && has '  1. ' && has '## How to read this' && has 'Read from 0 conversations and 1 reviews on this machine.' || fail 'a report with no headings still gives the whole page'
ok 'brief: a report without headings does not end the page'

status="$(run brief --agent nobody)"; [[ "$status" == 2 ]] || fail 'brief rejects an unknown --agent'
ok 'brief: bad usage exits 2'

printf '1..%s\n' "$count"
