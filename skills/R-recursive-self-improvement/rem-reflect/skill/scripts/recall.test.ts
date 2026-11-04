import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { recall, lessonDetail, firstMessageRecall } from './recall.ts';
import { run } from './rem-reflect.ts';
import { appendRows } from './lessons.ts';
import { git } from './store.ts';
import { tmp, fixtureCheckout, fixtureConfig, makeStore, FixtureBackend } from './test-helpers.ts';
import type { Config } from './config.ts';

const NOW = new Date('2026-09-08T00:00:00Z');
const ARMED = 'rem-reflect --interval 24h next in 3h';
function idx(lines: string[]): string[] {
  const h = lines.indexOf("Lessons from this machine's own sessions");
  return lines.slice(h + 1, lines.length - 1);
}

function lesson(id: string, over: Record<string, unknown> = {}): Record<string, unknown> {
  return { lesson_id: id, page_id: `pg-${id}`, status: 'accepted', count: 1, helped: 0, harmful: 0, measured: false,
    created_run: '20260901-0000', project_id: 'p', agent_id: 'codex', user_id: 'u', skill_target: null, applies_to: 'general',
    advice: `advice ${id}`, because: `because ${id}`, situation: { task_type: 'w', trigger: `trigger ${id}`, tools: [] },
    scenario: { task_type: 'w', trigger: 't', tools: [] }, polarity: 'from_failure',
    evidence: [{ trace_id: 't.v1', line_start: 2, line_end: 2, quote: 'q' }], counter_examples: 'not searched', listed: true, ...over };
}
// Seed lessons (and optional ledger rows / report) into the store and commit, so recall reads them at HEAD.
function seed(config: Config, lessons: Record<string, unknown>[], ledger: Record<string, unknown>[] = [], report = false): string {
  const store = makeStore(config);
  appendRows(join(store, 'wiki/lessons.jsonl'), lessons);
  if (ledger.length) { mkdirSync(join(store, 'ledger'), { recursive: true }); appendRows(join(store, 'ledger/skill-impact.jsonl'), ledger); }
  if (report) { mkdirSync(join(store, 'staging/20260907-0000'), { recursive: true }); writeFileSync(join(store, 'staging/20260907-0000/REPORT.md'), '# Run\n'); }
  git(store, ['add', '--all']);
  git(store, ['commit', '--quiet', '-m', 'seed']);
  return store;
}

// the index, its scope filter, cap, truncation, instruction line, and shown line ---
test('recall prints the fixed heading, one index line per in-scope accepted lesson, and one instruction line', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-a')]);
  const r = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  assert.equal(r.code, 0);
  assert.equal(r.lines[0], "Lessons from this machine's own sessions", 'the fixed heading is first when armed');
  assert.ok(r.lines[1].startsWith('L-a · general · trigger L-a — advice L-a\n'), 'the heading retains the trigger and advice');
  assert.ok(r.lines[1].includes('situation: {"task_type":"w","trigger":"trigger L-a","tools":[]}'));
  assert.equal(r.lines[2], 'Read one in full with: sno rem-reflect lesson <lesson_id> --session S1 --agent claude-code --cwd ' + checkout);
  assert.equal(r.lines.length, 3, 'nothing else');
  // one shown line appended
  const usage = readFileSync(join(store, 'ledger/usage.jsonl'), 'utf8').trim().split('\n');
  assert.equal(usage.length, 1);
  const shown = JSON.parse(usage[0]);
  assert.equal(shown.type, 'shown'); assert.equal(shown.session_id, 'S1'); assert.deepEqual(shown.lesson_ids, ['L-a']);
});

test('the index prints at most 10 lines even with twelve in-scope accepted lessons', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, Array.from({ length: 12 }, (_, i) => lesson(`L-${i}`, { helped: i })));
  const r = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  const index = idx(r.lines);
  assert.equal(index.length, 10, 'exactly ten index lines');
});

