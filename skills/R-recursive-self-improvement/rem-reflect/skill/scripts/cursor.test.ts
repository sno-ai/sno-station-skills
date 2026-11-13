// Cursor as a session source and a lesson-recall target. Rows follow the measured Cursor transcript shape
// (`{"role","message":{"content":[…]}}` plus `{"type":"turn_ended"}`, no timestamps, no tool output).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, lstatSync, mkdirSync, readFileSync, readlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { harvest } from './harvest.ts';
import type { Trace } from './harvest.ts';
import { buildCloudBatch } from './cloud.ts';
import { loadRenderBudgets, renderTrace } from './render.ts';
import { BackendError, RealBackend } from './backend.ts';
import { run } from './rem-reflect.ts';
import { appendRows } from './lessons.ts';
import { emptyState, git } from './store.ts';
import { DAY, fixtureCheckout, fixtureConfig, makeStore, setMtime, tmp } from './test-helpers.ts';

const COMMAND = fileURLToPath(new URL('./rem-reflect.ts', import.meta.url));

function writeTranscript(root: string, project: string, id: string, mtimeMs: number): string {
  const dir = join(root, project, 'agent-transcripts', id);
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `${id}.jsonl`);
  const rows = [
    { role: 'user', message: { content: [{ type: 'text', text: '<timestamp>Thursday, Oct 8, 2026, 1:57 PM (UTC-7)</timestamp>\n<user_query>\nAppend a line to note.txt\n</user_query>' }] } },
    { role: 'assistant', message: { content: [{ type: 'text', text: 'Appending it now.' },
      { type: 'tool_use', name: 'Shell', input: { command: "printf 'x\\n' >> note.txt", description: 'Append to note.txt' } }] } },
    { role: 'assistant', message: { content: [{ type: 'text', text: 'Done.' }] } },
    { type: 'turn_ended', status: 'success' },
  ];
  writeFileSync(path, rows.map(row => JSON.stringify(row)).join('\n') + '\n');
  setMtime(path, mtimeMs);
  return path;
}

function writeConversation(profile: string, id: string, project: string | null): void {
  mkdirSync(join(profile, 'cursor', 'conversations'), { recursive: true });
  writeFileSync(join(profile, 'cursor', 'conversations', `${id}.json`), JSON.stringify({ conversation_id: id, surface: 'ide', project }));
}

test('harvest collects Cursor conversations: the recorded repository scopes one, a conversation with no record is unscoped', () => {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ cursor_root: tmp('cursor-projects') });
  const profile = process.env.SNO_PROFILE_DIR ?? '';
  const now = new Date('2026-10-10T12:00:00Z');
  writeTranscript(config.cursor_root, 'Users-u-repoA', 'conv-scoped', now.getTime() - DAY);
  writeTranscript(config.cursor_root, 'Users-u-repoB', 'conv-unscoped', now.getTime() - DAY);
  writeConversation(profile, 'conv-scoped', checkout);
  const store = tmp('store');
  const { traces } = harvest(store, config, emptyState(), 'u', now);
  const byId = new Map(traces.map(trace => [trace.session_id, trace]));
  assert.deepEqual([...byId.keys()].sort(), ['conv-scoped', 'conv-unscoped']);
  const scoped = byId.get('conv-scoped');
  assert.ok(scoped);
  assert.equal(scoped.agent_id, 'cursor');
  assert.equal(scoped.project_id, 'github.com/example/project');
  assert.equal(byId.get('conv-unscoped')?.project_id, 'user-level');
  assert.equal(scoped.records.length, 3, 'the user row and both assistant rows are kept; turn_ended is skipped');
  assert.equal(scoped.skipped_records, 1);
  assert.equal(scoped.trivial, false, 'a tool call makes the conversation non-trivial');
  assert.ok(existsSync(join(store, 'raw', 'u', 'github.com', 'example', 'project', 'cursor', 'conv-scoped.v1.json')));
  const rendered = renderTrace(scoped, loadRenderBudgets()).records.map(row => row.text);
  assert.equal(rendered[0], '2: user Append a line to note.txt\n', 'the typed text, without the timestamp wrapper');
  assert.match(rendered[1], /Shell .*note\.txt/);
});

function lessonStore(): { store: string; checkout: string } {
  const checkout = fixtureCheckout();
  const store = makeStore(fixtureConfig());
  appendRows(join(store, 'wiki/lessons.jsonl'), [{ lesson_id: 'L-cursor', status: 'accepted', applies_to: 'general',
    situation: { task_type: 'fix', trigger: 'broken build', tools: [] }, advice: 'read the compiler error' }]);
  git(store, ['add', '--all']);
  git(store, ['commit', '--quiet', '-m', 'lesson']);
  return { store, checkout };
}

