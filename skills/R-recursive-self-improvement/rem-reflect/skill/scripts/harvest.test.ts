import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, closeSync, existsSync, ftruncateSync, mkdirSync, openSync, readFileSync, readdirSync, utimesSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, resolve } from 'node:path';
import { redact, verdictLine, isTrivial, skillsLoaded, harvest } from './harvest.ts';
import type { StoredRecord } from './harvest.ts';
import { readCatalogue } from './catalogue.ts';
import { loadRenderBudgets, renderTrace } from './render.ts';
import { chunkRendering, reassembleChunks } from './chunk.ts';
import { emptyState, parseState } from './store.ts';
import {
  DAY, tmp, fixtureCheckout, fixtureConfig, fixtureHarnessHomes, writeClaudeSession, writeCodexSession,
  claudeUser, claudeAssistant, codexMeta, codexUser, codexAssistant,
} from './test-helpers.ts';

function rec(line: number, record: Record<string, unknown>): StoredRecord {
  return { line_number: line, source_line: line, record };
}
function labelFiles(store: string): string[] {
  const out: string[] = [];
  const walk = (d: string) => { for (const e of readdirSync(d, { withFileTypes: true })) {
    const p = join(d, e.name); if (e.isDirectory()) walk(p); else if (e.name.endsWith('.label.json')) out.push(p); } };
  const raw = join(store, 'raw'); if (existsSync(raw)) walk(raw);
  return out;
}

// Redaction removes the three secret shapes and counts them.
test('redact strips sk-, bearer, and a private-key block, counting three', () => {
  const secret = [
    'key sk-ABCDEF0123456789abcdef',
    'Authorization: Bearer abc.def-ghi_jkl',
    '-----BEGIN PRIVATE KEY-----\nMIIEvQIBADAN\n-----END PRIVATE KEY-----',
  ].join('\n');
  const { text, count } = redact(secret);
  assert.equal(count, 3);
  assert.doesNotMatch(text, /sk-ABCDEF/);
  assert.doesNotMatch(text, /Bearer abc/);
  assert.doesNotMatch(text, /MIIEvQIBADAN/);
});

test('a harvested trace carries redactions:3 and the written file holds none of the secrets', () => {
  const config = fixtureConfig({ claude_root: tmp('croot'), codex_root: tmp('xroot') });
  const store = tmp('store');
  const now = new Date('2026-09-02T00:00:00Z');
  const body = 'sk-ABCDEF0123456789abcdef and Bearer zzz.yyy_www and\n-----BEGIN PRIVATE KEY-----\nMIIEvQIBADAN\n-----END PRIVATE KEY-----';
  writeClaudeSession(config.claude_root, 'slug', 'sess-redact', [
    claudeUser('/nowhere', 'sess-redact', body),
    claudeAssistant('/nowhere', 'sess-redact', [{ type: 'text', text: 'ok' }]),
  ], now.getTime() - DAY);
  const { traces } = harvest(store, config, emptyState(), 'u', now);
  assert.equal(traces.length, 1);
  assert.equal(traces[0].redactions, 3);
  const raw = readFileSync(traces[0].source_path ? join(store, 'raw', 'u', 'user-level', 'claude-code', 'sess-redact.v1.json') : '', 'utf8');
  assert.doesNotMatch(raw, /sk-ABCDEF/);
  assert.doesNotMatch(raw, /Bearer zzz/);
  assert.doesNotMatch(raw, /MIIEvQIBADAN/);
});

