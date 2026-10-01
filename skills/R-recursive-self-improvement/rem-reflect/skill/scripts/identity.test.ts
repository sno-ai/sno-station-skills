import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, realpathSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { normalizeRemote, projectId, readUserId, resolveIdentity } from './identity.ts';
import { git } from './store.ts';
import { tmp } from './test-helpers.ts';

test('missing Station identity generates one stable id in the loop store; an invalid present identity fails', () => {
  const store = tmp('identity-store');
  const missing = join(tmp('station-home'), 'identity.json');
  const first = readUserId(store, missing);
  assert.ok(first.length > 0);
  assert.equal(readUserId(store, missing), first, 'the generated id is reused');

  const invalid = join(tmp('station-home'), 'identity.json');
  writeFileSync(invalid, '{}\n');
  assert.throws(() => readUserId(store, invalid), /missing user_cuid/);
});

// Identity: remote host/org/repo, else configured name, else user-level ---
test('normalizeRemote folds scp and https to host/org/repo, drops .git', () => {
  assert.equal(normalizeRemote('git@github.com:example/project.git'), 'github.com/example/project');
  assert.equal(normalizeRemote('https://github.com/example/project.git'), 'github.com/example/project');
  assert.equal(normalizeRemote('git@github.com:example/project'), 'github.com/example/project');
  assert.equal(normalizeRemote(undefined), undefined);
});

test('projectId: remote wins, else a configured name for the directory', () => {
  assert.equal(projectId('/any', 'git@github.com:example/project.git', {}), 'github.com/example/project');
  assert.equal(projectId('/srv/notes', undefined, { '/srv/notes': 'my-notes' }), 'my-notes');
});

test('projectId derives a stable dir id from a non-git path or an origin-less work-tree top, while empty cwd stays user-level', () => {
  const plain = tmp('identity-plain');
  const repo = tmp('identity-originless');
  const nested = join(repo, 'packages', 'one');
  git(repo, ['init', '--quiet']);
  mkdirSync(nested, { recursive: true });
  const dirId = (path: string) => `dir:${createHash('sha256').update(realpathSync(path)).digest('hex').slice(0, 16)}`;

  assert.equal(projectId(plain, undefined, {}), dirId(plain));
  assert.equal(projectId(plain, undefined, {}), projectId(plain, undefined, {}), 'the same path is stable');
  assert.equal(projectId(nested, undefined, {}), dirId(repo), 'all directories in one origin-less work tree share its top-level id');
  assert.equal(projectId('', undefined, {}), 'user-level');
});

test('resolveIdentity carries the kind, the same source harness, and a path-derived project when no remote', () => {
  const cwd = tmp('identity-resolve');
  const claude = resolveIdentity({ user_id: 'u', harness: 'claude-code', cwd, project_names: {} });
  assert.equal(claude.project_id, `dir:${createHash('sha256').update(realpathSync(cwd)).digest('hex').slice(0, 16)}`);
  assert.equal(claude.agent_id, 'claude-code');
  assert.equal(claude.source_harness, 'claude-code');
  const codex = resolveIdentity({ user_id: 'u', harness: 'codex', cwd: '/x', remote: 'git@github.com:example/project.git', project_names: {}, originator: 'codex_exec' });
  assert.equal(codex.project_id, 'github.com/example/project');
  assert.equal(codex.originator, 'codex_exec');
});