test('a candidate, a tbd, and an under_review lesson never appear, and lesson detail refuses each naming status', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-ok'), lesson('L-cand', { status: 'candidate', listed: false }), lesson('L-tbd', { status: 'tbd' }),
    lesson('L-rev', { status: 'under_review' }), lesson('L-otherproj', { applies_to: 'project:github.com/other/repo' })]);
  const r = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  const index = idx(r.lines);
  // isolates BOTH filters: L-otherproj is accepted but out of scope, the rest are in scope but not accepted
  assert.deepEqual(index.map(l => l.split(' · ')[0]), ['L-ok'], 'only the accepted, in-scope lesson is listed');
  for (const id of ['L-cand', 'L-tbd', 'L-rev']) {
    const d = lessonDetail(store, id, { session: 'S1', cwd: checkout, agent: 'claude-code' }, NOW);
    assert.equal(d.code, 1);
    assert.match(d.lines.join('\n'), /status (candidate|tbd|under_review)/, `${id} refused naming status`);
  }
});

test('lesson detail prints the available fields and appends one read line; --session S9 with no shown line still works', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-a')]);
  const d = lessonDetail(store, 'L-a', { session: 'S9', cwd: checkout, agent: 'claude-code' }, NOW);
  assert.equal(d.code, 0);
  assert.equal(d.lines.length, 5, 'the old fields and the skill reference, without invented outcomes');
  assert.match(d.lines[0], /^situation: .*"trigger":"trigger L-a"/, 'situation carries its content, not an empty field');
  assert.equal(d.lines[1], 'advice: advice L-a');
  assert.equal(d.lines[2], 'skill_target: null');
  assert.equal(d.lines[3], 'because: because L-a');
  assert.match(d.lines[4], /^evidence: .*"trace_id":"t\.v1"/, 'evidence carries its content');
  const usage = readFileSync(join(store, 'ledger/usage.jsonl'), 'utf8').trim().split('\n');
  assert.equal(usage.length, 1, 'exactly one read line is appended, not two');
  const read = JSON.parse(usage[0]);
  assert.equal(read.type, 'read'); assert.equal(read.session_id, 'S9'); assert.equal(read.lesson_id, 'L-a');
});

test('a lesson whose scope is a different project is refused naming the scope and appends nothing', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-other', { applies_to: 'project:github.com/other/repo' })]);
  const d = lessonDetail(store, 'L-other', { session: 'S1', cwd: checkout, agent: 'claude-code' }, NOW);
  assert.equal(d.code, 1);
  assert.match(d.lines.join('\n'), /scope project:github.com\/other\/repo/);
  assert.ok(!existsSync(join(store, 'ledger/usage.jsonl')), 'a refused detail appends no read line');
});

test('recall shares project and general lessons across harnesses, hides agent scopes, and refuses another project', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [
    lesson('L-project', { applies_to: 'project:github.com/example/project' }),
    lesson('L-general'),
    lesson('L-agent', { applies_to: 'agent:codex' }),
    lesson('L-other', { applies_to: 'project:github.com/other/repo' }),
  ]);
  for (const agent of ['claude-code', 'codex'] as const) {
    const result = recall(store, agent, { session_id: `S-${agent}`, cwd: checkout }, NOW, ARMED);
    assert.deepEqual(idx(result.lines).map(line => line.split(' · ')[0]).sort(), ['L-general', 'L-project']);
  }
  const refused = lessonDetail(store, 'L-other', { session: 'S1', cwd: checkout, agent: 'codex' }, NOW);
  assert.equal(refused.code, 1);
  assert.match(refused.lines.join('\n'), /scope project:github.com\/other\/repo/);
  const agentScoped = lessonDetail(store, 'L-agent', { session: 'S1', cwd: checkout, agent: 'codex' }, NOW);
  assert.equal(agentScoped.code, 1);
  assert.match(agentScoped.lines.join('\n'), /scope agent:codex/);
});

