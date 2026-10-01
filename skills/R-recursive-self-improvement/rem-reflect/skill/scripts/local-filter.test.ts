import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { BackendError } from './backend.ts';
import type { Backend, SpawnRequest } from './backend.ts';
import type { Trace, StoredRecord } from './harvest.ts';
import { labelHalf } from './labeler.ts';
import { tmp } from './test-helpers.ts';

function rec(line: number, role: 'user' | 'assistant', text: string): StoredRecord {
  return { line_number: line, source_line: line,
    record: { type: 'response_item', payload: { type: 'message', role, content: [{ type: role === 'user' ? 'input_text' : 'output_text', text }] } } };
}

function trace(version: number, records: StoredRecord[]): Trace {
  return {
    user_id: 'u', project_id: 'p', agent_id: 'codex', source_harness: 'codex', originator: 'codex',
    trace_id: `s.v${version}`, session_id: 's', version, source_path: '/x', source_line_range: [1, records.length],
    source_mtime: version, records, skipped_records: 0, skipped_blocks: 0, redactions: 0,
    trivial: false, skills_loaded: [],
  };
}

function stored(trace: Trace): string {
  const store = tmp('filter');
  const raw = join(store, 'raw');
  mkdirSync(raw);
  writeFileSync(join(raw, `${trace.trace_id}.json`), JSON.stringify(trace));
  return store;
}

test('one session uses its own CLI once, keeping bounded typed context without prior tool output', () => {
  const old = trace(1, [rec(2, 'user', 'my typed goal'), {
    line_number: 3, source_line: 3,
    record: { type: 'response_item', payload: { type: 'message', role: 'user', content: [{ type: 'tool_result', content: 'TOOL-OUTPUT-' + 'X'.repeat(200_000) }] } },
  }]);
  const current = trace(2, [rec(2, 'user', 'finish the goal'), rec(3, 'assistant', 'Y'.repeat(90_000))]);
  const store = stored(current);
  const calls: SpawnRequest[] = [];
  const backend: Backend = {
    preflight: () => true,
    spawn(request) {
      calls.push(request);
      return { stdout: JSON.stringify({ decision: 'keep', outcome: 'fail', reason: 'the goal was not reached', evidence: [], key_ranges: [], notes: '' }) };
    },
  };

  const result = labelHalf(store, 'run', 'codex', 'codex', [current], backend, [], [old, current]);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].cli, 'codex');
  assert.match(calls[0].input, /my typed goal/);
  assert.doesNotMatch(calls[0].input, /TOOL-OUTPUT-/);
  assert.ok(calls[0].input.length < 150_000, 'an earlier version cannot dominate the current session');
  assert.deepEqual(result.writes.map(row => [row.label.decision, row.label.outcome]), [['keep', 'fail']]);
});

test('an unavailable own CLI publishes a persisted keep/unknown decision instead of retrying it tomorrow', () => {
  const current = trace(1, [rec(2, 'user', 'do the task'), rec(3, 'assistant', 'not done')]);
  const store = stored(current);
  let calls = 0;
  const backend: Backend = {
    preflight: () => true,
    spawn() { calls++; throw new BackendError('labeler-unavailable'); },
  };
  const result = labelHalf(store, 'run', 'codex', 'codex', [current], backend, [], [current]);

  assert.equal(calls, 1);
  assert.equal(result.writes.length, 1);
  assert.deepEqual([result.writes[0].label.decision, result.writes[0].label.outcome], ['keep', 'unknown']);
  assert.match(result.writes[0].label.reason, /labeler-unavailable/);
});

test('invalid model output cannot authorize a drop', () => {
  const current = trace(1, [rec(2, 'user', 'do the task'), rec(3, 'assistant', 'answer')]);
  const store = stored(current);
  const backend: Backend = {
    preflight: () => true,
    spawn: () => ({ stdout: '{"decision":"drop","outcome":"success"}' }),
  };
  const result = labelHalf(store, 'run', 'codex', 'codex', [current], backend, [], [current]);

  assert.deepEqual([result.writes[0].label.decision, result.writes[0].label.outcome], ['keep', 'unknown']);
  assert.match(result.writes[0].label.reason, /invalid-response/);
});
