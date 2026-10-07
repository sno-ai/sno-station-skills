import { randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { BackendError } from './backend.ts';
import type { Backend, Cli } from './backend.ts';
import { limits, reflectionFiles, skillRoots, stationCell, SettingsUnavailable } from './config.ts';
import type { Config } from './config.ts';
import { traceKey, validateEvidence } from './evidence.ts';
import type { Evidence } from './evidence.ts';
import type { Trace } from './harvest.ts';
import { eventLines } from './labeler.ts';
import { appendLedger } from './ledger.ts';
import { loadLocalSettings } from './local-settings.ts';
import { appendRows } from './lessons.ts';
import { firstObject, reference, validateSchema } from './model-json.ts';
import { readPages, writePage } from './pages.ts';
import type { Page } from './pages.ts';
import { proposalSignature, validateProposal } from './proposer.ts';
import { loadRenderBudgets, renderHeader, renderTrace } from './render.ts';
import { CeilingReached } from './session.ts';
import { atomicWrite, privateDirectory, writeJson } from './store.ts';

interface WrittenLesson {
  summary: string; class: 'SKILL_DEFECT' | 'EXECUTION_LAPSE';
  situation: { task_type: string; trigger: string; tools: string[] };
  advice: string; because: string; polarity: 'from_failure' | 'from_success';
  evidence: { line_start: number; line_end: number; quote: string }[];
  skill_target: string | null; reminder_line: string | null;
}

function doneKeys(store: string): Set<string> {
  const path = join(store, reflectionFiles.localWriter);
  if (!existsSync(path)) return new Set();
  return new Set(readFileSync(path, 'utf8').split('\n').filter(Boolean).map(line => String((JSON.parse(line) as { trace_key: unknown }).trace_key)));
}

// Sessions with the most failed calls and typed owner lines go first; a session with neither has little to teach.
function pick(eligible: readonly Trace[], harness: Trace['agent_id'], done: ReadonlySet<string>): { trace: Trace; events: Set<number> }[] {
  return eligible.filter(trace => trace.agent_id === harness && !done.has(traceKey(trace)))
    .map(trace => ({ trace, events: eventLines(trace) }))
    .filter(item => item.events.size > 0)
    .sort((a, b) => b.events.size - a.events.size)
    .slice(0, limits.localSessionsPerHalf);
}

function promptFor(instructions: string, trace: Trace, events: ReadonlySet<number>, maxChars: number, windowLines: number): string {
  const prefix = `${instructions}\n${reference('local-writer.schema.json')}\n${renderHeader(trace)}\n`;
  const rendered = renderTrace(trace, loadRenderBudgets());
  const full = rendered.body.length + prefix.length <= maxChars;
  let body = '';
  for (const row of rendered.records) {
    if (!full && ![...events].some(line => Math.abs(line - row.line_number) <= windowLines)) continue;
    if (prefix.length + body.length + row.text.length > maxChars) break;
    body += row.text;
  }
  return prefix + body;
}

function pageFor(id: string, trace: Trace, lesson: WrittenLesson, evidence: Evidence[], skillTarget: string | null, now: Date): Page {
  return {
    page_id: id, body: `${lesson.because}\n\n${lesson.advice}\n`, count: 1, task_ids: [trace.trace_id],
    last_seen: now.toISOString(), skills_observed: trace.skills_loaded, backend: 'local',
    summary: lesson.summary, class: lesson.class,
    root_cause: { subject: lesson.situation.trigger, relation: 'caused', fact: lesson.because, valid_at: now.toISOString().slice(0, 10),
      evidence_pages: [], evidence_traces: [trace.trace_id] },
    fix: lesson.advice, scenario: lesson.situation, skills_used: trace.skills_loaded, skill_target: skillTarget, knowledge_used: [],
    outcome: lesson.polarity === 'from_failure' ? 'fail' : 'success', agent_id: trace.agent_id, project_id: trace.project_id,
    user_id: trace.user_id, evidence: evidence.map(item => `Line ${item.line_start}: ${item.quote.slice(0, 120)}`),
    citations: evidence, counter_examples: 'not searched', superseded: false,
  };
}

// A reminder line for the skill the session read, staged exactly as a cloud proposal is, for the owner to accept or reject.
function stageReminder(store: string, config: Config, runId: string, harness: string, page: Page, line: string, log: string[]): boolean {
  const raw = { kind: 'patch', target: page.skill_target, region: 'reminders', class: page.class,
    purpose: { summary: page.summary, page_ids: [page.page_id] }, scenario: page.scenario, skills_used: page.skills_used,
    skill_target: page.skill_target, knowledge_used: [], outcome: page.outcome, evidence: page.evidence, line };
  let validated: ReturnType<typeof validateProposal>;
  try {
    validated = validateProposal(raw, { store, roots: skillRoots(config), pages: readPages(store) }, new Set([String(page.skill_target)]));
  } catch (error) {
    log.push(`proposal refused: run ${runId} half ${harness} target ${String(page.skill_target)}: ${String(error)}`);
    return false;
  }
  const directory = join(store, reflectionFiles.staging, runId, harness);
  const hashes = validated.targetHashes ?? {};
  writeJson(join(directory, reflectionFiles.proposal), { ...raw, target_hashes: hashes });
  writeJson(join(directory, reflectionFiles.patch), { region: validated.region, ops: validated.ops ?? null,
    line: validated.reminderLine ?? null, replace_line: validated.replaceLine ?? null });
  atomicWrite(join(directory, reflectionFiles.purpose), `${page.summary}\nPages: ${page.page_id}\n`);
  appendLedger(store, { type: 'proposal', proposal_id: `${runId}/${harness}`, run_id: runId, half: harness, backend: 'local',
    kind: validated.kind, target: validated.target, region: validated.region, diff: validated.diff,
    expertise: { scenario: page.scenario, skills_used: page.skills_used, skill_target: page.skill_target, knowledge_used: [],
      outcome: page.outcome, evidence: page.evidence },
    purpose: raw.purpose, verdict: 'pending', evidence: page.evidence, signature: proposalSignature(validated.proposal),
    target_hashes: hashes });
  return true;
}

// Local First's nightly work: ask each chosen session's own CLI for one lesson, keep only answers whose quotes
// are verbatim in the session, and store them as pages, listed lessons and at most one reminder proposal per
// harness. Nothing is sent to Sno: the session text goes only to the user's own agent CLI and its model account. A lesson
// is not recalled until the owner accepts it. Sno CLI serves the prompt from its compiled binary; the public skill carries no prompt file.
export function writeLocally(store: string, config: Config, runId: string, eligible: readonly Trace[], backend: Backend,
  log: string[], now: Date): { asked: number; lessons: number; proposals: number } {
  const done = doneKeys(store);
  const settings = loadLocalSettings(store, log);
  const result = { asked: 0, lessons: 0, proposals: 0 };
  let instructions: string | undefined;
  const mark = (trace: Trace, outcome: string): void => appendRows(join(store, reflectionFiles.localWriter),
    [{ trace_key: traceKey(trace), run_id: runId, call_id: 'R5', result: outcome }]);
  for (const harness of ['claude-code', 'codex'] as const) {
    let staged = false;
    for (const { trace, events } of pick(eligible, harness, done)) {
      try {
        if (stationCell('R5') !== 'host') { log.push('R5 local lesson generation: off'); continue; }
      } catch (error) {
        if (!(error instanceof SettingsUnavailable)) throw error;
        log.push(`local writer: R5 unavailable: ${error.message}; no model call made`);
        continue;
      }
      if (instructions === undefined) {
        const fetched = spawnSync('sno', ['skills', 'get', 'rem-reflect-local-writer'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
        if (fetched.error || fetched.status !== 0 || !fetched.stdout.trim()) {
          log.push(`local writer: sno skills get rem-reflect-local-writer failed: ${fetched.error?.message ?? (fetched.stderr.trim() || `exit ${fetched.status}`)}; no lessons or reminders written`);
          return result;
        }
        instructions = fetched.stdout;
      }
      log.push(`R5 local lesson generation: host (${harness})`);
      const cwd = join(store, reflectionFiles.staging, runId, harness);
      privateDirectory(cwd);
      const cli: Cli = harness === 'codex' ? 'codex' : 'claude';
      let stdout: string;
      try {
        stdout = backend.spawn({ cli, cwd, input: promptFor(instructions, trace, events, settings.labeler_input_max_chars, settings.labeler_event_window_lines),
          kind: 'model' }).stdout;
      } catch (error) {
        if (!(error instanceof BackendError) && !(error instanceof CeilingReached)) throw error;
        log.push(`${trace.trace_id}: local writer unavailable (${error.message})`);
        continue;
      }
      result.asked++;
      let lesson: WrittenLesson | null;
      let evidence: Evidence[] = [];
      try {
        const value = firstObject(stdout);
        validateSchema(value, JSON.parse(reference('local-writer.schema.json')));
        lesson = (value as { lesson: WrittenLesson | null }).lesson;
        if (lesson) {
          evidence = lesson.evidence.map(item => ({ ...item, trace_id: trace.trace_id }));
          validateEvidence(evidence, [trace]);
        }
      } catch (error) {
        log.push(`${trace.trace_id}: local writer answer refused: ${String(error)}`);
        mark(trace, 'refused');
        continue;
      }
      mark(trace, lesson ? 'lesson' : 'none');
      if (!lesson) continue;
      const id = `${runId}-${randomBytes(6).toString('hex')}`;
      const skillTarget = lesson.skill_target && trace.skills_loaded.includes(lesson.skill_target) ? lesson.skill_target : null;
      const page = pageFor(id, trace, lesson, evidence, skillTarget, now);
      writePage(store, page);
      appendRows(join(store, reflectionFiles.lessons), [{ lesson_id: `L-${id}`, page_id: id, status: 'candidate', listed: true,
        count: 1, helped: 0, harmful: 0, measured: false, created_run: runId, project_id: trace.project_id, agent_id: trace.agent_id,
        user_id: trace.user_id, skill_target: skillTarget, scenario: lesson.situation, situation: lesson.situation,
        advice: lesson.advice, because: lesson.because, applies_to: `project:${trace.project_id}`, polarity: lesson.polarity,
        evidence, counter_examples: 'not searched' }]);
      result.lessons++;
      if (!staged && lesson.class === 'EXECUTION_LAPSE' && skillTarget && lesson.reminder_line?.trim()) {
        staged = stageReminder(store, config, runId, harness, page, lesson.reminder_line.trim(), log);
        if (staged) result.proposals++;
      }
    }
  }
  log.push(`local writer: ${result.asked} sessions asked; ${result.lessons} lessons; ${result.proposals} proposals`);
  return result;
}
