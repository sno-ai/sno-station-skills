import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { appendFileSync, existsSync, readFileSync, readdirSync } from 'node:fs';
import { basename, join } from 'node:path';
import type { Config } from './config.ts';
import { reflectionFiles, isObject, limits, skillRoots, stationCell, readStationSettings } from './config.ts';
import { installedCatalogue } from './catalogue.ts';
import { chunkRendering } from './chunk.ts';
import { traceKey } from './evidence.ts';
import { existingTraces } from './harvest.ts';
import type { Trace } from './harvest.ts';
import type { Label } from './labeler.ts';
import { readLabels } from './labeler.ts';
import { readLedger } from './ledger.ts';
import { appendLedger } from './ledger.ts';
import { appendRows, readLessonReads, readLessons, readLessonsShown } from './lessons.ts';
import { readPages, renderIndex, writePage } from './pages.ts';
import type { Page } from './pages.ts';
import { proposalSignature, validateProposal } from './proposer.ts';
import { loadRenderBudgets, renderTrace } from './render.ts';
import { readCalls } from './calls.ts';
import { skillImpact } from './report.ts';
import { lessonProject, observe } from './observe.ts';
import { atomicWrite, commitStore, writeJson } from './store.ts';

export interface CloudResponse {
  schema_version: 1;
  run_id: string;
  history_acknowledged: boolean;
  history_links: unknown[];
  halves: unknown[];
}

