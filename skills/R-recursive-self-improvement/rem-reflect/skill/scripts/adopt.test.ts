import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync, type SpawnSyncReturns } from 'node:child_process';
import { chmodSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { verdictCommand } from './adopt.ts';
import { reflectionFiles } from './config.ts';
import { appendLedger, readLedger } from './ledger.ts';
import { appendRows, readLessons } from './lessons.ts';
import { git, writeJson } from './store.ts';
import { applyCloudResponse } from './cloud.ts';
import { fixtureConfig, makeStore, tmp } from './test-helpers.ts';

const NOW = new Date('2026-09-23T00:00:00Z');

function lesson(id: string, appliesTo: string, advice = `advice ${id}`): Record<string, unknown> {
  const situation = { task_type: 'debug', trigger: `trigger ${id}`, tools: [] };
  return { lesson_id: id, page_id: `pg-${id}`, status: 'candidate', count: 1, helped: 0, harmful: 0,
    measured: false, created_run: '20260923-0000', project_id: 'github.com/example/project', agent_id: 'codex', user_id: 'u',
    skill_target: null, scenario: situation, situation, advice, because: `because ${id}`, applies_to: appliesTo,
    polarity: 'from_failure', evidence: [], counter_examples: { searched: true, traces_checked: ['t.v1'], found: [] },
    listed: true, judgment_id: `j-${id}` };
}

function commandHarness(store: string): { run(args: string[]): SpawnSyncReturns<string>; bin: string } {
  const bin = tmp('adopt-bin');
  const sno = join(bin, 'sno');
  writeFileSync(sno, '#!/bin/sh\n[ "$*" = "station consent" ] && { echo off; exit 0; }\nexit 2\n');
  chmodSync(sno, 0o755);
  const entry = join(import.meta.dirname, 'rem-reflect.ts');
  return { bin, run: (args: string[]) => spawnSync(process.execPath, ['--experimental-strip-types', entry, ...args], {
    encoding: 'utf8', env: { ...process.env, PATH: `${bin}:${process.env.PATH ?? ''}`, REM_REFLECT_STORE: store },
  }) };
}

test('running with no arguments prints the usage and exits 0; an unknown command exits 2', () => {
  const harness = commandHarness(makeStore(fixtureConfig()));
  const bare = harness.run([]);
  assert.equal(bare.status, 0, bare.stderr);
  assert.match(bare.stdout, /Usage: sno rem-reflect/);
  assert.equal(harness.run(['nonsense']).status, 2);
});

test('verdict command refuses values outside accept, reject, and tbd', () => {
  const store = makeStore(fixtureConfig());
  const result = verdictCommand(store, 'Parked', '20260908-0000/codex');
  assert.equal(result.code, 2);
  assert.match(result.lines.join('\n'), /unknown verdict: Parked/);
});

test('verdict command names a proposal id that does not exist', () => {
  const store = makeStore(fixtureConfig());
  const result = verdictCommand(store, 'accept', '20260908-0000/codex');
  assert.equal(result.code, 1);
  assert.match(result.lines.join('\n'), /no such proposal/);
});

test('plain accept keeps project scope while --all-projects records a general lesson and promoted pending verdict', () => {
  const store = makeStore(fixtureConfig());
  appendRows(join(store, reflectionFiles.lessons), [
    lesson('L-project', 'project:github.com/example/project'),
    lesson('L-promoted', 'project:github.com/example/project'),
  ]);
  const { run } = commandHarness(store);

  const plain = run(['accept', 'L-project']);
  assert.equal(plain.status, 0, plain.stderr);
  const promoted = run(['accept', 'L-promoted', '--all-projects']);
  assert.equal(promoted.status, 0, promoted.stderr);

  const lessons = new Map(readLessons(store).map(row => [row.lesson_id, row]));
  const projectLesson = lessons.get('L-project');
  assert.ok(projectLesson, 'plain accept stores the lesson');
  assert.equal(projectLesson.status, 'accepted');
  assert.equal(projectLesson.applies_to, 'project:github.com/example/project');
  assert.equal(lessons.get('L-promoted')?.applies_to, 'general');
  const pending = readLedger(store).filter(row => row.type === 'cloud-verdict' && row.status === 'pending');
  const projectPending = pending.find(row => row.judgment_id === 'j-L-project');
  assert.ok(projectPending, 'plain accept stores the linked pending cloud verdict');
  assert.equal(projectPending.applies_to, undefined);
  assert.equal(pending.find(row => row.judgment_id === 'j-L-promoted')?.applies_to, 'general');
});

test('an accepted project lesson can be promoted once to all projects', () => {
  const store = makeStore(fixtureConfig());
  appendRows(join(store, reflectionFiles.lessons), [lesson('L-late-promotion', 'project:github.com/example/project')]);
  const { run } = commandHarness(store);

  const plain = run(['accept', 'L-late-promotion']);
  assert.equal(plain.status, 0, plain.stderr);
  const promoted = run(['accept', 'L-late-promotion', '--all-projects']);
  assert.equal(promoted.status, 0, promoted.stderr);
  assert.equal(readLessons(store).find(row => row.lesson_id === 'L-late-promotion')?.applies_to,
    'general');
  assert.equal(readLedger(store).some(row => row.type === 'cloud-verdict' && row.judgment_id === 'j-L-late-promotion'
    && row.applies_to === 'general'), true);
  const before = readFileSync(join(store, reflectionFiles.lessons), 'utf8');
  const ledgerBefore = readLedger(store);
  assert.equal(run(['accept', 'L-late-promotion', '--all-projects']).status, 0);
  assert.equal(readFileSync(join(store, reflectionFiles.lessons), 'utf8'), before);
  assert.deepEqual(readLedger(store), ledgerBefore);
});

test('plain accept of a skill lesson keeps it in its project without editing SKILL.md; promotion adopts it user-wide', () => {
  const config = fixtureConfig();
  const store = makeStore(config);
  const target = join(config.claude_home, 'skills', 'heartbeat');
  const copies = [config.claude_home, config.codex_home].map(home => join(home, 'skills', 'heartbeat', 'SKILL.md'));
  const before = copies.map(path => readFileSync(path, 'utf8'));
  appendRows(join(store, reflectionFiles.lessons), [
    lesson('L-skill-project', `skill:${target}`, 'project-only reminder'),
    lesson('L-skill-general', `skill:${target}`, 'all-project reminder'),
  ]);
  const { run } = commandHarness(store);

  const plain = run(['accept', 'L-skill-project']);
  assert.equal(plain.status, 0, plain.stderr);
  assert.deepEqual(copies.map(path => readFileSync(path, 'utf8')), before, 'plain accept does not edit either installed skill');
  assert.equal(readLessons(store).find(row => row.lesson_id === 'L-skill-project')?.applies_to, 'project:github.com/example/project');

  const promoted = run(['accept', 'L-skill-general', '--all-projects']);
  assert.equal(promoted.status, 0, promoted.stderr);
  for (const path of copies) assert.match(readFileSync(path, 'utf8'), /all-project reminder/);
  assert.equal(readLessons(store).find(row => row.lesson_id === 'L-skill-general')?.applies_to, 'general');
});

test('--all-projects is refused for reject, tbd, and proposal ids without appending a row', () => {
  const store = makeStore(fixtureConfig());
  appendRows(join(store, reflectionFiles.lessons), [lesson('L-reject', 'project:p'), lesson('L-tbd', 'project:p')]);
  appendLedger(store, { type: 'proposal', proposal_id: '20260923-0000/codex', run_id: '20260923-0000', half: 'codex',
    kind: 'no_action', target: null, region: null, purpose: { summary: 'none', page_ids: [] }, verdict: 'pending' });
  const { run } = commandHarness(store);
  for (const args of [
    ['reject', 'L-reject', '--all-projects'],
    ['tbd', 'L-tbd', '--all-projects'],
    ['accept', '20260923-0000/codex', '--all-projects'],
  ]) {
    const lessonsBefore = readFileSync(join(store, reflectionFiles.lessons), 'utf8');
    const ledgerBefore = readFileSync(join(store, reflectionFiles.ledger), 'utf8');
    const result = run(args);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /--all-projects.*only.*lesson.*accept|--all-projects.*lesson.*accept.*only/i);
    assert.equal(readFileSync(join(store, reflectionFiles.lessons), 'utf8'), lessonsBefore);
    assert.equal(readFileSync(join(store, reflectionFiles.ledger), 'utf8'), ledgerBefore);
  }
});

