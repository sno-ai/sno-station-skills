import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildCloudBatch } from './cloud.ts';
import { labelHalf } from './labeler.ts';
import { renderTrace, loadRenderBudgets } from './render.ts';
import { fixtureConfig, makeStore } from './test-helpers.ts';
import type { Trace } from './harvest.ts';

function trace(agent: 'codex' | 'claude-code', records: Trace['records']): Trace {
  return { user_id: 'u', project_id: 'p', agent_id: agent, source_harness: agent, originator: agent,
    trace_id: 's.v1', session_id: 's', version: 1, source_path: '/source', source_line_range: [1, records.length + 1],
    source_mtime: 1, records, skipped_records: 0, skipped_blocks: 0, redactions: 0, trivial: false, skills_loaded: [] };
}
function batch(row: Trace): { calls: Record<string, unknown>[] } {
  const config = fixtureConfig();
  const store = makeStore(config);
  const labels = new Map([['u/' + row.agent_id + '/s.v1', { decision: 'keep' as const, outcome: 'fail' as const,
    reason: 'failed', evidence: [], key_ranges: [], labeled_by: 'codex', model: 'local' }]]);
  return buildCloudBatch(store, config, 'run', [row], labels, false).halves[0].sessions[0] as { calls: Record<string, unknown>[] };
}

test('Codex command and failed script reach the batch with literal failure facts', () => {
  const row = trace('codex', [
    { line_number: 2, source_line: 2, record: { type: 'response_item', timestamp: '2026-09-09T20:00:00Z', payload: {
      type: 'custom_tool_call', call_id: 'call-1', name: 'exec', input: 'patch file' } } },
    { line_number: 3, source_line: 3, record: { type: 'event_msg', payload: { type: 'item_completed', turn_id: 'turn-1',
      started_at_ms: 1788984000000, completed_at_ms: 1788984001000, item: { type: 'CommandExecution', id: 'exec-1',
        parsed_cmd: [{ cmd: 'false' }], status: 'failed', exit_code: 1, aggregated_output: 'bad command' } } } },
    { line_number: 4, source_line: 4, record: { type: 'response_item', timestamp: '2026-09-09T20:00:02Z', payload: {
      type: 'custom_tool_call_output', call_id: 'call-1', output: [{ type: 'input_text', text: 'Script failed\nScript error:\napply_patch verification failed' }] } } },
  ]);
  const calls = batch(row).calls;
  assert.equal(calls.length, 2);
  assert.deepEqual(calls.map(call => [call.call_id, call.failed, call.failure_kind, call.exit_code]),
    [['exec-1', true, 'exit_nonzero', 1], ['call-1', true, 'edit_mismatch', null]]);
  assert.match(renderTrace(row, loadRenderBudgets()).body, /3: command false exit 1 bad command/);
  assert.match(renderTrace(row, loadRenderBudgets()).body, /4: custom_tool_call_output Script failed/);
});

test('a script failure returned by wait keeps the original script call id', () => {
  const row = trace('codex', [
    { line_number: 2, source_line: 2, record: { type: 'response_item', payload: {
      type: 'custom_tool_call', call_id: 'call-2', input: 'apply a patch' } } },
    { line_number: 3, source_line: 3, record: { type: 'response_item', payload: {
      type: 'custom_tool_call_output', call_id: 'call-2', output: [{ type: 'input_text', text: 'Script running with cell ID 42' }] } } },
    { line_number: 4, source_line: 4, record: { type: 'response_item', payload: {
      type: 'function_call', call_id: 'wait-1', name: 'wait', arguments: '{"cell_id":"42"}' } } },
    { line_number: 5, source_line: 5, record: { type: 'response_item', payload: {
      type: 'function_call_output', call_id: 'wait-1', output: 'Script failed\napply_patch verification failed' } } },
  ]);
  assert.deepEqual(batch(row).calls.map(call => [call.call_id, call.line_start, call.line_end, call.failure_kind]),
    [['call-2', 2, 5, 'edit_mismatch']]);
});

test('Claude benign nonzero stays successful and injected notification is marked', () => {
  const row = trace('claude-code', [
    { line_number: 2, source_line: 2, record: { type: 'assistant', timestamp: '2026-09-09T20:00:00Z',
      message: { role: 'assistant', content: [{ type: 'tool_use', id: 'toolu-1', name: 'Bash', input: { command: 'grep x file' } }] } } },
    { line_number: 3, source_line: 3, record: { type: 'user', timestamp: '2026-09-09T20:00:01Z', promptId: 'turn-1',
      toolUseResult: { returnCodeInterpretation: 'no match' }, message: { role: 'user', content: [
        { type: 'tool_result', tool_use_id: 'toolu-1', content: 'Exit code 1\nno match', is_error: false }] } } },
    { line_number: 4, source_line: 4, record: { type: 'user', message: { role: 'user', content: '<task-notification>done</task-notification>' } } },
    { line_number: 5, source_line: 5, record: { type: 'user', isMeta: true, message: { role: 'user', content: 'Base directory for this skill: /skills/x' } } },
    { line_number: 6, source_line: 6, record: { type: 'user', message: { role: 'user', content: 'please stop' } } },
    { line_number: 7, source_line: 7, record: { type: 'user', isCompactSummary: true, message: { role: 'user', content: 'This session is being continued' } } },
  ]);
  assert.deepEqual(batch(row).calls.map(call => [call.failed, call.benign_nonzero, call.exit_code]), [[false, true, 1]]);
  const body = renderTrace(row, loadRenderBudgets()).body;
  assert.match(body, /4: user \[harness-shaped\] <task-notification>/);
  assert.match(body, /5: user \[harness-shaped\] Base directory/);
  assert.match(body, /6: user please stop/);
  assert.match(body, /7: user \[harness-shaped\] This session/);
});

test('labeling starts with the session that has more failures and typed owner messages across harnesses', () => {
  const claude = { ...trace('claude-code', [{ line_number: 2, source_line: 2, record: {
    type: 'user', message: { role: 'user', content: 'please help' } } }]), trace_id: 'claude.v1', session_id: 'claude' };
  const codex = { ...trace('codex', [
    { line_number: 2, source_line: 2, record: { type: 'response_item', payload: {
      type: 'message', role: 'user', content: [{ type: 'input_text', text: 'fix it' }] } } },
    { line_number: 3, source_line: 3, record: { type: 'event_msg', payload: { type: 'item_completed', turn_id: 'turn',
      item: { type: 'CommandExecution', id: 'exec-1', parsed_cmd: [{ cmd: 'false' }], status: 'failed',
        exit_code: 1, aggregated_output: 'failed' } } } },
  ]), trace_id: 'codex.v1', session_id: 'codex' };
  const store = makeStore(fixtureConfig());
  const raw = join(store, 'raw');
  mkdirSync(raw, { recursive: true });
  writeFileSync(join(raw, 'claude.v1.json'), JSON.stringify(claude));
  writeFileSync(join(raw, 'codex.v1.json'), JSON.stringify(codex));
  const ordered: string[] = [];
  const backend = { preflight: () => true,
    spawn: ({ input }: { input: string }) => {
      ordered.push(/"trace_id":"([^"]+)"/.exec(input)?.[1] ?? 'missing');
      return { stdout: JSON.stringify({ decision: 'keep', outcome: 'fail', reason: 'failure', evidence: [], key_ranges: [], notes: '' }) };
    } };
  const result = labelHalf(store, 'run', null, null, [claude, codex], backend, [], [claude, codex]);
  assert.deepEqual(ordered, ['codex.v1', 'claude.v1']);
  assert.equal(result.writes.length, 2);
});
