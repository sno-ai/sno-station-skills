import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { run } from './rem-reflect.ts';
import { FixtureBackend, fixtureConfig, makeStore, tmp, writeCodexSession, codexMeta, codexUser, codexAssistant } from './test-helpers.ts';

test('ordinary daily entry uploads every kept session at full consent and opens no cloud connection below full', t => {
  const bin = tmp('sno-cloud-day');
  const executable = join(bin, 'sno');
  writeFileSync(executable, [
    '#!/usr/bin/env node',
    "const fs = require('node:fs');",
    "const args = process.argv.slice(2).join(' ');",
    "if (args === 'station telemetry consent get') { console.log(process.env.REM_TEST_CONSENT); process.exit(0); }",
    "if (args !== 'rem judge') { console.error('unexpected sno command: ' + args); process.exit(2); }",
    "const input = fs.readFileSync(0, 'utf8');",
    "fs.writeFileSync(process.env.REM_REQUEST_CAPTURE, input);",
    "const batch = JSON.parse(input);",
    "console.log(JSON.stringify({schema_version:1,run_id:batch.run_id,history_acknowledged:true,history_links:[],halves:batch.halves.map(half=>({harness:half.harness,attention:half.sessions.map(session=>({trace_id:session.trace_id,jev_outcome:'success',fail_probability:0.2,basis:'jev'})),pages:[],lessons:[],proposals:[],read_judgments:[],log_entry:'No evidence warrants a change'}))}));",
  ].join('\n') + '\n');
  chmodSync(executable, 0o755);
  const before = { path: process.env.PATH, consent: process.env.REM_TEST_CONSENT, capture: process.env.REM_REQUEST_CAPTURE };
  process.env.PATH = `${bin}:${before.path ?? ''}`;
  t.after(() => {
    for (const [key, value] of [['PATH', before.path], ['REM_TEST_CONSENT', before.consent], ['REM_REQUEST_CAPTURE', before.capture]] as const) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  });

  for (const consent of ['full', 'off', 'metadata-only']) {
    const config = fixtureConfig();
    const store = makeStore(config);
    writeCodexSession(config.codex_root, `session-${consent}`,
      [codexMeta(`session-${consent}`, '/n'), codexUser('Finish this repair'), codexAssistant('The repair is incomplete')],
      Date.parse('2026-09-20T00:00:00Z'), '2026/09/20', '2026-09-20T00-00-00');
    const capture = join(bin, `request-${consent}.json`);
    process.env.REM_TEST_CONSENT = consent;
    process.env.REM_REQUEST_CAPTURE = capture;
    const backend = new FixtureBackend();
    const result = run(store, new Date('2026-09-21T00:00:00Z'), 'u', backend);

    assert.equal(result.code, 0, result.lines.join('\n'));
    // Labels only serve the upload, so below full consent nothing runs locally either.
    assert.equal(backend.calls.filter(call => call.kind === 'labeler').length, consent === 'full' ? 1 : 0);
    assert.deepEqual(backend.calls.filter(call => call.kind !== 'preflight').map(call => call.kind), consent === 'full' ? ['labeler'] : [],
      consent === 'full' ? 'only the labeler runs locally' : `${consent} runs nothing locally`);
    const report = readFileSync(join(store, 'staging', '20260921-0000', 'REPORT.md'), 'utf8');
    if (consent === 'full') {
      assert.equal(existsSync(capture), true, 'the full-consent day reached the CLI');
      const batch = JSON.parse(readFileSync(capture, 'utf8'));
      assert.deepEqual(batch.halves.flatMap((half: { sessions: { trace_id: string }[] }) => half.sessions.map(row => row.trace_id)), [`session-${consent}.v1`]);
      assert.match(report, /No evidence warrants a change/);
      assert.match(report, /Attention order:[\s\S]*session-full\.v1: predicted success; fail probability 0\.2; local fail/);
      assert.match(report, /Cloud-ranked: 1/);
      assert.match(report, /Evidence: .*cloud-request\.json/);
    } else {
      assert.equal(existsSync(capture), false, `${consent} must make zero cloud calls`);
      assert.match(report, /no.upload/i);
    }
  }
});
