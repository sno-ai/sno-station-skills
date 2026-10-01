import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { run } from './rem-reflect.ts';
import { reflect } from './reflect.ts';
import { readLabels } from './labeler.ts';
import { appendRows } from './lessons.ts';
import { reflectionFiles } from './config.ts';
import { readState } from './store.ts';
import { tmp, fixtureConfig, makeStore, FixtureBackend,
  writeCodexSession, codexMeta, codexUser, codexAssistant } from './test-helpers.ts';

test('a long trace gets one persisted keep decision on its own CLI', () => {
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = makeStore(config);
  writeCodexSession(config.codex_root, 'big', [
    codexMeta('big', '/n', { originator: 'codex_exec' }), codexUser('start the task'),
    codexAssistant('Z'.repeat(60_000)), codexUser('more'), codexAssistant('done'),
  ], Date.parse('2026-09-07T00:00:00Z'));
  const backend = new FixtureBackend();
  const result = run(store, new Date('2026-09-08T00:00:00Z'), 'u', backend);
  assert.equal(result.code, 0);
  const labels = readLabels(store);
  assert.equal(labels.size, 1);
  const [label] = [...labels.values()];
  assert.equal(label.labeled_by, 'codex');
  assert.equal(label.decision, 'keep');
  assert.deepEqual(backend.calls.filter(call => call.kind === 'labeler').map(call => call.cli), ['codex']);
});

test('a failed cloud day retries the exact saved batch without repeating the local decision', t => {
  const bin = tmp('retry-bin');
  const script = join(bin, 'sno');
  const marker = join(bin, 'failed-once');
  const first = join(bin, 'first.json');
  const second = join(bin, 'second.json');
  writeFileSync(script, `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2).join(' ');
if (args === 'station telemetry consent get') { console.log('full'); process.exit(0); }
if (args !== 'rem judge') process.exit(2);
const input = fs.readFileSync(0, 'utf8');
if (!fs.existsSync(${JSON.stringify(marker)})) {
  fs.writeFileSync(${JSON.stringify(first)}, input);
  fs.writeFileSync(${JSON.stringify(marker)}, '1');
  console.error('temporary cloud outage'); process.exit(2);
}
fs.writeFileSync(${JSON.stringify(second)}, input);
const batch = JSON.parse(input);
console.log(JSON.stringify({schema_version:1,run_id:batch.run_id,history_acknowledged:true,history_links:[],
  halves:batch.halves.map(half=>({harness:half.harness,attention:[],pages:[],lessons:[],proposals:[],read_judgments:[],log_entry:'no supported change'}))}));
`);
  chmodSync(script, 0o755);
  const oldPath = process.env.PATH;
  process.env.PATH = `${bin}:${oldPath ?? ''}`;
  t.after(() => { if (oldPath === undefined) delete process.env.PATH; else process.env.PATH = oldPath; });

  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = makeStore(config);
  writeCodexSession(config.codex_root, 'cx', [codexMeta('cx', '/n'), codexUser('do it'), codexAssistant('ok')], Date.parse('2026-09-07T00:00:00Z'));
  const today = new Date('2026-09-08T00:00:00Z');
  const firstBackend = new FixtureBackend();
  const failed = run(store, today, 'u', firstBackend);
  assert.equal(failed.code, 1);
  assert.equal(readState(store).last_terminal?.status, 'failed');
  assert.equal(firstBackend.calls.filter(call => call.kind === 'labeler').length, 1);
  assert.equal(existsSync(first), true);

  const secondBackend = new FixtureBackend();
  const resumed = run(store, today, 'u', secondBackend);
  assert.equal(resumed.code, 0, resumed.lines.join('\n'));
  assert.equal(secondBackend.calls.filter(call => call.kind === 'labeler').length, 0);
  assert.equal(readFileSync(second, 'utf8'), readFileSync(first, 'utf8'), 'the same persisted batch reached the cloud');
  assert.equal(JSON.parse(readFileSync(second, 'utf8')).halves[0].sessions.length, 1);
});

test('eligible lessons show their advice and both accept commands, while no eligible lesson shows neither command', t => {
  const bin = tmp('report-bin');
  const sno = join(bin, 'sno');
  writeFileSync(sno, '#!/bin/sh\n[ "$*" = "station telemetry consent get" ] && { echo full; exit 0; }\nexit 2\n');
  chmodSync(sno, 0o755);
  const oldPath = process.env.PATH;
  process.env.PATH = `${bin}:${oldPath ?? ''}`;
  t.after(() => { if (oldPath === undefined) delete process.env.PATH; else process.env.PATH = oldPath; });

  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = makeStore(config);
  const situation = { task_type: 'debug', trigger: 'a repeated failure', tools: [] };
  appendRows(join(store, reflectionFiles.lessons), [{
    lesson_id: 'L-report', page_id: 'pg-report', status: 'candidate', count: 1, helped: 0, harmful: 0,
    measured: false, created_run: '20260923-0000', project_id: 'p', agent_id: 'codex', user_id: 'u', skill_target: null,
    scenario: situation, situation, advice: 'check the exact failure before retrying', because: 'blind retries repeat it',
    applies_to: 'project:p', polarity: 'from_failure', evidence: [], counter_examples: 'not searched', listed: true,
  }]);
  const report = reflect(store, config, '20260923-0000', new FixtureBackend(), [], new Date('2026-09-23T00:00:00Z')).report.join('\n');
  assert.match(report, /L-report: check the exact failure before retrying/);
  assert.match(report, /rem-reflect accept L-report(?:\n|$)/);
  assert.match(report, /rem-reflect accept L-report --all-projects/);

  const empty = makeStore(config);
  const emptyReport = reflect(empty, config, '20260923-0100', new FixtureBackend(), [], new Date('2026-09-23T01:00:00Z')).report.join('\n');
  assert.doesNotMatch(emptyReport, /rem-reflect accept/);
});
