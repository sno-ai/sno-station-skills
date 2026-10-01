import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateLabel } from './labeler.ts';
import type { Trace, StoredRecord } from './harvest.ts';

function rec(line: number, text: string): StoredRecord {
  return { line_number: line, source_line: line, record: { type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text }] } } };
}
function trace(records: StoredRecord[]): Trace {
  // claude-shaped records (message.role) => a claude-code trace, so render reads them
  return { user_id: 'u', project_id: 'p', agent_id: 'claude-code', source_harness: 'claude-code', originator: 'claude-code',
    trace_id: 's.v1', session_id: 's', version: 1, source_path: '/x', source_line_range: [1, records.length + 1],
    source_mtime: 1, records, skipped_records: 0, skipped_blocks: 0, redactions: 0, trivial: false, skills_loaded: [] };
}

// --- (labeler output validation) ---
test('a keep decision with empty evidence and no key_ranges is valid', () => {
  const t = trace([rec(2, 'alpha'), rec(3, 'beta')]);
  const out = validateLabel({ decision: 'keep', outcome: 'fail', reason: 'the goal was not reached', evidence: [], key_ranges: [], notes: '' }, t, []);
  assert.equal(out.decision, 'keep');
  assert.equal(out.outcome, 'fail');
});

test('the quote must appear within the CITED lines, not merely somewhere in the trace', () => {
  const t = trace([rec(2, 'alpha'), rec(3, 'beta')]);
  const good = { decision: 'keep', outcome: 'fail', reason: 'r', evidence: [{ trace_id: 's.v1', line_start: 2, line_end: 2, quote: 'alpha' }], key_ranges: [], notes: '' };
  assert.doesNotThrow(() => validateLabel(good, t, []));
  // 'beta' exists in the trace (line 3) but NOT in the cited line 2 -> refused (proves a ranged, not whole-trace, search)
  const wrongLine = { ...good, evidence: [{ trace_id: 's.v1', line_start: 2, line_end: 2, quote: 'beta' }] };
  assert.throws(() => validateLabel(wrongLine, t, []), /.*/, 'a quote from another line is refused');
});

test('a range outside the trace is refused even when the quote is real', () => {
  const t = trace([rec(2, 'alpha'), rec(3, 'beta')]);
  // line 9 does not exist; quote 'alpha' IS real (line 2). Only the range check can reject this.
  const badRange = { decision: 'keep', outcome: 'fail', reason: 'r', evidence: [{ trace_id: 's.v1', line_start: 2, line_end: 9, quote: 'alpha' }], key_ranges: [], notes: '' };
  assert.throws(() => validateLabel(badRange, t, []), /.*/, 'an end line outside the trace is refused');
});

test('a single local model decision needs no key_ranges even when the rendering is long', () => {
  const t = trace([rec(2, 'alpha'), rec(3, 'beta')]);
  assert.doesNotThrow(() => validateLabel({ decision: 'keep', outcome: 'unknown', reason: 'r', evidence: [], key_ranges: [], notes: '' }, t, []));
  assert.doesNotThrow(() => validateLabel({ decision: 'keep', outcome: 'unknown', reason: 'r', evidence: [], key_ranges: [{ line_start: 2, line_end: 3, why: 'the decisive turns' }], notes: '' }, t, []));
});

test('a bad outcome value or a missing field is refused by the contract', () => {
  const t = trace([rec(2, 'alpha')]);
  assert.throws(() => validateLabel({ decision: 'keep', outcome: 'maybe', reason: 'r', evidence: [], key_ranges: [], notes: '' }, t, []), /.*/);
  assert.throws(() => validateLabel({ decision: 'keep', outcome: 'fail', evidence: [], key_ranges: [], notes: '' }, t, []), /.*/, 'missing reason');
  assert.throws(() => validateLabel({ decision: 'uncertain', outcome: 'fail', reason: 'r', evidence: [], key_ranges: [], notes: '' }, t, []), /.*/, 'uncertain cannot be treated as a drop');
});
