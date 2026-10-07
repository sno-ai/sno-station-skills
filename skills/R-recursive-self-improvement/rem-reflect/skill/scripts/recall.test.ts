import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { recall, lessonDetail } from './recall.ts';
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
  assert.equal(r.lines[1], 'L-a · general · trigger L-a — advice L-a', 'one index line with the trigger and the advice');
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
  const store = seed(config, [lesson('L-ok'), lesson('L-cand', { status: 'candidate' }), lesson('L-tbd', { status: 'tbd' }),
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

test('lesson detail prints the four fields and appends one read line; --session S9 with no shown line still works', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-a')]);
  const d = lessonDetail(store, 'L-a', { session: 'S9', cwd: checkout, agent: 'claude-code' }, NOW);
  assert.equal(d.code, 0);
  assert.equal(d.lines.length, 4, 'exactly the four fields');
  assert.match(d.lines[0], /^situation: .*"trigger":"trigger L-a"/, 'situation carries its content, not an empty field');
  assert.equal(d.lines[1], 'advice: advice L-a');
  assert.equal(d.lines[2], 'because: because L-a');
  assert.match(d.lines[3], /^evidence: .*"trace_id":"t\.v1"/, 'evidence carries its content');
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
  const store = seed(config, [lesson('L-a')]);
  // make the usage file read-only so the append fails
  mkdirSync(join(store, 'ledger'), { recursive: true });
  writeFileSync(join(store, 'ledger/usage.jsonl'), '');
  chmodSync(join(store, 'ledger/usage.jsonl'), 0o400);
  const r = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  assert.equal(r.code, 0, 'recall still exits 0');
  assert.match(r.lines[0], /Lessons from this machine/);
  assert.equal(r.stderr?.length, 1, 'one stderr line names the append failure');
  assert.match(r.stderr!.join('\n'), /could not record use/);
  chmodSync(join(store, 'ledger/usage.jsonl'), 0o600);
});

test('a 300-character trigger and its advice reach the session-start list uncut', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = seed(config, [lesson('L-long', { situation: { task_type: 'w', trigger: 'z'.repeat(300), tools: [] },
    advice: 'Check the key field is unique before a production batch.' })]);
  const r = recall(store, 'claude-code', { session_id: 'S1', cwd: checkout }, NOW, ARMED);
  assert.equal(r.lines[1], `L-long · general · ${'z'.repeat(300)} — Check the key field is unique before a production batch.`);
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
    lesson('L-unverified', { status: 'candidate', listed: true }),
    lesson('L-verification-refused', { status: 'candidate', listed: true, verification: { accepted: false } }),
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
