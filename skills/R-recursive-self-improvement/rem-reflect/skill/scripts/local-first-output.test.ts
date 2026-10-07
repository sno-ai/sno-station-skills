import { test } from 'node:test';
import type { TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, existsSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { run } from './rem-reflect.ts';
import { BackendError } from './backend.ts';
import type { Backend, SpawnRequest } from './backend.ts';
import { readLessons } from './lessons.ts';
import { readLedger } from './ledger.ts';
import { readPages } from './pages.ts';
import {
  tmp, fixtureConfig, fixtureCheckout, makeStore, writeStationSettings,
  writeCodexSession, codexMeta, codexUser, codexAssistant,
} from './test-helpers.ts';
import type { Config } from './config.ts';

const MT = new Date('2026-09-07T00:00:00Z').getTime();
const NIGHT = new Date('2026-09-08T00:00:00Z');
const NEXT = new Date('2026-09-09T00:00:00Z');
const CORRECTION = 'always read the account after writing the report';
const CLI = fileURLToPath(new URL('./rem-reflect.ts', import.meta.url));

function localFirst(t: TestContext): void {
  const before = process.env.SNO_PROFILE_DIR;
  process.env.SNO_PROFILE_DIR = writeStationSettings('local-first');
  t.after(() => { if (before === undefined) delete process.env.SNO_PROFILE_DIR; else process.env.SNO_PROFILE_DIR = before; });
}

// A session that read the `heartbeat` skill and was then corrected by its owner.
function correctedSession(config: Config, mtime: number = MT): void {
  writeCodexSession(config.codex_root, 'cx', [
    codexMeta('cx', '/n'),
    codexUser('<skill>\n<name>heartbeat</name>\n</skill>'),
    codexUser('write the weekly report'),
    codexAssistant('Report written, done.'),
    codexUser(`No, ${CORRECTION}`),
    codexAssistant('You are right, I checked it now.'),
  ], mtime);
}

// The agent CLI is the one external dependency: this stand-in answers like a model that read the staged
// prompt, quoting a line of it, so the real prompt, parser and quote check all run.
class WriterCli implements Backend {
  readonly asked: SpawnRequest[] = [];
  private readonly answer: (prompt: string) => unknown;
  constructor(answer: (prompt: string) => unknown = prompt => lessonFor(prompt)) { this.answer = answer; }
  spawn(request: SpawnRequest): { stdout: string } {
    this.asked.push(request);
    return { stdout: JSON.stringify(this.answer(request.input)) };
  }
}
function lessonFor(prompt: string, quote: string = CORRECTION): unknown {
  const line = Number(new RegExp(`^(\\d+): .*${quote}`, 'm').exec(prompt)?.[1]);
  const header = JSON.parse(/^(\{"trace_id".*)$/m.exec(prompt)![1]) as { skills_loaded: string[] };
  return { lesson: {
    summary: 'The report was declared done without reading the account back', class: 'EXECUTION_LAPSE',
    situation: { task_type: 'write a report', trigger: 'a report was written to an account and declared done', tools: [] },
    advice: 'Read the account back after writing a report before saying it is done.',
    because: 'The owner had to ask for the read-back after the agent reported success.', polarity: 'from_failure',
    evidence: [{ line_start: line, line_end: line, quote }], skill_target: header.skills_loaded[0] ?? null,
    reminder_line: 'Read the account back after writing, before reporting the work done.',
  } };
}
function cliRun(store: string, ...args: string[]) {
  return spawnSync(process.execPath, [CLI, ...args], { encoding: 'utf8', env: { ...process.env, REM_REFLECT_STORE: store } });
}
function staged(store: string, name: string): string[] {
  return readdirSync(join(store, 'staging'), { recursive: true }).map(String).filter(path => path.endsWith(name));
}

test('a Local First night writes a lesson and a skill reminder the owner can read, accept and reject, and uploads nothing', t => {
  localFirst(t);
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = makeStore(config);
  correctedSession(config);
  const writer = new WriterCli();
  const result = run(store, NIGHT, 'u', writer);
  assert.equal(result.code, 0, result.lines.join('\n'));

  // Only the session's own CLI was asked, once, and nothing was prepared for the cloud.
  assert.deepEqual(writer.asked.map(call => [call.cli, call.kind]), [['codex', 'model']]);
  assert.deepEqual(staged(store, 'cloud-request.json'), []);

  // Stored as the owner's pending decisions: a listed lesson, its page, and one staged reminder proposal.
  const [lesson] = readLessons(store);
  assert.equal(readLessons(store).length, 1);
  assert.deepEqual([lesson.status, lesson.listed, lesson.advice], ['candidate', true, 'Read the account back after writing a report before saying it is done.']);
  assert.equal(lesson.verification, undefined, 'a local lesson carries no cloud verification');
  assert.deepEqual(readPages(store).map(page => page.page_id), [lesson.page_id]);
  const proposal = readLedger(store).find(row => row.type === 'proposal');
  assert.deepEqual([proposal?.verdict, proposal?.backend, proposal?.region], ['pending', 'local', 'reminders']);
  const proposalDirectory = join(store, 'staging', '20260908-0000', 'codex');
  for (const file of ['proposal.json', 'patch.json', 'PURPOSE.md']) assert.equal(existsSync(join(proposalDirectory, file)), true, file);

  // The report names both, with the commands that decide them.
  const report = readFileSync(join(store, 'staging', '20260908-0000', 'REPORT.md'), 'utf8');
  assert.match(report, /Uploaded: 0/);
  assert.match(report, /New lessons: 1/);
  assert.match(report, /New proposals: 1/);
  assert.match(report, new RegExp(`${lesson.lesson_id}: Read the account back`));
  assert.match(report, new RegExp(`sno rem-reflect accept ${lesson.lesson_id}`));
  assert.match(report, /Pending decisions: 2/);
  assert.match(report, /20260908-0000\/codex: .*heartbeat/);

  // The ordinary commands decide them. Accepting the proposal changes the installed skill.
  const target = String(proposal?.target);
  assert.equal(readFileSync(join(target, 'SKILL.md'), 'utf8').includes('Read the account back after writing'), false);
  const acceptProposal = cliRun(store, 'accept', '20260908-0000/codex');
  assert.equal(acceptProposal.status, 0, acceptProposal.stdout + acceptProposal.stderr);
  assert.match(readFileSync(join(target, 'SKILL.md'), 'utf8'), /Read the account back after writing, before reporting the work done\./);
  // A lesson is not recalled until accepted; once accepted, a new session in that project sees it.
  const checkout = fixtureCheckout();
  const recall = () => spawnSync(process.execPath, [CLI, 'recall', '--agent', 'codex'], { encoding: 'utf8',
    input: JSON.stringify({ session_id: 'later', cwd: checkout }), env: { ...process.env, REM_REFLECT_STORE: store } });
  const pending = recall().stdout;
  assert.match(pending, new RegExp(`1 lessons await your verdict: ${lesson.lesson_id}`), 'the session start asks for the verdict');
  assert.doesNotMatch(pending, new RegExp(`^${lesson.lesson_id} · `, 'm'), 'an undecided lesson is not given to the agent as experience');
  const acceptLesson = cliRun(store, 'accept', lesson.lesson_id);
  assert.equal(acceptLesson.status, 0, acceptLesson.stdout + acceptLesson.stderr);
  assert.equal(readLessons(store)[0].status, 'accepted');
  assert.match(recall().stdout, new RegExp(`^${lesson.lesson_id} · `, 'm'));
  // And the other verdict works on a second lesson from another night.
  const second = new WriterCli(prompt => lessonFor(prompt, 'write the weekly report'));
  writeCodexSession(config.codex_root, 'cx2', [codexMeta('cx2', '/n'), codexUser('write the weekly report'),
    codexAssistant('done'), codexUser('write the weekly report again, the first one was empty')], MT + 3_600_000);
  assert.equal(run(store, NEXT, 'u', second).code, 0);
  const fresh = readLessons(store).find(row => row.status === 'candidate');
  assert.ok(fresh, 'the second night wrote a second lesson');
  const reject = cliRun(store, 'reject', fresh.lesson_id);
  assert.equal(reject.status, 0, reject.stdout + reject.stderr);
  assert.equal(readLessons(store).find(row => row.lesson_id === fresh.lesson_id)?.status, 'rejected');
});

test('a session already written about is not asked again, so a second night adds no duplicate', t => {
  localFirst(t);
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = makeStore(config);
  correctedSession(config);
  assert.equal(run(store, NIGHT, 'u', new WriterCli()).code, 0);
  const again = new WriterCli();
  assert.equal(run(store, NEXT, 'u', again).code, 0);
  assert.equal(again.asked.length, 0);
  assert.equal(readLessons(store).length, 1);
  assert.equal(readLedger(store).filter(row => row.type === 'proposal').length, 1);
});

test('an answer whose quote is not in the session is refused and writes nothing, and the night still succeeds', t => {
  localFirst(t);
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = makeStore(config);
  correctedSession(config);
  const writer = new WriterCli(prompt => {
    const answer = lessonFor(prompt) as { lesson: { evidence: { quote: string }[] } };
    answer.lesson.evidence[0].quote = 'the owner never said this';
    return answer;
  });
  const result = run(store, NIGHT, 'u', writer);
  assert.equal(result.code, 0, result.lines.join('\n'));
  assert.equal(writer.asked.length, 1);
  assert.deepEqual([readLessons(store).length, readPages(store).length, readLedger(store).filter(row => row.type === 'proposal').length], [0, 0, 0]);
  assert.match(readFileSync(join(store, 'staging', '20260908-0000', 'run.log'), 'utf8').concat(result.lines.join('\n')), /local writer answer refused/);
  const report = readFileSync(join(store, 'staging', '20260908-0000', 'REPORT.md'), 'utf8');
  assert.match(report, /New lessons: 0/);
});

test('a session the model finds nothing in writes nothing, and a CLI that cannot run is asked again next night', t => {
  localFirst(t);
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = makeStore(config);
  correctedSession(config, MT + 12 * 3_600_000);
  const down: Backend = { spawn() { throw new BackendError('labeler-unavailable', 'exit 1'); } };
  assert.equal(run(store, NIGHT, 'u', down).code, 0);
  assert.equal(readLessons(store).length, 0);
  const none = new WriterCli(() => ({ lesson: null }));
  assert.equal(run(store, NEXT, 'u', none).code, 0);
  assert.equal(none.asked.length, 1, 'the unavailable CLI left the session unmarked');
  assert.equal(readLessons(store).length, 0);
  const after = new WriterCli();
  assert.equal(run(store, new Date('2026-09-10T00:00:00Z'), 'u', after).code, 0);
  assert.equal(after.asked.length, 0, 'a session the model answered "nothing" is not asked again');
});

// The whole command, not the function: the real `sno rem-reflect run` spawns the real backend, which starts `codex exec`
// from PATH. Only that external program is a stand-in; it reads the staged prompt on stdin and quotes a line of it.
test('the real command in Local First prints a report with a lesson and a reminder, uploads nothing and leaves the owner settings untouched', () => {
  const profile = writeStationSettings('local-first');
  const settingsBefore = readFileSync(join(profile, 'settings.json'), 'utf8');
  const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
  const store = makeStore(config);
  correctedSession(config);
  const bin = tmp('bin');
  const calls = join(bin, 'calls.log');
  writeFileSync(join(bin, 'codex'), `#!/usr/bin/env node
const fs = require('node:fs');
const prompt = fs.readFileSync(0, 'utf8');
fs.appendFileSync(${JSON.stringify(calls)}, process.argv.slice(2).join(' ') + '\\n');
const quote = ${JSON.stringify(CORRECTION)};
const line = Number(new RegExp('^(\\\\d+): .*' + quote, 'm').exec(prompt)[1]);
const header = JSON.parse(/^(\\{"trace_id".*)$/m.exec(prompt)[1]);
process.stdout.write(JSON.stringify({ lesson: {
  summary: 'The report was declared done without reading the account back', class: 'EXECUTION_LAPSE',
  situation: { task_type: 'write a report', trigger: 'a report was written to an account and declared done', tools: [] },
  advice: 'Read the account back after writing a report before saying it is done.',
  because: 'The owner had to ask for the read-back after the agent reported success.', polarity: 'from_failure',
  evidence: [{ line_start: line, line_end: line, quote }], skill_target: header.skills_loaded[0] ?? null,
  reminder_line: 'Read the account back after writing, before reporting the work done.' } }));
`, { mode: 0o755 });
  const ran = spawnSync(process.execPath, [CLI, 'run', '--now', NIGHT.toISOString()], { encoding: 'utf8',
    env: { ...process.env, REM_REFLECT_STORE: store, SNO_PROFILE_DIR: profile, PATH: `${bin}:${process.env.PATH}` } });
  assert.equal(ran.status, 0, ran.stdout + ran.stderr);
  assert.match(ran.stdout, /^20260908-0000 success/m);

  assert.deepEqual(readFileSync(calls, 'utf8').trim().split('\n'), ['exec --skip-git-repo-check -'], 'the session CLI was asked exactly once');
  assert.deepEqual(staged(store, 'cloud-request.json'), [], 'nothing was prepared for upload');
  assert.equal(readFileSync(join(profile, 'settings.json'), 'utf8'), settingsBefore, 'the owner settings file is unchanged');

  const report = readFileSync(join(store, 'staging', '20260908-0000', 'REPORT.md'), 'utf8');
  const [lesson] = readLessons(store);
  assert.match(report, /New lessons: 1/);
  assert.match(report, /New proposals: 1/);
  assert.match(report, new RegExp(`${lesson.lesson_id}: Read the account back after writing a report before saying it is done\\.`));
  assert.match(report, new RegExp(`sno rem-reflect accept ${lesson.lesson_id}`));
  assert.match(report, /20260908-0000\/codex: .*heartbeat/);
  assert.equal(readLedger(store).filter(row => row.type === 'proposal' && row.verdict === 'pending').length, 1);
});

test('a public build without a private prompt gets the binary-served instructions and produces a lesson', t => {
  // The public release does not carry the `.private.` prompt: run a copy of the skill that lacks it.
  const copy = tmp('public-build');
  t.after(() => rmSync(copy, { recursive: true, force: true }));
  cpSync(fileURLToPath(new URL('..', import.meta.url)), join(copy, 'skill'), { recursive: true, filter: source => !source.includes('.private.') });
  assert.equal(existsSync(join(copy, 'skill', 'references', 'local-writer.private.md')), false);
  const scripts = join(copy, 'skill', 'scripts');
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', `
    import { run } from '${scripts}/rem-reflect.ts';
    import { tmp, fixtureConfig, makeStore, writeStationSettings, writeCodexSession, codexMeta, codexUser, codexAssistant } from '${scripts}/test-helpers.ts';
    import { existsSync, readFileSync } from 'node:fs';
    import { join } from 'node:path';
    process.env.SNO_PROFILE_DIR = writeStationSettings('local-first');
    const config = fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') });
    const store = makeStore(config);
    writeCodexSession(config.codex_root, 'cx', [codexMeta('cx', '/n'), codexUser('write the report'), codexAssistant('done'), codexUser('No, check it first')], ${MT});
    let asked = 0;
    const result = run(store, new Date('${NIGHT.toISOString()}'), 'u', { spawn({input}) {
      asked++;
      const quote = 'No, check it first';
      const line = Number(new RegExp('^(\\\\d+): .*' + quote, 'm').exec(input)[1]);
      return {stdout: JSON.stringify({lesson:{summary:'Check the written report', class:'EXECUTION_LAPSE', situation:{task_type:'report',trigger:'a completed report',tools:[]}, advice:'Check the report before declaring it done.', because:'The owner asked for verification.', polarity:'from_failure', evidence:[{line_start:line,line_end:line,quote}],skill_target:null,reminder_line:null}})};
    } });
    console.log(JSON.stringify({ code: result.code, asked, lessons: existsSync(join(store, 'wiki/lessons.jsonl')),
      log: readFileSync(join(store, 'staging', '20260908-0000', 'run.log'), 'utf8'),
      report: readFileSync(join(store, 'staging', '20260908-0000', 'REPORT.md'), 'utf8') }));
  `], { encoding: 'utf8', timeout: 120_000 });
  assert.equal(child.status, 0, child.stderr);
  const out = JSON.parse(child.stdout.trim().split('\n').pop()!) as { code: number; asked: number; lessons: boolean; log: string; report: string };
  assert.deepEqual([out.code, out.asked, out.lessons], [0, 1, true]);
  assert.match(out.log, /R5 local lesson generation: host/);
  assert.match(out.report, /New lessons: 1/);
});


test('R5 off makes no local model call and preserves the user choice', t => {
  const before = process.env.SNO_PROFILE_DIR;
  process.env.SNO_PROFILE_DIR = writeStationSettings('local-first', {R5:{'local-first':'off','agent-native':'off','rem-enhanced':'off'}});
  t.after(() => { if (before === undefined) delete process.env.SNO_PROFILE_DIR; else process.env.SNO_PROFILE_DIR = before; });
  const config = fixtureConfig({claude_root:tmp('c'),codex_root:tmp('x')});
  const store = makeStore(config);
  correctedSession(config);
  const backend = new WriterCli();
  assert.equal(run(store,NIGHT,'u',backend).code,0);
  assert.equal(backend.asked.length,0);
  assert.equal(readLessons(store).length,0);
});


test('published settings without R5 use the Local First default without rewriting the file', t => {
  localFirst(t);
  const path = join(process.env.SNO_PROFILE_DIR!, 'settings.json');
  const settings = JSON.parse(readFileSync(path, 'utf8'));
  delete settings.modelCalls.R5;
  writeFileSync(path, JSON.stringify(settings));
  const before = readFileSync(path, 'utf8');
  const config = fixtureConfig({claude_root:tmp('c'),codex_root:tmp('x')});
  const store = makeStore(config);
  correctedSession(config);
  assert.equal(run(store,NIGHT,'u',new WriterCli()).code,0);
  assert.equal(readLessons(store).length,1);
  assert.equal(readFileSync(path,'utf8'),before);
});