test('a lesson verdict and second run ignore a legacy global lock while run.lock still blocks the second run', () => {
  const store = makeStore(fixtureConfig());
  appendRows(join(store, reflectionFiles.lessons), [lesson('L-during-run', 'project:github.com/example/project')]);
  const holder = { pid: process.pid, command: 'run', id: '20260923-0000' };
  writeFileSync(join(store, 'run.lock'), `${JSON.stringify(holder)}\n`);
  const legacy = `${JSON.stringify({ pid: process.pid, command: 'legacy-global', id: 'legacy-holder' })}\n`;
  writeFileSync(join(store, '.lock'), legacy);
  const { run } = commandHarness(store);

  const accepted = run(['accept', 'L-during-run']);
  assert.equal(accepted.status, 0, accepted.stderr);
  assert.equal(readLessons(store).find(row => row.lesson_id === 'L-during-run')?.status, 'accepted');
  assert.equal(readFileSync(join(store, '.lock'), 'utf8'), legacy, 'accept ignores and preserves the legacy lock bytes');

  const second = run(['run', '--now', '2026-09-23T01:00:00Z']);
  assert.equal(second.status, 0, second.stderr);
  assert.match(second.stdout, /lock held by run 20260923-0000/);
  assert.equal(readFileSync(join(store, '.lock'), 'utf8'), legacy, 'run ignores and preserves the legacy lock bytes');
});