function recallRun(store: string, args: string[], input: unknown, env: NodeJS.ProcessEnv = {}) {
  return spawnSync(process.execPath, [COMMAND, 'recall', ...args], { input: JSON.stringify(input), encoding: 'utf8',
    env: { ...process.env, REM_REFLECT_STORE: store, ...env } });
}

function usageRows(store: string): Record<string, unknown>[] {
  const path = join(store, 'ledger/usage.jsonl');
  return existsSync(path) ? readFileSync(path, 'utf8').split('\n').filter(Boolean).map(line => JSON.parse(line) as Record<string, unknown>) : [];
}

test('recall --agent cursor answers in Cursor form, scoped by the git root of the first workspace folder', () => {
  const { store, checkout } = lessonStore();
  const sub = join(checkout, 'skills');
  const start = recallRun(store, ['--agent', 'cursor'], { conversation_id: 'c-1', session_id: 'c-1', hook_event_name: 'sessionStart',
    cursor_version: '3.24.9', workspace_roots: [sub, '/elsewhere'], transcript_path: null });
  assert.equal(start.status, 0);
  const answer = JSON.parse(start.stdout) as { additional_context: string };
  assert.match(answer.additional_context, /L-cursor/);
  assert.match(answer.additional_context, /read the compiler error/);
  const shown = usageRows(store).find(row => row.type === 'shown' && row.session_id === 'c-1');
  assert.equal(shown?.agent_id, 'cursor');
  assert.equal(shown?.project_id, 'github.com/example/project');

  const outside = recallRun(store, ['--agent', 'cursor'], { conversation_id: 'c-2', workspace_roots: [tmp('not-a-repo')] });
  assert.equal(outside.status, 0);
  assert.equal(outside.stdout.trim(), '{}');
  assert.match(outside.stderr, /no git work tree/);

  const noStore = recallRun(join(tmp('gone'), 'store'), ['--agent', 'cursor'], { conversation_id: 'c-3', workspace_roots: [checkout] });
  assert.equal(noStore.status, 0, 'a Cursor hook never fails the conversation');
  assert.equal(noStore.stdout.trim(), '{}');
  assert.equal(noStore.stderr, '', 'before the first nightly run the mainline recall emits no error');
});

test('the Cursor first-prompt hook brings the lesson index once when no session start showed it', () => {
  const { store, checkout } = lessonStore();
  const prompt = (text: string) => recallRun(store, ['--agent', 'cursor', '--first-message'],
    { conversation_id: 'ide-first', hook_event_name: 'beforeSubmitPrompt', prompt: text, workspace_roots: [checkout] });
  const first = prompt('fix the broken build please');
  assert.equal(first.status, 0);
  assert.match((JSON.parse(first.stdout) as { additional_context: string }).additional_context, /L-cursor/);
  const second = prompt('and now the tests');
  assert.equal(second.status, 0);
  assert.equal(second.stdout.trim(), '{}', 'the index is not repeated on a later prompt');

  const started = recallRun(store, ['--agent', 'cursor'], { conversation_id: 'cli-run', workspace_roots: [checkout] });
  assert.match(started.stdout, /L-cursor/);
  const afterStart = recallRun(store, ['--agent', 'cursor', '--first-message'],
    { conversation_id: 'cli-run', prompt: 'fix the broken build please', workspace_roots: [checkout] });
  assert.equal(afterStart.stdout.trim(), '{}', 'a conversation whose session start showed the index does not get it twice');
});

test('a Claude-format recall hook run by the Cursor IDE does nothing, while a real Claude Code session still recalls', () => {
  const { store, checkout } = lessonStore();
  const before = usageRows(store).length;
  const inCursor = recallRun(store, ['--agent', 'claude-code'], { conversation_id: 'c-9', session_id: 'c-9',
    hook_event_name: 'sessionStart', cursor_version: '3.23.23', workspace_roots: [checkout] });
  assert.equal(inCursor.status, 0);
  assert.equal(inCursor.stdout, '');
  const inCursorFirst = recallRun(store, ['--agent', 'claude-code', '--first-message'], { session_id: 'c-9', prompt: 'broken build',
    hook_event_name: 'beforeSubmitPrompt', cursor_version: '3.23.23', workspace_roots: [checkout] });
  assert.equal(inCursorFirst.stdout, '');
  assert.equal(usageRows(store).length, before, 'nothing is recorded for a Cursor-shaped input');
  const claude = recallRun(store, ['--agent', 'claude-code'], { session_id: 'claude-1', cwd: checkout });
  assert.match(claude.stdout, /L-cursor/);
});

