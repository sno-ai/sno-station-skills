import { test } from 'node:test';
import { saveLocalSettings } from './local-settings.ts';
import assert from 'node:assert/strict';
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildCloudBatch, sendCloudBatch } from './cloud.ts';
import { chunkRendering } from './chunk.ts';
import { appendLedger } from './ledger.ts';
import type { Trace, StoredRecord } from './harvest.ts';
import { renderTrace, loadRenderBudgets } from './render.ts';
import { fixtureConfig, makeStore, tmp, writeInstalledSkill } from './test-helpers.ts';

function trace(session: string): Trace {
  const records: StoredRecord[] = [2, 3, 4, 5, 6].map((line, index) => ({
    line_number: line, source_line: line,
    record: { type: 'response_item', payload: { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: `${session}-${index}-` + 'x'.repeat(15_000) }] } },
  }));
  return {
    user_id: 'local-u', project_id: 'p', agent_id: 'codex', source_harness: 'codex', originator: 'codex',
    trace_id: `${session}.v1`, session_id: session, version: 1, source_path: '/source', source_line_range: [1, 6],
    source_mtime: Date.parse('2026-09-21T00:00:00Z'), records, skipped_records: 0, skipped_blocks: 0,
    redactions: 0, trivial: false, skills_loaded: [],
  };
}

test('cloud batch sends every retained chunk, complete installed skill bodies, and only relevant actual reads', () => {
  const config = fixtureConfig();
  const first = writeInstalledSkill(config.claude_home, 'batch-first', 'FIRST-BODY-' + 'a'.repeat(1200));
  const second = writeInstalledSkill(config.codex_home, 'batch-second', 'SECOND-BODY-' + 'b'.repeat(1300));
  const store = makeStore(config);
  const retained = [trace('kept-a'), trace('kept-b')];
  const usage = join(store, 'ledger', 'usage.jsonl');
  mkdirSync(join(store, 'ledger'), { recursive: true });
  writeFileSync(usage, [
    { type: 'shown', session_id: 'kept-a', lesson_ids: ['L-a', 'L-b'] },
    { type: 'shown', session_id: 'kept-a', agent_id: 'codex', lesson_ids: ['L-b', 'L-c'] },
    { type: 'shown', session_id: 'kept-b', lesson_ids: [] },
    { type: 'shown', session_id: 'not-uploaded', lesson_ids: ['L-x'] },
    { type: 'read', session_id: 'kept-a', lesson_id: 'L-used' },
    { type: 'read', session_id: 'not-uploaded', lesson_id: 'L-irrelevant' },
  ].map(row => JSON.stringify(row)).join('\n') + '\n');
  const labels = new Map(retained.map(row => [`local-u/codex/${row.trace_id}`, {
    decision: 'keep' as const, outcome: 'fail' as const, reason: 'the task failed',
    evidence: [], key_ranges: [], labeled_by: 'codex', model: 'local-model',
  }]));

  const batch = buildCloudBatch(store, config, '20260921-0100', retained, labels, false);

  assert.equal(batch.halves.length, 1);
  assert.deepEqual(batch.halves[0].sessions.map(row => row.trace_id), retained.map(row => row.trace_id));
  for (const [index, row] of batch.halves[0].sessions.entries()) {
    const expected = chunkRendering(retained[index].trace_id, renderTrace(retained[index], loadRenderBudgets()));
    assert.ok(expected.length > 1, 'this fixture really exercises multi-chunk upload');
    assert.deepEqual(row.chunks.map(chunk => chunk.text), expected.map(chunk => chunk.text));
    assert.equal(row.local_outcome, 'fail');
    assert.equal(row.local_reason, 'the task failed');
  }
  const byPath = new Map(batch.catalogue.map(item => [item.path, item]));
  assert.match(byPath.get(join(first, 'SKILL.md'))?.skill_md ?? '', /FIRST-BODY-a{1200}/);
  assert.match(byPath.get(join(second, 'SKILL.md'))?.skill_md ?? '', /SECOND-BODY-b{1300}/);
  assert.equal(byPath.get(join(first, 'SKILL.md'))?.skill_md, readFileSync(join(first, 'SKILL.md'), 'utf8'));
  assert.deepEqual(batch.usage_reads, [{ session_id: 'kept-a', lesson_id: 'L-used' }]);
  assert.deepEqual(batch.usage_shown, [{ session_id: 'kept-a', lesson_ids: ['L-a', 'L-b', 'L-c'] }]);
  assert.equal('history' in batch, false);

  appendLedger(store, { type: 'proposal', proposal_id: 'old-proposal', verdict: 'pending' });
  appendLedger(store, { type: 'verdict', proposal_id: 'old-proposal', verdict: 'Rejected' });
  const firstBatch = buildCloudBatch(store, config, '20260921-0100', retained, labels, true);
  assert.deepEqual(firstBatch.history?.proposals.map(row => row.proposal_id), ['old-proposal']);
  assert.deepEqual(firstBatch.history?.skill_impact_rows.map(row => row.verdict), ['Rejected']);
});