export function localConsent(): 'off' | 'metadata-only' | 'full' {
  const result = spawnSync('sno', ['station', 'consent'], { encoding: 'utf8' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr?.trim() || `sno station consent exited ${result.status}`);
  const level = result.stdout?.trim();
  if (level !== 'off' && level !== 'metadata-only' && level !== 'full') throw new Error(`sno station consent returned ${level}`);
  return level;
}

// R4 (first-prompt lookup) sends text only when its cell is `sno-gpu` and consent is `full`.
// Daily runs and verdicts instead share by mode, with consent enforced by sno rem. Throws when the
// consent level cannot be read; the caller reports that and sends nothing.
export function cloudStepGate(id: 'R4'): { send: true } | { send: false; reason: string } {
  const cell = stationCell(id);
  if (cell !== 'sno-gpu') return { send: false, reason: `${id} is ${cell} under this mode` };
  const consent = localConsent();
  return consent === 'full' ? { send: true } : { send: false, reason: `consent ${consent}` };
}

export function flushCloudVerdicts(store: string): { sent: number; pending: number; errors: string[] } {
  const newest = new Map<string, Record<string, unknown>>();
  for (const row of readLedger(store).filter(row => row.type === 'cloud-verdict' && typeof row.judgment_id === 'string')) {
    newest.set(String(row.judgment_id), row);
  }
  const pending = [...newest.values()].filter(row => row.status === 'pending');
  const errors: string[] = [];
  if (!pending.length) return { sent: 0, pending: 0, errors };
  let sent = 0;
  for (const row of pending) {
    const id = String(row.judgment_id);
    const verdict = String(row.verdict);
    const promoted = row.applies_to === 'general';
    try {
      if (readStationSettings().mode === 'local-first') break;
      const result = spawnSync('sno', ['rem', 'verdict', id, verdict, ...(promoted ? ['--all-projects'] : [])],
        { encoding: 'utf8' });
      if (result.error) throw result.error;
      if (result.status !== 0) throw new Error(result.stderr?.trim() || `sno rem verdict exited ${result.status}`);
      if (!result.stdout) throw new Error('cloud verdict: empty acknowledgment');
      const answer: unknown = JSON.parse(result.stdout);
      if (!isObject(answer) || answer.schema_version !== 1 || answer.judgment_id !== id
        || answer.verdict !== verdict || answer.acknowledged !== true
        || (promoted && answer.applies_to !== 'general')) throw new Error('cloud verdict: mismatched acknowledgment');
      appendLedger(store, { ...row, status: 'acked', ...(promoted ? { applies_to: answer.applies_to } : {}) });
      commitStore(store, `cloud verdict ${id}`);
      sent++;
    } catch (error) {
      const message = `cloud verdict ${id} send failed: ${String(error)}; local verdict unchanged, upload pending`;
      errors.push(message);
      const logPath = join(store, reflectionFiles.runLog);
      try { appendFileSync(logPath, `${message}\n`); }
      catch (logError) { errors.push(`cloud verdict ${id} log failed at ${logPath}: ${String(logError)}`); }
    }
  }
  return { sent, pending: pending.length - sent, errors };
}

export function buildCloudBatch(store: string, config: Config, runId: string, retained: readonly Trace[],
  labels: ReadonlyMap<string, Label>, includeHistory: boolean) {
  const selectedSessions = new Set(retained.map(trace => trace.session_id));
  const ledger = readLedger(store);
  const halves = (['claude-code', 'codex'] as const).map(harness => ({
    harness,
    sessions: retained.filter(trace => trace.agent_id === harness).map(trace => {
      const label = labels.get(traceKey(trace));
      if (!label || label.decision !== 'keep') throw new Error(`cloud batch: missing keep decision for ${trace.trace_id}`);
      const chunks = chunkRendering(trace.trace_id, renderTrace(trace, loadRenderBudgets()));
      return {
        trace_id: trace.trace_id, session_id: trace.session_id, project_id: trace.project_id, user_id: trace.user_id,
        version: trace.version, source_mtime_ms: trace.source_mtime, source_line_range: trace.source_line_range,
        skills_loaded: trace.skills_loaded, trivial: trace.trivial, local_outcome: label.outcome, local_reason: label.reason,
        chunks: chunks.map(chunk => ({ id: chunk.id, line_start: chunk.line_range[0], line_end: chunk.line_range[1], text: chunk.text })),
        calls: readCalls(trace),
      };
    }),
  })).filter(half => half.sessions.length > 0);
  return {
    schema_version: 1,
    run_id: runId,
    halves,
    catalogue: installedCatalogue(skillRoots(config)),
    usage_reads: readLessonReads(store, []).filter(read => selectedSessions.has(read.session_id)),
    usage_shown: readLessonsShown(store, []).filter(row => selectedSessions.has(row.session_id)),
    outcome_summary: { adopted_units: skillImpact(skillRoots(config), existingTraces(store, () => false), readLabels(store), ledger) },
    ...(includeHistory ? { history: {
      pages: readPages(store), lessons: readLessons(store),
      proposals: ledger.filter(row => row.type === 'proposal'),
      skill_impact_rows: ledger.filter(row => row.type !== 'proposal'),
    } } : {}),
  };
}

export function sendCloudBatch(store: string, batch: {
  schema_version: number; run_id: string; halves: unknown; catalogue: unknown; usage_reads: unknown; usage_shown: unknown; outcome_summary: unknown;
}, waitMs: number = limits.cloudWaitMs): CloudResponse {
  const staging = join(store, reflectionFiles.staging);
  const pending = readdirSync(staging).sort().find(id =>
    existsSync(join(staging, id, 'cloud-request.json')) && !existsSync(join(staging, id, 'cloud-response.json')));
  const directory = join(staging, pending ?? batch.run_id);
  const requestPath = join(directory, 'cloud-request.json');
  if (!pending) writeJson(requestPath, batch);
  // A half surrogate pair (from a session or an older truncation) is invalid JSON text for the sno CLI,
  // and a NUL (session text, older proposal signatures) is refused by the cloud's JSON column;
  // the same replacement on every send keeps a replayed request byte-identical.
  const sent: unknown = JSON.parse(readFileSync(requestPath, 'utf8'));
  const input = JSON.stringify(sent, (_key, value: unknown) =>
    typeof value === 'string' ? value.toWellFormed().replaceAll('\0', '') : value);
  if (!isObject(sent) || typeof sent.run_id !== 'string') throw new Error('cloud batch: pending request has no run id');

  const result = spawnSync('sno', ['rem', 'judge'], { input, encoding: 'utf8', maxBuffer: Infinity, timeout: waitMs, killSignal: 'SIGKILL' });
  if ((result.error as NodeJS.ErrnoException | undefined)?.code === 'ETIMEDOUT') {
    throw new Error(`sno rem judge gave no answer within ${Math.round(waitMs / 60_000)} minutes; the saved request is resent on the next run`);
  }
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr?.trim() || `sno rem judge exited ${result.status}`);
  if (!result.stdout) throw new Error('cloud batch: empty judgment response');
  const response: unknown = JSON.parse(result.stdout);
  if (!isObject(response) || response.schema_version !== 1 || response.run_id !== sent.run_id
    || typeof response.history_acknowledged !== 'boolean'
    || !Array.isArray(response.history_links) || !Array.isArray(response.halves)) {
    throw new Error('cloud batch: response does not match the pending run');
  }
  writeJson(join(directory, 'cloud-response.json'), response);
  return response as unknown as CloudResponse;
}

