import { test } from 'node:test';
import assert from 'node:assert/strict';
import { truncate, renderTrace, stripCodexPreamble } from './render.ts';
import type { RenderBudgets } from './render.ts';
import { chunkRendering, reassembleChunks } from './chunk.ts';
import type { Rendering } from './render.ts';
import type { Trace, StoredRecord } from './harvest.ts';

const BUDGETS: RenderBudgets = { tool_arguments: 400, tool_results: 1600, skill_blocks: 3000 };

function trace(agent: 'claude-code' | 'codex', records: StoredRecord[], over: Partial<Trace> = {}): Trace {
  return {
    user_id: 'u', project_id: 'github.com/example/project', agent_id: agent, source_harness: agent,
    originator: agent, trace_id: 's.v1', session_id: 's', version: 1, source_path: '/x', source_line_range: [1, 1],
    source_mtime: 0, records, skipped_records: 0, skipped_blocks: 0, redactions: 0, trivial: false, skills_loaded: [],
    ...over,
  };
}
function rec(line: number, record: Record<string, unknown>): StoredRecord {
  return { line_number: line, source_line: line, record };
}

// --- (rendering portion): truncation keeps head and tail with one omitted-count marker ---
test('truncate keeps the actual head and the actual tail, with one marker', () => {
  // Distinct head and tail so the test proves head is head and tail is tail, not merely length.
  const out = truncate('H'.repeat(2500) + 'T'.repeat(2500), 1600);
  assert.equal(out.slice(0, 800), 'H'.repeat(800), 'head is the real head');
  assert.equal(out.slice(-800), 'T'.repeat(800), 'tail is the real tail');
  assert.equal((out.match(/\[… 3400 characters omitted …\]/g) ?? []).length, 1);
  assert.doesNotMatch(out, /H{801}/);
  assert.doesNotMatch(out, /T{801}/);
  // budget 400 -> 200 head + 200 tail
  const small = truncate('A'.repeat(2500) + 'B'.repeat(2500), 400);
  assert.equal(small, 'A'.repeat(200) + '[… 4600 characters omitted …]' + 'B'.repeat(200));
});

test('compact view: reminder and thinking dropped+counted, tool/skill results head+tail, line numbers', () => {
  const skillUse = { type: 'tool_use', id: 'su1', name: 'Skill', input: { skill: 'heartbeat' } };
  const t = trace('claude-code', [
    rec(2, { type: 'assistant', message: { role: 'assistant', content: [
      { type: 'text', text: 'before <system-reminder>injected</system-reminder> after' },
      { type: 'thinking', thinking: 'secret plan' },
      skillUse,
    ] } }),
    rec(3, { type: 'user', message: { role: 'user', content: [
      { type: 'tool_result', tool_use_id: 'tr1', content: 'A'.repeat(5000) },
    ] } }),
    rec(4, { type: 'user', message: { role: 'user', content: [
      { type: 'tool_result', tool_use_id: 'su1', content: 'B'.repeat(10000) },
    ] } }),
  ]);
  const r = renderTrace(t, BUDGETS);
  assert.equal(r.dropped.system_reminder, 1);
  assert.equal(r.dropped.thinking, 1);
  // every rendered line carries its stored line number prefix
  for (const record of r.records) assert.match(record.text, new RegExp(`^${record.line_number}: `));
  const line2 = r.records.find(x => x.line_number === 2)!.text;
  assert.doesNotMatch(line2, /injected/);
  assert.match(line2, /\[system-reminder dropped: 1\]/);
  assert.match(line2, /\[thinking dropped: 1\]/);
  // the dropped blocks' content must not survive anywhere in the rendering
  assert.doesNotMatch(r.body, /injected/);
  assert.doesNotMatch(r.body, /secret plan/);
  // tool_result 5000 under budget 1600 -> 800 + marker(3400) + 800
  const line3 = r.records.find(x => x.line_number === 3)!.text;
  assert.match(line3, /\[… 3400 characters omitted …\]/);
  // skill result (tool_use_id of a Skill block) 10000 under budget 3000 -> 1500 + marker(7000) + 1500
  const line4 = r.records.find(x => x.line_number === 4)!.text;
  assert.match(line4, /\[… 7000 characters omitted …\]/);
});

