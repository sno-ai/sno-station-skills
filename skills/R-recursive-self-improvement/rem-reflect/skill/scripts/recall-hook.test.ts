import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { chmodSync, copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { git } from './store.ts';
import { appendRows } from './lessons.ts';
import { tmp, fixtureCheckout, fixtureConfig, makeStore } from './test-helpers.ts';

// the printed SessionStart hook entries, merged into an isolated harness config, make
// a REAL `claude -p` / `codex exec` run the recall index command at session start — proven by the
// recorded `shown` line (session id matching the run's own transcript) and by the recall heading being
// injected into that transcript. This spends subscription quota; models are chosen small via env.
//
// It is skipped unless REM_E2E=1 is set, so the ordinary unit run never spends quota.

const RUN = process.env.REM_E2E === '1';
const SCRIPTS = dirname(fileURLToPath(import.meta.url));
const REMREFLECT = join(SCRIPTS, 'rem-reflect.ts');
const HEADING = "Lessons from this machine's own sessions";
// The hook fires at session start regardless of the prompt, and the proof is the recorded shown line
// plus the heading in the session transcript (not the model's free-text answer, which is not reliably
// the recall heading — a real headless session injects its own `#` context headings too). So the
// prompt is a cheap no-op that only opens a session.
const PROMPT = 'ok';
function hasHeading(text: string): boolean { return text.includes(HEADING); }
function anyTranscriptHasHeading(homeDir: string, sub: string): boolean {
  const root = join(homeDir, sub);
  let found = false;
  const walk = (d: string): void => { if (!existsSync(d)) return; for (const e of readdirSync(d, { withFileTypes: true })) { const q = join(d, e.name); if (e.isDirectory()) walk(q); else if (e.name.endsWith('.jsonl') && hasHeading(readFileSync(q, 'utf8'))) found = true; } };
  walk(root);
  return found;
}
const CLAUDE_MODEL = process.env.REM_E2E_CLAUDE_MODEL ?? '';
const CODEX_MODEL = process.env.REM_E2E_CODEX_MODEL ?? '';

// One accepted, general-scoped lesson, seeded and committed so recall reads it at HEAD (recall.test.ts).
function lessonRow(id: string): Record<string, unknown> {
  return { lesson_id: id, page_id: `pg-${id}`, status: 'accepted', count: 1, helped: 0, harmful: 0, measured: false,
    created_run: '20260901-0000', project_id: 'p', agent_id: 'codex', user_id: 'u', skill_target: null, applies_to: 'general',
    advice: `advice ${id}`, because: `because ${id}`, situation: { task_type: 'w', trigger: `trigger ${id}`, tools: [] },
    scenario: { task_type: 'w', trigger: 't', tools: [] }, polarity: 'from_failure',
    evidence: [{ trace_id: 't.v1', line_start: 2, line_end: 2, quote: 'q' }], counter_examples: 'not searched', listed: true };
}
function seedStore(): { store: string; checkout: string } {
  const checkout = fixtureCheckout();
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = makeStore(config);
  appendRows(join(store, 'wiki/lessons.jsonl'), [lessonRow('L-e2e')]);
  git(store, ['add', '--all']);
  git(store, ['commit', '--quiet', '-m', 'seed']);
  return { store, checkout };
}

// A `sno` executable whose `rem-reflect` subcommand runs the source against the given store; the hook command resolves
// to it through PATH, exactly as a deployed `sno rem-reflect` would (deployment is out of scope).
function remReflectShim(store: string, name = 'sno'): string {
  const dir = tmp('shimbin');
  const p = join(dir, name);
  writeFileSync(p, ['#!/usr/bin/env bash',
    'shift', `exec env REM_REFLECT_STORE=${JSON.stringify(store)} node --experimental-strip-types ${JSON.stringify(REMREFLECT)} "$@"`,
  ].join('\n') + '\n');
  chmodSync(p, 0o755);
  return dir;
}

function shownLines(store: string): Record<string, unknown>[] {
  const p = join(store, 'ledger', 'usage.jsonl');
  if (!existsSync(p)) return [];
  return readFileSync(p, 'utf8').split('\n').filter(Boolean).map(l => JSON.parse(l)).filter(r => r.type === 'shown');
}
// The session id claude/codex recorded in its own transcript file under the isolated home.
function transcriptSessionId(homeDir: string, sub: string): string | undefined {
  const root = join(homeDir, sub);
  const found: string[] = [];
  const walk = (d: string): void => { if (!existsSync(d)) return; for (const e of readdirSync(d, { withFileTypes: true })) { const q = join(d, e.name); if (e.isDirectory()) walk(q); else if (e.name.endsWith('.jsonl')) found.push(q); } };
  walk(root);
  if (!found.length) return undefined;
  // claude: file stem is the session id. codex rollout: id is the trailing uuid of the filename.
  const f = basename(found[0]).replace(/\.jsonl$/, '');
  const codex = /^rollout-.*-([0-9a-f-]{36})$/.exec(f);
  return codex ? codex[1] : f;
}

test('install-hooks prints SessionStart and first-message entries without writing harness files', () => {
  const out = execFileSync(process.execPath, ['--experimental-strip-types', REMREFLECT, 'install-hooks', '--print'], { encoding: 'utf8' });
  assert.match(out, /~\/\.claude\/settings\.json/);
  assert.match(out, /~\/\.codex\/hooks\.json/);
  assert.match(out, /"command": "sno rem-reflect recall --agent claude-code"/, 'the Claude entry runs recall with the agent kind');
  assert.match(out, /"command": "sno rem-reflect recall --agent codex"/, 'the Codex entry runs recall with the agent kind (the nested command shape codex runs)');
  assert.match(out, /"command": "sno rem-reflect recall --agent claude-code --first-message"/);
  assert.match(out, /"command": "sno rem-reflect recall --agent codex --first-message"/);
  assert.doesNotMatch(out, /"SessionEnd"|"PreToolUse"/);
  // the program contains no write to settings.json or hooks.json (it only prints them)
  for (const f of readdirSync(SCRIPTS).filter(n => n.endsWith('.ts') && !n.endsWith('.test.ts') && n !== 'test-helpers.ts')) {
    const src = readFileSync(join(SCRIPTS, f), 'utf8');
    assert.ok(!/writeFileSync\([^)]*settings\.json|writeFileSync\([^)]*hooks\.json|atomicWrite\([^)]*settings\.json|atomicWrite\([^)]*hooks\.json/.test(src),
      `${f} must not write settings.json or hooks.json`);
  }
});

test('a real claude -p session runs the recall hook at session start (shown line + heading in transcript)', { skip: RUN ? false : 'set REM_E2E=1 to spend quota' }, () => {
  assert.ok(CLAUDE_MODEL, 'set REM_E2E_CLAUDE_MODEL to the claude model to use');
  const { store, checkout } = seedStore();
  const shimDir = remReflectShim(store);
  const iso = tmp('claude-cfg');
  mkdirSync(iso, { recursive: true });
  const cred = join(homedir(), '.claude', '.credentials.json');
  assert.ok(existsSync(cred), 'the real Claude credential is present to seed the isolated home');
  copyFileSync(cred, join(iso, '.credentials.json'));
  chmodSync(join(iso, '.credentials.json'), 0o600);
  writeFileSync(join(iso, 'settings.json'), JSON.stringify({ hooks: { SessionStart: [{ hooks: [{ type: 'command', command: 'sno rem-reflect recall --agent claude-code' }] }] } }));

  const env = { ...process.env, CLAUDE_CONFIG_DIR: iso, PATH: `${shimDir}:${process.env.PATH}` };
  execFileSync('claude', ['-p', PROMPT, '--model', CLAUDE_MODEL], { cwd: checkout, env, encoding: 'utf8', timeout: 180_000, stdio: ['ignore', 'pipe', 'pipe'] });

  // the hook ran recall at session start: it recorded one shown line and its output was injected into
  // the session (the recall heading is in the session transcript).
  const shown = shownLines(store);
  assert.equal(shown.length, 1, 'exactly one shown line was recorded by the hook');
  assert.deepEqual(shown[0].lesson_ids, ['L-e2e'], 'the shown line names the in-scope lesson');
  const sid = transcriptSessionId(iso, 'projects');
  assert.ok(sid && shown[0].session_id === sid, `the shown session_id equals the transcript session id (${String(shown[0].session_id)} vs ${String(sid)})`);
  assert.ok(anyTranscriptHasHeading(iso, 'projects'), 'the recall heading was injected into the claude session transcript');
});

test('a real codex exec runs the recall hook only with hook trust; no trust and a missing binary add no shown line', { skip: RUN ? false : 'set REM_E2E=1 to spend quota' }, () => {
  assert.ok(CODEX_MODEL, 'set REM_E2E_CODEX_MODEL to the codex model to use');
  const { store, checkout } = seedStore();
  const shimDir = remReflectShim(store);
  const iso = tmp('codex-home');
  mkdirSync(iso, { recursive: true });
  const auth = join(homedir(), '.codex', 'auth.json');
  assert.ok(existsSync(auth), 'the real Codex auth is present to seed the isolated home');
  copyFileSync(auth, join(iso, 'auth.json'));
  chmodSync(join(iso, 'auth.json'), 0o600);
  writeFileSync(join(iso, 'hooks.json'), JSON.stringify({ hooks: { SessionStart: [{ hooks: [{ type: 'command', command: 'sno rem-reflect recall --agent codex' }] }] } }));

  const env = { ...process.env, CODEX_HOME: iso, PATH: `${shimDir}:${process.env.PATH}` };
  // The isolated home has no config.toml, so the explicit flag selects the sandbox mode.
  // Hook trust is bypassed to stand in for one-time interactive approval.
  const trust = ['exec', '--skip-git-repo-check', '--sandbox', 'danger-full-access', '--dangerously-bypass-hook-trust', '--model', CODEX_MODEL, PROMPT];
  const noflag = ['exec', '--skip-git-repo-check', '--sandbox', 'danger-full-access', '--model', CODEX_MODEL, PROMPT];
  const runCodex = (args: string[]): void => {
    try { execFileSync('codex', args, { cwd: checkout, env, encoding: 'utf8', timeout: 180_000, stdio: ['ignore', 'pipe', 'pipe'] }); }
    catch { /* the answer text is not the oracle; the shown line and transcript are */ }
  };

  // with hook trust, the hook fires: one shown line is added and the heading is injected into the run's
  // own transcript.
  runCodex(trust);
  const afterTrust = shownLines(store);
  assert.equal(afterTrust.length, 1, 'codex with hook trust recorded exactly one shown line');
  assert.deepEqual(afterTrust[0].lesson_ids, ['L-e2e'], 'the shown line names the in-scope lesson');
  const sid = transcriptSessionId(iso, 'sessions');
  assert.ok(sid && afterTrust.some(s => s.session_id === sid), 'a shown line carries the codex transcript session id');
  assert.ok(anyTranscriptHasHeading(iso, 'sessions'), 'the recall heading was injected into the codex session transcript');

  // without the trust flag and with no trust entry, the hook does not fire: no new shown line.
  runCodex(noflag);
  assert.equal(shownLines(store).length, 1, 'without hook trust the hook does not fire, so no new shown line is added');

  // planted defect: point the hook command at a missing binary -> the hook cannot run -> no new shown line.
  writeFileSync(join(iso, 'hooks.json'), JSON.stringify({ hooks: { SessionStart: [{ hooks: [{ type: 'command', command: 'sno-does-not-exist rem-reflect recall --agent codex' }] }] } }));
  runCodex(trust);
  assert.equal(shownLines(store).length, 1, 'a missing hook binary cannot run recall, so no new shown line is added (planted defect)');
});