export function applyCloudHistoryLinks(store: string, links: readonly unknown[]): Set<string> {
  const linked = new Set(readLedger(store).flatMap(row => typeof row.judgment_id === 'string' ? [row.judgment_id] : []));
  for (const raw of links) {
    if (!isObject(raw) || typeof raw.kind !== 'string' || typeof raw.local_id !== 'string'
      || typeof raw.judgment_id !== 'string') throw new Error('cloud batch: invalid history link');
    if (linked.has(raw.judgment_id)) continue;
    appendLedger(store, { type: 'cloud-link', kind: raw.kind, local_id: raw.local_id, judgment_id: raw.judgment_id });
    linked.add(raw.judgment_id);
  }
  return linked;
}

export function applyCloudResponse(store: string, config: Config, response: CloudResponse): void {
  let userLessonsIssued = 0;
  const projectLessonsIssued = new Map<string, number>();
  const request: unknown = JSON.parse(readFileSync(join(store, reflectionFiles.staging, response.run_id, 'cloud-request.json'), 'utf8'));
  if (!isObject(request) || !Array.isArray(request.catalogue)) throw new Error('cloud batch: saved catalogue missing');
  const uploaded = new Map<string, string>();
  for (const entry of request.catalogue) {
    if (!isObject(entry) || typeof entry.path !== 'string' || typeof entry.skill_md !== 'string') throw new Error('cloud batch: saved catalogue invalid');
    uploaded.set(entry.path, entry.skill_md);
  }
  const linked = applyCloudHistoryLinks(store, response.history_links);
  const judged = new Set(readLedger(store).filter(row => row.type === 'lesson-judgment')
    .map(row => `${row.trace_id}::${row.lesson_id}`));
  for (const half of response.halves) {
    if (!isObject(half) || !['claude-code', 'codex'].includes(String(half.harness))
      || !Array.isArray(half.pages) || !Array.isArray(half.lessons) || !Array.isArray(half.proposals)
      || !Array.isArray(half.read_judgments)) {
      throw new Error('cloud batch: invalid half');
    }
    for (const item of half.pages) {
      if (!isObject(item) || typeof item.judgment_id !== 'string' || !isObject(item.page)
        || typeof item.page.page_id !== 'string') throw new Error('cloud batch: invalid page');
      const page = { ...item.page, judgment_id: item.judgment_id } as unknown as Page;
      // Judgment ids are UUIDv7 and sort by time: a replayed older or identical answer never overwrites a newer one.
      const stored = (readPages(store).find(row => row.page_id === page.page_id) as { judgment_id?: string } | undefined)?.judgment_id;
      if (stored && stored >= item.judgment_id) continue;
      writePage(store, page);
      if (page.superseded) {
        const accepted = readLessons(store).find(row => row.page_id === page.page_id && row.status === 'accepted');
        if (accepted) appendRows(join(store, reflectionFiles.lessons), [{ ...accepted, status: 'under_review' }]);
      }
    }
    for (const item of half.lessons) {
      if (!isObject(item) || typeof item.judgment_id !== 'string' || !isObject(item.lesson)
        || typeof item.lesson.lesson_id !== 'string') throw new Error('cloud batch: invalid lesson');
      const lesson = item.lesson;
      const current = readLessons(store).find(row => row.lesson_id === lesson.lesson_id);
      // A replayed cloud answer never undoes the owner's accept or reject, nor the scope chosen with it.
      if (current?.status === 'accepted' || current?.status === 'rejected') continue;
      if (!current?.judgment_id || current.judgment_id < item.judgment_id) {
        appendRows(join(store, reflectionFiles.lessons), [{ ...lesson, judgment_id: item.judgment_id }]);
        const project = lessonProject(lesson.applies_to, config);
        if (project === undefined) userLessonsIssued++;
        else projectLessonsIssued.set(project, (projectLessonsIssued.get(project) ?? 0) + 1);
      }
    }
    if (half.proposals.length > 1) throw new Error('cloud batch: more than one proposal in a half');
    for (const item of half.proposals) {
      if (!isObject(item) || typeof item.judgment_id !== 'string' || !isObject(item.proposal)) throw new Error('cloud batch: invalid proposal');
      if (linked.has(item.judgment_id)) continue;
      const roots = skillRoots(config);
      const target = typeof item.proposal.target === 'string' ? item.proposal.target.replace(/\/SKILL\.md$/, '') : '';
      const hashes: Record<string, string> = {};
      let validated: ReturnType<typeof validateProposal>;
      // A proposal this machine refuses is logged and skipped; the rest of the response still applies.
      try {
        validated = validateProposal(item.proposal, { store, roots, pages: readPages(store) }, new Set([target]));
        if (validated.kind === 'patch' && validated.target) {
          for (const root of roots) {
            const payload = join(root, basename(validated.target));
            const body = uploaded.get(join(payload, 'SKILL.md'));
            if (body) hashes[payload] = createHash('sha256').update(body).digest('hex');
          }
          if (!Object.keys(hashes).length) throw new Error('proposal target was not uploaded');
        }
      } catch (error) {
        appendFileSync(join(store, reflectionFiles.staging, response.run_id, reflectionFiles.runLog),
          `proposal refused: run ${response.run_id} half ${String(half.harness)} target ${target || '(none)'}: ${String(error)}\n`);
        continue;
      }
      const directory = join(store, reflectionFiles.staging, response.run_id, String(half.harness));
      writeJson(join(directory, reflectionFiles.proposal), { ...item.proposal, judgment_id: item.judgment_id, target_hashes: hashes });
      if (validated.kind === 'create') atomicWrite(join(directory, reflectionFiles.skillMd), validated.skillMd ?? '');
      if (validated.kind === 'patch') writeJson(join(directory, reflectionFiles.patch), {
        region: validated.region, ops: validated.ops ?? null, line: validated.reminderLine ?? null,
        replace_line: validated.replaceLine ?? null,
      });
      atomicWrite(join(directory, reflectionFiles.purpose), `${validated.proposal.purpose.summary}\nPages: ${validated.proposal.purpose.page_ids.join(', ')}\n`);
      const p = validated.proposal;
      appendLedger(store, { type: 'proposal', proposal_id: `${response.run_id}/${half.harness}`, run_id: response.run_id,
        half: half.harness, backend: 'sno-cloud', kind: validated.kind, target: validated.target, region: validated.region,
        diff: validated.diff, expertise: { scenario: p.scenario, skills_used: p.skills_used ?? [], skill_target: p.skill_target ?? null,
          knowledge_used: p.knowledge_used ?? [], outcome: p.outcome ?? 'unknown', evidence: p.evidence ?? [] },
        purpose: p.purpose, verdict: 'pending', evidence: p.evidence ?? [], signature: proposalSignature(p),
        judgment_id: item.judgment_id, target_hashes: hashes });
      linked.add(item.judgment_id);
    }
    const traces = new Map(existingTraces(store, () => false).map(trace => [trace.trace_id, trace]));
    const labels = readLabels(store);
    const reads = new Set(readLessonReads(store, []).map(read => `${read.session_id}::${read.lesson_id}`));
    for (const item of half.read_judgments) {
      if (!isObject(item) || typeof item.trace_id !== 'string' || typeof item.lesson_id !== 'string'
        || !['yes', 'no', 'unclear'].includes(String(item.followed))
        || !['helped', 'harmful', 'neutral'].includes(String(item.effect))) throw new Error('cloud batch: invalid read judgment');
      const trace = traces.get(item.trace_id);
      if (!trace || !reads.has(`${trace.session_id}::${item.lesson_id}`)) throw new Error('cloud batch: read judgment has no actual lesson read');
      const pair = `${item.trace_id}::${item.lesson_id}`;
      if (judged.has(pair)) continue;
      appendLedger(store, { type: 'lesson-judgment', trace_id: item.trace_id, lesson_id: item.lesson_id,
        followed: item.followed, effect: item.effect });
      judged.add(pair);
      const outcome = labels.get(traceKey(trace))?.outcome;
      if (item.followed !== 'yes' || !['helped', 'harmful'].includes(String(item.effect))
        || (outcome !== 'success' && outcome !== 'fail')) continue;
      const lesson = readLessons(store).find(row => row.lesson_id === item.lesson_id);
      if (!lesson) continue;
      appendRows(join(store, reflectionFiles.lessons), [{ ...lesson, measured: true,
        helped: lesson.helped + Number(item.effect === 'helped'),
        harmful: lesson.harmful + Number(item.effect === 'harmful') }]);
    }
  }
  atomicWrite(join(store, reflectionFiles.index), renderIndex(readPages(store), existingTraces(store, () => false)));
  observe('rsi.lesson', { level: 'user', count: userLessonsIssued },
    join(store, reflectionFiles.staging, response.run_id, reflectionFiles.runLog));
  for (const [project, count] of projectLessonsIssued) {
    observe('rsi.lesson', { level: 'project', project, count },
      join(store, reflectionFiles.staging, response.run_id, reflectionFiles.runLog));
  }
}
