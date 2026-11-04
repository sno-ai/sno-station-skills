import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { chmodSync, copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { git } from './store.ts';
import { appendRows } from './lessons.ts';
import { tmp, fixtureCheckout, fixtureConfig, makeStore, writeStationSettings } from './test-helpers.ts';

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

test('install-hooks run through sno prints the absolute sno path, because a hook PATH often lacks ~/.local/bin', () => {
  const out = execFileSync(process.execPath, ['--experimental-strip-types', REMREFLECT, 'install-hooks', '--print'],
    { encoding: 'utf8', env: { ...process.env, SNO_EXECUTABLE: "/srv/o'neil/.local/bin/sno" } });
  const quoted = "'/srv/o'\\\\''neil/.local/bin/sno'";
  for (const agent of ['claude-code', 'codex']) {
    assert.ok(out.includes(`"command": "${quoted} rem-reflect recall --agent ${agent}"`), `${agent} session start uses the absolute path`);
    assert.ok(out.includes(`"command": "${quoted} rem-reflect recall --agent ${agent} --first-message"`), `${agent} first message uses the absolute path`);
  }
});

// These cases exercise an actual task after ordinary approval. The draft is produced by
// the real cloud-writer check, rather than supplied as a model answer by this harness.
function experienceFixture(): { store: string; checkout: string; lesson: Record<string, unknown> } {
  const draftPath = process.env.REM_EXPERIENCE_DRAFT;
  assert.ok(draftPath && existsSync(draftPath), 'REM_EXPERIENCE_DRAFT names the real cloud draft');
  const draft = JSON.parse(readFileSync(draftPath, 'utf8'));
  const lesson = draft.lesson ?? draft;
  for (const field of ['expected_result', 'success_criteria', 'advice']) {
    assert.equal(typeof lesson[field], 'string', `real draft includes ${field}`);
    assert.ok(lesson[field].trim());
  }
  const checkout = fixtureCheckout();
  assert.equal(typeof lesson.project_id, 'string', 'the real draft retains its project context');
  git(checkout, ['remote', 'remove', 'origin']);
  const store = makeStore(fixtureConfig({ claude_root: tmp('experience-claude'), codex_root: tmp('experience-codex'),
    project_names: { [checkout]: String(lesson.project_id) } }));
  writeFileSync(join(checkout, 'labels.csv'), 'label\n beta \nALPHA\nbeta\n gamma \n');
  writeFileSync(join(checkout, 'check-output.cjs'), [
    "const assert = require('node:assert/strict');",
    "const fs = require('node:fs');",
    "assert.equal(fs.readFileSync('labels.txt', 'utf8'), 'ALPHA\\nBETA\\nGAMMA\\n');",
    "console.log('labels criterion passed');",
  ].join('\n') + '\n');
  return { store, checkout, lesson };
}

function approveExperience(store: string, lesson: Record<string, unknown>): void {
  assert.equal(lesson.listed, true, 'the real cloud draft is eligible for ordinary acceptance');
  appendRows(join(store, 'wiki/lessons.jsonl'), [{ ...lesson, status: 'candidate' }]);
  git(store, ['add', 'wiki/lessons.jsonl']);
  git(store, ['commit', '--quiet', '-m', 'stage cloud lesson']);
  const result = execFileSync(process.execPath, ['--experimental-strip-types', REMREFLECT, 'accept', String(lesson.lesson_id), '--this-project'],
    { encoding: 'utf8', env: { ...process.env, REM_REFLECT_STORE: store } });
  assert.match(result, /accepted/);
}

function experienceClaudeHome(store: string, promptHook: boolean): { iso: string; env: NodeJS.ProcessEnv } {
  assert.ok(CLAUDE_MODEL, 'set REM_E2E_CLAUDE_MODEL to the configured Claude model');
  const iso = tmp('experience-claude-home');
  const cred = join(homedir(), '.claude', '.credentials.json');
  assert.ok(existsSync(cred), 'Claude credential is available for an isolated config');
  copyFileSync(cred, join(iso, '.credentials.json'));
  chmodSync(join(iso, '.credentials.json'), 0o600);
  const skillDir = join(iso, 'skills', 'label-normalization');
  mkdirSync(skillDir, { recursive: true });
  writeFileSync(join(skillDir, 'SKILL.md'), '---\nname: label-normalization\ndescription: Normalize CSV labels\n---\nTrim labels, uppercase, remove duplicates, sort, then run the existing node check-output.cjs.\n');
  const hooks = promptHook
    ? { UserPromptSubmit: [{ hooks: [{ type: 'command', command: 'sno rem-reflect recall --agent claude-code --first-message' }] }] }
    : { SessionStart: [{ hooks: [{ type: 'command', command: 'sno rem-reflect recall --agent claude-code' }] }] };
  writeFileSync(join(iso, 'settings.json'), JSON.stringify({ hooks }));
  return { iso, env: { ...process.env, CLAUDE_CONFIG_DIR: iso, SNO_PROFILE_DIR: writeStationSettings('local-first'),
    PATH: `${remReflectShim(store)}:${process.env.PATH}` } };
}

function experienceTranscript(iso: string): string {
  const texts: string[] = [];
  const walk = (dir: string): void => {
    if (!existsSync(dir)) return;
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) walk(path);
      else if (entry.name.endsWith('.jsonl')) texts.push(readFileSync(path, 'utf8'));
    }
  };
  walk(join(iso, 'projects'));
  return texts.join('\n');
}

