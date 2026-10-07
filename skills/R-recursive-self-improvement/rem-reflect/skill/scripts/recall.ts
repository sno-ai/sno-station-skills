import { appendFileSync, existsSync, readFileSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { cloudStepGate } from './cloud.ts';
import { isObject, loadConfig, reflectionFiles } from './config.ts';
import { message } from './text.ts';
import { gitRemote, projectId } from './identity.ts';
import type { Harness } from './identity.ts';
import { lessonsFrom } from './lessons.ts';
import type { Lesson } from './lessons.ts';
import { headRevision, parseState, readHead } from './store.ts';
import { loadLocalSettings } from './local-settings.ts';
import type { CommandResult } from './rem-reflect.ts';

// A lesson is recalled when the owner accepted it, or when it is listed and its cloud verification accepted it;
// never once the owner rejected it.
function recallStatus(lesson: Lesson): boolean {
  return lesson.status === 'accepted'
    || (lesson.status === 'candidate' && lesson.listed === true && lesson.verification?.accepted === true);
}
// In scope: user-wide, the resolved project, or a skill lesson learned in the resolved project.
function inScope(lesson: Lesson, project: string): boolean {
  const scope = lesson.applies_to;
  return scope === 'general' || scope === `project:${project}` || (scope.startsWith('skill:') && lesson.project_id === project);
}
function recallable(lesson: Lesson, project: string): boolean {
  return recallStatus(lesson) && inScope(lesson, project);
}
// ranking: helped − harmful, then count, then recency (the created run id sorts by date).
function rank(a: Lesson, b: Lesson): number {
  return (b.helped - b.harmful) - (a.helped - a.harmful) || b.count - a.count || b.created_run.localeCompare(a.created_run);
}
function ledgerFrom(text: string): Record<string, unknown>[] {
  return text.split('\n').filter(Boolean).map(line => JSON.parse(line) as Record<string, unknown>).filter(isObject);
}
// The last-row-wins verdict for a proposal id or lesson id at HEAD.
function hasVerdict(ledger: readonly Record<string, unknown>[], type: string, key: string, id: string): boolean {
  return ledger.some(row => row.type === type && row[key] === id);
}
function newestReport(store: string): string {
  const dir = join(store, reflectionFiles.staging);
  if (!existsSync(dir)) return '';
  const runs = readdirSync(dir).filter(name => existsSync(join(dir, name, 'REPORT.md'))).sort();
  return runs.length ? join(store, reflectionFiles.staging, runs[runs.length - 1], 'REPORT.md') : '';
}
// the count of staged proposals and listed lessons that have no verdict at HEAD.
// This project's and the user-wide undecided lessons are raised, by id, so a session never asks about
// another project's lesson or about one the owner already decided.
function pendingVerdictLine(store: string, revision: string | undefined, lessons: readonly Lesson[], project: string): string | undefined {
  const ledger = ledgerFrom(readHead(store, reflectionFiles.ledger, revision) ?? '');
  const proposals = new Set<string>();
  for (const row of ledger) {
    if (row.type === 'proposal' && row.kind !== 'no_action' && row.verdict === 'pending' && typeof row.proposal_id === 'string'
      && !hasVerdict(ledger, 'verdict', 'proposal_id', row.proposal_id)) proposals.add(row.proposal_id);
  }
  const listed = lessons.filter(lesson => lesson.listed === true && lesson.status === 'candidate'
    && (lesson.project_id === project || lesson.applies_to === 'general'))
    .map(lesson => lesson.lesson_id);
  if (proposals.size === 0 && listed.length === 0) return undefined;
  return message('pendingVerdict', { n: proposals.size, m: listed.length, ids: listed.join(', '), path: newestReport(store) });
}
function armed(heartbeat: string): boolean {
  return heartbeat.split('\n').some(line => /(?:^|\s)rem-reflect(?:\s|$)/.test(line));
}
// Read the working usage file, counting lines that do not parse (they are left in place).
function countBadUsage(store: string): number {
  const path = join(store, reflectionFiles.usage);
  if (!existsSync(path)) return 0;
  let bad = 0;
  for (const line of readFileSync(path, 'utf8').split('\n').filter(Boolean)) {
    try { JSON.parse(line); } catch { bad++; }
  }
  return bad;
}
function appendUsage(store: string, row: Record<string, unknown>): void {
  appendFileSync(join(store, reflectionFiles.usage), `${JSON.stringify(row)}\n`, { mode: 0o600 });
}

export interface RecallInput { session_id?: string; cwd?: string; prompt?: string }
// the index command. Reads at HEAD, never takes the lock, prints the scoped index
// with the not-armed and pending-verdict prefixes, and records one `shown` line.
export function recall(store: string, agent: Harness, input: RecallInput, now: Date = new Date(), heartbeat: string = ''): CommandResult {
  if (!input.session_id) return { code: 1, lines: [message('recallMissing', { field: 'session_id' })] };
  if (!input.cwd) return { code: 1, lines: [message('recallMissing', { field: 'cwd' })] };
  if (!existsSync(store)) return { code: 1, lines: ['no store'] };
  const config = loadConfig(store);
  const project = projectId(input.cwd, gitRemote(input.cwd), config.project_names);
  const revision = headRevision(store);
  const lessons = lessonsFrom(readHead(store, reflectionFiles.lessons, revision) ?? '');
  const scoped = lessons.filter(lesson => recallable(lesson, project)).sort(rank).slice(0, 10);
  const index = scoped.map(lesson => message('recallIndexLine', { id: lesson.lesson_id, headline: lesson.situation.trigger,
    advice: lesson.advice, scope: lesson.applies_to }));
  const prefix: string[] = [];
  if (!armed(heartbeat)) {
    const stateText = readHead(store, 'state.json', revision);
    const date = stateText ? parseState(stateText).last_terminal?.date ?? '' : '';
    prefix.push(message('notArmed', { date }));
  }
  const pending = pendingVerdictLine(store, revision, lessons, project);
  if (pending) prefix.push(pending);
  const stderr: string[] = [];
  const bad = countBadUsage(store);
  if (bad) stderr.push(message('usageMalformedCount', { n: bad }));
  try {
    appendUsage(store, { type: 'shown', session_id: input.session_id, cwd: input.cwd, project_id: project,
      agent_id: agent, lesson_ids: scoped.map(lesson => lesson.lesson_id), time: now.toISOString() });
  } catch (error) { stderr.push(message('usageAppendFailed', { error: String(error) })); }
  return { code: 0, lines: [...prefix, message('recallHeading'), ...index,
    message('recallInstruction', { session: input.session_id, agent, cwd: input.cwd })], stderr };
}

export function firstMessageRecall(store: string, agent: Harness, input: RecallInput, now: Date = new Date()): CommandResult {
  if (!input.session_id || !input.cwd || !input.prompt || !existsSync(store)) return { code: 0, lines: [] };
  const rows = ledgerFrom(existsSync(join(store, reflectionFiles.usage))
    ? readFileSync(join(store, reflectionFiles.usage), 'utf8') : '');
  if (rows.some(row => row.type === 'first-message-recall' && row.session_id === input.session_id)) return { code: 0, lines: [] };
  const settingsLog: string[] = [];
  const settings = loadLocalSettings(store, settingsLog);
  const config = loadConfig(store);
  const project = projectId(input.cwd, gitRemote(input.cwd), config.project_names);
  // R4: the message goes to the Sno cloud only when its cell is sno-gpu and consent is full. The row
  // below marks this session's first message as handled either way, so a later prompt never counts as first.
  let gate: ReturnType<typeof cloudStepGate>;
  try { gate = cloudStepGate('R4'); }
  catch (error) { gate = { send: false, reason: error instanceof Error ? error.message : String(error) }; }
  appendUsage(store, { type: 'first-message-recall', session_id: input.session_id, agent_id: agent,
    project_id: project, time: now.toISOString(), settings: settingsLog[0], call: 'R4',
    ...(gate.send ? {} : { skipped: gate.reason }) });
  if (!gate.send) return { code: 0, lines: [] };
  const revision = headRevision(store);
  const lessons = lessonsFrom(readHead(store, reflectionFiles.lessons, revision) ?? '')
    .filter(lesson => recallable(lesson, project));
  const request = { project_id: project, message: input.prompt,
    lessons: lessons.map(lesson => ({ lesson_id: lesson.lesson_id, situation: lesson.situation, advice: lesson.advice })) };
  const result = spawnSync('sno', ['rem', 'recall'], { input: JSON.stringify(request), encoding: 'utf8',
    timeout: settings.recall_timeout_ms });
  if (result.error || result.status !== 0) {
    appendUsage(store, { type: 'first-message-recall-failed', session_id: input.session_id,
      error: String(result.error ?? result.stderr?.trim() ?? `exit ${result.status}`), time: now.toISOString() });
    return { code: 0, lines: [] };
  }
  try {
    const answer: unknown = JSON.parse(result.stdout);
    if (!isObject(answer) || !Array.isArray(answer.lesson_ids) || !answer.lesson_ids.every(id => typeof id === 'string')) {
      throw new Error('invalid recall response');
    }
    const selected = answer.lesson_ids.map(id => lessons.find(lesson => lesson.lesson_id === id)).filter((lesson): lesson is Lesson => !!lesson);
    if (!selected.length) return { code: 0, lines: [] };
    appendUsage(store, { type: 'shown', session_id: input.session_id, agent_id: agent, project_id: project,
      lesson_ids: selected.map(lesson => lesson.lesson_id), time: now.toISOString() });
    const text = selected.map(lesson => `${lesson.lesson_id}: ${lesson.situation.trigger}\n${lesson.advice}`).join('\n');
    return { code: 0, lines: [JSON.stringify({ hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: text } })] };
  } catch (error) {
    appendUsage(store, { type: 'first-message-recall-failed', session_id: input.session_id,
      error: String(error), time: now.toISOString() });
    return { code: 0, lines: [] };
  }
}

