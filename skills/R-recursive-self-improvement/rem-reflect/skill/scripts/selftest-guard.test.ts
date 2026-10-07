import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, utimesSync, writeFileSync } from 'node:fs';
import { testTempRoot } from './test-helpers.ts';
import { join } from 'node:path';

test('self-test run refuses a missing store before reading sessions or invoking sno', t => {
  const dir = mkdtempSync(join(testTempRoot, 'rem-selftest-guard-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const home = join(dir, 'home');
  const bin = join(dir, 'bin');
  const profile = join(dir, 'profile');
  for (const path of [home, bin, profile]) mkdirSync(path, { recursive: true });
  const claudeRoot = join(home, '.claude', 'projects');
  const codexRoot = join(home, '.codex', 'sessions');
  const claudeFile = join(claudeRoot, 'fake', 'session.jsonl');
  const codexFile = join(codexRoot, '2026', '09', '29', 'session.jsonl');
  for (const file of [claudeFile, codexFile]) {
    mkdirSync(join(file, '..'), { recursive: true });
    writeFileSync(file, '{}\n');
    const old = new Date('2026-09-29T00:00:00Z');
    utimesSync(file, old, old);
  }
  writeFileSync(join(profile, 'settings.json'), JSON.stringify({ mode: 'local-first', modelCalls: {
    R2: { 'local-first': 'off' }, R3: { 'local-first': 'off' }, R4: { 'local-first': 'off' },
  } }));
  const marker = join(dir, 'sno-called');
  for (const name of ['sno', 'claude', 'codex']) {
    const path = join(bin, name);
    writeFileSync(path, '#!/bin/sh\nprintf "%s\\n" "$0 $*" >> "$REM_TEST_MARKER"\nexit 2\n');
    chmodSync(path, 0o755);
  }
  const probeTrace = join(dir, 'probe.trace.log');
  const probe = spawnSync('strace', ['-e', 'trace=openat', '-o', probeTrace, process.execPath,
    '-e', 'require("node:fs").readFileSync(process.argv[1])', claudeFile], { encoding: 'utf8' });
  assert.equal(probe.status, 0, probe.stderr);
  assert.ok(readFileSync(probeTrace, 'utf8').includes(claudeFile),
    'the trace instrument detects a real session file read');
  const store = join(dir, 'missing-store');
  const entry = join(import.meta.dirname, 'rem-reflect.ts');
  mkdirSync(join(home, '.sno', 'experience'), { recursive: true });
  for (const [name, configuredStore] of [['missing', store], ['unset', undefined]] as const) {
    const trace = join(dir, `${name}.trace.log`);
    const env: NodeJS.ProcessEnv = { HOME: home, CODEX_HOME: join(home, '.codex'),
      CLAUDE_CONFIG_DIR: join(home, '.claude'), XDG_CONFIG_HOME: join(home, '.config'),
      SNO_PROFILE_DIR: profile, REM_SELFTEST: '1', REM_REFLECT_STORE: configuredStore,
      REM_TEST_MARKER: marker, PATH: `${bin}:/usr/bin:/bin`, TMPDIR: dir, NODE_OPTIONS: '' };
    if (configuredStore === undefined) delete env.REM_REFLECT_STORE;
    const result = spawnSync('strace', ['-f', '-e', 'trace=openat,connect,execve', '-o', trace,
      process.execPath, '--experimental-strip-types', entry, 'run', '--now', '2026-09-30T08:00:00Z'], {
      encoding: 'utf8', env,
    });
    assert.equal(result.error, undefined);
    const calls = readFileSync(trace, 'utf8').split('\n');
    const opened = calls.filter(line => line.includes('openat('));
    assert.equal(opened.some(line => line.includes(claudeRoot) || line.includes(codexRoot)), false,
      `${name}: the process must not open either session root`);
    assert.equal(calls.some(line => line.includes('connect(') && /sa_family=AF_INET6?/.test(line)), false,
      `${name}: the process must not open a network connection`);
    assert.equal(calls.some(line => /execve\("[^"]*\/(?:sno|claude|codex)"/.test(line)), false,
      `${name}: the process must not invoke an external client`);
    assert.equal(existsSync(marker), false, `${name}: the process must not invoke sno or another external client`);
    assert.notEqual(result.status, 0, `${name}: a missing self-test store must fail`);
    assert.equal(result.stderr.trim().split('\n').length, 1, result.stderr);
    assert.match(result.stderr, /missing.*store|store.*missing/i);
  }
});