test('ordinary accept succeeds and leaves appended rows for the next commit when git is busy', () => {
  const store = makeStore(fixtureConfig());
  appendRows(join(store, reflectionFiles.lessons), [lesson('L-git-busy', 'project:github.com/example/project')]);
  const before = git(store, ['rev-parse', 'HEAD']).trim();
  const indexLock = join(store, '.git', 'index.lock');
  writeFileSync(indexLock, 'held by fixture\n');
  const { run } = commandHarness(store);

  try {
    const started = Date.now();
    const accepted = run(['accept', 'L-git-busy']);
    assert.equal(accepted.status, 0, accepted.stderr);
    assert.ok(Date.now() - started < 2000, 'accept returns promptly while git is busy');
    assert.equal(readLessons(store).find(row => row.lesson_id === 'L-git-busy')?.status, 'accepted');
    assert.ok(readLedger(store).some(row => row.type === 'cloud-verdict' && row.judgment_id === 'j-L-git-busy'
      && row.status === 'pending'));
    assert.equal(git(store, ['rev-parse', 'HEAD']).trim(), before, 'accept does not require or claim a new commit');
  } finally {
    unlinkSync(indexLock);
  }
});

test('plain accept keeps a user-wide lesson user-wide, --this-project moves it to its project, and an agent scope becomes the project', () => {
  const store = makeStore(fixtureConfig());
  appendRows(join(store, reflectionFiles.lessons), [lesson('L-user-wide', 'general'), lesson('L-moved', 'general'),
    lesson('L-old-agent', 'agent:codex')]);
  const { run } = commandHarness(store);
  const scopeAfter = (args: string[]): string | undefined => {
    const result = run(args);
    assert.equal(result.status, 0, result.stderr);
    return readLessons(store).find(row => row.lesson_id === args[1])?.applies_to;
  };
  assert.equal(scopeAfter(['accept', 'L-user-wide']), 'general');
  assert.equal(scopeAfter(['accept', 'L-moved', '--this-project']), 'project:github.com/example/project');
  assert.equal(scopeAfter(['accept', 'L-old-agent']), 'project:github.com/example/project');
  assert.equal(run(['reject', 'L-user-wide', '--this-project']).status, 2);
});

test('replaying an older cloud answer does not undo an accepted lesson or its promotion', () => {
  const config = fixtureConfig();
  const store = makeStore(config);
  const decided = { ...lesson('L-decided', 'general'), status: 'accepted', judgment_id: 'j-new' };
  appendRows(join(store, reflectionFiles.lessons), [decided]);
  const response = { schema_version: 1 as const, run_id: '20260921-0100', history_acknowledged: true, history_links: [],
    halves: [{ harness: 'codex', attention: [], pages: [], proposals: [], read_judgments: [], log_entry: 'old',
      lessons: [{ judgment_id: 'j-old', lesson: lesson('L-decided', 'project:github.com/example/project') }] }] };
  writeJson(join(store, 'staging', response.run_id, 'cloud-request.json'), {
    schema_version: 1, run_id: response.run_id, halves: [], catalogue: [], usage_reads: [], outcome_summary: {} });
  applyCloudResponse(store, config, response as never);
  const latest = readLessons(store).filter(row => row.lesson_id === 'L-decided').pop();
  assert.equal(latest?.status, 'accepted');
  assert.equal(latest?.applies_to, 'general');
});

test('accepting a lesson known to the cloud only through a history link sends its verdict', () => {
  const store = makeStore(fixtureConfig());
  const old = lesson('L-history', 'project:github.com/example/project');
  delete old.judgment_id;
  appendRows(join(store, reflectionFiles.lessons), [old]);
  appendLedger(store, { type: 'cloud-link', kind: 'lesson', local_id: 'L-history', judgment_id: 'j-history' });
  const { run } = commandHarness(store);
  const result = run(['accept', 'L-history', '--all-projects']);
  assert.equal(result.status, 0, result.stderr);
  const pending = readLedger(store).filter(row => row.type === 'cloud-verdict' && row.judgment_id === 'j-history');
  assert.equal(pending.length, 1);
  assert.equal(pending[0].applies_to, 'general');
});