test('an unwritable usage log still lets recall print the index and exit 0 with one stderr line', { skip: process.getuid?.() === 0 ? 'root ignores file mode' : false }, () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-a', { expected_result: 'The report is readable.',
    success_criteria: 'The account read contains the report.' })]);
  // make the usage file read-only so the append fails
  mkdirSync(join(store, 'ledger'), { recursive: true });
  writeFileSync(join(store, 'ledger/usage.jsonl'), '');
  chmodSync(join(store, 'ledger/usage.jsonl'), 0o400);
  const r = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  assert.equal(r.code, 0, 'recall still exits 0');
  assert.match(r.lines[0], /Lessons from this machine/);
  assert.ok(r.lines.join('\n').includes('success_criteria: The account read contains the report.'));
  assert.equal(r.stderr?.length, 1, 'one stderr line names the append failure');
  assert.match(r.stderr!.join('\n'), /could not record use/);
  assert.match(r.stderr!.join('\n'), /session S1, lessons L-a; context delivered without use measurement/);
  const detail = lessonDetail(store, 'L-a', { session: 'S1', cwd: checkout, agent: 'claude-code' }, NOW);
  assert.equal(detail.code, 0);
  assert.ok(detail.lines.join('\n').includes('success_criteria: The account read contains the report.'));
  assert.match(detail.stderr?.join('\n') ?? '', /session S1, lesson L-a; context delivered without read measurement/);
  chmodSync(join(store, 'ledger/usage.jsonl'), 0o600);
});

test('a 300-character trigger and its advice reach the session-start list uncut', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-long', { situation: { task_type: 'w', trigger: 'z'.repeat(300), tools: [] },
    advice: 'Check the key field is unique before a production batch.' })]);
  const r = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  assert.ok(r.lines[1].startsWith(`L-long · general · ${'z'.repeat(300)} — Check the key field is unique before a production batch.\n`));
});

test('verified listed lessons are recalled without the owner, in their layer, and the full-lesson command agrees', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const here = 'github.com/example/project';
  const verified = { status: 'candidate', listed: true, verification: { accepted: true } };
  const store = seed(config, [
    lesson('L-accepted'),
    lesson('L-verified-here', { ...verified, applies_to: `project:${here}`, project_id: here }),
    lesson('L-verified-user-wide', { ...verified, applies_to: 'general', project_id: 'github.com/other/repo' }),
    lesson('L-verified-skill-here', { ...verified, applies_to: 'skill:/skills/heartbeat', project_id: here }),
    lesson('L-unverified', { status: 'candidate', listed: false }),
    lesson('L-verification-refused', { status: 'candidate', listed: false, verification: { accepted: false } }),
    lesson('L-rejected', { status: 'rejected', verification: { accepted: true } }),
    lesson('L-verified-other-project', { ...verified, applies_to: 'project:github.com/other/repo', project_id: 'github.com/other/repo' }),
    lesson('L-verified-skill-other', { ...verified, applies_to: 'skill:/skills/heartbeat', project_id: 'github.com/other/repo' }),
  ]);
  const shown = idx(recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED).lines).map(l => l.split(' · ')[0]);
  const recalled = ['L-accepted', 'L-verified-here', 'L-verified-user-wide', 'L-verified-skill-here'];
  assert.deepEqual(shown.sort(), [...recalled].sort());
  for (const id of recalled) assert.equal(lessonDetail(store, id, { session: 'S1', cwd: checkout, agent: 'claude-code' }, NOW).code, 0, id);
  for (const id of ['L-unverified', 'L-verification-refused', 'L-rejected']) {
    assert.match(lessonDetail(store, id, { session: 'S1', cwd: checkout, agent: 'claude-code' }, NOW).lines.join('\n'), /status/, id);
  }
  for (const id of ['L-verified-other-project', 'L-verified-skill-other']) {
    assert.match(lessonDetail(store, id, { session: 'S1', cwd: checkout, agent: 'claude-code' }, NOW).lines.join('\n'), /scope/, id);
  }
});

test('the not-armed notice precedes the index only when sno heartbeat --list shows no rem-reflect label', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-a')]);
  const off = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, 'nothing here');
  assert.match(off.lines[0], /daily run not armed since .*; arm with: sno heartbeat --interval 24h/);
  const on = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  assert.doesNotMatch(on.lines.join('\n'), /not armed/);
});

