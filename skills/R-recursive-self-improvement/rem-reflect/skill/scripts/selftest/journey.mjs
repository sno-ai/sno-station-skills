// Two-day fixture through the real local backend and the recording sno CLI.
// REM_DROP_SPAWN_ENV=1 plants an isolation failure on this test backend instance only.
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { run } from '../rem-reflect.ts';
import { RealBackend } from '../backend.ts';
import { existingTraces } from '../harvest.ts';
import { readLabels } from '../labeler.ts';
import { readPages } from '../pages.ts';
import { readLedger } from '../ledger.ts';
import { hashListing, stationSettings } from '../test-helpers.ts';
import {
  tmp, makeConfig, makeStore, writeInstalledSkill,
  writeClaudeSession, claudeUser, claudeAssistant, writeCodexSession, codexMeta, codexUser, codexAssistant,
} from '../test-helpers.ts';

const BIN = fileURLToPath(new URL('./bin', import.meta.url));
const DAY1 = new Date('2026-09-15T00:00:00Z');
const DAY2 = new Date('2026-09-16T00:00:00Z');
const SRC_MT = new Date('2026-09-14T00:00:00Z').getTime(); // fixture sessions: older than DAY1's quiet window
const SELF_MT = new Date('2026-09-15T06:00:00Z').getTime(); // loop-own turns: between DAY1 and DAY2's quiet window

// A fixture HOME whose .claude/projects and .codex/sessions ARE the harvest roots, so that when the
// isolation env is dropped the shim's fallback ($HOME/.claude, $HOME/.codex) lands in the harvest root.
const home = tmp('home');
const claudeHome = join(home, '.claude'), codexHome = join(home, '.codex');
mkdirSync(claudeHome, { recursive: true }); mkdirSync(codexHome, { recursive: true });
for (const name of ['heartbeat', 'second-skill', 'nested-skill']) {
  writeInstalledSkill(claudeHome, name);
  writeInstalledSkill(codexHome, name);
}
writeFileSync(join(claudeHome, '.credentials.json'), '{"claude":"fixture-token"}');
writeFileSync(join(codexHome, 'auth.json'), '{"codex":"fixture-token"}');
const config = makeConfig({
  claude_home: claudeHome, codex_home: codexHome,
  claude_root: join(claudeHome, 'projects'), codex_root: join(codexHome, 'sessions'),
  project_names: {}, time_zone: 'UTC',
});
const store = makeStore(config);

// three Claude Code sessions and three Codex sessions, all newer than the cursor and older than quiet
for (let i = 0; i < 3; i++) {
  writeClaudeSession(config.claude_root, 'proj', `cc${i}`,
    [claudeUser('/n', `cc${i}`, 'do it'), claudeAssistant('/n', `cc${i}`, [{ type: 'text', text: 'ok' }])], SRC_MT + i);
  writeCodexSession(config.codex_root, `cx${i}`,
    [codexMeta(`cx${i}`, '/n'), codexUser('do it'), codexAssistant('ok')], SRC_MT + i, `2026/09/1${i + 4}`, `2026-09-1${i + 4}T00-00-00`);
}

// the loop spawns the shims: put them first on PATH and pin their session mtime to the test clock
process.env.HOME = home;
process.env.CLAUDE_CONFIG_DIR = claudeHome;
process.env.CODEX_HOME = codexHome;
// When run directly the driver puts its own shim bin on PATH. Under the self-test harness
// PATH is already the allowlist-only bin that holds the shims, so leave it untouched.
if (!process.env.REM_SELFTEST) process.env.PATH = `${BIN}:${process.env.PATH}`;
process.env.REM_SHIM_MTIME = String(SELF_MT);
process.env.REM_SNO_CAPTURE = join(home, 'cloud-requests.jsonl');
mkdirSync(join(home, '.sno'), { recursive: true });
writeFileSync(join(home, '.sno', 'settings.json'), stationSettings('rem-enhanced'));
const backend = () => {
  const live = new RealBackend(30_000, { loopHomeBase: join(store, '.loop-home') });
  if (process.env.REM_DROP_SPAWN_ENV === '1') live.spawnEnv = () => undefined;
  return live;
};

// the fixture real directories must be untouched by the run (only .loop-home receives the copies)
const claudeHomeBefore = hashListing(claudeHome);
const codexHomeBefore = hashListing(codexHome);

// --- day one ---
const r1 = run(store, DAY1, 'u', backend());
assert.equal(r1.code, 0, `day one exits success:\n${r1.lines.join('\n')}`);
assert.equal(readStatus(), 'success', 'day one terminal is success');

const traces = existingTraces(store);
assert.equal(traces.length, 6, `six traces harvested, got ${traces.length}`);
for (const t of traces) {
  for (const f of ['user_id', 'project_id', 'agent_id', 'source_harness', 'originator']) {
    assert.ok(t[f] !== undefined && t[f] !== '', `trace ${t.trace_id} carries ${f}`);
  }
  assert.ok(!('outcome' in t), `trace ${t.trace_id} carries no outcome`);
  const raw = JSON.parse(readFileSync(t.source_path_in_store ?? traceFile(t), 'utf8'));
  assert.ok(!('outcome' in raw), `trace file ${t.trace_id} holds no outcome`);
}
const labels = readLabels(store);
assert.equal(labels.size, 6, `six label files, got ${labels.size}`);
assert.ok([...labels.values()].some(label => label.decision === 'keep' && label.outcome === 'fail'
  && label.reason === 'fixture fail'), 'the own-CLI answer was parsed, not replaced by keep/unknown fallback');
