import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { run, main } from './rem-reflect.ts';
import { git } from './store.ts';
import { tmp, makeConfig, makeStore, FixtureBackend, fixtureHarnessHomes } from './test-helpers.ts';

// Cloud proposal generation is exercised in the cloud service's integration tests;
// local cloud-answer staging and stale-target refusal are exercised in cloud-apply.test.ts.
test('a run with config.json deleted exits non-zero before the lock, with no commit', () => {
  const { claudeHome, codexHome } = fixtureHarnessHomes(['heartbeat']);
  const config = makeConfig({ claude_home: claudeHome, codex_home: codexHome,
    claude_root: tmp('c'), codex_root: tmp('x') });
  const store = makeStore(config);
  const commitsBefore = git(store, ['log', '--format=%s']).trim().split('\n').length;
  unlinkSync(join(store, 'config.json'));
  assert.throws(() => run(store, new Date('2026-09-08T00:00:00Z'), 'u', new FixtureBackend()), /config\.json/);
  assert.equal(existsSync(join(store, '.lock')), false);
  const previous = process.env.REM_REFLECT_STORE;
  process.env.REM_REFLECT_STORE = store;
  try { assert.equal(main(['run']), 1); }
  finally { if (previous === undefined) delete process.env.REM_REFLECT_STORE; else process.env.REM_REFLECT_STORE = previous; }
  assert.equal(git(store, ['log', '--format=%s']).trim().split('\n').length, commitsBefore);
});
