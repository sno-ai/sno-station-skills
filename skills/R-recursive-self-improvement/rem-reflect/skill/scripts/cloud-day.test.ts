import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { run } from './rem-reflect.ts';
import { readState } from './store.ts';
import { FixtureBackend, fixtureConfig, makeStore, tmp, writeStationSettings,
  writeCodexSession, codexMeta, codexUser, codexAssistant } from './test-helpers.ts';

test('daily sharing follows mode, only enhanced reports cloud judgments, and rejected sends preserve the local report', t => {
  const bin = tmp('sno-cloud-day');
  const executable = join(bin, 'sno');
  writeFileSync(executable, [
    '#!/usr/bin/env node',
    "const fs = require('node:fs');",
    "const args = process.argv.slice(2).join(' ');",
    "if (args !== 'rem judge') { console.error('unexpected sno command: ' + args); process.exit(2); }",
    "const input = fs.readFileSync(0, 'utf8');",
    "fs.writeFileSync(process.env.REM_REQUEST_CAPTURE, input);",
    "if (process.env.REM_TEST_CONSENT !== 'full') { console.error('upload rejected: consent ' + process.env.REM_TEST_CONSENT); process.exit(1); }",
    "if (process.env.REM_TEST_FAIL === '1') { console.error('temporary cloud outage'); process.exit(1); }",
    "const batch = JSON.parse(input);",
    "const page = {page_id:'cloud-page',summary:'Cloud page judgment',body:'cloud body',root_cause:{fact:'cloud fact'},citations:[],count:1,last_seen:'2026-09-21',superseded:false};",
    "console.log(JSON.stringify({schema_version:1,run_id:batch.run_id,history_acknowledged:true,history_links:[],halves:batch.halves.map(half=>({harness:half.harness,attention:half.sessions.map(session=>({trace_id:session.trace_id,jev_outcome:'success',fail_probability:0.2,basis:'jev'})),pages:[{judgment_id:'j-page',page}],lessons:[],proposals:[],read_judgments:[],log_entry:'Cloud judgment for this run'}))}));",
  ].join('\n') + '\n');
  chmodSync(executable, 0o755);
  const keys = ['PATH', 'SNO_PROFILE_DIR', 'REM_TEST_CONSENT', 'REM_REQUEST_CAPTURE', 'REM_TEST_FAIL'];
  const before = new Map(keys.map(key => [key, process.env[key]]));
  process.env.PATH = `${bin}:${process.env.PATH ?? ''}`;
  t.after(() => {
    for (const [key, value] of before) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  });
  const config = fixtureConfig();
  let nativeReport = '';
  for (const mode of ['agent-native', 'rem-enhanced', 'local-first']) {
    for (const outcome of ['success', 'off', 'metadata-only', 'outage']) {
      process.env.SNO_PROFILE_DIR = writeStationSettings(mode);
      process.env.REM_TEST_CONSENT = outcome === 'off' || outcome === 'metadata-only' ? outcome : 'full';
      process.env.REM_TEST_FAIL = outcome === 'outage' ? '1' : '0';
      const store = makeStore(config);
      writeCodexSession(config.codex_root, 'session',
        [codexMeta('session', '/n'), codexUser('Finish this repair'), codexAssistant('The repair is incomplete')],
        Date.parse('2026-09-20T00:00:00Z'), '2026/09/20', '2026-09-20T00-00-00');
      const capture = join(bin, `request-${mode}-${outcome}.json`);
      process.env.REM_REQUEST_CAPTURE = capture;
      const backend = new FixtureBackend();
      const result = run(store, new Date('2026-09-21T00:00:00Z'), 'u', backend);
      assert.equal(result.code, 0, result.lines.join('\n'));
      assert.equal(readState(store).last_terminal?.status, 'success');
      const report = readFileSync(join(store, 'staging', '20260921-0000', 'REPORT.md'), 'utf8');
      const log = readFileSync(join(store, 'staging', '20260921-0000', 'run.log'), 'utf8');
      if (mode === 'local-first') {
        assert.equal(existsSync(capture), false);
        assert.equal(backend.calls.filter(call => call.kind === 'labeler').length, 0);
        assert.match(report, /No-upload: local-first mode/);
      } else {
        assert.equal(existsSync(capture), true, `${mode} reaches the CLI even when it rejects consent`);
        const batch = JSON.parse(readFileSync(capture, 'utf8'));
        assert.deepEqual(batch.halves.flatMap((half: { sessions: { trace_id: string }[] }) => half.sessions.map(row => row.trace_id)), ['session.v1']);
        assert.equal(backend.calls.filter(call => call.kind === 'labeler').length, 1);
        if (mode === 'agent-native') {
          if (outcome === 'success') nativeReport = report;
          assert.equal(report, nativeReport, 'sending cannot alter the native local report');
          assert.doesNotMatch(report, /Cloud judgment|Cloud-ranked|predicted success/);
          assert.equal(existsSync(join(store, 'wiki', 'patterns', 'cloud-page.md')), false, 'native does not apply the cloud judgment');
        } else if (outcome === 'success') {
          assert.match(report, /Cloud judgment for this run/);
          assert.match(report, /Cloud-ranked: 1/);
          assert.match(readFileSync(join(store, 'wiki', 'patterns', 'cloud-page.md'), 'utf8'), /Cloud page judgment/);
          assert.match(report, /session\.v1: predicted success/);
        } else {
          assert.match(report, /Local session outcomes:[\s\S]*session\.v1: fail/);
          assert.doesNotMatch(report, /Cloud judgment|Cloud-ranked|Run .* failed/);
        }
        if (outcome !== 'success') {
          assert.match(log, /cloud run 20260921-0000 send failed: .*?(upload rejected: consent|temporary cloud outage)/);
          assert.doesNotMatch(report, /send failed|upload rejected|cloud outage/);
        }
      }
    }
  }
});

test('an empty completed run is sent through the ordinary daily entry', t => {
  const capture = join(tmp('empty-day'), 'request.json');
  const bin = tmp('empty-cli');
  writeFileSync(join(bin, 'sno'), `#!/usr/bin/env node
const fs = require('node:fs');
const batch = JSON.parse(fs.readFileSync(0, 'utf8'));
fs.writeFileSync(process.env.REM_REQUEST_CAPTURE, JSON.stringify(batch));
console.log(JSON.stringify({schema_version:1,run_id:batch.run_id,history_acknowledged:true,history_links:[],halves:[]}));
`, { mode: 0o755 });
  const before = { PATH: process.env.PATH, SNO_PROFILE_DIR: process.env.SNO_PROFILE_DIR, REM_REQUEST_CAPTURE: process.env.REM_REQUEST_CAPTURE };
  Object.assign(process.env, { PATH: `${bin}:${process.env.PATH ?? ''}`, SNO_PROFILE_DIR: writeStationSettings('agent-native'), REM_REQUEST_CAPTURE: capture });
  t.after(() => { for (const [key, value] of Object.entries(before)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; } });
  const store = makeStore(fixtureConfig());
  const result = run(store, new Date('2026-09-21T00:00:00Z'), 'u', new FixtureBackend());
  assert.equal(result.code, 0, result.lines.join('\n'));
  const batch = JSON.parse(readFileSync(capture, 'utf8'));
  assert.equal(batch.run_id, '20260921-0000');
  assert.deepEqual(batch.halves, []);
});
