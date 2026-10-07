import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { applyCloudHistoryLinks, applyCloudResponse, buildCloudBatch, sendCloudBatch } from './cloud.ts';
import type { CloudResponse } from './cloud.ts';
import { isObject, reflectionFiles, SettingsUnavailable, stationCell, readStationSettings } from './config.ts';
import type { Config } from './config.ts';
import type { Backend } from './backend.ts';
import { traceKey } from './evidence.ts';
import { existingTraces } from './harvest.ts';
import { labelHalf, readLabels } from './labeler.ts';
import { writeLocally } from './local-writer.ts';
import { saveLocalSettings } from './local-settings.ts';
import { readLedger } from './ledger.ts';
import { readLessons } from './lessons.ts';
import type { Lesson } from './lessons.ts';
import { eligibleTraces } from './sampling.ts';
import { writeJson } from './store.ts';
import { observe } from './observe.ts';

export interface Reflection { failed: boolean; report: string[] }

export function reflect(store: string, config: Config, runId: string, backend: Backend, log: string[], now: Date): Reflection {
  // Only tonight's sessions (and their earlier versions, which the labeler reads) keep their text.
  const tonight = eligibleTraces(existingTraces(store, () => false), now.getTime());
  const tonightSessions = new Set(Object.values(tonight.halves).flat().map(trace => `${trace.user_id}/${trace.agent_id}/${trace.session_id}`));
  const traces = existingTraces(store, trace => tonightSessions.has(`${trace.user_id}/${trace.agent_id}/${trace.session_id}`));
  const pool = eligibleTraces(traces, now.getTime());
  const labels = readLabels(store);
  const eligible = Object.values(pool.halves).flat();
  // The mode controls sharing; sno rem enforces consent itself. R2 still selects the local labeler.
  let mode: ReturnType<typeof readStationSettings>['mode'] | undefined;
  let reason = '';
  let labelerOn = false;
  try { mode = readStationSettings().mode; labelerOn = stationCell('R2') === 'host'; }
  catch (error) {
    if (!(error instanceof SettingsUnavailable)) throw error;
    reason = error.message;
  }
  const upload = mode === 'agent-native' || mode === 'rem-enhanced';
  const enhanced = mode === 'rem-enhanced';
  if (mode === 'local-first') reason = 'local-first mode';
  log.push(`R2 labeling ${upload && labelerOn ? 'runs' : 'off'}; R3 upload ${upload ? 'sends' : `skipped: ${reason}`}`);
  if (eligible.length && upload) {
    const result = labelHalf(store, runId, null, null, eligible, backend, log, traces, labelerOn);
    for (const [key, label] of result.labels) labels.set(key, label);
    for (const write of result.writes) writeJson(write.path, write.label);
  }
  const retained = eligible.filter(trace => labels.get(traceKey(trace))?.decision !== 'drop');
  const dropped = eligible.length - retained.length;
  for (const trace of pool.expired) log.push(`${trace.trace_id}: expired unknown`);
  for (const trace of pool.superseded) log.push(`${trace.trace_id}: superseded by newer version`);
  const counts = [`Kept: ${retained.length}`, `Dropped: ${dropped}`, `Expired: ${pool.expired.length}`];

  const staging = join(store, reflectionFiles.staging);
  const acknowledged = new Set<string>();
  let historyAcknowledged = false;
  const saved = readdirSync(staging).sort().filter(id => existsSync(join(staging, id, 'cloud-response.json')));
  for (const id of saved) {
    const response: CloudResponse = JSON.parse(readFileSync(join(staging, id, 'cloud-response.json'), 'utf8'));
    if (enhanced) applyCloudResponse(store, config, response);
    else if (mode === 'agent-native') {
      try { applyCloudHistoryLinks(store, response.history_links); }
      catch (error) { log.push(`cloud run ${response.run_id} history links not saved: ${String(error)}; local report unchanged`); }
    }
    historyAcknowledged ||= response.history_acknowledged;
    const request = JSON.parse(readFileSync(join(staging, id, 'cloud-request.json'), 'utf8'));
    for (const half of request.halves) for (const session of half.sessions) {
      acknowledged.add(`${half.harness}/${session.session_id}/${session.version}`);
    }
  }

  if (!upload) {
    // Local First still does the nightly work: each chosen session's own CLI writes lessons and a reminder proposal here.
    const local = mode === 'local-first' ? writeLocally(store, config, runId, retained, backend, log, now) : undefined;
    const lessons = readLessons(store).filter(lesson => lesson.status === 'candidate' && lesson.listed === true);
    const proposals = readLedger(store).filter(row => row.type === 'proposal' && row.verdict === 'pending');
    observe('rsi.proposal', { level: 'user', proposal_count: local?.proposals ?? 0, skills_touched: local?.proposals ?? 0 },
      join(staging, runId, reflectionFiles.runLog));
    return { failed: false, report: [...counts, 'Uploaded: 0', `No-upload: ${reason}`,
      ...(local ? [`Local sessions asked: ${local.asked}`, `New lessons: ${local.lessons}`, `New proposals: ${local.proposals}`] : []),
      ...log.filter(line => line.startsWith('local writer:')),
      ...decisionLines(lessons, proposals)] };
  }

  const requestPath = join(staging, runId, 'cloud-request.json');
  if (!existsSync(requestPath)) {
    try {
      writeJson(requestPath, buildCloudBatch(store, config, runId,
        retained.filter(trace => !acknowledged.has(`${trace.agent_id}/${trace.session_id}/${trace.version}`)), labels, !historyAcknowledged));
    } catch (error) { log.push(`cloud run ${runId} request not saved: ${String(error)}; local run and report unchanged`); }
  }

  let uploaded = 0;
  const responses: CloudResponse[] = [];
  let currentAcknowledged = saved.includes(runId);
  for (;;) {
    const remaining = retained.filter(trace => !acknowledged.has(`${trace.agent_id}/${trace.session_id}/${trace.version}`));
    const pending = readdirSync(staging).some(id =>
      existsSync(join(staging, id, 'cloud-request.json')) && !existsSync(join(staging, id, 'cloud-response.json')));
    if (!pending && currentAcknowledged) break;
    let response: CloudResponse;
    try {
      const batch = buildCloudBatch(store, config, runId, remaining, labels, !historyAcknowledged);
      response = sendCloudBatch(store, batch);
    } catch (error) {
      const pendingRun = readdirSync(staging).sort().find(id =>
        existsSync(join(staging, id, 'cloud-request.json')) && !existsSync(join(staging, id, 'cloud-response.json')));
      log.push(`cloud run ${pendingRun ?? runId} send failed: ${String(error)}; local run and report unchanged`);
      break;
    }
    currentAcknowledged ||= response.run_id === runId;
    if (enhanced) {
      try { saveLocalSettings(store, response); }
      catch (error) { log.push(`local settings not saved: ${String(error)}`); }
      applyCloudResponse(store, config, response);
      responses.push(response);
    } else {
      try { applyCloudHistoryLinks(store, response.history_links); }
      catch (error) { log.push(`cloud run ${response.run_id} history links not saved: ${String(error)}; local report unchanged`); }
    }
    log.push(`cloud run ${response.run_id} sent`);
    historyAcknowledged ||= response.history_acknowledged;
    const sent = JSON.parse(readFileSync(join(staging, response.run_id, 'cloud-request.json'), 'utf8'));
    for (const half of sent.halves) for (const session of half.sessions) {
      uploaded++;
      acknowledged.add(`${half.harness}/${session.session_id}/${session.version}`);
    }
  }
  const halves = responses.flatMap(response => response.halves as Record<string, unknown>[]);
  const attention = halves.flatMap(half => Array.isArray(half.attention) ? half.attention as Record<string, unknown>[] : []);
  const lines = halves.map(half => String(half.log_entry ?? '')).filter(Boolean);
  const pages = halves.flatMap(half => Array.isArray(half.pages) ? half.pages : []).filter(isObject)
    .map(item => isObject(item.page) ? `${item.page.page_id}: ${item.page.summary}` : '').filter(Boolean);
  const lessons = readLessons(store).filter(lesson => lesson.status === 'candidate' && lesson.listed === true);
  const proposals = readLedger(store).filter(row => row.type === 'proposal' && row.verdict === 'pending');
  const currentProposals = proposals.filter(row => row.run_id === runId);
  observe('rsi.proposal', { level: 'user', proposal_count: currentProposals.length,
    skills_touched: new Set(currentProposals.map(row => row.target)).size }, join(staging, runId, reflectionFiles.runLog));
  const evidence = responses.map(response => join(staging, response.run_id, 'cloud-request.json'));
  const localOutcome = new Map(traces.map(trace => [trace.trace_id, labels.get(traceKey(trace))?.outcome]));
  // The cloud's response names its ranking basis and predicted outcome with its own wire names ('jev', jev_outcome); the report prints "cloud".
  return { failed: false, report: [...counts,
    'Local session outcomes:', ...retained.map(trace => `${trace.trace_id}: ${labels.get(traceKey(trace))?.outcome ?? 'unknown'}`),
    ...(enhanced && responses.length ? [`Uploaded: ${uploaded}`,
    `Cloud-ranked: ${attention.filter(row => row.basis === 'jev').length}`,
    `Local-order fallback: ${attention.filter(row => row.basis === 'local-fallback').length}`,
    'Attention order:', ...attention.map(row =>
      `${row.trace_id}: predicted ${row.jev_outcome ?? 'unscored'}; fail probability ${row.fail_probability ?? 'unscored'}; local ${localOutcome.get(String(row.trace_id))} (${row.basis === 'jev' ? 'cloud' : row.basis})`),
    `Pages written: ${pages.length}`, ...pages] : []),
    ...decisionLines(lessons, proposals),
    ...(enhanced && responses.length ? [`Evidence: ${evidence.join(', ') || 'none'}`, ...lines] : [])] };
}

// What waits for the owner: listed lessons with their accept commands, and staged proposals.
function decisionLines(lessons: readonly Lesson[], proposals: readonly Record<string, unknown>[]): string[] {
  return [`Lessons eligible for decision: ${lessons.length}`, ...lessons.flatMap(lesson => [
    `${lesson.lesson_id}: ${lesson.advice}`,
    `sno rem-reflect accept ${lesson.lesson_id}`,
    `sno rem-reflect accept ${lesson.lesson_id} --all-projects`,
  ]),
  `Pending decisions: ${proposals.length + lessons.length}`,
  ...proposals.map(row => `${row.proposal_id}: ${row.target} — ${isObject(row.purpose) ? row.purpose.summary : ''}`)];
}