export interface LessonInput { session?: string; cwd?: string; agent?: Harness }
// the detail command. No stdin; cwd and agent from flags; reads at HEAD; records one
// `read` line. Refuses any lesson that is not recallable here, naming the reason.
export function lessonDetail(store: string, lessonId: string, input: LessonInput, now: Date = new Date()): CommandResult {
  if (!input.cwd) return { code: 1, lines: [message('lessonMissing', { field: 'cwd' })] };
  if (!input.agent) return { code: 1, lines: [message('lessonMissing', { field: 'agent' })] };
  if (!existsSync(store)) return { code: 1, lines: ['no store'] };
  const config = loadConfig(store);
  const project = projectId(input.cwd, gitRemote(input.cwd), config.project_names);
  const revision = headRevision(store);
  const lesson = lessonsFrom(readHead(store, reflectionFiles.lessons, revision) ?? '').find(row => row.lesson_id === lessonId);
  if (!lesson) return { code: 1, lines: [`${lessonId}: no such lesson`] };
  if (!recallStatus(lesson)) return { code: 1, lines: [message('lessonRefusedScope', { id: lessonId, reason: `status ${lesson.status}` })] };
  if (!inScope(lesson, project)) return { code: 1, lines: [message('lessonRefusedScope', { id: lessonId, reason: `scope ${lesson.applies_to}` })] };
  const stderr: string[] = [];
  try { appendUsage(store, { type: 'read', session_id: input.session ?? '', lesson_id: lessonId, time: now.toISOString() }); }
  catch (error) { stderr.push(message('usageAppendFailed', { error: String(error) })); }
  return { code: 0, stderr, lines: [
    message('lessonField', { key: 'situation', value: JSON.stringify(lesson.situation) }),
    message('lessonField', { key: 'advice', value: lesson.advice }),
    message('lessonField', { key: 'because', value: lesson.because }),
    message('lessonField', { key: 'evidence', value: JSON.stringify(lesson.evidence) }),
  ] };
}

