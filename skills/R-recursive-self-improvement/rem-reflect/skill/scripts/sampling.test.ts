import { test } from 'node:test';
import assert from 'node:assert/strict';
import { eligibleTraces } from './sampling.ts';
import type { Trace } from './harvest.ts';
import type { Harness } from './identity.ts';

const DAY = 86_400_000;
const NOW = Date.parse('2026-09-21T12:00:00Z');

function trace(half: Harness, session: string, version: number, ageDays: number, trivial = false): Trace {
  return {
    user_id: 'u', project_id: 'p', agent_id: half, source_harness: half, originator: half,
    trace_id: `${session}.v${version}`, session_id: session, version,
    source_path: `/x/${session}`, source_line_range: [1, 2], source_mtime: NOW - ageDays * DAY,
    records: [], skipped_records: 0, skipped_blocks: 0, redactions: 0,
    trivial, skills_loaded: [],
  };
}

test('the local pool retains every newest recent version, including trivial sessions, without a sample limit', () => {
  const older = trace('codex', 'resumed', 1, 2);
  const latest = trace('codex', 'resumed', 2, 1);
  const many = Array.from({ length: 12 }, (_, index) => trace('codex', `codex-${index}`, 1, 1, true));
  const claude = trace('claude-code', 'claude', 1, 0.5);
  const pool = eligibleTraces([older, latest, ...many, claude], NOW);

  assert.deepEqual(pool.halves.codex.map(row => row.trace_id), [latest.trace_id, ...many.map(row => row.trace_id)]);
  assert.deepEqual(pool.halves['claude-code'].map(row => row.trace_id), [claude.trace_id]);
  assert.deepEqual(pool.superseded.map(row => row.trace_id), [older.trace_id]);
  assert.deepEqual(pool.expired, []);
});

test('an expired newest version closes the session; an exactly three-day-old trace is expired', () => {
  const old = trace('codex', 'expired', 2, 3);
  const prior = trace('codex', 'expired', 1, 4);
  const recent = trace('claude-code', 'recent', 1, 2.99);
  const pool = eligibleTraces([prior, recent, old], NOW);

  assert.deepEqual(pool.halves.codex, []);
  assert.deepEqual(pool.halves['claude-code'].map(row => row.trace_id), [recent.trace_id]);
  assert.deepEqual(pool.expired.map(row => row.trace_id), [old.trace_id]);
  assert.deepEqual(pool.superseded.map(row => row.trace_id), [prior.trace_id]);
});
