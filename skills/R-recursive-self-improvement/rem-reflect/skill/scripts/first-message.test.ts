import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { appendRows } from './lessons.ts';
import { git } from './store.ts';
import { fixtureCheckout, fixtureConfig, makeStore, tmp } from './test-helpers.ts';

test('first owner message returns ranked context once and logs a later network failure without stdout', () => {
  const checkout = fixtureCheckout();
  const store = makeStore(fixtureConfig());
  appendRows(join(store, 'wiki/lessons.jsonl'), [{ lesson_id: 'L-1', status: 'accepted', applies_to: 'general',
    situation: { task_type: 'fix', trigger: 'broken build', tools: [] }, advice: 'read the compiler error' }]);
  git(store, ['add', '--all']);
  git(store, ['commit', '--quiet', '-m', 'lesson']);
  const bin = tmp('recall-bin');
  const executable = join(bin, 'sno');
  const requests = join(bin, 'requests.jsonl');
  writeFileSync(executable, '#!/usr/bin/env node\nconst fs=require("node:fs");\nif(process.argv.slice(2).join(" ")==="station consent"){console.log("full");process.exit(0);}\nfs.appendFileSync(process.env.RECALL_REQUESTS, fs.readFileSync(0,"utf8")+"\\n");\nif(process.env.RECALL_FAIL==="1") process.exit(7);\nif(process.env.RECALL_FAIL==="timeout") setTimeout(()=>{},1000); else console.log(JSON.stringify({lesson_ids:["L-1"]}));\n');
  chmodSync(executable, 0o755);
  const command = fileURLToPath(new URL('./rem-reflect.ts', import.meta.url));
  const run = (session: string, fail = '') => spawnSync(process.execPath,
    [command, 'recall', '--agent', 'codex', '--first-message'], {
      input: JSON.stringify({ session_id: session, cwd: checkout, prompt: 'broken build' }), encoding: 'utf8',
      env: { ...process.env, REM_REFLECT_STORE: store, RECALL_REQUESTS: requests,
        RECALL_FAIL: fail, PATH: `${bin}:${process.env.PATH ?? ''}` },
    });
  const first = run('session-1');
  assert.equal(first.status, 0);
  assert.deepEqual(JSON.parse(first.stdout), { hookSpecificOutput: { hookEventName: 'UserPromptSubmit',
    additionalContext: 'L-1: broken build\nread the compiler error' } });
  assert.deepEqual(JSON.parse(readFileSync(requests, 'utf8').trim()), { project_id: 'github.com/example/project',
    message: 'broken build', lessons: [{ lesson_id: 'L-1', situation: { task_type: 'fix', trigger: 'broken build', tools: [] },
      advice: 'read the compiler error' }] });
  const again = run('session-1');
  assert.equal(again.stdout, '');
  assert.equal(readFileSync(requests, 'utf8').trim().split('\n').length, 1);
  const failed = run('session-2', '1');
  assert.equal(failed.status, 0);
  assert.equal(failed.stdout, '');
  assert.match(readFileSync(join(store, 'ledger/usage.jsonl'), 'utf8'), /"type":"first-message-recall-failed","session_id":"session-2"/);
  writeFileSync(join(store, 'settings.local.json'), JSON.stringify({ version: 'test', labeler_input_max_chars: 120000,
    labeler_event_window_lines: 60, recall_timeout_ms: 30 }));
  const timedOut = run('session-3', 'timeout');
  assert.equal(timedOut.status, 0);
  assert.equal(timedOut.stdout, '');
  assert.match(readFileSync(join(store, 'ledger/usage.jsonl'), 'utf8'), /"type":"first-message-recall-failed","session_id":"session-3"/);
});

test('first-message recall sends only recallable lessons and records the selected ones as shown', () => {
  const checkout = fixtureCheckout();
  const store = makeStore(fixtureConfig());
  const base = { situation: { task_type: 'batch', trigger: 'duplicate keys', tools: [] }, advice: 'check key uniqueness first' };
  appendRows(join(store, 'wiki/lessons.jsonl'), [
    { ...base, lesson_id: 'L-verified', status: 'candidate', listed: true, verification: { accepted: true }, applies_to: 'general' },
    { ...base, lesson_id: 'L-unverified', status: 'candidate', listed: true, applies_to: 'general' },
  ]);
  git(store, ['add', '--all']);
  git(store, ['commit', '--quiet', '-m', 'lessons']);
  const bin = tmp('recall-echo-bin');
  const requests = join(bin, 'requests.jsonl');
  // The substitute for the cloud recall selects every lesson it is sent.
  writeFileSync(join(bin, 'sno'), '#!/usr/bin/env node\nconst fs=require("node:fs");\nif(process.argv.slice(2).join(" ")==="station consent"){console.log("full");process.exit(0);}\nconst r=JSON.parse(fs.readFileSync(0,"utf8"));\nfs.appendFileSync(process.env.RECALL_REQUESTS, JSON.stringify(r)+"\\n");\nconsole.log(JSON.stringify({lesson_ids:r.lessons.map(l=>l.lesson_id)}));\n');
  chmodSync(join(bin, 'sno'), 0o755);
  const result = spawnSync(process.execPath, [fileURLToPath(new URL('./rem-reflect.ts', import.meta.url)), 'recall', '--agent', 'codex', '--first-message'], {
    input: JSON.stringify({ session_id: 'session-9', cwd: checkout, prompt: 'run the batch' }), encoding: 'utf8',
    env: { ...process.env, REM_REFLECT_STORE: store, RECALL_REQUESTS: requests, PATH: `${bin}:${process.env.PATH ?? ''}` },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(readFileSync(requests, 'utf8').trim()).lessons.map((l: { lesson_id: string }) => l.lesson_id), ['L-verified']);
  const shown = readFileSync(join(store, 'ledger/usage.jsonl'), 'utf8').trim().split('\n').map(line => JSON.parse(line))
    .filter(row => row.type === 'shown');
  assert.deepEqual(shown.map(row => [row.session_id, row.lesson_ids]), [['session-9', ['L-verified']]]);
});