for (const [, label] of labels) {
  assert.equal(label.decision, 'keep', 'the local CLI never affirmatively dropped a fixture session');
  assert.ok(['success', 'fail', 'unknown'].includes(label.outcome), 'a label carries an outcome');
  assert.ok(label.reason, 'a label carries a reason');
  assert.ok(label.model || label.labeled_by, 'a label carries the resolving model or backend');
}
const pages = readPages(store);
assert.equal(pages.length, 6, 'the recorded cloud answer wrote one cited page for every retained session');
assert.ok(pages.every(p => p.class), 'every page carries a class');
assert.deepEqual(new Set(pages.map(p => p.agent_id)), new Set(['codex', 'claude-code']));
assert.ok(existsSync(join(store, 'wiki', 'index.md')), 'the index is written');
const proposals = readLedger(store).filter(x => x.type === 'proposal');
assert.ok(proposals.some(p => p.half === 'claude-code') && proposals.some(p => p.half === 'codex'), 'one proposal per half');

const sent = readFileSync(process.env.REM_SNO_CAPTURE, 'utf8').trim().split('\n').map(line => JSON.parse(line));
assert.equal(sent.length, 1, 'one complete batch crossed the recorded cloud CLI');
assert.equal(sent[0].halves.flatMap(half => half.sessions).length, 6, 'all kept sessions crossed the same consent boundary');
assert.equal(sent[0].catalogue.length, 6, 'each installed skill body from both harness homes was uploaded');
for (const entry of sent[0].catalogue) assert.ok(entry.skill_md.includes(`name: ${entry.name}`), 'complete SKILL.md body was uploaded');
const uploaded = new Map(sent[0].halves.flatMap(half => half.sessions).map(session => [session.trace_id, session]));
for (const page of pages) {
  const cite = page.citations[0];
  const trace = uploaded.get(cite.trace_id);
  assert.ok(trace && trace.chunks.some(chunk => chunk.text.includes(cite.quote)), `page ${page.page_id} cites uploaded text`);
}
assert.ok(existsSync(join(store, 'staging', idOf(DAY1), 'cloud-response.json')), 'the answer is saved for repeatable local application');

const report = readFileSync(join(store, 'staging', idOf(DAY1), 'REPORT.md'), 'utf8');
assert.match(report, /Uploaded: 6/);
assert.match(report, /Pages written: 6/);
assert.match(report, /Pending decisions: 2/);

// the seeded credential copies live under .loop-home; the fixture real dirs are unchanged
assert.equal(readFileSync(join(store, '.loop-home', 'claude', '.credentials.json'), 'utf8'), '{"claude":"fixture-token"}', 'the Claude credential was copied under .loop-home');
assert.equal(readFileSync(join(store, '.loop-home', 'codex', 'auth.json'), 'utf8'), '{"codex":"fixture-token"}', 'the Codex credential was copied under .loop-home');

// the shims wrote their own session files during their turns; under isolation those are under .loop-home
const loopOwn = (root) => existsSync(root) ? findJsonl(root).filter(p => /loopself-/.test(p)) : [];
if (process.env.REM_DROP_SPAWN_ENV !== '1') {
  assert.ok(loopOwn(join(store, '.loop-home', 'claude', 'projects')).length > 0, 'a Claude loop-own session landed under .loop-home');
  assert.ok(loopOwn(join(store, '.loop-home', 'codex', 'sessions')).length > 0, 'a Codex loop-own session landed under .loop-home');
}

// --- day two ---
const r2 = run(store, DAY2, 'u', backend());
const day2New = existingTraces(store).filter(t => /loopself-/.test(t.session_id));
assert.equal(r2.code, 0, `day two succeeded:\n${r2.lines.join('\n')}`);
const day2Log = readFileSync(join(store, 'staging', idOf(DAY2), 'run.log'), 'utf8');
assert.ok(/harvested sessions under store: 0/.test(day2Log), 'day two ran the harvest and recorded the under-store count');
const citingLoop = readPages(store).some(page => page.citations.some(cite => /loopself-/.test(cite.trace_id)));
assert.equal(day2New.length, 0, `day two harvested no loop-own session; got ${day2New.length}, cloud cited it: ${citingLoop}`);
assert.equal(hashListing(claudeHome), claudeHomeBefore, 'the real Claude home stayed unchanged');
assert.equal(hashListing(codexHome), codexHomeBefore, 'the real Codex home stayed unchanged');
console.log('JOURNEY OK isolated');

function readStatus() {
  const s = JSON.parse(readFileSync(join(store, 'state.json'), 'utf8'));
  return s.last_terminal?.status;
}
function idOf(now) {
  const p = new Intl.DateTimeFormat('en-CA', { timeZone: 'UTC', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(now);
  const g = (n) => p.find(x => x.type === n).value;
  return `${g('year')}${g('month')}${g('day')}-${g('hour')}${g('minute')}`;
}
function findJsonl(root) {
  const out = [];
  const walk = (d) => { for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); if (e.isDirectory()) walk(p); else if (e.name.endsWith('.jsonl')) out.push(p); } };
  walk(root);
  return out;
}
function traceFile(t) {
  // raw/<user>/<agent>/<project>/<session>.v<n>.json — find it by session id under raw/
  const hits = findRaw(join(store, 'raw')).filter(p => p.includes(t.session_id) && p.endsWith('.json') && !p.endsWith('.label.json'));
  return hits[0];
}
function findRaw(root) {
  if (!existsSync(root)) return [];
  const out = [];
  const walk = (d) => { for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); if (e.isDirectory()) walk(p); else out.push(p); } };
  walk(root);
  return out;
}
