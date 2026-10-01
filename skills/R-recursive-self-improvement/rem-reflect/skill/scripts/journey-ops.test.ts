// Test-owned: the daily cadence is a same-day no-op that writes
// nothing, a next-day run proceeds, and the unit is armed by `heartbeat` — no crontab, no busy loop.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { run } from './rem-reflect.ts';
import { calendar } from './config.ts';
import { readState, writeState } from './store.ts';
import {
  hashListing, tmp, fixtureConfig, makeStore, FixtureBackend,
  writeClaudeSession, claudeUser, claudeAssistant, writeCodexSession, codexMeta, codexUser, codexAssistant,
} from './test-helpers.ts';
import type { Config } from './config.ts';

const NOW = new Date('2026-09-08T12:00:00Z');
const MT = new Date('2026-09-07T00:00:00Z').getTime();
const UNIT_DIR = fileURLToPath(new URL('..', import.meta.url)); // skills/rem-reflect/skill/
const ARM_LINE = 'heartbeat --interval 24h --max-hours 0 --label rem-reflect -- rem-reflect run';
function cfg(): Config { return fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') }); }
function bothHalves(config: Config): void {
  writeClaudeSession(config.claude_root, 'proj', 'cc', [claudeUser('/n', 'cc', 'do it'), claudeAssistant('/n', 'cc', [{ type: 'text', text: 'ok' }])], MT);
  writeCodexSession(config.codex_root, 'cx', [codexMeta('cx', '/n'), codexUser('do it'), codexAssistant('ok')], MT);
}

// A run on a day that already reached a successful reflection is a recorded no-op that writes nothing.
test('a same-day run after today already succeeded is a no-op that writes nothing', () => {
  const config = cfg();
  const store = makeStore(config);
  const today = calendar(NOW, config.time_zone);
  const state = readState(store);
  state.last_start = today;
  state.last_terminal = { ...today, status: 'success' }; // today already succeeded
  writeState(store, state);
  const before = hashListing(store);
  const r = run(store, NOW, 'u', new FixtureBackend());
  assert.equal(r.code, 0, r.lines.join('\n'));
  assert.ok(r.lines.some(line => /no-op: .*already succeeded/.test(line)), 'the run names the no-op');
  assert.equal(hashListing(store), before, 'the no-op leaves the store byte-identical');
});

// retry-until-success: a day whose only run FAILED is not done, so a same-day run proceeds.
test('a same-day run after today only failed proceeds instead of no-opping', () => {
  const config = cfg();
  const store = makeStore(config);
  bothHalves(config);
  const today = calendar(NOW, config.time_zone);
  const state = readState(store);
  state.last_start = today;
  state.last_terminal = { ...today, status: 'failed' }; // today's only run failed
  writeState(store, state);
  const r = run(store, NOW, 'u', new FixtureBackend());
  assert.equal(r.code, 0, r.lines.join('\n'));
  assert.ok(!r.lines.some(line => /no-op/.test(line)), 'a failed day retries rather than no-opping');
  assert.equal(readState(store).last_terminal?.status, 'success', 'the retry reaches success');
});

// With the last start set to yesterday, the same store runs the full pass instead of the no-op.
test('a next-day run proceeds past the no-op guard', () => {
  const config = cfg();
  const store = makeStore(config);
  bothHalves(config);
  const yesterday = calendar(new Date('2026-09-07T12:00:00Z'), config.time_zone);
  const state = readState(store);
  state.last_start = yesterday;
  writeState(store, state);
  const r = run(store, NOW, 'u', new FixtureBackend());
  assert.equal(r.code, 0, r.lines.join('\n'));
  assert.ok(!r.lines.some(line => /no-op/.test(line)), 'the next-day run does not report a no-op');
  const staged = readdirSync(join(store, 'staging')).filter(n => /^\d/.test(n));
  assert.ok(staged.includes(calendar(NOW, config.time_zone).id), 'the run staged its own run id');
});

// the unit's SKILL.md names the exact heartbeat arm line the owner runs.
test('the unit SKILL.md names the exact heartbeat arm line', () => {
  const skillMd = readFileSync(join(UNIT_DIR, 'SKILL.md'), 'utf8');
  assert.ok(skillMd.includes(ARM_LINE), 'SKILL.md carries the exact heartbeat arm line');
});

// the shipped program schedules through heartbeat, not a crontab entry or a busy-wait loop.
test('the shipped unit source has no crontab and no busy-wait loop', () => {
  // grep the shipped source only: SKILL.md, references, and non-test scripts (test files legitimately
  // name these strings as search terms; the deployed program must not).
  const hits = (pattern: string): string => {
    try {
      return execFileSync('grep', ['-rIl', '--exclude=*.test.ts', '--exclude-dir=selftest', pattern, UNIT_DIR], { encoding: 'utf8' });
    } catch (e) {
      // grep exits 1 when nothing matches; any other status is a broken instrument
      if (e && typeof e === 'object' && (e as { status?: number }).status === 1) return '';
      throw new Error(`grep unusable: ${String(e)}`);
    }
  };
  assert.equal(hits('crontab'), '', 'no crontab in the shipped source');
  assert.equal(hits('while true'), '', 'no `while true` busy loop in the shipped source');
  // positive control: grep can find a string that is present, so an empty result above is real
  assert.ok(hits('rem-reflect').length > 0, 'grep can find a present string (instrument works)');
});

// the exact arm line's flags are accepted by the installed heartbeat. `heartbeat` is a
// foreground daemon, so it is spawned detached (never awaited); a unique label avoids colliding with a
// real rem-reflect heartbeat; heartbeat fires the hook at once, so the run gets a fixture store.
// The arm is stopped in a finally and the process group killed as a backstop.
test('the installed heartbeat accepts the exact arm line flags and stops again', async () => {
  // a short, unique label (never the real `rem-reflect`): `heartbeat --list` truncates the label
  // column to ~20 chars, so a long label would never match its own listing.
  const label = `q19-${process.pid}`;
  const list = (): string => { try { return execFileSync('heartbeat', ['--list'], { encoding: 'utf8' }); } catch { return ''; } };
  const child = spawn('heartbeat', ['--interval', '24h', '--max-hours', '0', '--label', label, '--', 'rem-reflect', 'run'],
    { detached: true, stdio: 'ignore', env: { ...process.env, REM_REFLECT_STORE: makeStore(fixtureConfig()) } });
  const spawnErr = await new Promise<NodeJS.ErrnoException | null>(resolve => {
    child.once('error', err => resolve(err as NodeJS.ErrnoException));
    setTimeout(() => resolve(null), 300);
  });
  if (spawnErr?.code === 'ENOENT') { assert.ok(true, 'heartbeat not installed on PATH; arm check skipped'); return; }
  assert.equal(spawnErr, null, `heartbeat failed to start: ${spawnErr?.message ?? ''}`);
  try {
    let seen = false;
    for (let i = 0; i < 30 && !seen; i++) { if (new RegExp(label).test(list())) seen = true; else execFileSync('sleep', ['0.1']); }
    assert.ok(seen, 'the armed heartbeat is listed');
  } finally {
    try { execFileSync('heartbeat', ['--stop', label], { timeout: 10_000 }); } catch { /* already gone */ }
    try { if (child.pid) process.kill(-child.pid, 'SIGKILL'); } catch { /* already gone */ }
  }
  for (let i = 0; i < 20 && new RegExp(label).test(list()); i++) execFileSync('sleep', ['0.1']);
  assert.doesNotMatch(list(), new RegExp(label), 'the heartbeat is stopped and no longer listed');
});
