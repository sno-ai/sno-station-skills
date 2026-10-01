import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { chmodSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { appendLedger, readLedger } from './ledger.ts';
import { flushCloudVerdicts } from './cloud.ts';
import { commitStore, readState, writeState } from './store.ts';
import { fixtureConfig, makeStore, tmp } from './test-helpers.ts';

test('ordinary reject applies locally while off, then a same-day full-consent entry sends the linked verdict', () => {
  const config = fixtureConfig();
  const store = makeStore(config);
  const id = '20260921-0100/codex';
  appendLedger(store, { type: 'proposal', proposal_id: id, run_id: '20260921-0100', half: 'codex',
    kind: 'patch', target: '/installed/target', region: 'body', purpose: { summary: 'a change', page_ids: ['page'] },
    verdict: 'pending', judgment_id: 'j-original' });
  const bin = tmp('sno-verdict');
  const capture = join(bin, 'verdict.json');
  const sno = join(bin, 'sno');
  writeFileSync(sno, [
    '#!/usr/bin/env node',
    "const fs = require('node:fs');",
    "const args = process.argv.slice(2);",
    "if (args.join(' ') === 'station telemetry consent get') { console.log(process.env.REM_TEST_CONSENT); process.exit(0); }",
    "if (args[0] !== 'rem' || args[1] !== 'verdict') { console.error('unexpected network verb'); process.exit(2); }",
    "const ledger = fs.readFileSync(process.env.REM_TEST_LEDGER, 'utf8');",
    "if (!ledger.includes('\\\"verdict\\\":\\\"Rejected\\\"')) { console.error('local decision did not happen first'); process.exit(2); }",
    "if (process.env.REM_TEST_FAIL === '1') { console.error('temporary cloud outage'); process.exit(1); }",
    "fs.writeFileSync(process.env.REM_REQUEST_CAPTURE, JSON.stringify(args));",
    "console.log(JSON.stringify({schema_version:1,judgment_id:args[2],verdict:args[3],acknowledged:true}));",
  ].join('\n') + '\n');
  chmodSync(sno, 0o755);
  const env = { ...process.env, PATH: `${bin}:${process.env.PATH ?? ''}`, REM_REFLECT_STORE: store,
    REM_TEST_LEDGER: join(store, 'ledger', 'skill-impact.jsonl'), REM_REQUEST_CAPTURE: capture };
  const entry = join(import.meta.dirname, 'rem-reflect.ts');

  const off = execFileSync(process.execPath, ['--experimental-strip-types', entry, 'reject', id],
    { env: { ...env, REM_TEST_CONSENT: 'off' }, encoding: 'utf8' });
  assert.match(off, /Rejected/);
  assert.equal(existsSync(capture), false);
  assert.ok(readLedger(store).some(row => row.type === 'verdict' && row.proposal_id === id && row.verdict === 'Rejected'));
  assert.ok(readLedger(store).some(row => row.type === 'cloud-verdict' && row.judgment_id === 'j-original' && row.status === 'pending'));

  const state = readState(store);
  state.last_terminal = { id: '20260921-0000', date: '2026-09-21', status: 'success' };
  writeState(store, state);
  commitStore(store, 'already completed today');
  assert.throws(() => execFileSync(process.execPath, ['--experimental-strip-types', entry, 'run', '--now', '2026-09-21T01:00:00Z'],
    { env: { ...env, REM_TEST_CONSENT: 'full', REM_TEST_FAIL: '1' }, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }),
  /Command failed/);
  assert.equal(existsSync(capture), false);
  assert.ok(readLedger(store).some(row => row.type === 'cloud-verdict' && row.judgment_id === 'j-original' && row.status === 'pending'));
  const full = execFileSync(process.execPath, ['--experimental-strip-types', entry, 'run', '--now', '2026-09-21T01:00:00Z'],
    { env: { ...env, REM_TEST_CONSENT: 'full' }, encoding: 'utf8' });
  assert.match(full, /already succeeded/);
  assert.deepEqual(JSON.parse(readFileSync(capture, 'utf8')), ['rem', 'verdict', 'j-original', 'reject']);
  assert.ok(readLedger(store).some(row => row.type === 'cloud-verdict' && row.judgment_id === 'j-original' && row.status === 'acked'));
});

test('a promoted verdict keeps --all-projects through retry and records only an acknowledgment that echoes general', t => {
  const bin = tmp('promoted-verdict');
  const capture = join(bin, 'args.json');
  const sno = join(bin, 'sno');
  writeFileSync(sno, [
    '#!/usr/bin/env node',
    "const fs = require('node:fs');",
    "const args = process.argv.slice(2);",
    "if (args.join(' ') === 'station telemetry consent get') { console.log('full'); process.exit(0); }",
    "fs.writeFileSync(process.env.REM_REQUEST_CAPTURE, JSON.stringify(args));",
    "const answer = {schema_version:1,judgment_id:args[2],verdict:args[3],acknowledged:true};",
    "if (process.env.REM_ECHO_PROMOTION === '1') answer.applies_to = 'general';",
    "console.log(JSON.stringify(answer));",
  ].join('\n') + '\n');
  chmodSync(sno, 0o755);
  const prior = { PATH: process.env.PATH, REM_REQUEST_CAPTURE: process.env.REM_REQUEST_CAPTURE,
    REM_ECHO_PROMOTION: process.env.REM_ECHO_PROMOTION };
  process.env.PATH = `${bin}:${prior.PATH ?? ''}`;
  process.env.REM_REQUEST_CAPTURE = capture;
  t.after(() => {
    for (const [key, value] of Object.entries(prior)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  });

  const store = makeStore(fixtureConfig());
  appendLedger(store, { type: 'cloud-verdict', judgment_id: 'j-promoted', item_id: 'L-promoted', verdict: 'accept',
    status: 'pending', applies_to: 'general', at: '2026-09-23' });
  delete process.env.REM_ECHO_PROMOTION;
  assert.throws(() => flushCloudVerdicts(store), /mismatched acknowledgment/);
  assert.equal(readLedger(store).filter(row => row.judgment_id === 'j-promoted').at(-1)?.status, 'pending');

  process.env.REM_ECHO_PROMOTION = '1';
  assert.deepEqual(flushCloudVerdicts(store), { sent: 1, pending: 0 });
  assert.deepEqual(JSON.parse(readFileSync(capture, 'utf8')), ['rem', 'verdict', 'j-promoted', 'accept', '--all-projects']);
  const acked = readLedger(store).filter(row => row.judgment_id === 'j-promoted').at(-1);
  assert.equal(acked?.status, 'acked');
  assert.equal(acked?.applies_to, 'general');
});
