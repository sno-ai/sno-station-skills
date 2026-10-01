import { test } from 'node:test';
import type { TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { run } from './rem-reflect.ts';
import { stationCell } from './config.ts';
import type { Config } from './config.ts';
import { appendRows } from './lessons.ts';
import { git } from './store.ts';
import {
  tmp, fixtureConfig, fixtureCheckout, makeStore, FixtureBackend, writeStationSettings, stationSettings,
  writeCodexSession, codexMeta, codexUser, codexAssistant,
} from './test-helpers.ts';

const MT = new Date('2026-09-07T00:00:00Z').getTime();
const NIGHT = new Date('2026-09-08T00:00:00Z');

function useEnv(t: TestContext, vars: Record<string, string>): void {
  for (const [key, value] of Object.entries(vars)) {
    const before = process.env[key];
    process.env[key] = value;
    t.after(() => { if (before === undefined) delete process.env[key]; else process.env[key] = before; });
  }
}
function cfg(): Config { return fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') }); }
function codexTrace(config: Config): void {
  writeCodexSession(config.codex_root, 'cx', [codexMeta('cx', '/n'), codexUser('do it'), codexAssistant('ok')], MT);
}
function stagingFile(store: string, name: string): string | undefined {
  return readdirSync(join(store, 'staging'), { recursive: true }).map(String).find(path => path.endsWith(name));
}
function labelFiles(store: string): string[] {
  return readdirSync(join(store, 'raw'), { recursive: true }).map(String).filter(p => p.endsWith('.label.json'));
}
function nightRun(t: TestContext, mode: string, rows: Record<string, Record<string, string>> = {}, env: Record<string, string> = {}) {
  useEnv(t, { SNO_PROFILE_DIR: writeStationSettings(mode, rows), ...env });
  const config = cfg();
  const store = makeStore(config);
  codexTrace(config);
  const backend = new FixtureBackend();
  const result = run(store, NIGHT, 'u', backend);
  return { store, backend, result, labeler: backend.calls.filter(call => call.kind === 'labeler').length };
}

test('the cell comes from the file for the current mode, and a missing file, mode, row or value says which', () => {
  const profile = writeStationSettings('rem-enhanced', { R3: { 'local-first': 'off', 'agent-native': 'sno-gpu', 'rem-enhanced': 'off' } });
  assert.equal(stationCell('R2', { SNO_PROFILE_DIR: profile }), 'host');
  assert.equal(stationCell('R3', { SNO_PROFILE_DIR: profile }), 'off');
  const empty = tmp('empty-profile');
  assert.throws(() => stationCell('R2', { SNO_PROFILE_DIR: empty }), /settings unavailable: .*settings\.json: file missing; run sno setup/);
  const write = (body: string) => { const dir = tmp('bad-profile'); writeFileSync(join(dir, 'settings.json'), body); return dir; };
  assert.throws(() => stationCell('R2', { SNO_PROFILE_DIR: write('{') }), /not valid JSON/);
  assert.throws(() => stationCell('R2', { SNO_PROFILE_DIR: write(JSON.stringify({ modelCalls: {} })) }), /mode is missing or unknown/);
  assert.throws(() => stationCell('R4', { SNO_PROFILE_DIR: write(JSON.stringify({ mode: 'agent-native', modelCalls: { R2: {} } })) }), /modelCalls\.R4 is missing/);
  assert.throws(() => stationCell('R2', { SNO_PROFILE_DIR: write(stationSettings('agent-native', { R2: { 'agent-native': 'cloud' } })) }),
    /modelCalls\.R2\.agent-native is not off, host or sno-gpu/);
});

test('local-first labels nothing, uploads nothing and says why', t => {
  const { store, result, labeler } = nightRun(t, 'local-first');
  assert.equal(result.code, 0, result.lines.join('\n'));
  assert.equal(labeler, 0, 'no labeler process');
  assert.equal(stagingFile(store, 'cloud-request.json'), undefined, 'no upload');
  assert.equal(labelFiles(store).length, 0);
  assert.match(readFileSync(join(store, 'staging', readdirSync(join(store, 'staging'))[0], 'run.log'), 'utf8'), /R2 labeling off; R3 upload skipped: R3 is off under this mode/);
});

test('agent-native at full consent labels on its own CLI and uploads the labeled session', t => {
  const { store, result, labeler } = nightRun(t, 'agent-native');
  assert.equal(result.code, 0, result.lines.join('\n'));
  assert.equal(labeler, 1);
  assert.ok(stagingFile(store, 'cloud-request.json'), 'the session went to the cloud');
  assert.match(readFileSync(join(store, 'raw', labelFiles(store)[0]), 'utf8'), /"decision": "keep"/);
  assert.match(readFileSync(join(store, 'staging', readdirSync(join(store, 'staging'))[0], 'run.log'), 'utf8'), /R2 labeling runs; R3 upload sends/);
});

test('below full consent neither the labeler nor the upload runs, in every mode', async t => {
  for (const mode of ['agent-native', 'rem-enhanced']) {
    await t.test(mode, sub => {
      const { store, labeler } = nightRun(sub, mode, {}, { REM_TEST_CONSENT: 'metadata-only' });
      assert.equal(labeler, 0, 'no labeler');
      assert.equal(stagingFile(store, 'cloud-request.json'), undefined, 'no upload');
    });
  }
});

test('with the upload cell off the labeler does not run either', t => {
  const { store, labeler } = nightRun(t, 'agent-native', { R3: { 'local-first': 'off', 'agent-native': 'off', 'rem-enhanced': 'off' } });
  assert.equal(labeler, 0);
  assert.equal(stagingFile(store, 'cloud-request.json'), undefined);
});

test('with the labeling cell off the session still uploads, kept with an unknown outcome and no CLI turn', t => {
  const { store, result, labeler } = nightRun(t, 'agent-native', { R2: { 'local-first': 'off', 'agent-native': 'off', 'rem-enhanced': 'off' } });
  assert.equal(result.code, 0, result.lines.join('\n'));
  assert.equal(labeler, 0);
  const sent = stagingFile(store, 'cloud-request.json');
  assert.ok(sent, 'the upload went ahead');
  const batch = JSON.parse(readFileSync(join(store, 'staging', sent), 'utf8'));
  assert.equal(batch.halves.flatMap((half: { sessions: unknown[] }) => half.sessions).length, 1);
  const label = JSON.parse(readFileSync(join(store, 'raw', labelFiles(store)[0]), 'utf8'));
  assert.deepEqual([label.decision, label.outcome, label.reason], ['keep', 'unknown', 'labeler-off']);
});

test('a missing settings file runs no model, uploads nothing and the report names the file', t => {
  useEnv(t, { SNO_PROFILE_DIR: tmp('empty-profile') });
  const config = cfg();
  const store = makeStore(config);
  codexTrace(config);
  const backend = new FixtureBackend();
  const result = run(store, NIGHT, 'u', backend);
  assert.equal(result.code, 0);
  assert.equal(backend.calls.filter(call => call.kind === 'labeler').length, 0);
  assert.equal(stagingFile(store, 'cloud-request.json'), undefined);
  const report = readFileSync(join(store, 'staging', readdirSync(join(store, 'staging'))[0], 'REPORT.md'), 'utf8');
  assert.match(report, /No-upload: settings unavailable: .*settings\.json: file missing; run sno setup/);
});

test('a session whose CLI fails its health check is kept unlabeled without any labeler turn', t => {
  useEnv(t, { SNO_PROFILE_DIR: writeStationSettings('agent-native') });
  const config = cfg();
  const store = makeStore(config);
  codexTrace(config);
  const backend = new FixtureBackend({ preflight: () => false });
  const result = run(store, NIGHT, 'u', backend);
  assert.equal(result.code, 0);
  assert.match(result.lines.join('\n'), /labeler-unavailable; labeler_codex/);
  assert.match(readFileSync(join(store, 'raw', labelFiles(store)[0]), 'utf8'), /"decision": "keep"/);
  assert.equal(backend.calls.filter(call => call.kind === 'labeler').length, 0);
  assert.equal(backend.calls.filter(call => call.kind === 'preflight').length, 1, 'the health check runs with no model named');
});

test('a long session is labeled in bounded windows around its owner messages', t => {
  useEnv(t, { SNO_PROFILE_DIR: writeStationSettings('agent-native') });
  const config = cfg();
  const store = makeStore(config);
  const turns = Array.from({ length: 9 }, (_, i) => codexUser(`turn ${i} ${'x'.repeat(40_000)}`));
  writeCodexSession(config.codex_root, 'big', [codexMeta('big', '/n'), ...turns, codexAssistant('ok')], MT);
  const backend = new FixtureBackend();
  const r = run(store, NIGHT, 'u', backend);
  assert.equal(r.code, 0);
  const labeler = backend.calls.filter(c => c.kind === 'labeler');
  assert.ok(labeler.length > 1, 'the full session needs multiple windows');
  assert.ok(labeler.every(c => c.input.length <= 120000));
  assert.equal(labeler[0].cli, 'codex');
  assert.equal(labelFiles(store).length, 1);
  const second = new FixtureBackend();
  run(store, new Date('2026-09-09T00:00:00Z'), 'u', second);
  assert.equal(second.calls.filter(c => c.kind === 'labeler').length, 0, 'the next run does not retry it');
});

// The first prompt's cloud lookup: a shim `sno` records every request that would leave the machine.
function firstPrompt(t: TestContext, mode: string, consent: string, rows: Record<string, Record<string, string>> = {}, profile?: string) {
  const checkout = fixtureCheckout();
  const store = makeStore(fixtureConfig());
  appendRows(join(store, 'wiki/lessons.jsonl'), [{ lesson_id: 'L-1', status: 'accepted', applies_to: 'general',
    situation: { task_type: 'fix', trigger: 'broken build', tools: [] }, advice: 'read the compiler error' }]);
  git(store, ['add', '--all']);
  git(store, ['commit', '--quiet', '-m', 'lesson']);
  const bin = tmp('r4-bin');
  const requests = join(bin, 'requests.jsonl');
  const sno = join(bin, 'sno');
  writeFileSync(sno, '#!/usr/bin/env node\nconst fs=require("node:fs");\nconst a=process.argv.slice(2).join(" ");\nif(a==="station telemetry consent get"){console.log(process.env.CONSENT);process.exit(0);}\nfs.appendFileSync(process.env.RECALL_REQUESTS, fs.readFileSync(0,"utf8")+"\\n");\nconsole.log(JSON.stringify({lesson_ids:["L-1"]}));\n');
  chmodSync(sno, 0o755);
  const env = { ...process.env, REM_REFLECT_STORE: store, RECALL_REQUESTS: requests, CONSENT: consent,
    SNO_PROFILE_DIR: profile ?? writeStationSettings(mode, rows), PATH: `${bin}:${process.env.PATH ?? ''}` };
  const command = fileURLToPath(new URL('./rem-reflect.ts', import.meta.url));
  const prompt = (session: string) => spawnSync(process.execPath, [command, 'recall', '--agent', 'codex', '--first-message'],
    { input: JSON.stringify({ session_id: session, cwd: checkout, prompt: 'broken build' }), encoding: 'utf8', env });
  return { store, requests, prompt, sent: () => (existsSync(requests) ? readFileSync(requests, 'utf8').trim().split('\n').length : 0) };
}

test('the first-prompt lookup reaches the cloud only when its cell is sno-gpu and consent is full', t => {
  const sent = firstPrompt(t, 'agent-native', 'full');
  const answer = sent.prompt('s1');
  assert.equal(answer.status, 0, answer.stderr);
  assert.match(answer.stdout, /read the compiler error/);
  assert.equal(sent.sent(), 1);
  for (const [name, args] of [['local-first mode', ['local-first', 'full']], ['metadata-only consent', ['agent-native', 'metadata-only']],
    ['cell off', ['agent-native', 'full', { R4: { 'local-first': 'off', 'agent-native': 'off', 'rem-enhanced': 'off' } }]]] as const) {
    const blocked = firstPrompt(t, ...(args as [string, string, Record<string, Record<string, string>>?]));
    const first = blocked.prompt('s1');
    assert.equal(first.status, 0, `${name}: the prompt is never blocked`);
    assert.equal(first.stdout, '', name);
    assert.equal(blocked.sent(), 0, `${name}: nothing left the machine`);
    const usage = readFileSync(join(blocked.store, 'ledger/usage.jsonl'), 'utf8');
    assert.match(usage, /"type":"first-message-recall","session_id":"s1".*"call":"R4","skipped":/, name);
    blocked.prompt('s1');
    assert.equal(readFileSync(join(blocked.store, 'ledger/usage.jsonl'), 'utf8').trim().split('\n').length, 1, `${name}: a later prompt in the session is not a first prompt again`);
  }
});

test('the first-prompt lookup with no settings file sends nothing, records the missing file and never fails the prompt', t => {
  const missing = firstPrompt(t, 'agent-native', 'full', {}, tmp('empty-profile'));
  const first = missing.prompt('s1');
  assert.equal(first.status, 0);
  assert.equal(first.stdout, '');
  assert.equal(missing.sent(), 0);
  assert.match(readFileSync(join(missing.store, 'ledger/usage.jsonl'), 'utf8'), /"skipped":"settings unavailable: .*settings\.json: file missing; run sno setup"/);
});
