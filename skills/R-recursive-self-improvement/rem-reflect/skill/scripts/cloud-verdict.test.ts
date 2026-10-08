import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { chmodSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { run } from './rem-reflect.ts';
import { appendLedger, readLedger } from './ledger.ts';
import { flushCloudVerdicts } from './cloud.ts';
import { commitStore, readState, writeState } from './store.ts';
import { fixtureConfig, makeStore, tmp, writeStationSettings, FixtureBackend } from './test-helpers.ts';

test('ordinary reject stays successful when upload is rejected, and a same-day retry sends its linked verdict', () => {
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
    "if (args.join(' ') === 'station consent') { console.log(process.env.REM_TEST_CONSENT); process.exit(0); }",
    "if (args[0] !== 'rem' || args[1] !== 'verdict') { console.error('unexpected network verb'); process.exit(2); }",
    "if (process.env.REM_TEST_CONSENT !== 'full') { console.error('upload rejected: consent ' + process.env.REM_TEST_CONSENT); process.exit(1); }",
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
  assert.match(off, /cloud verdict j-original send failed: .*upload rejected: consent off/);
  assert.equal(existsSync(capture), false);
  assert.ok(readLedger(store).some(row => row.type === 'verdict' && row.proposal_id === id && row.verdict === 'Rejected'));
  assert.ok(readLedger(store).some(row => row.type === 'cloud-verdict' && row.judgment_id === 'j-original' && row.status === 'pending'));

  const state = readState(store);
  state.last_terminal = { id: '20260921-0000', date: '2026-09-21', status: 'success' };
  writeState(store, state);
  commitStore(store, 'already completed today');
  const failed = execFileSync(process.execPath, ['--experimental-strip-types', entry, 'run', '--now', '2026-09-21T01:00:00Z'],
    { env: { ...env, REM_TEST_CONSENT: 'full', REM_TEST_FAIL: '1' }, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  assert.match(failed, /already succeeded/);
  assert.match(failed, /cloud verdict j-original send failed: .*temporary cloud outage/);
  assert.equal(readState(store).last_terminal?.status, 'success');
  assert.match(readFileSync(join(store, 'run.log'), 'utf8'), /cloud verdict j-original send failed/);
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
    "if (args.join(' ') === 'station consent') { console.log('full'); process.exit(0); }",
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
  const failed = flushCloudVerdicts(store);
  assert.equal(failed.sent, 0);
  assert.equal(failed.pending, 1);
  assert.match(failed.errors.join('\n'), /cloud verdict j-promoted send failed: .*mismatched acknowledgment/);
  assert.equal(readLedger(store).filter(row => row.judgment_id === 'j-promoted').at(-1)?.status, 'pending');

  process.env.REM_ECHO_PROMOTION = '1';
  assert.deepEqual(flushCloudVerdicts(store), { sent: 1, pending: 0, errors: [] });
  assert.deepEqual(JSON.parse(readFileSync(capture, 'utf8')), ['rem', 'verdict', 'j-promoted', 'accept', '--all-projects']);
  const acked = readLedger(store).filter(row => row.judgment_id === 'j-promoted').at(-1);
  assert.equal(acked?.status, 'acked');
  assert.equal(acked?.applies_to, 'general');
});


test('queued accept, reject and tbd verdicts send in both sharing modes, and local-first sends nothing', t => {
  const bin = tmp('mode-verdicts');
  const capture = join(bin, 'sent.jsonl');
  writeFileSync(join(bin, 'sno'), `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2);
if (args[0] !== 'rem' || args[1] !== 'verdict') process.exit(2);
fs.appendFileSync(process.env.REM_REQUEST_CAPTURE, JSON.stringify(args) + '\\n');
console.log(JSON.stringify({schema_version:1,judgment_id:args[2],verdict:args[3],acknowledged:true}));
`, { mode: 0o755 });
  const before = { PATH: process.env.PATH, SNO_PROFILE_DIR: process.env.SNO_PROFILE_DIR, REM_REQUEST_CAPTURE: process.env.REM_REQUEST_CAPTURE };
  Object.assign(process.env, { PATH: `${bin}:${process.env.PATH ?? ''}`, REM_REQUEST_CAPTURE: capture });
  t.after(() => { for (const [key, value] of Object.entries(before)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; } });
  for (const mode of ['local-first', 'agent-native', 'rem-enhanced']) {
    process.env.SNO_PROFILE_DIR = writeStationSettings(mode);
    const store = makeStore(fixtureConfig());
    for (const verdict of ['accept', 'reject', 'tbd']) appendLedger(store, {
      type: 'cloud-verdict', judgment_id: `j-${mode}-${verdict}`, item_id: `L-${verdict}`, verdict, status: 'pending',
    });
    const result = flushCloudVerdicts(store);
    assert.deepEqual(result, { sent: mode === 'local-first' ? 0 : 3, pending: mode === 'local-first' ? 3 : 0, errors: [] });
    if (mode === 'local-first') assert.equal(existsSync(capture), false);
  }
  const commands = readFileSync(capture, 'utf8').trim().split('\n').map(line => JSON.parse(line));
  assert.deepEqual(commands, ['agent-native', 'rem-enhanced'].flatMap(mode => ['accept', 'reject', 'tbd']
    .map(verdict => ['rem', 'verdict', `j-${mode}-${verdict}`, verdict])));
});


test('a native run stores history links without cloud judgments and its later local verdict uploads', t => {
  const config = fixtureConfig();
  const store = makeStore(config);
  const id = '20260920-0100/codex';
  appendLedger(store, { type: 'proposal', proposal_id: id, run_id: '20260920-0100', half: 'codex',
    kind: 'patch', target: '/installed/target', region: 'body', purpose: { summary: 'a local change', page_ids: ['local-page'] },
    verdict: 'pending' });
  const bin = tmp('native-linked-verdict');
  const capture = join(bin, 'verdict.json');
  const request = join(bin, 'request.json');
  writeFileSync(join(bin, 'sno'), `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2);
if (args.join(' ') === 'rem judge') {
  const batch = JSON.parse(fs.readFileSync(0, 'utf8'));
  fs.writeFileSync(process.env.REM_NATIVE_REQUEST, JSON.stringify(batch));
  console.log(JSON.stringify({schema_version:1,run_id:batch.run_id,history_acknowledged:true,
    history_links:[{kind:'proposal',local_id:${JSON.stringify(id)},judgment_id:'j-native-local'}],
    halves:[{harness:'codex',pages:[],lessons:[],proposals:[{judgment_id:'j-new-cloud',proposal:{kind:'no_action',purpose:{summary:'Cloud judgment excluded from the local report',page_ids:[]}}}],read_judgments:[],log_entry:'Cloud judgment excluded from the local report'}]}));
  process.exit(0);
}
if (args[0] !== 'rem' || args[1] !== 'verdict') process.exit(2);
fs.writeFileSync(process.env.REM_REQUEST_CAPTURE, JSON.stringify(args));
console.log(JSON.stringify({schema_version:1,judgment_id:args[2],verdict:args[3],acknowledged:true}));
`, { mode: 0o755 });
  const before = { PATH: process.env.PATH, SNO_PROFILE_DIR: process.env.SNO_PROFILE_DIR,
    REM_REQUEST_CAPTURE: process.env.REM_REQUEST_CAPTURE, REM_NATIVE_REQUEST: process.env.REM_NATIVE_REQUEST };
  Object.assign(process.env, { PATH: `${bin}:${process.env.PATH ?? ''}`, SNO_PROFILE_DIR: writeStationSettings('agent-native'),
    REM_REQUEST_CAPTURE: capture, REM_NATIVE_REQUEST: request });
  t.after(() => { for (const [key, value] of Object.entries(before)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; } });
  const result = run(store, new Date('2026-09-21T00:00:00Z'), 'u', new FixtureBackend());
  assert.equal(result.code, 0, result.lines.join('\n'));
  const batch = JSON.parse(readFileSync(request, 'utf8'));
  assert.equal(batch.history.proposals[0].proposal_id, id, 'the service received the local item it associates');
  assert.ok(readLedger(store).some(row => row.type === 'cloud-link' && row.local_id === id && row.judgment_id === 'j-native-local'));
  assert.equal(readLedger(store).filter(row => row.type === 'proposal').length, 1, 'cloud proposals are not applied');
  const report = readFileSync(join(store, 'staging', '20260921-0000', 'REPORT.md'), 'utf8');
  assert.doesNotMatch(report, /Cloud judgment excluded|j-native-local|j-new-cloud/);
  const entry = join(import.meta.dirname, 'rem-reflect.ts');
  const verdict = execFileSync(process.execPath, ['--experimental-strip-types', entry, 'reject', id],
    { env: { ...process.env, REM_REFLECT_STORE: store }, encoding: 'utf8' });
  assert.match(verdict, /Rejected/);
  assert.deepEqual(JSON.parse(readFileSync(capture, 'utf8')), ['rem', 'verdict', 'j-native-local', 'reject']);
  assert.ok(readLedger(store).some(row => row.type === 'cloud-verdict' && row.judgment_id === 'j-native-local' && row.status === 'acked'));
  assert.equal(readFileSync(join(store, 'staging', '20260921-0000', 'REPORT.md'), 'utf8'), report, 'verdict delivery leaves the run report unchanged');
});