test('recall install writes the two Cursor entries once, in place, and keeps entries another program wrote', () => {
  const home = tmp('cursor-install-home');
  mkdirSync(join(home, '.cursor'));
  const foreign = { command: '/opt/orca/hook.sh beforeSubmitPrompt' };
  writeFileSync(join(home, '.cursor', 'hooks.json'), JSON.stringify({ version: 1, other: 'kept',
    hooks: { beforeSubmitPrompt: [foreign, { command: 'sno rem-reflect recall --agent cursor --first-message', timeout: 2 }],
      stop: [{ command: '/opt/orca/hook.sh stop' }] } }));
  const bin = tmp('sno-bin');
  writeFileSync(join(bin, 'sno'), '#!/bin/sh\n', { mode: 0o755 });
  const env = { ...process.env, HOME: home, PATH: `${bin}:${process.env.PATH ?? ''}` };
  const install = () => spawnSync(process.execPath, [COMMAND, 'recall', 'install'], { encoding: 'utf8', env });
  assert.equal(install().status, 0);
  const second = install();
  assert.equal(second.status, 0, second.stderr);
  const file = JSON.parse(readFileSync(join(home, '.cursor', 'hooks.json'), 'utf8')) as Record<string, unknown> & { hooks: Record<string, unknown[]> };
  assert.equal(file.version, 1);
  assert.equal(file.other, 'kept');
  assert.deepEqual(file.hooks.sessionStart, [{ command: `'${bin}/sno' rem-reflect recall --agent cursor`, timeout: 15 }]);
  assert.deepEqual(file.hooks.beforeSubmitPrompt, [foreign, { command: `'${bin}/sno' rem-reflect recall --agent cursor --first-message`, timeout: 8 }],
    'the earlier bare-sno entry is replaced in place');
  assert.deepEqual(file.hooks.stop, [{ command: '/opt/orca/hook.sh stop' }]);

  const fresh = tmp('cursor-fresh-home');
  assert.equal(spawnSync(process.execPath, [COMMAND, 'recall', 'install'], { encoding: 'utf8', env: { ...env, HOME: fresh } }).status, 0);
  assert.equal(Object.keys((JSON.parse(readFileSync(join(fresh, '.cursor', 'hooks.json'), 'utf8')) as { hooks: object }).hooks).length, 2);
});