test('the pending-verdict line appears when a staged proposal and listed lessons lack a verdict, and is gone after verdicts', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  // one staged proposal without a verdict, two listed candidate lessons without a verdict
  const here = { project_id: 'github.com/example/project' };
  const store = seed(config, [lesson('L-1', { status: 'candidate', ...here }), lesson('L-2', { status: 'candidate', ...here })],
    [{ type: 'proposal', proposal_id: '20260907/codex', run_id: '20260907', half: 'codex', kind: 'patch', target: 'skills/heartbeat/skill', verdict: 'pending' }], true);
  const r = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  assert.match(r.lines[0], /^1 skill proposals and 2 lessons await your verdict: L-1, L-2; .*this project or all your projects.*; report: .*REPORT\.md$/);
  // after verdicts on all three, the line is gone
  const done = seed(config, [lesson('L-1', { status: 'accepted' }), lesson('L-2', { status: 'accepted' })],
    [{ type: 'proposal', proposal_id: '20260907/codex', run_id: '20260907', half: 'codex', kind: 'patch', target: 'skills/heartbeat/skill', verdict: 'pending' },
     { type: 'verdict', proposal_id: '20260907/codex', verdict: 'Accepted', at: '2026-09-07' }], true);
  const r2 = recall(done, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  assert.doesNotMatch(r2.lines.join('\n'), /await your verdict/);
});

// Recall: recall omits an under_review lesson; still lists an accepted one whose
//     counters suggest review; no lesson row is deleted ---
test('recall omits an under_review lesson but still lists an accepted one with harmful >= helped', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  // L-sup has a later under_review row; L-cnt is accepted with harmful>helped
  const store = seed(config, [lesson('L-sup'), lesson('L-sup', { status: 'under_review' }), lesson('L-cnt', { helped: 1, harmful: 2 })]);
  const r = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  const ids = idx(r.lines).map(l => l.split(' · ')[0]);
  assert.ok(!ids.includes('L-sup'), 'the under_review lesson is omitted');
  assert.ok(ids.includes('L-cnt'), 'an accepted lesson with adverse counters is still listed');
});

// recall reads HEAD, never the working file, and does not take the lock ---
test('recall reads the committed state, never an uncommitted half-written lessons row, and ignores a held lock', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-a')]);
  // an uncommitted under_review row on the working file must NOT be seen by recall
  appendRows(join(store, 'wiki/lessons.jsonl'), [lesson('L-a', { status: 'under_review' })]);
  // a run holds the store lock; recall must not wait for it
  writeFileSync(join(store, '.lock'), JSON.stringify({ pid: process.pid, command: 'run', id: '20260908-0000', journal: null }) + '\n');
  const started = Date.now();
  const r = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  assert.ok(Date.now() - started < 2000, 'recall returns within two seconds while the lock is held');
  const ids = idx(r.lines).map(l => l.split(' · ')[0]);
  assert.deepEqual(ids, ['L-a'], 'recall shows the committed accepted lesson, not the uncommitted under_review row');
});

test('many shown appends each land as one whole parseable line, and uncommitted usage lands in the next run commit', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-a')]);
  // eight recall invocations each append one shown line via a single write call; every line parses
  // whole (the concurrency measurement is external; here we prove the per-line format)
  for (let i = 0; i < 8; i++) recall(store, 'claude-code', { session_id: `S${i}`, cwd: checkout }, NOW, ARMED);
  const lines = readFileSync(join(store, 'ledger/usage.jsonl'), 'utf8').split('\n').filter(Boolean);
  assert.equal(lines.length, 8, 'eight whole lines');
  const sessions = lines.map(l => JSON.parse(l).session_id).sort();
  assert.deepEqual(sessions, ['S0', 'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7'], 'each line parses and names its own session');
  // the uncommitted usage lines are staged and committed by the next run
  const r = run(store, new Date('2026-09-09T00:00:00Z'), 'u', new FixtureBackend());
  assert.equal(r.code, 0, r.lines.join('\n'));
  const committed = git(store, ['show', 'HEAD:ledger/usage.jsonl']).split('\n').filter(Boolean);
  assert.equal(committed.length, 8, 'the next run commits the usage lines that were appended without the lock');
});

test('a non-parsing usage line is skipped, counted on stderr, and does not stop the shown line', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-a')]);
  mkdirSync(join(store, 'ledger'), { recursive: true });
  writeFileSync(join(store, 'ledger/usage.jsonl'), 'not json\n');
  const r = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  assert.equal(r.code, 0);
  assert.match(r.stderr!.join('\n'), /skipped 1 unparsable usage line/);
  const usage = readFileSync(join(store, 'ledger/usage.jsonl'), 'utf8').trim().split('\n');
  assert.equal(usage.length, 2, 'the bad line is left in place and the shown line is appended after it');
});

