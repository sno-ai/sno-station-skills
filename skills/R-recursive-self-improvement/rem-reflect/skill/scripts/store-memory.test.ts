import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { run } from './rem-reflect.ts';
import { existingTraces } from './harvest.ts';
import { fixtureConfig, makeStore, tmp, FixtureBackend, writeCodexSession, codexMeta, codexUser, codexAssistant } from './test-helpers.ts';

const DAY = 86_400_000;
const NIGHT = new Date('2026-09-08T00:00:00Z');
const NEXT = new Date('2026-09-09T00:00:00Z');

// A store of many old, large sessions plus one fresh session. Old ones are inside the first-run window
// but past the three-day eligibility, so they are stored and never processed again.
function bigStore(old: number, messages: number) {
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = makeStore(config);
  const text = (n: number) => `${n} ${'lorem ipsum '.repeat(120)}`;
  for (let i = 0; i < old; i++) {
    const records = Array.from({ length: messages }, (_, n) => (n % 2 ? codexAssistant(text(n)) : codexUser(text(n))));
    writeCodexSession(config.codex_root, `old${i}`, [codexMeta(`old${i}`, '/n'), ...records], NIGHT.getTime() - 5 * DAY);
  }
  assert.equal(run(store, NIGHT, 'u', new FixtureBackend()).code, 0);
  writeCodexSession(config.codex_root, 'fresh', [codexMeta('fresh', '/n'), codexUser('do it'), codexAssistant('ok')], NEXT.getTime() - 2 * 3_600_000);
  return { config, store };
}

test('a trace read without text keeps its summary and loses only the records', () => {
  const { store } = bigStore(2, 20);
  const full = existingTraces(store);
  const summary = existingTraces(store, () => false);
  assert.equal(summary.length, full.length);
  assert.ok(full.every(trace => trace.records.length > 0));
  assert.ok(summary.every(trace => trace.records.length === 0));
  assert.deepEqual(summary.map(trace => [trace.trace_id, trace.skills_loaded, trace.source_mtime]),
    full.map(trace => [trace.trace_id, trace.skills_loaded, trace.source_mtime]));
  const one = existingTraces(store, trace => trace.session_id === 'old0');
  assert.deepEqual(one.filter(trace => trace.records.length).map(trace => trace.session_id), ['old0']);
});

test('a night over a large history holds only its own sessions in memory', () => {
  const { store } = bigStore(30, 2500);
  const size = readdirSync(join(store, 'raw'), { recursive: true }).length;
  assert.ok(size > 30, 'the history is on disk');
  const scripts = pathToFileURL(new URL('./', import.meta.url).pathname).href;
  const child = spawnSync(process.execPath, ['--max-old-space-size=150', '--input-type=module', '-e',
    `import { run } from '${scripts}rem-reflect.ts'; import { FixtureBackend } from '${scripts}test-helpers.ts';
     const r = run(process.env.STORE, new Date(process.env.NIGHT), 'u', new FixtureBackend());
     console.log(r.lines.join('\\n')); process.exit(r.code);`],
  { encoding: 'utf8', env: { ...process.env, STORE: store, NIGHT: NEXT.toISOString() }, timeout: 120_000 });
  assert.equal(child.status, 0, `${child.signal ?? ''} ${child.stderr.slice(-300)}`);
  assert.ok(readdirSync(join(store, 'staging'), { recursive: true }).map(String).some(path => path.endsWith('cloud-request.json')),
    'the fresh session went to the cloud');
});