test('a lost cloud answer leaves the exact batch for the next entry to replay under its original id', t => {
  const config = fixtureConfig();
  const store = makeStore(config);
  const bin = tmp('sno-bin');
  const capture = join(bin, 'requests.jsonl');
  const executable = join(bin, 'sno');
  writeFileSync(executable, [
    '#!/usr/bin/env node',
    "const fs = require('node:fs');",
    "const raw = fs.readFileSync(0, 'utf8');",
    "const path = process.env.REM_REQUEST_CAPTURE;",
    "const first = !fs.existsSync(path);",
    "fs.appendFileSync(path, JSON.stringify(raw) + '\\n');",
    "if (first) { console.error('response lost'); process.exit(1); }",
    "const batch = JSON.parse(raw);",
    "console.log(JSON.stringify({schema_version:1,run_id:batch.run_id,history_acknowledged:true,history_links:[],halves:[],settings_version:'v1',local:{labeler_input_max_chars:120000,labeler_event_window_lines:60,recall_timeout_ms:5000}}));",
  ].join('\n') + '\n');
  chmodSync(executable, 0o755);
  const oldPath = process.env.PATH;
  const oldCapture = process.env.REM_REQUEST_CAPTURE;
  process.env.PATH = `${bin}:${oldPath ?? ''}`;
  process.env.REM_REQUEST_CAPTURE = capture;
  t.after(() => {
    if (oldPath === undefined) delete process.env.PATH; else process.env.PATH = oldPath;
    if (oldCapture === undefined) delete process.env.REM_REQUEST_CAPTURE; else process.env.REM_REQUEST_CAPTURE = oldCapture;
  });

  const firstBatch = { schema_version: 1, run_id: '20260921-0100', halves: [], catalogue: [], usage_reads: [], outcome_summary: {} };
  assert.throws(() => sendCloudBatch(store, firstBatch), /response lost/);
  const replacement = { ...firstBatch, run_id: '20260921-0300', outcome_summary: { changed: true } };
  const response = sendCloudBatch(store, replacement);
  assert.equal(response.run_id, firstBatch.run_id);
  saveLocalSettings(store, response);
  assert.deepEqual(JSON.parse(readFileSync(join(store, 'settings.local.json'), 'utf8')),
    { version: 'v1', labeler_input_max_chars: 120000, labeler_event_window_lines: 60, recall_timeout_ms: 5000 });
  const requests = readFileSync(capture, 'utf8').trim().split('\n').map(row => JSON.parse(row) as string);
  assert.equal(requests.length, 2);
  assert.equal(requests[1], requests[0], 'the complete stdin bytes, not a rebuilt batch, are replayed');
});

test('a request holding half of an emoji reaches sno as well-formed JSON text', t => {
  const config = fixtureConfig();
  const store = makeStore(config);
  const bin = tmp('sno-bin');
  const capture = join(bin, 'stdin.txt');
  const executable = join(bin, 'sno');
  writeFileSync(executable, [
    '#!/usr/bin/env node',
    "const fs = require('node:fs');",
    "const raw = fs.readFileSync(0, 'utf8');",
    "fs.writeFileSync(process.env.REM_REQUEST_CAPTURE, raw);",
    "const batch = JSON.parse(raw);",
    "console.log(JSON.stringify({schema_version:1,run_id:batch.run_id,history_acknowledged:true,history_links:[],halves:[]}));",
  ].join('\n') + '\n');
  chmodSync(executable, 0o755);
  const oldPath = process.env.PATH;
  const oldCapture = process.env.REM_REQUEST_CAPTURE;
  process.env.PATH = `${bin}:${oldPath ?? ''}`;
  process.env.REM_REQUEST_CAPTURE = capture;
  t.after(() => {
    if (oldPath === undefined) delete process.env.PATH; else process.env.PATH = oldPath;
    if (oldCapture === undefined) delete process.env.REM_REQUEST_CAPTURE; else process.env.REM_REQUEST_CAPTURE = oldCapture;
  });
  const batch = { schema_version: 1, run_id: '20260923-0000', halves: [{ text: 'React with \ud83d[… 12 characters omitted …]' }, { signature: 'patch\0skills/peer-review/skill' }],
    catalogue: [], usage_reads: [], outcome_summary: {} };
  sendCloudBatch(store, batch);
  assert.doesNotMatch(readFileSync(capture, 'utf8'), /\\u[dD][89abAB][0-9a-fA-F]{2}(?!\\u[dD][c-fC-F])/);
  // the cloud's JSON column refuses NUL, which older proposal signatures and some session text carry
  assert.doesNotMatch(readFileSync(capture, 'utf8'), /\\u0000/);
});
