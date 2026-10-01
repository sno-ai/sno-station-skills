import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, readdirSync, writeFileSync } from 'node:fs';
import { execFileSync, spawn } from 'node:child_process';
import { join } from 'node:path';
import { run } from './rem-reflect.ts';
import { BackendError, RealBackend } from './backend.ts';
import { CeilingReached } from './session.ts';
import { tmp, fixtureConfig, makeStore, FixtureBackend,
  writeCodexSession, codexMeta, codexUser, codexAssistant } from './test-helpers.ts';

test('elapsed local labeling time does not leave the remaining sessions unjudged', () => {
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = makeStore(config);
  for (const id of ['t1', 't2', 't3']) {
    writeCodexSession(config.codex_root, id, [codexMeta(id, '/n'), codexUser(`do ${id}`), codexAssistant('ok')],
      Date.parse('2026-09-07T00:00:00Z'), '2026/09/07', `2026-09-07T00-00-0${id.slice(1)}`);
  }
  const backend = new FixtureBackend();
  const clock = () => backend.calls.some(call => call.kind === 'labeler') ? 21 * 60_000 : 0;
  const result = run(store, new Date('2026-09-08T00:00:00Z'), 'u', backend, clock);
  assert.equal(result.code, 0);
  assert.equal(readdirSync(join(store, 'raw'), { recursive: true }).filter(path => String(path).endsWith('.label.json')).length, 3);
  assert.equal(backend.calls.filter(call => call.kind === 'labeler').length, 3);
  assert.doesNotMatch(result.lines.join('\n'), /labeler-timeout/);
});

test('a hanging own-CLI call times out and kills its process group', { skip: process.platform !== 'linux' ? 'needs a POSIX process group' : false }, () => {
  const bin = tmp('timeout-bin');
  const marker = `REMCLI-${process.pid}-${Date.now()}`;
  writeFileSync(join(bin, 'codex'), [
    '#!/usr/bin/env node',
    `require('node:child_process').spawn(process.execPath, ['-e', 'setInterval(()=>{}, 1e9)', '${marker}'], { stdio: 'ignore' });`,
    'setInterval(() => {}, 1e9);',
  ].join('\n') + '\n');
  chmodSync(join(bin, 'codex'), 0o755);
  const found = (pattern: string): boolean => {
    try { execFileSync('pgrep', ['-f', pattern]); return true; }
    catch (error) {
      if (error && typeof error === 'object' && (error as { status?: number }).status === 1) return false;
      throw error;
    }
  };
  const control = `REMCTRL-${process.pid}-${Date.now()}`;
  const visible = spawn(process.execPath, ['-e', 'setInterval(()=>{}, 1e9)', control], { detached: true, stdio: 'ignore' });
  visible.unref();
  execFileSync('sleep', ['0.3']);
  try { assert.equal(found(control), true, 'the process check detects a known running child'); }
  finally { if (visible.pid) process.kill(visible.pid, 'SIGKILL'); }
  const previous = process.env.PATH;
  process.env.PATH = `${bin}:${previous ?? ''}`;
  try {
    assert.throws(() => new RealBackend(800).spawn({ cli: 'codex', cwd: bin, input: 'own-CLI filter', kind: 'labeler' }),
      (error: unknown) => error instanceof CeilingReached && error.ceiling === 'per-call-timeout');
    execFileSync('sleep', ['1']);
    assert.equal(found(marker), false, 'the timed-out CLI left no child behind');
  } finally {
    if (previous === undefined) delete process.env.PATH; else process.env.PATH = previous;
    try { execFileSync('pkill', ['-9', '-f', marker]); } catch { /* nothing left */ }
  }
});

test('a 300 KB prompt reaches the CLI whole on stdin, and a failed spawn names its exit status and stderr', { skip: process.platform !== 'linux' ? 'the argv cap under test is Linux-specific' : false }, () => {
  const bin = tmp('stdin-bin');
  writeFileSync(join(bin, 'claude'), '#!/usr/bin/env node\nprocess.stdout.write(String(Buffer.byteLength(require("fs").readFileSync(0, "utf8"))));\n');
  writeFileSync(join(bin, 'codex'), '#!/usr/bin/env node\nprocess.stderr.write("HTTP 401 Unauthorized\\nmore\\n"); process.exit(2);\n');
  chmodSync(join(bin, 'claude'), 0o755);
  chmodSync(join(bin, 'codex'), 0o755);
  const previous = process.env.PATH;
  process.env.PATH = `${bin}:${previous ?? ''}`;
  try {
    const backend = new RealBackend(5000);
    assert.equal(backend.spawn({ cli: 'claude', cwd: bin, input: 'x'.repeat(300_000) }).stdout, '300000');
    assert.throws(() => backend.spawn({ cli: 'codex', cwd: bin, input: 'hi' }), (error: unknown) =>
      error instanceof BackendError && error.reason === 'labeler-unavailable' && /exit 2: HTTP 401 Unauthorized/.test(error.message));
  } finally { if (previous === undefined) delete process.env.PATH; else process.env.PATH = previous; }
});

test('Codex turns use the harness default sandbox', () => {
  const bin = tmp('sandbox-bin');
  writeFileSync(join(bin, 'codex'), '#!/usr/bin/env node\nprocess.stdout.write(JSON.stringify(process.argv.slice(2)));\n');
  chmodSync(join(bin, 'codex'), 0o755);
  const previous = process.env.PATH;
  process.env.PATH = `${bin}:${previous ?? ''}`;
  try {
    const args = JSON.parse(new RealBackend(5000).spawn({ cli: 'codex', cwd: bin, input: 'hi' }).stdout) as string[];
    assert.equal(args.includes('--sandbox'), false);
    assert.equal(args.includes('danger-full-access'), false);
  } finally { if (previous === undefined) delete process.env.PATH; else process.env.PATH = previous; }
});