// A session file beyond Node's maximum string length must be skipped and named so harvest continues.
test('a session file over the readable string limit is skipped and named, and the harvest still completes', () => {
  const config = fixtureConfig({ claude_root: tmp('croot'), codex_root: tmp('xroot') });
  const store = tmp('store');
  const now = new Date('2026-09-02T00:00:00Z');
  const mt = now.getTime() - DAY;
  // a normal small session that must still be harvested
  writeClaudeSession(config.claude_root, 'small', 'sess-small', [
    claudeUser('/nowhere', 'sess-small', 'do it'),
    claudeAssistant('/nowhere', 'sess-small', [{ type: 'text', text: 'ok' }]),
  ], mt);
  // a pathological oversized session, sparse so it reports a huge size but costs ~no disk; reading it
  // as a string would throw "Cannot create a string longer than 0x1fffffe8 characters".
  const bigDir = join(config.claude_root, 'huge');
  mkdirSync(bigDir, { recursive: true });
  const big = join(bigDir, 'huge.jsonl');
  const fd = openSync(big, 'w');
  try { ftruncateSync(fd, 0x1fffffe8 + 1); } finally { closeSync(fd); }
  utimesSync(big, mt / 1000, mt / 1000);

  const state = emptyState();
  const { traces, log } = harvest(store, config, state, 'u', now);
  assert.ok(log.some(l => /oversized: .*huge\.jsonl is \d+ bytes; skipped/.test(l)), `the oversized file is logged and skipped: ${log.join(' | ')}`);
  assert.ok(traces.some(t => t.session_id === 'sess-small'), 'the small session was still harvested despite the oversized sibling');
  // The state this harvest leaves behind is what the next run reads back through the validator
  // (state.json requires failures >= 1): an oversized skip must not poison every later run.
  const reloaded = parseState(JSON.stringify(state));
  assert.equal(reloaded.pending[big]?.status, 'unparseable', 'the oversized file is recorded as unparseable');
  assert.ok(reloaded.pending[big].failures >= 1, 'its failures count satisfies the state validator');
});

// An already-harvested session whose mtime is unchanged is skipped without
//     re-reading, so the whole multi-day window is not re-parsed every run. ---
test('an already-harvested session with an unchanged mtime is not re-read on the next harvest', { skip: process.getuid?.() === 0 ? 'root reads despite chmod 000' : false }, () => {
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = tmp('store');
  const state = emptyState();
  const now = new Date('2026-09-02T00:00:00Z');
  const p = writeClaudeSession(config.claude_root, 'proj', 'sess-x', [
    claudeUser('/n', 'sess-x', 'do it'), claudeAssistant('/n', 'sess-x', [{ type: 'text', text: 'ok' }]),
  ], now.getTime() - DAY);
  assert.equal(harvest(store, config, state, 'u', now).traces.length, 1, 'first harvest reads and stores the session');
  // Make the file unreadable but keep its mtime: a re-read would throw EACCES; the mtime-skip never touches it.
  chmodSync(p, 0o000);
  try {
    const second = harvest(store, config, state, 'u', new Date('2026-09-02T01:00:00Z'));
    assert.equal(second.traces.length, 0, 'the unchanged session is skipped, not re-read (no EACCES)');
  } finally { chmodSync(p, 0o600); }
});

// Verdict line is stored without an outcome or label file.
test('a codex_exec verdict line is recorded with its line number and no outcome/label', () => {
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = tmp('store');
  const now = new Date('2026-09-02T00:00:00Z');
  writeCodexSession(config.codex_root, 'sess-verdict', [
    codexMeta('sess-verdict', '/nowhere', { originator: 'codex_exec' }),
    codexUser('do the task'),
    codexAssistant('work done.\nVerdict: failed'),
  ], now.getTime() - DAY);
  const { traces } = harvest(store, config, emptyState(), 'u', now);
  assert.equal(traces.length, 1);
  const t = traces[0];
  assert.ok(t.verdict_line, 'verdict_line present');
  assert.match(t.verdict_line!.text, /Verdict: failed/);
  assert.ok(t.verdict_line!.line_number >= 2);
  assert.equal((t as unknown as Record<string, unknown>).outcome, undefined);
  assert.equal((t as unknown as Record<string, unknown>).label, undefined);
  assert.equal(labelFiles(store).length, 0, 'harvest writes no label file');
});

test('harvest retains executed Codex steps and turn aborts but skips unrelated events', () => {
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = tmp('store');
  const now = new Date('2026-09-02T00:00:00Z');
  writeCodexSession(config.codex_root, 'steps', [
    codexMeta('steps', '/nowhere'),
    { type: 'event_msg', payload: { type: 'token_count', total: 200 } },
    { type: 'event_msg', payload: { type: 'item_completed', item: { type: 'CommandExecution', id: 'exec-1',
      status: 'failed', exit_code: 1 } } },
    { type: 'event_msg', payload: { type: 'turn_aborted', turn_id: 'turn-1', reason: 'interrupted' } },
  ], now.getTime() - DAY);
  const { traces } = harvest(store, config, emptyState(), 'u', now);
  assert.equal(traces.length, 1);
  assert.deepEqual(traces[0].records.filter(row => row.record.type === 'event_msg').map(row =>
    (row.record.payload as Record<string, unknown>).type), ['item_completed', 'turn_aborted']);
  assert.equal(traces[0].skipped_records, 1);
});

