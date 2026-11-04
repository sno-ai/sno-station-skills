import { test } from 'node:test';
import type { TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { appendFileSync, existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { BackendError } from './backend.ts';
import { removeLocallyWrittenSessions } from './cloud.ts';
import type { SpawnRequest } from './backend.ts';
import { run, status } from './rem-reflect.ts';
import { readLessons } from './lessons.ts';
import { readLedger } from './ledger.ts';
import { readState, writeJson } from './store.ts';
import {
  FixtureBackend, fixtureConfig, makeStore, setMtime, tmp, writeStationSettings,
  writeCodexSession, codexMeta, codexUser, codexAssistant, codexFailedTest,
} from './test-helpers.ts';

function environment(t: TestContext, mode: string): string {
  const before = { ...process.env };
  const profile = writeStationSettings(mode);
  const bin = tmp('allowance-bin');
  process.env.SNO_PROFILE_DIR = profile;
  process.env.SNO_IDENTITY_PATH = join(profile, 'explicit-identity.json');
  process.env.REM_REQUEST_CAPTURE = join(bin, 'requests.jsonl');
  process.env.REM_ALLOWANCE_REFUSED = 'yes';
  const delegate = before.PATH?.split(':').map(path => join(path, 'sno')).find(path => existsSync(path));
  assert.ok(delegate);
  writeFileSync(join(bin, 'sno'), `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2);
if (args[0] === 'rem' && args[1] === 'judge') {
  const batch = JSON.parse(fs.readFileSync(0, 'utf8'));
  fs.appendFileSync(process.env.REM_REQUEST_CAPTURE, JSON.stringify({args, batch}) + '\\n');
  if (process.env.REM_ALLOWANCE_REFUSED === 'request-failed') {
    console.log(JSON.stringify({error:'rem_request_failed',message:'this command failed; cause: REM judgment failed with HTTP 429'}));
    process.exit(1);
  }
  if (process.env.REM_ALLOWANCE_REFUSED === 'yes') {
    console.log(JSON.stringify({error:'allowance_used_up',message:'Your weekly allowance is used up.',reset_at:'2026-10-24T17:00:00Z',top_up_url:'https://example.com/top-up'}));
    process.exit(1);
  }
  console.log(JSON.stringify({schema_version:1,run_id:batch.run_id,history_acknowledged:true,history_links:[],halves:[]}));
  process.exit(0);
}
const result = require('node:child_process').spawnSync(${JSON.stringify(delegate)}, args, {encoding:'utf8'});
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
process.exit(result.status ?? 1);
`, { mode: 0o755 });
  process.env.PATH = `${bin}:${before.PATH ?? ''}`;
  t.after(() => {
    for (const key of ['PATH', 'SNO_PROFILE_DIR', 'SNO_IDENTITY_PATH', 'REM_REQUEST_CAPTURE', 'REM_ALLOWANCE_REFUSED']) {
      if (before[key] === undefined) delete process.env[key]; else process.env[key] = before[key];
    }
  });
  return profile;
}

class Writer extends FixtureBackend {
  override spawn(request: SpawnRequest): { stdout: string } {
    if (request.input.includes('previous_versions:')) return super.spawn(request);
    const line = Number(/^(\d+): .*No, read the report back/m.exec(request.input)?.[1]);
    const verdictLine = Number(/^(\d+) test failed /m.exec(request.input)?.[1]);
    return { stdout: JSON.stringify({ lesson: {
      summary: 'Read back the report', class: 'EXECUTION_LAPSE',
      situation: { task_type: 'report', trigger: 'report written', tools: [] },
      advice: 'Read the report back before declaring success.', because: 'The owner corrected an unchecked report.',
      expected_result: 'The stored report is the one written.', success_criteria: 'Read back the matching report title and body.', memory_fact_ids: [],
      polarity: 'from_failure', evidence: [{ line_start: line, line_end: line, quote: 'No, read the report back' }],
      skill_target: null, reminder_line: null, verdict_line: verdictLine,
    } }) };
  }
}

for (const mode of ['agent-native', 'rem-enhanced']) {
  test(`${mode}: two refused nights learn each session version once and upload a grown session after reset`, t => {
    const profile = environment(t, mode);
    const linked = mode === 'rem-enhanced';
    writeJson(join(profile, 'explicit-identity.json'), linked ? { user_account_id: 'account-test' } : {});
    writeJson(join(profile, 'identity.json'), linked ? {} : { user_account_id: 'account-test' });
    const settings = readFileSync(join(profile, 'settings.json'), 'utf8');
    assert.equal(JSON.parse(settings).modelCalls.R5[mode], 'off');
    const config = fixtureConfig({ time_zone: 'America/Los_Angeles' });
    const store = makeStore(config);
    const sessionPaths = ['first', 'second'].map(id =>
      writeCodexSession(config.codex_root, id, [codexMeta(id, '/n'),
        codexUser('write the report'), codexAssistant('done'), codexFailedTest(), codexUser('No, read the report back')],
      Date.parse('2026-10-18T01:00:00Z')));
    writeCodexSession(config.codex_root, 'quiet', [codexMeta('quiet', '/n'), codexAssistant('No correction or failed call.')],
      Date.parse('2026-10-18T01:00:00Z'));
    const session = (id: string) => ({ user_id: 'u', session_id: id, trace_id: `${id}.v1`, version: 1 });
    const saved = (runId: string, ids: string[]) => writeJson(join(store, 'staging', runId, 'cloud-request.json'), {
      schema_version: 1, run_id: runId, catalogue: [], usage_reads: [], usage_shown: [], outcome_summary: {},
      halves: [{ harness: 'codex', sessions: ids.map(session) }],
    });
    saved('20261016-0000', ['first', 'quiet']);
    saved('20261017-0000', ['first', 'second']);

    const first = run(store, new Date('2026-10-18T12:00:00Z'), 'u', new Writer());
    assert.equal(first.code, 0, first.lines.join('\n'));
    assert.deepEqual(readLessons(store).map(row => row.advice), [
      'Read the report back before declaring success.', 'Read the report back before declaring success.',
    ]);
    assert.equal(readState(store).last_terminal?.status, 'success');
    assert.equal(existsSync(join(store, 'staging', '20261017-0000', 'cloud-request.json')), false);
    const pendingSessions = () => readdirSync(join(store, 'staging')).flatMap(id => {
      const path = join(store, 'staging', id, 'cloud-request.json');
      if (!existsSync(path) || existsSync(join(store, 'staging', id, 'cloud-response.json'))) return [];
      const batch = JSON.parse(readFileSync(path, 'utf8'));
      return batch.halves.flatMap((half: { sessions: { session_id: string }[] }) => half.sessions.map(row => row.session_id));
    });
    assert.deepEqual(pendingSessions(), ['quiet', 'quiet']);
    const report = readFileSync(join(store, 'staging', '20261018-0500', 'REPORT.md'), 'utf8');
    assert.ok(report.includes("Self Learning ran on your own agent's model tonight: your weekly allowance is used up, resets Oct 24, 10:00 AM."));
    assert.ok(report.includes('Local sessions asked: 2\nNew lessons: 2\nNew proposals: 0'));
    assert.equal(report.includes('This computer gets one tenth of the free allowance until you link it: sno account claim.'), !linked);

    delete process.env.SNO_IDENTITY_PATH;
    writeCodexSession(config.codex_root, 'third', [codexMeta('third', '/n'), codexUser('write the report'),
      codexAssistant('done'), codexFailedTest(), codexUser('No, read the report back')], Date.parse('2026-10-19T01:00:00Z'));
    const second = run(store, new Date('2026-10-19T12:00:00Z'), 'u', new Writer());
    assert.equal(second.code, 0, second.lines.join('\n'));
    const ledger = readFileSync(join(store, 'ledger', 'local-writer.jsonl'), 'utf8').trim().split('\n').map(line => JSON.parse(line));
    assert.deepEqual(ledger.map(row => row.trace_key).sort(), ['u/codex/first.v1', 'u/codex/second.v1', 'u/codex/third.v1']);
    assert.equal(readLessons(store).length, 3);
    assert.deepEqual(pendingSessions(), ['quiet', 'quiet', 'quiet']);
    const secondRequestId = readdirSync(join(store, 'staging')).find(id => id.startsWith('20261019-0500-local-'));
    assert.ok(secondRequestId);
    const secondRequest = JSON.parse(readFileSync(join(store, 'staging', secondRequestId, 'cloud-request.json'), 'utf8'));
    assert.deepEqual(secondRequest.halves.flatMap((half: { sessions: { session_id: string }[] }) => half.sessions.map(row => row.session_id)), ['quiet']);
    const secondReport = readFileSync(join(store, 'staging', '20261019-0500', 'REPORT.md'), 'utf8');
    assert.ok(secondReport.includes('Local sessions asked: 1\nNew lessons: 1\nNew proposals: 0'));
    assert.equal(secondReport.includes('This computer gets one tenth of the free allowance until you link it: sno account claim.'), linked);
    assert.equal(existsSync(join(store, 'settings.local.json')), false);
    assert.deepEqual(readLedger(store), []);
    assert.equal(readFileSync(join(profile, 'settings.json'), 'utf8'), settings);
    assert.equal(status(store, new Date('2026-10-19T12:00:00Z'), '', true).lines[0], 'Self Learning');

    appendFileSync(sessionPaths[0], JSON.stringify(codexUser('No, read the report back again')) + '\n' + JSON.stringify(codexAssistant('checked')) + '\n');
    setMtime(sessionPaths[0], Date.parse('2026-10-20T01:00:00Z'));
    process.env.REM_ALLOWANCE_REFUSED = 'no';
    const reset = run(store, new Date('2026-10-20T12:00:00Z'), 'u', new Writer());
    assert.equal(reset.code, 0, reset.lines.join('\n'));
    const requests = readFileSync(String(process.env.REM_REQUEST_CAPTURE), 'utf8').trim().split('\n').map(line => JSON.parse(line));
    assert.deepEqual(requests[0].args, ['rem', 'judge', '--json']);
    assert.ok(requests[1].batch.run_id.startsWith('20261016-0000-local-'));
    for (const request of requests.slice(1)) {
      const versions = request.batch.halves.flatMap((half: { sessions: { trace_id: string }[] }) => half.sessions.map(row => row.trace_id)).sort();
      assert.deepEqual(versions, request.batch.run_id === '20261020-0500' ? ['first.v2', 'quiet.v1'] : ['quiet.v1']);
    }
    assert.ok(requests.some(request => request.batch.run_id === '20261020-0500'));
    assert.equal(readLessons(store).length, 3, 'the cloud handles the grown version after reset');
    assert.deepEqual(pendingSessions(), []);
  });
}

test('a CLI JSON error on stdout preserves its cause in the run log when stderr is empty', t => {
  environment(t, 'agent-native');
  process.env.REM_ALLOWANCE_REFUSED = 'request-failed';
  const config = fixtureConfig({ time_zone: 'America/Los_Angeles' });
  const store = makeStore(config);
  writeCodexSession(config.codex_root, 'request-failed', [codexMeta('request-failed', '/n'), codexUser('check the report')],
    Date.parse('2026-10-18T01:00:00Z'));

  run(store, new Date('2026-10-18T12:00:00Z'), 'u', new FixtureBackend());

  assert.ok(readFileSync(join(store, 'staging', '20261018-0500', 'run.log'), 'utf8').includes(
    'cloud run 20261018-0500 send failed: Error: this command failed; cause: REM judgment failed with HTTP 429; local run and report unchanged'));
});

test('an allowance refusal fails the night when every local session CLI is unavailable and leaves its request pending', t => {
  const profile = environment(t, 'agent-native');
  writeJson(join(profile, 'explicit-identity.json'), {});
  const config = fixtureConfig({ time_zone: 'America/Los_Angeles' });
  const store = makeStore(config);
  writeCodexSession(config.codex_root, 'unavailable', [codexMeta('unavailable', '/n'), codexUser('check the report'), codexFailedTest()],
    Date.parse('2026-10-18T01:00:00Z'));
  const result = run(store, new Date('2026-10-18T12:00:00Z'), 'u', {
    spawn(request) {
      if (request.input.includes('previous_versions:')) return new FixtureBackend().spawn(request);
      throw new BackendError('labeler-unavailable', 'codex login missing');
    },
  });
  assert.equal(result.code, 1);
  assert.equal(readState(store).last_terminal?.status, 'no_backend');
  assert.equal(readLessons(store).length, 0);
  assert.equal(existsSync(join(store, 'staging', '20261018-0500', 'cloud-request.json')), true);
  assert.ok(readFileSync(join(store, 'staging', '20261018-0500', 'run.log'), 'utf8').includes('unavailable.v1: local writer unavailable (codex: labeler-unavailable (codex login missing))'));
});

test('a saved request that cannot be edited keeps its bytes and logs the risk without losing local lessons', t => {
  const profile = environment(t, 'agent-native');
  writeJson(join(profile, 'explicit-identity.json'), {});
  const config = fixtureConfig({ time_zone: 'America/Los_Angeles' });
  const store = makeStore(config);
  writeCodexSession(config.codex_root, 'kept-lesson', [codexMeta('kept-lesson', '/n'), codexUser('write the report'),
    codexAssistant('done'), codexFailedTest(), codexUser('No, read the report back')], Date.parse('2026-10-18T01:00:00Z'));
  const broken = join(store, 'staging', '20261018-0600', 'cloud-request.json');
  writeJson(broken, {});
  writeFileSync(broken, '{unfinished request');
  const result = run(store, new Date('2026-10-18T12:00:00Z'), 'u', new Writer());
  assert.equal(result.code, 0, result.lines.join('\n'));
  assert.deepEqual(readLessons(store).map(row => row.advice), ['Read the report back before declaring success.']);
  assert.equal(readFileSync(broken, 'utf8'), '{unfinished request');
  assert.equal(existsSync(join(store, 'staging', '20261018-0500', 'cloud-request.json')), false);
  const log = readFileSync(join(store, 'staging', '20261018-0500', 'run.log'), 'utf8');
  assert.ok(log.includes('cloud run 20261018-0600 request not edited: SyntaxError:'));
  assert.ok(log.includes('full request kept, cloud may judge locally learned sessions again after reset'));
});


test('Local First learns a grown session version without asking an unchanged version twice', t => {
  environment(t, 'local-first');
  const config = fixtureConfig({ time_zone: 'America/Los_Angeles' });
  const store = makeStore(config);
  const path = writeCodexSession(config.codex_root, 'growing', [codexMeta('growing', '/n'),
    codexUser('write the report'), codexAssistant('done'), codexFailedTest(), codexUser('No, read the report back')],
    Date.parse('2026-10-18T01:00:00Z'));
  const first = run(store, new Date('2026-10-18T12:00:00Z'), 'u', new Writer());
  assert.equal(first.code, 0, first.lines.join('\n'));
  assert.equal(readLessons(store).length, 1);
  const unchanged = run(store, new Date('2026-10-19T12:00:00Z'), 'u', new Writer());
  assert.equal(unchanged.code, 0, unchanged.lines.join('\n'));
  assert.equal(readLessons(store).length, 1);
  appendFileSync(path, [codexFailedTest(), codexUser('No, read the report back again'), codexAssistant('checked')].map(row => JSON.stringify(row) + '\n').join(''));
  setMtime(path, Date.parse('2026-10-20T01:00:00Z'));
  const grown = run(store, new Date('2026-10-20T12:00:00Z'), 'u', new Writer());
  assert.equal(grown.code, 0, grown.lines.join('\n'));
  assert.equal(readLessons(store).length, 2);
  const ledger = readFileSync(join(store, 'ledger', 'local-writer.jsonl'), 'utf8').trim().split('\n').map(line => JSON.parse(line));
  assert.deepEqual(ledger.map(row => row.trace_key), ['u/codex/growing.v1', 'u/codex/growing.v2']);
  assert.equal(existsSync(String(process.env.REM_REQUEST_CAPTURE)), false);
});

test('pending request removes only the locally learned version', () => {
  const store = makeStore(fixtureConfig());
  const path = join(store, 'staging', '20261018-0500', 'cloud-request.json');
  const session = (version: number) => ({ user_id: 'u', session_id: 'growing', trace_id: `growing.v${version}`, version });
  writeJson(path, { run_id: '20261018-0500', halves: [{ harness: 'codex', sessions: [session(1), session(2)] }] });
  appendFileSync(join(store, 'ledger', 'local-writer.jsonl'), JSON.stringify({ trace_key: 'u/codex/growing.v1' }) + '\n');
  const log: string[] = [];
  removeLocallyWrittenSessions(store, log);
  const pending = readdirSync(join(store, 'staging')).filter(id => existsSync(join(store, 'staging', id, 'cloud-request.json')));
  assert.equal(pending.length, 1, 'the unlearned version keeps one pending request');
  assert.notEqual(pending[0], '20261018-0500', 'changed requests get a fresh identity');
  assert.equal(existsSync(path), false);
  assert.deepEqual(JSON.parse(readFileSync(join(store, 'staging', pending[0], 'cloud-request.json'), 'utf8')).halves, [{ harness: 'codex', sessions: [session(2)] }]);
  assert.deepEqual(log, []);
});
