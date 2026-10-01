import { test } from 'node:test';
import assert from 'node:assert/strict';
import { patchBody, renderIndex, serializePage, parsePage } from './pages.ts';
import type { Page } from './pages.ts';
import type { Trace } from './harvest.ts';

function page(over: Partial<Page>): Page {
  const base = { page_id: 'p1', summary: 's', class: 'EXECUTION_LAPSE', root_cause: { fact: 'f' } as Page['root_cause'],
    fix: 'x', body: 'body', count: 2, task_ids: ['a', 'b'], last_seen: '2026-09-01T00:00:00.000Z',
    skills_observed: [], skills_used: [], citations: [] };
  // only attach solved_by when a test asks for it; an undefined own field is not valid frontmatter
  const merged: Record<string, unknown> = { ...base, ...over };
  if (merged.solved_by === undefined) delete merged.solved_by;
  return merged as unknown as Page;
}
function trace(id: string, skills: string[]): Trace {
  return { user_id: 'u', project_id: 'p', agent_id: 'codex', source_harness: 'codex', originator: 'codex',
    trace_id: `${id}.v1`, session_id: id, version: 1, source_path: '/x', source_line_range: [1, 2], source_mtime: 1,
    records: [], skipped_records: 0, skipped_blocks: 0, redactions: 0, trivial: false, skills_loaded: skills };
}

// patch ops apply by exact substring; a new page is append-only ---
test('patchBody appends, replaces, and inserts_after by exact substring', () => {
  assert.equal(patchBody('', [{ op: 'append', text: 'hello world' }], true), 'hello world');
  assert.equal(patchBody('hello world', [{ op: 'replace', target: 'world', text: 'there' }]), 'hello there');
  assert.equal(patchBody('a c', [{ op: 'insert_after', target: 'a', text: 'b' }]), 'ab c');
});

test('a patch whose target is not a substring is refused', () => {
  assert.throws(() => patchBody('hello', [{ op: 'replace', target: 'absent', text: 'x' }]), /.*/);
});

test('a new page is append-only: replace is refused even when the text it targets was just appended', () => {
  // isolates the new-page rule: the target IS present after the append, so only the isNew guard rejects it
  assert.throws(() => patchBody('', [{ op: 'append', text: 'hello' }, { op: 'replace', target: 'hello', text: 'bye' }], true),
    /.*/, 'a create may not replace, only append');
});

test('a page round-trips through serialize/parse and keeps every field', () => {
  const p = page({ body: 'the body text', fix: 'release the lock', task_ids: ['s1', 's2'], count: 2 });
  const back = parsePage(serializePage(p));
  assert.equal(back.page_id, 'p1');
  assert.equal(back.body, 'the body text');
  assert.equal(back.root_cause.fact, 'f');
  assert.equal(back.fix, 'release the lock', 'fix survives the round-trip');
  assert.deepEqual(back.task_ids, ['s1', 's2'], 'task_ids survive the round-trip');
  assert.equal(back.count, 2);
});

// the index has one line per page file with the fixed fields and top loaded skills ---
test('renderIndex writes one line per page with id, summary, count, last_seen, solved_by/unsolved, skills', () => {
  const p1 = page({ page_id: 'pg-1', summary: 'disk full', count: 2, solved_by: 'heartbeat', last_seen: '2026-09-05T12:00:00.000Z',
    citations: [{ trace_id: 't1.v1', line_start: 2, line_end: 2, quote: 'x' }] as Page['citations'] });
  const p2 = page({ page_id: 'pg-2', summary: 'lock held', count: 3, solved_by: undefined, citations: [] });
  const traces = [trace('t1', ['skills/heartbeat/skill', 'skills/second-skill/skill'])];
  const out = renderIndex([p1, p2], traces);
  const lines = out.trimEnd().split('\n');
  assert.equal(lines.length, 2, 'one line per page');
  // the exact last_seen value and the COMPLETE skill list, not just a prefix
  assert.equal(lines[0], 'pg-1 | disk full | count 2 | last_seen 2026-09-05T12:00:00.000Z | solved_by heartbeat | skills_loaded skills/heartbeat/skill, skills/second-skill/skill');
  assert.equal(lines[1], 'pg-2 | lock held | count 3 | last_seen 2026-09-01T00:00:00.000Z | unsolved | skills_loaded none');
});

test('the index is rendered from the page files, so three pages give three lines even if a run names fewer', () => {
  const pages = [page({ page_id: 'a' }), page({ page_id: 'b' }), page({ page_id: 'c' })];
  assert.equal(renderIndex(pages, []).trimEnd().split('\n').length, 3);
});
