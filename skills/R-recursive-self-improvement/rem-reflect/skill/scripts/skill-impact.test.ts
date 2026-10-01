import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { applyCloudResponse } from './cloud.ts';
import { verdictCommand } from './adopt.ts';
import { readLedger, appendLedger } from './ledger.ts';
import { readLessons, appendRows } from './lessons.ts';
import { skillImpact } from './report.ts';
import { existingTraces } from './harvest.ts';
import { readLabels } from './labeler.ts';
import { skillRoots } from './config.ts';
import { writeJson } from './store.ts';
import { fixtureConfig, makeStore, fixtureHarnessHomes, writeInstalledSkill } from './test-helpers.ts';

const RUN = '20260921-0000';
function lesson(id: string, count: number, listed: boolean) {
  return { lesson_id: id, page_id: 'page', status: 'candidate', count, listed, helped: 0, harmful: 0, measured: false,
    created_run: RUN, project_id: 'p', agent_id: 'codex', user_id: 'u', skill_target: null,
    situation: { task_type: 'repair', trigger: 'failure', tools: [] }, scenario: { task_type: 'repair', trigger: 'failure', tools: [] },
    advice: 'Check the result', because: 'The result was absent', applies_to: 'general', polarity: 'from_failure',
    evidence: [], counter_examples: 'not searched' };
}
function seedTrace(store: string, id: string, mtime: number, skills: string[], outcome: string): void {
  const dir = join(store, 'raw', 'u', 'p', 'codex');
  mkdirSync(dir, { recursive: true });
  const trace = { user_id: 'u', project_id: 'p', agent_id: 'codex', source_harness: 'codex', originator: 'codex',
    trace_id: `${id}.v1`, session_id: id, version: 1, source_path: '/x', source_line_range: [1, 3], source_mtime: mtime,
    records: [{ line_number: 2, source_line: 2, record: { type: 'message', payload: { type: 'message', role: 'user', content: [{ type: 'input_text', text: 'x' }] } } }],
    skipped_records: 0, skipped_blocks: 0, redactions: 0, trivial: false, skills_loaded: skills };
  writeFileSync(join(dir, `${id}.v1.json`), JSON.stringify(trace));
  writeFileSync(join(dir, `${id}.v1.label.json`), JSON.stringify({ decision: 'keep', outcome, reason: 'observed',
    evidence: [], key_ranges: [], labeled_by: 'codex', model: 'fixture' }));
}

test('a cloud-staged lesson below the evidence gate cannot be accepted locally', () => {
  const store = makeStore(fixtureConfig());
  appendRows(join(store, 'wiki', 'lessons.jsonl'), [lesson('L-too-thin', 1, false)]);
  const refused = verdictCommand(store, 'accept', 'L-too-thin', new Date('2026-09-21T00:00:00Z'));
  assert.equal(refused.code, 1);
  assert.match(refused.lines.join('\n'), /count 1/);
  assert.equal(readLessons(store)[0].status, 'candidate');
  assert.equal(readLedger(store).filter(row => row.type === 'lesson-verdict').length, 0);
});

test('cloud read judgments count only followed, known-outcome effects once', () => {
  const config = fixtureConfig();
  const store = makeStore(config);
  seedTrace(store, 'A', Date.parse('2026-09-20T00:00:00Z'), [], 'success');
  seedTrace(store, 'B', Date.parse('2026-09-20T00:00:00Z'), [], 'unknown');
  appendRows(join(store, 'wiki', 'lessons.jsonl'), ['L1', 'L2', 'L3', 'L4'].map(id => lesson(id, 2, true)));
  appendRows(join(store, 'ledger', 'usage.jsonl'), [
    { type: 'read', session_id: 'A', lesson_id: 'L1' }, { type: 'read', session_id: 'A', lesson_id: 'L2' },
    { type: 'read', session_id: 'A', lesson_id: 'L4' }, { type: 'read', session_id: 'B', lesson_id: 'L3' },
  ]);
  writeJson(join(store, 'staging', RUN, 'cloud-request.json'), {
    schema_version: 1, run_id: RUN, halves: [], catalogue: [], usage_reads: [], outcome_summary: {},
  });
  const response = { schema_version: 1 as const, run_id: RUN, history_acknowledged: true, history_links: [], halves: [
    { harness: 'codex', attention: [], pages: [], lessons: [], proposals: [], log_entry: 'read effect', read_judgments: [
      { trace_id: 'A.v1', lesson_id: 'L1', followed: 'yes', effect: 'helped', line: 2 },
      { trace_id: 'A.v1', lesson_id: 'L2', followed: 'no', effect: 'helped', line: 2 },
      { trace_id: 'A.v1', lesson_id: 'L4', followed: 'yes', effect: 'neutral', line: 2 },
      { trace_id: 'B.v1', lesson_id: 'L3', followed: 'yes', effect: 'helped', line: 2 },
    ] },
  ] };
  applyCloudResponse(store, config, response);
  applyCloudResponse(store, config, response);
  const current = new Map(readLessons(store).map(row => [row.lesson_id, row]));
  assert.deepEqual([current.get('L1')?.helped, current.get('L1')?.measured], [1, true]);
  assert.deepEqual([current.get('L2')?.helped, current.get('L2')?.measured], [0, false]);
  assert.deepEqual([current.get('L4')?.helped, current.get('L4')?.measured], [0, false]);
  assert.deepEqual([current.get('L3')?.helped, current.get('L3')?.measured], [0, false]);
  assert.equal(readLedger(store).filter(row => row.type === 'lesson-judgment').length, 4);
});

test('skill impact counts only the adopted payload before and after its verdict', () => {
  const homes = fixtureHarnessHomes([]);
  for (const name of ['skill-x', 'skill-x-extra']) {
    writeInstalledSkill(homes.claudeHome, name); writeInstalledSkill(homes.codexHome, name);
  }
  const config = fixtureConfig({ claude_home: homes.claudeHome, codex_home: homes.codexHome });
  const store = makeStore(config);
  const target = join(homes.claudeHome, 'skills', 'skill-x-extra');
  const sibling = join(homes.claudeHome, 'skills', 'skill-x');
  appendLedger(store, { type: 'verdict', verdict: 'Accepted', proposal_id: 'P1', target, at: '2026-09-10', kind: 'patch' });
  seedTrace(store, 'before', Date.parse('2026-09-09T00:00:00Z'), [target], 'fail');
  seedTrace(store, 'after', Date.parse('2026-09-11T00:00:00Z'), [target], 'success');
  seedTrace(store, 'sibling', Date.parse('2026-09-11T00:00:00Z'), [sibling], 'fail');
  const impact = skillImpact(skillRoots(config), existingTraces(store), readLabels(store), readLedger(store));
  assert.deepEqual(impact[0].loaded_before, { traces: 1, fail: 1, unknown: 0 });
  assert.deepEqual(impact[0].loaded_after, { traces: 1, fail: 0, unknown: 0 });
  assert.equal(readFileSync(join(store, 'ledger', 'skill-impact.jsonl'), 'utf8').trim().split('\n').length, 1,
    'computing impact does not append a model-authored decision');
});