test('trivial is two-or-fewer assistant turns AND no tool call', () => {
  const oneTurn = [
    rec(2, { type: 'user', message: { role: 'user', content: 'hi' } }),
    rec(3, { type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: 'hello' }] } }),
  ];
  assert.equal(isTrivial(oneTurn, 'claude-code'), true);
  // three assistant turns and no tool call -> not trivial (the turn ceiling is load-bearing)
  const threeTurns = [
    rec(2, { type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: 'a' }] } }),
    rec(3, { type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: 'b' }] } }),
    rec(4, { type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: 'c' }] } }),
  ];
  assert.equal(isTrivial(threeTurns, 'claude-code'), false);
  // two turns but a tool call -> not trivial (the no-tool-call condition is load-bearing)
  const withTool = [...oneTurn, rec(4, { type: 'assistant', message: { role: 'assistant', content: [{ type: 'tool_use', name: 'Skill', input: {} }] } })];
  assert.equal(isTrivial(withTool, 'claude-code'), false);
});

test('verdictLine reads only the codex assistant message, even when a later user line also matches', () => {
  // Assistant verdict first, a matching user line LAST: without the role filter the last (user) match
  // would win at line 3; the assistant-only rule must return line 2.
  const recs = [
    rec(2, { type: 'response_item', payload: { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Verdict: done' }] } }),
    rec(3, { type: 'response_item', payload: { type: 'message', role: 'user', content: [{ type: 'input_text', text: 'is the Verdict: done rule right?' }] } }),
  ];
  const v = verdictLine(recs, '\\b[Vv]erdict\\s*[:]\\s*(done|failed)\\b');
  assert.ok(v);
  assert.equal(v!.line_number, 2, 'only the assistant message is read');
});

test('no repeated-prompt rule or exclusion list in the harvest, and signals.json is one regex', () => {
  const source = readFileSync(join(import.meta.dirname, 'harvest.ts'), 'utf8');
  // no exclusion list and no repeated-prompt comparison heuristic in the harvest
  assert.doesNotMatch(source, /exclusion/i, 'no exclusion list');
  assert.doesNotMatch(source, /previousPrompt|lastPrompt|repeatedPrompt|sameAsPrevious/i, 'no repeated-prompt rule');
  const signals = JSON.parse(readFileSync(join(import.meta.dirname, '..', 'references', 'signals.json'), 'utf8'));
  assert.deepEqual(Object.keys(signals), ['codex_exec_verdict']);
  assert.doesNotThrow(() => new RegExp(signals.codex_exec_verdict));
});

// skills_loaded resolved through the catalogue, deduped, in first-use order ---
test('skills_loaded dedups and resolves Claude Skill calls and a Codex <skill> block', () => {
  const { claudeHome, codexHome } = fixtureHarnessHomes();
  const catalogue = readCatalogue([join(claudeHome, 'skills'), join(codexHome, 'skills')]);
  const claude = ['heartbeat', 'second-skill', 'heartbeat'].map((skill, i) =>
    rec(i + 2, { type: 'assistant', message: { role: 'assistant', content: [{ type: 'tool_use', name: 'Skill', input: { skill } }] } }));
  assert.deepEqual(skillsLoaded(claude, 'claude-code', catalogue), [join(claudeHome, 'skills/heartbeat'), join(claudeHome, 'skills/second-skill')]);
  // first-use order, not alphabetical: second-skill is used before heartbeat here
  const reversed = ['second-skill', 'heartbeat'].map((skill, i) =>
    rec(i + 2, { type: 'assistant', message: { role: 'assistant', content: [{ type: 'tool_use', name: 'Skill', input: { skill } }] } }));
  assert.deepEqual(skillsLoaded(reversed, 'claude-code', catalogue), [join(claudeHome, 'skills/second-skill'), join(claudeHome, 'skills/heartbeat')]);
  const codex = [rec(2, { type: 'response_item', payload: { type: 'message', role: 'user', content: [{ type: 'input_text', text: '<skill>\n<name>nested-skill</name>\n</skill>' }] } })];
  assert.deepEqual(skillsLoaded(codex, 'codex', catalogue), [join(claudeHome, 'skills/nested-skill')]);
  const unknown = [rec(2, { type: 'response_item', payload: { type: 'message', role: 'user', content: [{ type: 'input_text', text: '<skill><name>no-such-skill</name></skill>' }] } })];
  assert.deepEqual(skillsLoaded(unknown, 'codex', catalogue), ['unresolved:no-such-skill']);
});

// A citation: a cited stored-line range maps to the same text before and after
//     the compact rendering and its 40,000-character chunking ---
test('a citation of v1 lines 3-5 resolves to the same text through rendering and the 40k chunk cut', () => {
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = tmp('store');
  const now = new Date('2026-09-02T00:00:00Z');
  // Lines 3-5 are the citation target; a later very long turn pushes the rendering past 40k so the
  // cut is real, not hypothetical. Assistant text blocks print whole (no truncation), so one long
  // block makes a large rendering without changing the cited lines.
  writeClaudeSession(config.claude_root, 'slug', 'cite', [
    claudeUser('/n', 'cite', 'one'),
    claudeAssistant('/n', 'cite', [{ type: 'text', text: 'alpha' }]),   // stored line 3
    claudeUser('/n', 'cite', 'two'),                                     // stored line 4
    claudeAssistant('/n', 'cite', [{ type: 'text', text: 'beta' }]),     // stored line 5
    claudeAssistant('/n', 'cite', [{ type: 'text', text: 'Z'.repeat(60_000) }]),
    claudeUser('/n', 'cite', 'three'),
  ], now.getTime() - DAY);
  const { traces } = harvest(store, config, emptyState(), 'u', now);
  const t = traces[0];
  const rendering = renderTrace(t, loadRenderBudgets());
  assert.ok(rendering.body.length > 40_000, 'rendering is large enough to chunk');
  // The stored line numbers are the citation addresses; each record carries its own.
  const cited = rendering.records.filter(r => r.line_number >= 3 && r.line_number <= 5);
  assert.equal(cited.length, 3, 'lines 3-5 each resolve to one rendered record');
  const citedText = cited.map(r => r.text).join('');
  const chunks = chunkRendering(t.trace_id, rendering, 40_000);
  assert.ok(chunks.length > 1, 'the trace actually splits into more than one chunk');
  // Reassembling the chunks reproduces the same bytes, so the cited text is unchanged by the cut.
  const reassembled = reassembleChunks(chunks);
  assert.equal(reassembled, rendering.body);
  assert.ok(reassembled.includes(citedText), 'cited lines 3-5 survive the rendering and the 40k cut verbatim');
  // lines 3-5 sit together in the first chunk (before the oversized turn), addressable by number
  assert.ok(chunks[0].body.includes(citedText), 'the cited range resolves within its chunk');
  assert.match(cited[0].text, /^3: assistant .*alpha/);
  assert.match(cited[2].text, /^5: assistant .*beta/);
});

// Harvest: project_id from the session's git remote, else user-level ---
test('harvested traces carry project_id from the remote and a working-directory id without one', () => {
  const repo = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = tmp('store');
  const now = new Date('2026-09-02T00:00:00Z');
  // Claude session whose cwd is the fixture checkout (has the remote).
  writeClaudeSession(config.claude_root, 'slug', 'sess-remote', [
    claudeUser(repo, 'sess-remote', 'work'), claudeAssistant(repo, 'sess-remote', [{ type: 'text', text: 'ok' }]),
  ], now.getTime() - DAY);
  // Codex session carrying the same repository_url in session_meta.
  writeCodexSession(config.codex_root, 'sess-codex', [
    codexMeta('sess-codex', repo), codexUser('work'), codexAssistant('ok'),
  ], now.getTime() - DAY);
  // Claude session whose cwd has no remote and no configured name.
  const plain = tmp('plain');
  writeClaudeSession(config.claude_root, 'slug2', 'sess-plain', [
    claudeUser(plain, 'sess-plain', 'work'), claudeAssistant(plain, 'sess-plain', [{ type: 'text', text: 'ok' }]),
  ], now.getTime() - DAY);
  const { traces } = harvest(store, config, emptyState(), 'u', now);
  const byId = Object.fromEntries(traces.map(t => [t.session_id, t.project_id]));
  assert.equal(byId['sess-remote'], 'github.com/example/project');
  assert.equal(byId['sess-codex'], 'github.com/example/project');
  assert.equal(byId['sess-plain'], `dir:${createHash('sha256').update(resolve(plain)).digest('hex').slice(0, 16)}`);
});
