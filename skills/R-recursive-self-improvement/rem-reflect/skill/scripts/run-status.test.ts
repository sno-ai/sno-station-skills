import { test } from 'node:test';
import assert from 'node:assert/strict';
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { run, status } from './rem-reflect.ts';
import { harvest } from './harvest.ts';
import { projectId } from './identity.ts';
import { atomicWrite, emptyState, git, processAlive, readState, writeState } from './store.ts';
import { calendar as cal } from './config.ts';
import {
  DAY, tmp, fixtureCheckout, fixtureConfig, makeStore, setMtime, FixtureBackend,
  writeClaudeSession, claudeUser, claudeAssistant,
} from './test-helpers.ts';

function fixtureRun(store: string, now: Date) {
  return run(store, now, 'u', new FixtureBackend());
}

function env(over: Record<string, unknown> = {}) {
  const repo = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x'), ...over });
  return { repo, config };
}
function rawFiles(store: string): string[] {
  const out: string[] = [];
  const walk = (d: string) => { for (const e of readdirSync(d, { withFileTypes: true })) {
    const p = join(d, e.name); if (e.isDirectory()) walk(p);
    else if (e.name.endsWith('.json') && !e.name.endsWith('.label.json')) out.push(p); } };
  const raw = join(store, 'raw'); if (existsSync(raw)) walk(raw);
  return out.sort();
}
function commits(store: string): string[] {
  return git(store, ['log', '--format=%s']).trim().split('\n').filter(Boolean);
}
// A content hash of every store file except volatile holders and git internals, so a test can
// prove a command changed nothing at all, not merely that it added no commit.
function snapshot(store: string): string {
  const hash = createHash('sha256');
  const walk = (d: string) => { for (const e of readdirSync(d, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (['.git', 'run.lock', '.recovery-lock'].includes(e.name) || e.name.startsWith('.tmp-')) continue;
    const p = join(d, e.name);
    if (e.isDirectory()) walk(p); else hash.update(`${p.slice(store.length)}\0${readFileSync(p)}\0`);
  } };
  walk(store);
  return hash.digest('hex');
}

// Run: a run that finds the lock held exits 0 naming the holder ---
test('run finds the lock held, exits 0, names the holder, writes nothing new', () => {
  const { config } = env();
  const store = makeStore(config);
  atomicWrite(join(store, 'run.lock'), JSON.stringify({ pid: process.pid, command: 'run', id: '20260908-0000', journal: null }) + '\n');
  const before = snapshot(store);
  const r = fixtureRun(store, new Date('2026-09-09T00:00:00Z'));
  assert.equal(r.code, 0);
  assert.match(r.lines.join('\n'), /lock held by run 20260908-0000/);
  assert.equal(snapshot(store), before, 'a lock-held run changes no store file at all');
  unlinkSync(join(store, 'run.lock'));
});

// Run: a writing run commits once; a same-day no-op makes no commit ---
test('a run commits under its id; a second run the same day is a no-op with no new commit', () => {
  const { config } = env();
  const store = makeStore(config);
  const day = new Date('2026-09-08T00:00:00Z');
  const base = commits(store).length;
  const r1 = fixtureRun(store, day);
  assert.equal(r1.code, 0);
  const id = cal(day, 'UTC').id;
  assert.ok(commits(store).includes(id), 'commit message is the run id');
  const after1 = commits(store).length;
  assert.equal(after1, base + 1, 'a writing run makes exactly one commit');
  assert.equal(readState(store).last_terminal?.status, 'success', 'the first run succeeded, so the day is done');
  const r2 = fixtureRun(store, new Date('2026-09-08T06:00:00Z'));
  assert.match(r2.lines.join('\n'), /no-op: .*already succeeded/);
  assert.equal(commits(store).length, after1, 'no-op day adds no commit');
});

// tolerant parsing; the bad-JSON file climbs to unparseable and stops being retried ---
function badPending(store: string) {
  const state = readState(store);
  const key = Object.keys(state.pending).find(p => p.endsWith('bad.jsonl'));
  return key ? state.pending[key] : undefined;
}

test('a well-formed, an unknown-record, and a bad-JSON session: run exits 0, harvests the good, records pending; failures climb to unparseable and stop', () => {
  const { config } = env();
  const store = makeStore(config);
  const mt = new Date('2026-09-05T00:00:00Z').getTime();
  writeClaudeSession(config.claude_root, 'a', 'good', [
    claudeUser('/n', 'good', 'hi'), claudeAssistant('/n', 'good', [{ type: 'text', text: 'ok' }]),
  ], mt);
  writeClaudeSession(config.claude_root, 'b', 'unk', [
    { type: 'future-kind', note: 'x' } as never, claudeUser('/n', 'unk', 'hi'),
    claudeAssistant('/n', 'unk', [{ type: 'text', text: 'ok' }]),
  ], mt);
  const badDir = join(config.claude_root, 'c'); mkdirSync(badDir, { recursive: true });
  const bad = join(badDir, 'bad.jsonl');
  writeFileSync(bad, `${JSON.stringify(claudeUser('/n', 'bad', 'hi'))}\nNOT JSON\n`);
  setMtime(bad, mt);

  // Day 1: the good and unknown-record sessions are harvested; the bad file records failure 1.
  const r = fixtureRun(store, new Date('2026-09-08T00:00:00Z'));
  assert.equal(r.code, 0);
  const ids = rawFiles(store).map(p => p.split('/').pop());
  assert.ok(ids.includes('good.v1.json'), 'well-formed harvested');
  const unkPath = rawFiles(store).find(p => p.endsWith('unk.v1.json'))!;
  assert.ok(unkPath, 'unknown-record session harvested');
  // the unknown record is kept but counted, not silently dropped
  const unkTrace = JSON.parse(readFileSync(unkPath, 'utf8'));
  assert.ok(unkTrace.skipped_records >= 1, 'the unknown record type is counted');
  assert.ok(!ids.includes('bad.v1.json'), 'bad-JSON session not harvested');
  assert.equal(badPending(store)?.failures, 1);
  assert.equal(badPending(store)?.status, 'pending');
  assert.match(r.lines.join('\n'), /pending:.*bad\.jsonl/);

  // Day 2: a newer well-formed session advances the project cursor PAST the bad file's mtime,
  // and the bad file is still retried regardless of the cursor -> failure 2.
  writeClaudeSession(config.claude_root, 'd', 'newer', [
    claudeUser('/n', 'newer', 'hi'), claudeAssistant('/n', 'newer', [{ type: 'text', text: 'ok' }]),
  ], new Date('2026-09-06T00:00:00Z').getTime());
  fixtureRun(store, new Date('2026-09-09T00:00:00Z'));
  assert.ok(rawFiles(store).some(p => p.endsWith('newer.v1.json')), 'newer session harvested, cursor advanced');
  assert.equal(badPending(store)?.failures, 2, 'bad file retried though the cursor moved past it');
  assert.equal(badPending(store)?.status, 'pending');

  // Day 3: third failure -> unparseable.
  fixtureRun(store, new Date('2026-09-10T00:00:00Z'));
  assert.equal(badPending(store)?.failures, 3);
  assert.equal(badPending(store)?.status, 'unparseable');

  // Day 4: an unparseable file is not retried -> failure count does not climb.
  fixtureRun(store, new Date('2026-09-11T00:00:00Z'));
  assert.equal(badPending(store)?.failures, 3, 'unparseable file is not retried');
});

test('a bad-JSON file repaired before the third failure is harvested and cleared from pending', () => {
  const { config } = env();
  const store = makeStore(config);
  const badDir = join(config.claude_root, 'c'); mkdirSync(badDir, { recursive: true });
  const bad = join(badDir, 'bad.jsonl');
  writeFileSync(bad, `${JSON.stringify(claudeUser('/n', 'bad', 'hi'))}\nNOT JSON\n`);
  setMtime(bad, new Date('2026-09-05T00:00:00Z').getTime());
  fixtureRun(store, new Date('2026-09-08T00:00:00Z'));
  assert.equal(badPending(store)?.failures, 1);
  // Repair it, then the next day's run harvests it and clears the pending entry.
  writeFileSync(bad, `${JSON.stringify(claudeUser('/n', 'bad', 'hi'))}\n${JSON.stringify(claudeAssistant('/n', 'bad', [{ type: 'text', text: 'ok' }]))}\n`);
  setMtime(bad, new Date('2026-09-05T12:00:00Z').getTime());
  fixtureRun(store, new Date('2026-09-09T00:00:00Z'));
  assert.ok(rawFiles(store).some(p => p.endsWith('bad.v1.json')), 'repaired file harvested');
  assert.equal(badPending(store), undefined, 'pending entry cleared');
});

// Run: a missing config.json stops the run before the lock, naming the field ---
test('a deleted config.json stops the run naming config.json, with no lock left', () => {
  const { config } = env();
  const store = makeStore(config);
  unlinkSync(join(store, 'config.json'));
  assert.throws(() => fixtureRun(store, new Date('2026-09-08T00:00:00Z')), /config\.json/);
  assert.equal(existsSync(join(store, 'run.lock')), false, 'no lock left behind');
});

// a dead run lock is stale, not an incident: the next run takes it over and proceeds ---
test('a dead run lock is taken over, the run proceeds, and its report opens with the notice', () => {
  const { config } = env();
  const store = makeStore(config);
  const deadPid = 2_147_483_646;
  assert.equal(processAlive(deadPid), false, 'chosen pid must be dead for the test to mean anything');
  const y = cal(new Date('2026-09-07T00:00:00Z'), 'UTC');
  writeState(store, { ...emptyState(), last_start: { id: y.id, date: y.date } });
  git(store, ['add', '--all']); git(store, ['commit', '--quiet', '-m', 'seed']);
  atomicWrite(join(store, 'run.lock'), JSON.stringify({ pid: deadPid, command: 'run', id: y.id }) + '\n');
  const today = cal(new Date('2026-09-08T00:00:00Z'), 'UTC');
  const r = fixtureRun(store, new Date('2026-09-08T00:00:00Z'));
  assert.equal(r.code, 0, r.lines.join('\n'));
  const report = readFileSync(join(store, 'staging', today.id, 'REPORT.md'), 'utf8');
  assert.match(report, new RegExp(`previous run ${y.id} did not finish`), 'the report opens with the notice');
  assert.equal(readState(store).last_terminal?.id, today.id, 'the taking-over run records its own terminal');
});

// A dead lock from a day that already succeeded still no-ops, and the stale lock does not block it.
test('a dead lock on a day that already succeeded still no-ops', () => {
  const { config } = env();
  const store = makeStore(config);
  const deadPid = 2_147_483_646;
  const today = cal(new Date('2026-09-08T00:00:00Z'), 'UTC');
  writeState(store, { ...emptyState(), last_start: { id: today.id, date: today.date },
    last_terminal: { id: today.id, date: today.date, status: 'success' } });
  git(store, ['add', '--all']); git(store, ['commit', '--quiet', '-m', 'seed']);
  atomicWrite(join(store, 'run.lock'), JSON.stringify({ pid: deadPid, command: 'run', id: today.id }) + '\n');
  const r = fixtureRun(store, new Date('2026-09-08T01:00:00Z'));
  assert.equal(r.code, 0);
  assert.match(r.lines.join('\n'), /already succeeded/);
});

// Run: a later-day run over unchanged roots writes no new trace; v1 byte-identical ---
test('a later-day run over unchanged roots writes no new trace and leaves v1 byte-identical', () => {
  const { config } = env();
  const store = makeStore(config);
  writeClaudeSession(config.claude_root, 'a', 'dup', [
    claudeUser('/n', 'dup', 'hi'), claudeAssistant('/n', 'dup', [{ type: 'text', text: 'ok' }]),
  ], new Date('2026-09-05T00:00:00Z').getTime());
  fixtureRun(store, new Date('2026-09-08T00:00:00Z'));
  const files1 = rawFiles(store);
  assert.equal(files1.length, 1);
  const bytes1 = readFileSync(files1[0], 'utf8');
  fixtureRun(store, new Date('2026-09-09T00:00:00Z'));
  const files2 = rawFiles(store);
  assert.equal(files2.length, 1, 'no duplicate trace on the second day');
  assert.equal(readFileSync(files2[0], 'utf8'), bytes1, 'v1 is byte-identical');
});

// Harvest: 7-day floor, cursor, 30-minute quiet, resume v2 ---
test('the first run harvests a 6-day-old session and not an 8-day-old one; cursor at the 6-day mtime', () => {
  const { config } = env();
  const store = tmp('store');
  const now = new Date('2026-09-10T00:00:00Z');
  const six = now.getTime() - 6 * DAY;
  const eight = now.getTime() - 8 * DAY;
  const plain = tmp('plain');
  writeClaudeSession(config.claude_root, 'a', 'six', [claudeUser(plain, 'six', 'hi'), claudeAssistant(plain, 'six', [{ type: 'text', text: 'ok' }])], six);
  writeClaudeSession(config.claude_root, 'b', 'eight', [claudeUser(plain, 'eight', 'hi'), claudeAssistant(plain, 'eight', [{ type: 'text', text: 'ok' }])], eight);
  const state = emptyState();
  const { traces } = harvest(store, config, state, 'u', now);
  assert.deepEqual(traces.map(t => t.session_id).sort(), ['six']);
  assert.equal(state.cursors[`claude-code:${projectId(plain, undefined, {})}`], six);
});

test('a session modified 10 minutes before the run is left; 30 minutes later it is harvested', () => {
  const { config } = env();
  const store = tmp('store');
  const now = new Date('2026-09-10T00:00:00Z');
  const plain = tmp('plain');
  writeClaudeSession(config.claude_root, 'a', 'young', [claudeUser(plain, 'young', 'hi'), claudeAssistant(plain, 'young', [{ type: 'text', text: 'ok' }])], now.getTime() - 10 * 60_000);
  const state = emptyState();
  assert.equal(harvest(store, config, state, 'u', now).traces.length, 0, 'too young to harvest');
  const later = new Date(now.getTime() + 30 * 60_000);
  assert.equal(harvest(store, config, state, 'u', later).traces.length, 1, 'harvested after it settles');
});

test('a grown session yields v2 covering only the new lines and leaves v1 byte-identical', () => {
  const { config } = env();
  const store = tmp('store');
  const plain = tmp('plain');
  const path = writeClaudeSession(config.claude_root, 'a', 'resume', [
    claudeUser(plain, 'resume', 'one'), claudeAssistant(plain, 'resume', [{ type: 'text', text: 'first' }]),
  ], new Date('2026-09-05T00:00:00Z').getTime());
  const state = emptyState();
  harvest(store, config, state, 'u', new Date('2026-09-08T00:00:00Z'));
  const v1path = rawFiles(store)[0];
  const v1bytes = readFileSync(v1path, 'utf8');
  appendFileSync(path, JSON.stringify(claudeUser(plain, 'resume', 'two')) + '\n' + JSON.stringify(claudeAssistant(plain, 'resume', [{ type: 'text', text: 'second' }])) + '\n');
  setMtime(path, new Date('2026-09-08T12:00:00Z').getTime());
  const { traces } = harvest(store, config, state, 'u', new Date('2026-09-09T00:00:00Z'));
  assert.equal(traces.length, 1);
  assert.equal(traces[0].version, 2);
  assert.equal(traces[0].source_line_range[0], 3, 'v2 starts after v1 last line');
  assert.equal(traces[0].source_line_range[1], 4);
  assert.equal(readFileSync(v1path, 'utf8'), v1bytes, 'v1 untouched');
  // v2 holds ONLY the new records, not a re-harvest of the whole session
  const v2path = rawFiles(store).find(p => p.endsWith('resume.v2.json'))!;
  const v2 = readFileSync(v2path, 'utf8');
  assert.match(v2, /two/); assert.match(v2, /second/);
  assert.doesNotMatch(v2, /"one"/); assert.doesNotMatch(v2, /first/);
});
