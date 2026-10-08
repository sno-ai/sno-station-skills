import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { run } from './rem-reflect.ts';
import { readState, writeJson } from './store.ts';
import { loadConfig } from './config.ts';
import {
  tmp, fixtureConfig, makeStore, FixtureBackend,
  writeClaudeSession, claudeUser, claudeAssistant, writeCodexSession, codexMeta, codexUser, codexAssistant,
} from './test-helpers.ts';
import type { Config } from './config.ts';

const NOW = new Date('2026-09-08T00:00:00Z');
const MT = new Date('2026-09-07T00:00:00Z').getTime();
function cfg(): Config { return fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') }); }
function reportOf(store: string): string {
  const runId = readdirSync(join(store, 'staging')).filter(n => /^\d/.test(n)).sort().pop()!;
  return readFileSync(join(store, 'staging', runId, 'REPORT.md'), 'utf8');
}
function bothHalves(config: Config): void {
  writeClaudeSession(config.claude_root, 'proj', 'cc', [claudeUser('/n', 'cc', 'do it'), claudeAssistant('/n', 'cc', [{ type: 'text', text: 'ok' }])], MT);
  writeCodexSession(config.codex_root, 'cx', [codexMeta('cx', '/n'), codexUser('do it'), codexAssistant('ok')], MT);
}
const cli = tmp('local-consent');
writeFileSync(join(cli, 'sno'), '#!/bin/sh\nif [ "$*" = "station consent" ]; then echo metadata-only; else exit 2; fi\n');
chmodSync(join(cli, 'sno'), 0o755);
const originalPath = process.env.PATH;
process.env.PATH = `${cli}:${originalPath ?? ''}`;
after(() => { if (originalPath === undefined) delete process.env.PATH; else process.env.PATH = originalPath; });

// seeding copies exactly the one credential file each
//     CLI needs into 0700 homes as 0600, and nothing else of the owner's interactive setup ---
test('seeding copies each credential file 0600 into 0700 homes and copies nothing else', () => {
  const config = cfg();
  // the real homes hold the credential plus decoy files that must never reach the isolated homes
  writeFileSync(join(config.claude_home, '.credentials.json'), '{"claude":"token"}');
  writeFileSync(join(config.claude_home, 'settings.json'), '{"decoy":"output-style, hooks, plugins"}');
  writeFileSync(join(config.codex_home, 'auth.json'), '{"codex":"token"}');
  writeFileSync(join(config.codex_home, 'config.toml'), 'model = "decoy"\n');
  const store = makeStore(config);
  bothHalves(config);
  const r = run(store, NOW, 'u', new FixtureBackend());
  assert.equal(r.code, 0, r.lines.join('\n'));
  const cdir = join(store, '.loop-home', 'claude'), xdir = join(store, '.loop-home', 'codex');
  // only the credential file lands in each isolated home (no settings.json or config.toml)
  assert.deepEqual(readdirSync(cdir), ['.credentials.json'], 'only .credentials.json under .loop-home/claude');
  assert.deepEqual(readdirSync(xdir), ['auth.json'], 'only auth.json under .loop-home/codex');
  assert.equal(readFileSync(join(cdir, '.credentials.json'), 'utf8'), '{"claude":"token"}', 'the real Claude credential was copied');
  assert.equal(readFileSync(join(xdir, 'auth.json'), 'utf8'), '{"codex":"token"}', 'the real Codex credential was copied');
  // isolated homes 0700, copied credential files 0600
  assert.equal(statSync(cdir).mode & 0o777, 0o700, '.loop-home/claude is 0700');
  assert.equal(statSync(xdir).mode & 0o777, 0o700, '.loop-home/codex is 0700');
  assert.equal(statSync(join(cdir, '.credentials.json')).mode & 0o777, 0o600, 'the copied Claude credential is 0600');
  assert.equal(statSync(join(xdir, 'auth.json')).mode & 0o777, 0o600, 'the copied Codex credential is 0600');
});

// a real credential missing at seeding is named in REPORT.md so the
//     owner sees why that harness degraded (the degrade itself is proven above and, on real CLIs, live) ---
test('a real credential missing at seeding is named in REPORT.md', () => {
  const config = cfg();
  // claude_home has no .credentials.json; codex_home is healthy
  writeFileSync(join(config.codex_home, 'auth.json'), '{"codex":"token"}');
  const store = makeStore(config);
  bothHalves(config);
  const r = run(store, NOW, 'u', new FixtureBackend());
  assert.equal(r.code, 0, r.lines.join('\n'));
  const report = reportOf(store);
  assert.ok(report.includes(join(config.claude_home, '.credentials.json')), 'the report names the missing Claude credential file');
  assert.ok(!report.includes(join(config.codex_home, 'auth.json')), 'the seeded Codex credential is not reported missing');
});

// a configured harvest root inside the store stops the run before it
//     writes anything and names the offending root ---
test('a harvest root inside the store stops the run before writing anything', () => {
  const config = cfg();
  const store = makeStore(config);
  writeJson(join(store, 'config.json'), { ...loadConfig(store), claude_root: join(store, 'raw') });
  assert.throws(
    () => run(store, NOW, 'u', new FixtureBackend()),
    (e: unknown) => e instanceof Error && e.message.includes('claude_root') && e.message.includes('lies inside store'),
    'the run refuses a harvest root under the store and names it',
  );
  const staged = readdirSync(join(store, 'staging')).filter(n => /^\d/.test(n));
  assert.equal(staged.length, 0, 'no run staging directory was created (nothing written)');
  assert.equal(readState(store).last_start, null, 'no run start was recorded');
});

// a credential whose source has gone away since a prior run must not
// survive as a stale copy in the isolated home; the empty home then fails preflight ---
test('a credential removed after a prior run is cleared from the isolated home next run', () => {
  const config = cfg();
  writeFileSync(join(config.claude_home, '.credentials.json'), '{"claude":"token"}');
  writeFileSync(join(config.codex_home, 'auth.json'), '{"codex":"token"}');
  const store = makeStore(config);
  bothHalves(config);
  assert.equal(run(store, new Date('2026-09-08T00:00:00Z'), 'u', new FixtureBackend()).code, 0);
  const cred = join(store, '.loop-home', 'claude', '.credentials.json');
  assert.ok(existsSync(cred), 'the first run seeded the Claude credential');
  // the real credential goes away; the next run must not leave the stale copy usable
  rmSync(join(config.claude_home, '.credentials.json'));
  run(store, new Date('2026-09-09T00:00:00Z'), 'u', new FixtureBackend());
  assert.ok(!existsSync(cred), 'the stale Claude credential copy was cleared when its source vanished');
  assert.ok(existsSync(join(store, '.loop-home', 'codex', 'auth.json')), 'the still-present Codex credential stays seeded');
});