function observeExperience(store: string, checkout: string, iso: string, lesson: Record<string, unknown>, moment: string,
  expectedSession?: string): void {
  const transcript = experienceTranscript(iso);
  for (const field of ['advice', 'expected_result', 'success_criteria']) {
    assert.ok(transcript.includes(JSON.stringify(lesson[field]).slice(1, -1)), `${field} reached the real session`);
  }
  assert.ok(transcript.includes('memory_fact_ids'), 'recorded fact references reached the session');
  assert.ok(transcript.includes('skill_target'), 'the recorded skill reference reached the session');
  let loadedSkill = false;
  for (const line of transcript.split('\n').filter(Boolean)) {
    const row = JSON.parse(line);
    if (!Array.isArray(row.message?.content)) continue;
    for (const item of row.message.content) {
      if (item.type !== 'tool_use') continue;
      if (item.name === 'Skill' && String(item.input.skill).includes('label-normalization')) loadedSkill = true;
      if (item.name === 'Read' && String(item.input.file_path).endsWith('/label-normalization/SKILL.md')) loadedSkill = true;
      if (item.name === 'Read') assert.notEqual(item.input.file_path, join(checkout, 'check-output.cjs'), 'the checker did not supply the transformation rules');
      if (item.name === 'Bash') assert.doesNotMatch(item.input.command, /(?:cat|head|tail|sed|less)\s[^\n]*check-output\.cjs/,
        'the checker was invoked as a black box');
    }
  }
  assert.ok(loadedSkill, 'the real session loaded the skill named by the lesson situation');
  assert.equal(readFileSync(join(checkout, 'labels.txt'), 'utf8'), 'ALPHA\nBETA\nGAMMA\n');
  assert.match(transcript, /labels criterion passed/, 'the agent ran the criterion and recorded its actual result');
  assert.ok(shownLines(store).some(row => Array.isArray(row.lesson_ids) && row.lesson_ids.includes(lesson.lesson_id)),
    'the ordinary hook recorded exposure to this lesson');
  if (expectedSession) {
    assert.ok(shownLines(store).some(row => row.session_id === expectedSession
      && Array.isArray(row.lesson_ids) && row.lesson_ids.includes(lesson.lesson_id)), 'post-approval exposure belongs to the original running session');
  }
  // Optional retention lets the existing real-cloud judge consume this same genuine session.
  const proofDir = process.env.REM_EXPERIENCE_PROOF_DIR;
  if (proofDir) {
    const out = join(proofDir, moment);
    mkdirSync(out, { recursive: true });
    writeFileSync(join(out, 'transcript.jsonl'), transcript);
    writeFileSync(join(out, 'lesson.json'), JSON.stringify(lesson, null, 2));
    copyFileSync(join(store, 'ledger/usage.jsonl'), join(out, 'usage.jsonl'));
    copyFileSync(join(store, 'wiki/lessons.jsonl'), join(out, 'lessons.jsonl'));
    copyFileSync(join(checkout, 'labels.txt'), join(out, 'labels.txt'));
  }
}

test('experience graph: session-start complete lesson guides a real Claude task',
  { skip: RUN ? false : 'set REM_E2E=1 to spend quota' }, () => {
    const { store, checkout, lesson } = experienceFixture();
    approveExperience(store, lesson);
    const { iso, env } = experienceClaudeHome(store, false);
    execFileSync('claude', ['-p', 'Use the label-normalization skill to create labels.txt from labels.csv.', '--model', CLAUDE_MODEL,
      '--permission-mode', 'bypassPermissions', '--append-system-prompt',
      `This is an isolated test project at ${checkout}. Work only in that directory and read skills only from ${join(iso, 'skills')}. Treat check-output.cjs as a black box: do not read its source or other files outside this project. You may invoke it.`],
    { cwd: checkout, env, encoding: 'utf8', timeout: 180_000 });
    observeExperience(store, checkout, iso, lesson, 'session-start');
  });

test('experience graph: current-session approved lesson guides a real Claude task',
  { skip: RUN ? false : 'set REM_E2E=1 to spend quota' }, () => {
    const { store, checkout, lesson } = experienceFixture();
    const { iso, env } = experienceClaudeHome(store, true);
    const session = randomUUID();
    const common = ['--model', CLAUDE_MODEL, '--permission-mode', 'bypassPermissions', '--append-system-prompt',
      `This is an isolated test project at ${checkout}. Work only in that directory and read skills only from ${join(iso, 'skills')}. Treat check-output.cjs as a black box: do not read its source or other files outside this project. You may invoke it.`];
    execFileSync('claude', ['-p', 'Write ready.txt containing ready.', '--session-id', session, ...common],
      { cwd: checkout, env, encoding: 'utf8', timeout: 90_000 });
    const usage = readFileSync(join(store, 'ledger/usage.jsonl'), 'utf8').split('\n').filter(Boolean).map(line => JSON.parse(line));
    assert.ok(usage.some(row => row.type === 'first-message-recall' && row.session_id === session), 'the original session handled its first prompt');
    assert.ok(!usage.some(row => row.type === 'first-message-recall-failed'), 'the first prompt did not fail recall');
    approveExperience(store, lesson);
    execFileSync('claude', ['-p', 'Use the label-normalization skill to create labels.txt from labels.csv.', '--resume', session, ...common],
      { cwd: checkout, env, encoding: 'utf8', timeout: 180_000 });
    observeExperience(store, checkout, iso, lesson, 'current-session', session);
  });