test('the pending-verdict line names this project\'s and user-wide undecided lessons, never another project\'s or an accepted one', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [
    lesson('L-here', { status: 'candidate', project_id: 'github.com/example/project' }),
    lesson('L-elsewhere', { status: 'candidate', project_id: 'github.com/other/repo', applies_to: 'project:github.com/other/repo' }),
    lesson('L-user-wide', { status: 'candidate', project_id: 'github.com/other/repo', applies_to: 'general' }),
    lesson('L-done', { status: 'accepted', applies_to: 'general' }),
  ], [], true);
  const r = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  assert.match(r.lines[0], /^0 skill proposals and 2 lessons await your verdict: L-here, L-user-wide; /);
  const other = seed(config, [lesson('L-elsewhere', { status: 'candidate', project_id: 'github.com/other/repo', applies_to: 'project:github.com/other/repo' })], [], true);
  assert.doesNotMatch(recall(other, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED).lines.join('\n'), /await your verdict/);
});

test('before the first nightly run there is no store, and recall prints nothing and exits 0 so the session-start hook does not fail', () => {
  const store = join(tmp('recall-no-store'), 'never-created');
  const result = recall(store, 'claude-code', { session_id: 's1', cwd: tmp('recall-no-store-cwd') }, NOW, ARMED);
  assert.deepEqual(result, { code: 0, lines: [] });
});

test('the timer sno setup installs counts as armed, so recall does not tell every session the daily run is off', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-a')]);
  const timed = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, '', true);
  assert.doesNotMatch(timed.lines.join('\n'), /not armed/);
  assert.ok(idx(timed.lines).some(line => line.startsWith('L-a · ')), timed.lines.join('\n'));
});

test('with nothing to show for this project, recall prints nothing instead of an empty heading every session', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-elsewhere', { project_id: 'github.com/other/repo', applies_to: 'project:github.com/other/repo' })]);
  assert.deepEqual(recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED).lines, []);
});

