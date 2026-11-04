import { test } from 'node:test';
import assert from 'node:assert/strict';
import { appendFileSync, existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildCloudBatch, applyCloudResponse, removeLocallyWrittenSessions, sendCloudBatch } from './cloud.ts';
import { writeLocally } from './local-writer.ts';
import { verdictCommand } from './adopt.ts';
import { existingTraces, harvest } from './harvest.ts';
import { readLedger } from './ledger.ts';
import { readState, writeJson } from './store.ts';
import type { SpawnRequest } from './backend.ts';
import { FixtureBackend, fixtureConfig, makeStore, tmp, writeStationSettings, writeCodexSession,
  codexMeta, codexUser, codexAssistant, codexFailedTest } from './test-helpers.ts';

class ReminderWriter extends FixtureBackend {
  override spawn(request: SpawnRequest): { stdout: string } {
    const header = /^(\{"trace_id".*)$/m.exec(request.input)?.[1];
    assert.ok(header);
    const target = (JSON.parse(header) as { skills_loaded: string[] }).skills_loaded[0];
    const line = Number(/^(\d+): .*No, read the report back/m.exec(request.input)?.[1]);
    const verdictLine = Number(/^(\d+) test failed /m.exec(request.input)?.[1]);
    return { stdout: JSON.stringify({ lesson: {
      summary: 'Read back the report', class: 'EXECUTION_LAPSE',
      situation: { task_type: 'report', trigger: 'report written', tools: [] },
      advice: 'Read the report back.', because: 'The owner corrected an unchecked report.', polarity: 'from_failure',
      expected_result: 'The stored report is the one written.', success_criteria: 'Read back the matching report title and body.', memory_fact_ids: [],
      evidence: [{ line_start: line, line_end: line, quote: 'No, read the report back' }],
      skill_target: target, reminder_line: 'Keep the local reminder.', verdict_line: verdictLine,
    } }) };
  }
}

test('a fallback reminder survives a later cloud proposal and remains adoptable', t => {
  const previous = process.env.SNO_PROFILE_DIR;
  process.env.SNO_PROFILE_DIR = writeStationSettings('rem-enhanced');
  t.after(() => { if (previous === undefined) delete process.env.SNO_PROFILE_DIR; else process.env.SNO_PROFILE_DIR = previous; });
  const config = fixtureConfig();
  const store = makeStore(config);
  const now = new Date('2026-10-18T12:00:00Z');
  const runId = '20261018-0500';
  for (const id of ['one', 'two', 'three', 'four']) {
    writeCodexSession(config.codex_root, id, [codexMeta(id, '/n'), codexUser('<skill>\n<name>heartbeat</name>\n</skill>'),
      codexUser('write the report'), codexAssistant('done'), codexFailedTest(), codexUser('No, read the report back')],
      Date.parse('2026-10-18T01:00:00Z'));
  }
  harvest(store, config, readState(store), 'u', now);
  const traces = existingTraces(store);
  const labels = new Map(traces.map(trace => [`u/codex/${trace.trace_id}`, {
    decision: 'keep' as const, outcome: 'fail' as const, reason: 'owner correction', evidence: [], key_ranges: [], labeled_by: 'codex', model: 'fixture',
  }]));
  writeJson(join(store, 'staging', runId, 'cloud-request.json'), buildCloudBatch(store, config, runId, traces, labels, true));
  assert.equal(writeLocally(store, config, runId, traces, new ReminderWriter(), [], now, true).proposals, 1);
  const local = readLedger(store).find(row => row.type === 'proposal' && row.backend === 'local');
  assert.ok(local);
  const files = ['proposal.json', 'patch.json', 'PURPOSE.md'];
  const directory = join(store, 'staging', String(local.proposal_id));
  const before = files.map(name => readFileSync(join(directory, name), 'utf8'));
  removeLocallyWrittenSessions(store, []);
  const pending = readdirSync(join(store, 'staging')).find(id => existsSync(join(store, 'staging', id, 'cloud-request.json')));
  assert.ok(pending);
  const batch = JSON.parse(readFileSync(join(store, 'staging', pending, 'cloud-request.json'), 'utf8'));
  assert.equal(batch.halves[0].sessions.length, 1);
  const proposal = { ...JSON.parse(before[0]), line: 'Keep the cloud reminder.',
    purpose: { summary: 'A separate cloud reminder', page_ids: JSON.parse(before[0]).purpose.page_ids } };
  delete proposal.target_hashes;
  applyCloudResponse(store, config, { schema_version: 1, run_id: batch.run_id, history_acknowledged: true, history_links: [],
    halves: [{ harness: 'codex', pages: [], lessons: [], read_judgments: [], proposals: [{ judgment_id: 'cloud-proposal-1', proposal }] }] });
  assert.deepEqual(files.map(name => readFileSync(join(directory, name), 'utf8')), before);
  const proposals = readLedger(store).filter(row => row.type === 'proposal');
  assert.equal(proposals.length, 2);
  assert.equal(new Set(proposals.map(row => row.proposal_id)).size, 2);
  const adopted = verdictCommand(store, 'accept', String(local.proposal_id), now);
  assert.equal(adopted.code, 0, adopted.lines.join('\n'));
  const installed = readFileSync(join(String(local.target), 'SKILL.md'), 'utf8');
  assert.ok(installed.includes('Keep the local reminder.'));
  assert.equal(installed.includes('Keep the cloud reminder.'), false);
});

test('a rewritten pending upload gets a new identity accepted by the immutable server contract', t => {
  const store = makeStore(fixtureConfig());
  const bin = tmp('immutable-server');
  const previous = process.env.PATH;
  t.after(() => { if (previous === undefined) delete process.env.PATH; else process.env.PATH = previous; });
  const records = join(bin, 'accepted.json');
  writeFileSync(join(bin, 'sno'), `#!/usr/bin/env node
const fs = require('node:fs');
const batch = JSON.parse(fs.readFileSync(0, 'utf8'));
const path = ${JSON.stringify(records)};
const seen = fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, 'utf8')) : {};
if (seen[batch.run_id] && JSON.stringify(seen[batch.run_id]) !== JSON.stringify(batch)) {
 console.log(JSON.stringify({error:'part_conflict',message:'same run id with different request'})); process.exit(1);
}
seen[batch.run_id] = batch; fs.writeFileSync(path, JSON.stringify(seen));
if (Object.keys(seen).length === 1) {
 console.log(JSON.stringify({error:'allowance_used_up',message:'allowance used up',reset_at:'2026-10-24T17:00:00Z'})); process.exit(1);
}
console.log(JSON.stringify({schema_version:1,run_id:batch.run_id,history_acknowledged:true,history_links:[],halves:[]}));
`, { mode: 0o755 });
  process.env.PATH = `${bin}:${previous ?? ''}`;
  const session = (id: string) => ({ user_id: 'u', session_id: id, trace_id: `${id}.v1`, version: 1 });
  const batch = { schema_version: 1, run_id: '20261018-0500', catalogue: [], usage_reads: [], usage_shown: [], outcome_summary: {},
    halves: [{ harness: 'codex', sessions: [session('learned'), session('pending')] }] };
  assert.throws(() => sendCloudBatch(store, batch), /allowance used up/);
  appendFileSync(join(store, 'ledger', 'local-writer.jsonl'), JSON.stringify({ trace_key: 'u/codex/learned.v1' }) + '\n');
  removeLocallyWrittenSessions(store, []);
  const response = sendCloudBatch(store, batch);
  assert.notEqual(response.run_id, batch.run_id);
  const accepted = JSON.parse(readFileSync(records, 'utf8'));
  assert.deepEqual(accepted[batch.run_id], batch);
  assert.deepEqual(accepted[response.run_id].halves[0].sessions, [session('pending')]);
});