// Print the SessionStart and UserPromptSubmit hook entries the owner installs by hand. The program never writes
// ~/.claude/settings.json or ~/.codex/hooks.json itself.
export function installHooksPrint(): CommandResult {
  const claude = { hooks: { SessionStart: [{ hooks: [{ type: 'command', command: 'sno rem-reflect recall --agent claude-code' }] }],
    UserPromptSubmit: [{ hooks: [{ type: 'command', command: 'sno rem-reflect recall --agent claude-code --first-message' }] }] } };
  // Codex reads the same nested `hooks: [{ type: command, command: <shell string> }]` shape as Claude
  // (a flat `{command: [argv]}` entry is not run; the nested command string
  // fires and receives the session JSON on stdin). Its SessionStart hook runs only after the owner
  // approves it once in an interactive session (hook trust).
  const codex = { hooks: { SessionStart: [{ hooks: [{ type: 'command', command: 'sno rem-reflect recall --agent codex' }] }],
    UserPromptSubmit: [{ hooks: [{ type: 'command', command: 'sno rem-reflect recall --agent codex --first-message' }] }] } };
  return { code: 0, lines: [
    '# ~/.claude/settings.json — merge these hooks:',
    JSON.stringify(claude, null, 2),
    '# ~/.codex/hooks.json — merge these hooks (Codex runs them only after you approve them once in an interactive session):',
    JSON.stringify(codex, null, 2),
  ] };
}