test('a Cursor labeling turn runs cursor-agent in the isolated home with the prompt on stdin and returns its result', () => {
  const home = tmp('cursor-user-home');
  mkdirSync(join(home, '.config', 'cursor'), { recursive: true });
  mkdirSync(join(home, '.local', 'share'), { recursive: true });
  writeFileSync(join(home, '.config', 'cursor', 'auth.json'), '{"accessToken":"t"}');
  const config = fixtureConfig({ cursor_root: tmp('cursor-projects') });
  const store = makeStore(config);
  const previousHome = process.env.HOME;
  process.env.HOME = home;
  try { assert.equal(run(store, new Date('2026-10-10T12:00:00Z'), 'u').code, 0); } finally { process.env.HOME = previousHome; }
  const loopHome = join(store, '.loop-home', 'cursor');
  // The login is a copy of auth.json on Linux; on macOS it lives in the login keychains, which are linked instead.
  if (process.platform === 'darwin') {
    assert.equal(readlinkSync(join(loopHome, 'Library', 'Keychains')), join(home, 'Library', 'Keychains'));
    assert.equal(existsSync(join(loopHome, '.config', 'cursor', 'auth.json')), false, 'no auth.json copy on macOS');
  } else {
    assert.equal(readFileSync(join(loopHome, '.config', 'cursor', 'auth.json'), 'utf8'), '{"accessToken":"t"}');
  }
  assert.equal(lstatSync(join(loopHome, '.local', 'share')).isSymbolicLink(), true);
  assert.equal(readlinkSync(join(loopHome, '.local', 'share')), join(home, '.local', 'share'));

  const bin = tmp('cursor-bin');
  const record = join(bin, 'call.json');
  writeFileSync(join(bin, 'cursor-agent'), `#!/usr/bin/env node
const fs = require('node:fs');
fs.writeFileSync(${JSON.stringify(record)}, JSON.stringify({ args: process.argv.slice(2), home: process.env.HOME, stdin: fs.readFileSync(0, 'utf8') }));
const helper = require('node:child_process').spawn('sleep', ['300'], { stdio: 'ignore' });
helper.unref();
fs.writeFileSync(${JSON.stringify(record)} + '.child', String(helper.pid));
if (process.env.FAKE_CURSOR === 'keychain') { process.stderr.write('Error: Your macOS login keychain is locked\\n'); process.exit(1); }
console.log(JSON.stringify(process.env.FAKE_CURSOR === 'error' ? { type: 'result', is_error: true, result: 'x' }
  : { type: 'result', subtype: 'success', is_error: false, result: '{"keep":true}', session_id: 's' }));
`);
  chmodSync(join(bin, 'cursor-agent'), 0o755);
  const previousPath = process.env.PATH;
  process.env.PATH = `${bin}:${previousPath ?? ''}`;
  try {
    const backend = new RealBackend(10_000, { loopHomeBase: join(store, '.loop-home') });
    assert.equal(backend.spawn({ cli: 'cursor', cwd: bin, input: 'label this session' }).stdout, '{"keep":true}');
    const call = JSON.parse(readFileSync(record, 'utf8')) as { args: string[]; home: string; stdin: string };
    assert.deepEqual(call.args, ['-p', '--trust', '--mode', 'ask', '--output-format', 'json']);
    assert.equal(call.home, loopHome);
    assert.equal(call.stdin, 'label this session');
    const helperPid = Number(readFileSync(`${record}.child`, 'utf8'));
    let helperState = '';
    const deadline = Date.now() + 1000;
    do {
      helperState = spawnSync('ps', ['-o', 'stat=', '-p', String(helperPid)], { encoding: 'utf8' }).stdout.trim();
      if (!helperState || helperState.startsWith('Z')) break;
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 10);
    } while (Date.now() < deadline);
    assert.equal(helperState === '' || helperState.startsWith('Z'), true, 'the helper is absent or terminated, never running');
    process.env.FAKE_CURSOR = 'error';
    assert.throws(() => backend.spawn({ cli: 'cursor', cwd: bin, input: 'x' }), (error: unknown) =>
      error instanceof BackendError && error.reason === 'labeler-invalid-response');
    process.env.FAKE_CURSOR = 'keychain';
    assert.throws(() => backend.spawn({ cli: 'cursor', cwd: bin, input: 'x' }), (error: unknown) =>
      error instanceof BackendError && error.reason === 'labeler-unavailable' && /Cursor CLI login unreadable \(keychain locked\)/.test(error.message));
  } finally {
    delete process.env.FAKE_CURSOR;
    process.env.PATH = previousPath;
  }
});

test('the cloud batch carries a cursor half only when a Cursor session is uploaded', () => {
  const config = fixtureConfig();
  const store = makeStore(config);
  const make = (agent: 'codex' | 'cursor', session: string): Trace => ({
    user_id: 'u', project_id: 'p', agent_id: agent, source_harness: agent, originator: agent,
    trace_id: `${session}.v1`, session_id: session, version: 1, source_path: '/source', source_line_range: [1, 2],
    source_mtime: Date.parse('2026-10-09T00:00:00Z'), skipped_records: 0, skipped_blocks: 0, redactions: 0, trivial: false,
    skills_loaded: [], records: [{ line_number: 2, source_line: 1, record: agent === 'codex'
      ? { type: 'response_item', payload: { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'done' }] } }
      : { type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: 'done' }] } } }],
  });
  const labelsFor = (traces: Trace[]) => new Map(traces.map(row => [`u/${row.agent_id}/${row.trace_id}`, {
    decision: 'keep' as const, outcome: 'fail' as const, reason: 'r', evidence: [], key_ranges: [], labeled_by: row.agent_id, model: 'm' }]));
  const codexOnly = [make('codex', 'x-1')];
  assert.deepEqual(buildCloudBatch(store, config, '20261010-0100', codexOnly, labelsFor(codexOnly), false).halves.map(half => half.harness), ['codex']);
  const both = [make('codex', 'x-1'), make('cursor', 'c-1')];
  const batch = buildCloudBatch(store, config, '20261010-0100', both, labelsFor(both), false);
  assert.deepEqual(batch.halves.map(half => half.harness), ['codex', 'cursor']);
  assert.deepEqual(batch.halves[1].sessions.map(row => row.trace_id), ['c-1.v1']);
});