// first-message recall: a used-up allowance pauses the cloud call until the reset the CLI names ---
test('after the cloud refuses for a used-up allowance, later sessions skip the call until reset_at and resume after it', t => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-a')]);
  const bin = tmp('recall-429-bin');
  const requests = join(bin, 'requests.jsonl');
  // `sno rem recall --json` answers the way the installed CLI does on HTTP 429 (sno-cli-core cli.rs print_cli_error).
  writeFileSync(join(bin, 'sno'), `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2).join(' ');
if (args === 'station consent --json') { console.log('{"consent":"full"}'); process.exit(0); }
if (args !== 'rem recall --json') process.exit(2);
fs.appendFileSync(${JSON.stringify(requests)}, fs.readFileSync(0, 'utf8') + '\\n');
if (process.env.RECALL_429 === 'reset') { console.log(JSON.stringify({ error: 'allowance_used_up', message: 'Your weekly allowance is used up. Resets Sep 9, 1:00 AM.', reset_at: '2026-09-09T01:00:00Z' })); process.exit(1); }
if (process.env.RECALL_429 === 'no-reset') { console.log(JSON.stringify({ error: 'allowance_used_up', message: 'used up' })); process.exit(1); }
console.log(JSON.stringify({ lesson_ids: ['L-a'] }));
`);
  chmodSync(join(bin, 'sno'), 0o755);
  const oldPath = process.env.PATH;
  process.env.PATH = `${bin}:${oldPath ?? ''}`;
  t.after(() => { if (oldPath === undefined) delete process.env.PATH; else process.env.PATH = oldPath; delete process.env.RECALL_429; });
  const sent = () => existsSync(requests) ? readFileSync(requests, 'utf8').trim().split('\n').length : 0;
  const usage = () => readFileSync(join(store, 'ledger/usage.jsonl'), 'utf8').trim().split('\n').map(line => JSON.parse(line));
  const call = (session: string, at: string) => firstMessageRecall(store, 'claude-code', { session_id: session, cwd: checkout, prompt: 'broken build' }, new Date(at));

  // A 429 without reset_at keeps the old failure row and pauses nothing.
  process.env.RECALL_429 = 'no-reset';
  assert.deepEqual(call('s0', '2026-09-08T00:00:00Z'), { code: 0, lines: [], stderr: [] });
  assert.equal(sent(), 1);
  assert.equal(usage().filter(row => row.type === 'first-message-recall-skipped').length, 0);
  assert.match(JSON.stringify(usage().find(row => row.type === 'first-message-recall-failed')), /allowance_used_up/);

  // The first 429 with reset_at is sent, refused, and recorded with the reset.
  process.env.RECALL_429 = 'reset';
  assert.deepEqual(call('s1', '2026-09-08T00:10:00Z'), { code: 0, lines: [], stderr: [] });
  assert.equal(sent(), 2);
  const first = usage().filter(row => row.session_id === 's1');
  assert.deepEqual(first.map(row => row.type), ['first-message-recall', 'first-message-recall-skipped']);
  assert.equal(first[1].until, '2026-09-09T01:00:00Z');

  // Before the reset the next session never spawns the CLI and records the same pause.
  delete process.env.RECALL_429;
  assert.deepEqual(call('s2', '2026-09-08T12:00:00Z'), { code: 0, lines: [], stderr: [] });
  assert.equal(sent(), 2, 'no request left the machine');
  assert.deepEqual(usage().filter(row => row.session_id === 's2').map(row => [row.type, row.until]),
    [['first-message-recall-skipped', '2026-09-09T01:00:00Z']]);
  assert.deepEqual(call('s2', '2026-09-08T12:01:00Z'), { code: 0, lines: [], stderr: [] });
  assert.equal(usage().filter(row => row.session_id === 's2').length, 1, 'a later prompt in a paused session is not a first prompt again');

  // After the reset the call goes out again and the answer is shown.
  const resumed = call('s3', '2026-09-09T01:00:01Z');
  assert.equal(sent(), 3);
  assert.match(resumed.lines[0], /read the compiler error|advice L-a/);
  assert.deepEqual(usage().filter(row => row.session_id === 's3').map(row => row.type), ['first-message-recall', 'shown']);
});

test('a lesson bound to a failed call names what it fires on in its index line', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [
    lesson('L-on', { trigger_match: { tool: 'Bash', command_id: 'bun test', error_signature: 'Cannot find module ./x', path_glob: null } }),
    lesson('L-edit', { trigger_match: { tool: 'Edit', command_id: null, error_signature: 'String to replace not found', path_glob: '*.ts' } }),
    lesson('L-plain', { trigger_match: null }),
  ]);
  const index = idx(recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED).lines).map(line => line.split('\n')[0]).sort();
  assert.deepEqual(index, [
    'L-edit · general · trigger L-edit [on: *.ts] — advice L-edit',
    'L-on · general · trigger L-on [on: bun test] — advice L-on',
    'L-plain · general · trigger L-plain — advice L-plain',
  ]);
});