// Codex preamble strip keeps an in-body close tag; a <-opening message is whole+flagged ---
test('Codex preamble: only the leading wrapper is stripped, in-body close tag survives', () => {
  const body = 'Please review this doc: it contains </INSTRUCTIONS> inside a quote.';
  const stripped = stripCodexPreamble(`<environment_context>env</environment_context>\n${body}`);
  assert.equal(stripped.text.trim(), body);
  assert.equal(stripped.harness_shaped, false);
});

test('a Codex user message opening with < is kept whole and flagged harness-shaped', () => {
  const t = trace('codex', [
    rec(2, { type: 'response_item', payload: { type: 'message', role: 'user', content: [
      { type: 'input_text', text: '<role>senior engineer</role> do the migration and report back' },
    ] } }),
  ]);
  const r = renderTrace(t, BUDGETS);
  const line = r.records[0].text;
  assert.equal(r.records[0].harness_shaped, true);
  assert.match(line, /\[harness-shaped\]/);
  // the whole message is kept, head included — the <role> opener is not cut away
  assert.match(line, /<role>senior engineer<\/role> do the migration and report back/);
});

// --- (chunking portion): boundaries, contiguous ranges, byte-identical reassembly ---
function rendering(records: { line_number: number; text: string }[]): Rendering {
  const recs = records.map(r => ({ ...r, harness_shaped: false }));
  return { body: recs.map(r => r.text).join(''), records: recs, dropped: { system_reminder: 0, thinking: 0, reasoning: 0 }, skills_loaded: [] };
}

test('a long rendering splits at record boundaries, ranges contiguous, reassembly byte-identical', () => {
  const records = Array.from({ length: 400 }, (_, i) => ({ line_number: i + 2, text: `${i + 2}: ${'z'.repeat(230)}\n` }));
  const r = rendering(records);
  assert.ok(r.body.length > 90_000 && r.body.length < 100_000, `body ${r.body.length}`);
  const chunks = chunkRendering('s.v1', r, 40_000);
  assert.equal(chunks.length, 3);
  // each chunk header names the trace id, "chunk k of N", and its line range
  chunks.forEach((c, i) => assert.match(c.header, new RegExp(`^s\\.v1 chunk ${i + 1} of 3 lines \\d+-\\d+`)));
  // no chunk exceeds the size by its body, none is flagged oversized here
  for (const c of chunks) {
    assert.ok(c.body.length <= 40_000);
    assert.equal(c.oversized, false);
    // each chunk begins at a record boundary: its body opens with a stored line-number prefix
    assert.match(c.body, /^\d+: /, 'chunk body starts at a whole record, not a mid-record cut');
  }
  // ranges contiguous and cover every stored line exactly once
  assert.equal(chunks[0].line_range[0], 2);
  assert.equal(chunks[chunks.length - 1].line_range[1], 401);
  for (let i = 1; i < chunks.length; i++) assert.equal(chunks[i].line_range[0], chunks[i - 1].line_range[1] + 1);
  // byte-identical reassembly
  assert.equal(reassembleChunks(chunks), r.body);
});

test('a single record longer than the chunk size is one oversized chunk', () => {
  const r = rendering([{ line_number: 2, text: `2: ${'q'.repeat(50_000)}\n` }]);
  const chunks = chunkRendering('s.v1', r, 40_000);
  assert.equal(chunks.length, 1);
  assert.equal(chunks[0].oversized, true);
  assert.equal(reassembleChunks(chunks), r.body);
});

test('truncate never leaves half of a surrogate pair', () => {
  const text = `${'a'.repeat(9)}👍${'b'.repeat(40)}👀${'c'.repeat(9)}`;
  for (const budget of [18, 19, 20, 21]) {
    assert.equal(truncate(text, budget).isWellFormed(), true, `budget ${budget}`);
  }
});
