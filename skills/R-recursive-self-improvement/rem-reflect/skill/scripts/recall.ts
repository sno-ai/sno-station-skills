import { appendFileSync, existsSync, readFileSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { cloudStepGate } from './cloud.ts';
import { isObject, loadConfig, reflectionFiles } from './config.ts';
import { message } from './text.ts';
import { gitRemote, projectId } from './identity.ts';
import type { Harness } from './identity.ts';
import { lessonContext, lessonsFrom } from './lessons.ts';
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

export interface RecallInput { session_id?: string; cwd?: string; prompt?: string; hook_event_name?: string; source?: string }
// the index command. Reads at HEAD, never takes the lock, prints the scoped index
// with the not-armed and pending-verdict prefixes, and records one `shown` line.
export function recall(store: string, agent: Harness, input: RecallInput, now: Date = new Date(), heartbeat: string = '',
  timer: boolean = false): CommandResult {
  if (!input.session_id) return { code: 1, lines: [message('recallMissing', { field: 'session_id' })] };
  if (!input.cwd) return { code: 1, lines: [message('recallMissing', { field: 'cwd' })] };
  // Before the first nightly run there is nothing to recall; a failing session-start hook would only show an error.
  if (!existsSync(store)) return { code: 0, lines: [] };
  const config = loadConfig(store);
  const project = projectId(input.cwd, gitRemote(input.cwd), config.project_names);
  const revision = headRevision(store);
  const lessons = lessonsFrom(readHead(store, reflectionFiles.lessons, revision) ?? '');
  const scoped = lessons.filter(lesson => recallable(lesson, project)).sort(rank).slice(0, 10);
  // A lesson bound to a failed call names what it fires on, so the agent can tell it apart from the general list.
  const on = (lesson: Lesson): string => lesson.trigger_match
    ? ` [on: ${lesson.trigger_match.command_id ?? lesson.trigger_match.path_glob ?? lesson.trigger_match.tool}]` : '';
  const index = scoped.map(lesson => message('recallIndexLine', { id: lesson.lesson_id, headline: `${lesson.situation.trigger}${on(lesson)}`,
    advice: lesson.advice, scope: lesson.applies_to }) + `\n${lessonContext(lesson)}`);
  const prefix: string[] = [];
  if (!timer && !armed(heartbeat)) {
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
  } catch (error) { stderr.push(`${message('usageAppendFailed', { error: String(error) })}; session ${input.session_id}, lessons ${scoped.map(lesson => lesson.lesson_id).join(', ')}; context delivered without use measurement`); }
  // With no lesson for this project the heading and instruction would only add noise to every session start.
  return { code: 0, lines: [...prefix, ...(index.length ? [message('recallHeading'), ...index,
    message('recallInstruction', { session: input.session_id, agent, cwd: input.cwd })] : [])], stderr };
}

export function firstMessageRecall(store: string, agent: Harness, input: RecallInput, now: Date = new Date()): CommandResult {
  if (!input.session_id || !input.cwd || !existsSync(store)) return { code: 0, lines: [] };
  const stderr: string[] = [];
  const rows: Record<string, unknown>[] = [];
  const usage = join(store, reflectionFiles.usage);
  try {
    const text = existsSync(usage) ? readFileSync(usage, 'utf8') : '';
    for (const line of text.split('\n').filter(Boolean)) {
      try { const row: unknown = JSON.parse(line); if (isObject(row)) rows.push(row); }
      catch (error) { stderr.push(`${usage}: ${String(error)}; malformed usage row ignored, lesson delivery continues`); }
    }
  } catch (error) { stderr.push(`${usage}: ${String(error)}; usage unavailable, lesson delivery continues`); }
  const record = (row: Record<string, unknown>): void => {
    try { appendUsage(store, row); }
    catch (error) {
      const lessons = Array.isArray(row.lesson_ids) ? `, lessons ${row.lesson_ids.join(', ')}` : '';
      stderr.push(`${message('usageAppendFailed', { error: String(error) })}; session ${String(row.session_id)}${lessons}; context delivered without use measurement`);
    }
  };
  const config = loadConfig(store);
  const project = projectId(input.cwd, gitRemote(input.cwd), config.project_names);
  const revision = headRevision(store);
  const verdicts = ledgerFrom(readHead(store, reflectionFiles.ledger, revision) ?? '');
  const compact = input.hook_event_name === 'PostCompact'
    || input.hook_event_name === 'SessionStart' && input.source === 'compact';
  const accepted = lessonsFrom(readHead(store, reflectionFiles.lessons, revision) ?? '')
    // A compaction restores every lesson the session could recall; a prompt delivers only local approvals.
    .filter(lesson => compact ? recallable(lesson, project) : lesson.status === 'accepted' && inScope(lesson, project));
  const approval = (lesson: Lesson): number => verdicts.findLastIndex(row => row.type === 'lesson-verdict' && row.lesson_id === lesson.lesson_id);
  const handled = rows.some(row => ['first-message-recall', 'first-message-recall-skipped'].includes(String(row.type))
    && row.session_id === input.session_id);
  // The first prompt records the approvals the session already knows; a later prompt delivers only newer approvals.
  const known = accepted.map(lesson => ({ lesson_id: lesson.lesson_id, verdict: approval(lesson) }));
  const selected = !compact && !handled ? [] : accepted.filter(lesson => compact || !rows.some(row => row.session_id === input.session_id
    && ['shown', 'first-message-recall', 'first-message-recall-skipped'].includes(String(row.type))
    && Array.isArray(row.accepted_verdicts) && row.accepted_verdicts.some(value => isObject(value)
      && value.lesson_id === lesson.lesson_id && value.verdict === approval(lesson))));
  if (selected.length) {
    record({ type: 'shown', session_id: input.session_id, agent_id: agent, project_id: project,
      lesson_ids: selected.map(lesson => lesson.lesson_id),
      accepted_verdicts: selected.map(lesson => ({ lesson_id: lesson.lesson_id, verdict: approval(lesson) })), time: now.toISOString() });
    const event = compact ? input.hook_event_name : input.hook_event_name === 'SessionStart' ? 'SessionStart' : 'UserPromptSubmit';
    return { code: 0, stderr, lines: [JSON.stringify({ hookSpecificOutput: { hookEventName: event,
      additionalContext: selected.map(lesson => `${lesson.lesson_id}:\n${lessonContext(lesson)}`).join('\n') } })] };
  }
  if (compact || handled || !input.prompt) return { code: 0, lines: [], stderr };
  const settingsLog: string[] = [];
  const settings = loadLocalSettings(store, settingsLog);
  // R4: the message goes to the Sno cloud only when its cell is sno-gpu and consent is full. The row
  // below marks this session's first message as handled either way, so a later prompt never counts as first.
  let gate: ReturnType<typeof cloudStepGate>;
  try { gate = cloudStepGate('R4'); }
  catch (error) { gate = { send: false, reason: error instanceof Error ? error.message : String(error) }; }
  // After the cloud refused for a used-up allowance, no session calls it again before the reset it named.
  const paused = rows.filter(row => row.type === 'first-message-recall-skipped').pop();
  if (gate.send && typeof paused?.until === 'string' && now.getTime() < Date.parse(paused.until)) {
    record({ type: 'first-message-recall-skipped', session_id: input.session_id, until: paused.until, time: now.toISOString(),
      accepted_verdicts: known });
    return { code: 0, lines: [], stderr };
  }
  record({ type: 'first-message-recall', session_id: input.session_id, agent_id: agent,
    project_id: project, time: now.toISOString(), settings: settingsLog[0], call: 'R4',
    ...(gate.send ? {} : { skipped: gate.reason }), accepted_verdicts: known });
  if (!gate.send) return { code: 0, lines: [], stderr };
  const lessons = lessonsFrom(readHead(store, reflectionFiles.lessons, revision) ?? '')
    .filter(lesson => recallable(lesson, project));
  const request = { project_id: project, message: input.prompt,
    lessons: lessons.map(lesson => ({ lesson_id: lesson.lesson_id, situation: lesson.situation, advice: lesson.advice })) };
  const result = spawnSync('sno', ['rem', 'recall', '--json'], { input: JSON.stringify(request), encoding: 'utf8',
    timeout: settings.recall_timeout_ms });
  if (result.error || result.status !== 0) {
    let refusal: unknown;
    try { refusal = JSON.parse(result.stdout); } catch { /* not the CLI's JSON error: the failure row below keeps the text */ }
    if (isObject(refusal) && refusal.error === 'allowance_used_up' && typeof refusal.reset_at === 'string'
      && Number.isFinite(Date.parse(refusal.reset_at))) {
      record({ type: 'first-message-recall-skipped', session_id: input.session_id, until: refusal.reset_at, time: now.toISOString() });
      return { code: 0, lines: [], stderr };
    }
    record({ type: 'first-message-recall-failed', session_id: input.session_id,
      error: String(result.error ?? (result.stdout?.trim() || result.stderr?.trim() || `exit ${result.status}`)), time: now.toISOString() });
    return { code: 0, lines: [], stderr };
  }
  try {
    const answer: unknown = JSON.parse(result.stdout);
    if (!isObject(answer) || !Array.isArray(answer.lesson_ids) || !answer.lesson_ids.every(id => typeof id === 'string')) {
      throw new Error('invalid recall response');
    }
    const selected = answer.lesson_ids.map(id => lessons.find(lesson => lesson.lesson_id === id)).filter((lesson): lesson is Lesson => !!lesson);
    if (!selected.length) return { code: 0, lines: [], stderr };
    record({ type: 'shown', session_id: input.session_id, agent_id: agent, project_id: project,
      lesson_ids: selected.map(lesson => lesson.lesson_id), time: now.toISOString() });
    const text = selected.map(lesson => `${lesson.lesson_id}:\n${lessonContext(lesson)}`).join('\n');
    return { code: 0, lines: [JSON.stringify({ hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: text } })], stderr };
  } catch (error) {
    record({ type: 'first-message-recall-failed', session_id: input.session_id,
      error: String(error), time: now.toISOString() });
    return { code: 0, lines: [], stderr };
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
  if (!recallStatus(lesson) && !(lesson.status === 'candidate' && lesson.listed === true)) {
    return { code: 1, lines: [message('lessonRefusedScope', { id: lessonId, reason: `status ${lesson.status}` })] };
  }
  if (!inScope(lesson, project)) return { code: 1, lines: [message('lessonRefusedScope', { id: lessonId, reason: `scope ${lesson.applies_to}` })] };
  const stderr: string[] = [];
  try { appendUsage(store, { type: 'read', session_id: input.session ?? '', lesson_id: lessonId, time: now.toISOString() }); }
  catch (error) { stderr.push(`${message('usageAppendFailed', { error: String(error) })}; session ${input.session ?? ''}, lesson ${lessonId}; context delivered without read measurement`); }
  return { code: 0, stderr, lines: [
    ...lessonContext(lesson).split('\n'),
    message('lessonField', { key: 'because', value: lesson.because }),
    message('lessonField', { key: 'evidence', value: JSON.stringify(lesson.evidence) }),
  ] };
}

// Print the SessionStart and UserPromptSubmit hook entries the owner installs by hand. The program never writes
// ~/.claude/settings.json, ~/.codex/hooks.json or ~/.hermes/config.yaml itself.
export function installHooksPrint(): CommandResult {
  // sno passes its own absolute path; a hook's PATH often lacks ~/.local/bin, where a bare `sno` is not found.
  const executable = process.env.SNO_EXECUTABLE;
  const sno = executable ? `'${executable.replaceAll("'", "'\\''")}'` : 'sno';
  const claude = { hooks: { SessionStart: [{ hooks: [{ type: 'command', command: `${sno} rem-reflect recall --agent claude-code` }] }],
    UserPromptSubmit: [{ hooks: [{ type: 'command', command: `${sno} rem-reflect recall --agent claude-code --first-message` }] }] } };
  // Codex reads the same nested `hooks: [{ type: command, command: <shell string> }]` shape as Claude
  // (a flat `{command: [argv]}` entry is not run; the nested command string
  // fires and receives the session JSON on stdin). Its SessionStart hook runs only after the owner
  // approves it once in an interactive session (hook trust).
  const codex = { hooks: { SessionStart: [{ hooks: [{ type: 'command', command: `${sno} rem-reflect recall --agent codex` }] }],
    UserPromptSubmit: [{ hooks: [{ type: 'command', command: `${sno} rem-reflect recall --agent codex --first-message` }] }] } };
  return { code: 0, lines: [
    '# ~/.claude/settings.json — merge these hooks:',
    JSON.stringify(claude, null, 2),
    '# ~/.codex/hooks.json — merge these hooks (Codex runs them only after you approve them once in an interactive session):',
    JSON.stringify(codex, null, 2),
    '# ~/.hermes/config.yaml — merge this shell hook; recall returns {"context": ...} only on is_first_turn:',
    'hooks:\n  pre_llm_call:\n    - command: sno rem-reflect recall --agent hermes',
    '# OpenClaw lessons come from the Sno memory plugin; no shell hook to install.',
  ] };
}