test('experience graph: emits complete lesson context', t => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const complete = lesson('L-complete', { expected_result: 'The account contains the report that was written.',
    success_criteria: 'Read the account and observe the report title and body.', memory_fact_ids: ['fact-report-format'],
    skill_target: 'skills/report-writer', situation: { task_type: 'report', trigger: 'writing the report', tools: ['account_read'] } });
  const store = seed(config, [complete, lesson('L-old'), lesson('L-pending', { ...complete, lesson_id: 'L-pending', status: 'candidate' })]);
  const fields = ['"task_type":"report"', '"tools":["account_read"]', 'advice L-complete',
    String(complete.expected_result), String(complete.success_criteria), 'fact-report-format', 'skills/report-writer'];
  const start = recall(store, 'claude-code', { session_id: 'experience-start', cwd: checkout }, NOW, ARMED);
  assert.equal(start.code, 0);
  const detail = lessonDetail(store, 'L-complete', { session: 'experience-start', cwd: checkout, agent: 'claude-code' }, NOW);
  assert.equal(detail.code, 0);
  for (const value of fields) {
    assert.ok(start.lines.join('\n').includes(value), `session-start contains ${value}`);
    assert.ok(detail.lines.join('\n').includes(value), `detail contains ${value}`);
  }
  const pending = lessonDetail(store, 'L-pending', { cwd: checkout, agent: 'claude-code' }, NOW);
  assert.equal(pending.code, 0, 'the owner can inspect a listed candidate before deciding');
  assert.ok(pending.lines.join('\n').includes(String(complete.success_criteria)));

  const bin = tmp('experience-recall-bin');
  writeFileSync(join(bin, 'sno'), `#!/usr/bin/env node
const args = process.argv.slice(2).join(' ');
if (args === 'station consent --json') console.log('{"consent":"full"}');
else if (args === 'rem recall --json') console.log('{"lesson_ids":["L-complete"]}');
else process.exit(2);
`, { mode: 0o755 });
  const beforePath = process.env.PATH;
  process.env.PATH = `${bin}:${beforePath ?? ''}`;
  t.after(() => { if (beforePath === undefined) delete process.env.PATH; else process.env.PATH = beforePath; });
  const prompt = firstMessageRecall(store, 'claude-code', { session_id: 'experience-prompt', cwd: checkout, prompt: 'write the report' }, NOW);
  assert.equal(prompt.code, 0);
  const context = JSON.parse(prompt.lines[0]).hookSpecificOutput.additionalContext as string;
  for (const value of fields) assert.ok(context.includes(value), `prompt contains ${value}`);
  assert.ok(!context.includes('L-old'), 'the selected prompt does not add an unrelated lesson');
  const usage = readFileSync(join(store, 'ledger/usage.jsonl'), 'utf8').trim().split('\n').map(line => JSON.parse(line));
  assert.ok(usage.some(row => row.type === 'shown' && row.session_id === 'experience-prompt' && row.lesson_ids.includes('L-complete')));
  assert.ok(usage.some(row => row.type === 'read' && row.session_id === 'experience-start' && row.lesson_id === 'L-complete'));
});

test('experience graph: prompt context survives a failed shown append', t => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const complete = lesson('L-prompt-failure', { expected_result: 'The saved report matches the requested content.',
    success_criteria: 'Read back the report title and body.', memory_fact_ids: ['fact-report-format'],
    skill_target: 'skills/report-writer' });
  const store = seed(config, [complete]);
  const bin = tmp('experience-shown-failure');
  const entry = join(bin, 'entry.jsonl');
  const usage = join(store, 'ledger/usage.jsonl');
  writeFileSync(join(bin, 'sno'), `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2).join(' ');
if (args === 'station consent --json') console.log('{"consent":"full"}');
else if (args === 'rem recall --json') {
  fs.copyFileSync(${JSON.stringify(usage)}, ${JSON.stringify(entry)});
  fs.unlinkSync(${JSON.stringify(usage)});
  fs.mkdirSync(${JSON.stringify(usage)});
  console.log('{"lesson_ids":["L-prompt-failure"]}');
} else process.exit(2);
`, { mode: 0o755 });
  const beforePath = process.env.PATH;
  process.env.PATH = `${bin}:${beforePath ?? ''}`;
  t.after(() => { if (beforePath === undefined) delete process.env.PATH; else process.env.PATH = beforePath; });
  const result = firstMessageRecall(store, 'claude-code', {
    session_id: 'experience-prompt-failure', cwd: checkout, prompt: 'write the report',
  }, NOW);
  const handled = JSON.parse(readFileSync(entry, 'utf8').trim());
  assert.equal(handled.type, 'first-message-recall', 'the ordinary first-message append succeeded before selection');
  assert.equal(handled.session_id, 'experience-prompt-failure');
  assert.equal(result.code, 0);
  const context = JSON.parse(result.lines[0]).hookSpecificOutput.additionalContext as string;
  for (const value of [JSON.stringify(complete.situation), String(complete.advice), String(complete.expected_result),
    String(complete.success_criteria), 'fact-report-format', 'skills/report-writer']) assert.ok(context.includes(value));
  assert.match(result.stderr?.join('\n') ?? '', /EISDIR/);
  assert.match(result.stderr?.join('\n') ?? '', /session experience-prompt-failure, lessons L-prompt-failure; context delivered without use measurement/);
});
