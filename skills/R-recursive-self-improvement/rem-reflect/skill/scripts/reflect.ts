import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { applyCloudResponse, buildCloudBatch, cloudStepGate, sendCloudBatch } from './cloud.ts';
import type { CloudResponse } from './cloud.ts';
import { isObject, reflectionFiles, SettingsUnavailable, stationCell } from './config.ts';
import type { Config } from './config.ts';
import type { Backend } from './backend.ts';
import { traceKey } from './evidence.ts';
import { existingTraces } from './harvest.ts';
import { labelHalf, readLabels } from './labeler.ts';
import { saveLocalSettings } from './local-settings.ts';
import { readLedger } from './ledger.ts';
import { readLessons } from './lessons.ts';
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
  // Sno Station's R2 (label sessions) and R3 (nightly upload) cells and the one consent decide the night:
  // labels only serve the upload, so nothing is labeled or sent unless the upload will go.
  let upload: ReturnType<typeof cloudStepGate>;
  let labelerOn = false;
  try { labelerOn = stationCell('R2') === 'host'; upload = cloudStepGate('R3'); }
  catch (error) {
    if (!(error instanceof SettingsUnavailable)) throw error;
    upload = { send: false, reason: error.message };
  }
  log.push(`R2 labeling ${upload.send && labelerOn ? 'runs' : 'off'}; R3 upload ${upload.send ? 'sends' : `skipped: ${upload.reason}`}`);
  if (eligible.length && upload.send) {
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
    applyCloudResponse(store, config, response);
    historyAcknowledged ||= response.history_acknowledged;
    const request = JSON.parse(readFileSync(join(staging, id, 'cloud-request.json'), 'utf8'));
    for (const half of request.halves) for (const session of half.sessions) {
      acknowledged.add(`${half.harness}/${session.session_id}/${session.version}`);
    }
  }

  if (!upload.send) {
    observe('rsi.proposal', { level: 'user', proposal_count: 0, skills_touched: 0 }, join(staging, runId, reflectionFiles.runLog));
    return { failed: false, report: [...counts, 'Uploaded: 0', `No-upload: ${upload.reason}`] };
  }

  let uploaded = 0;
  const responses: CloudResponse[] = [];
  for (;;) {
    const remaining = retained.filter(trace => !acknowledged.has(`${trace.agent_id}/${trace.session_id}/${trace.version}`));
    const pending = readdirSync(staging).some(id =>
      existsSync(join(staging, id, 'cloud-request.json')) && !existsSync(join(staging, id, 'cloud-response.json')));
    if (!pending && !remaining.length) break;
    const batch = buildCloudBatch(store, config, runId, remaining, labels, !historyAcknowledged);
    const response = sendCloudBatch(store, batch);
    try { saveLocalSettings(store, response); }
    catch (error) { log.push(`local settings not saved: ${String(error)}`); }
    applyCloudResponse(store, config, response);
    responses.push(response);
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
  return { failed: false, report: [...counts, `Uploaded: ${uploaded}`,
    `Cloud-ranked: ${attention.filter(row => row.basis === 'jev').length}`,
    `Local-order fallback: ${attention.filter(row => row.basis === 'local-fallback').length}`,
    'Attention order:', ...attention.map(row =>
      `${row.trace_id}: predicted ${row.jev_outcome ?? 'unscored'}; fail probability ${row.fail_probability ?? 'unscored'}; local ${localOutcome.get(String(row.trace_id))} (${row.basis === 'jev' ? 'cloud' : row.basis})`),
    `Pages written: ${pages.length}`, ...pages,
    `Lessons eligible for decision: ${lessons.length}`, ...lessons.flatMap(lesson => [
      `${lesson.lesson_id}: ${lesson.advice}`,
      `rem-reflect accept ${lesson.lesson_id}`,
      `rem-reflect accept ${lesson.lesson_id} --all-projects`,
    ]),
    `Pending decisions: ${proposals.length + lessons.length}`,
    ...proposals.map(row => `${row.proposal_id}: ${row.target} — ${isObject(row.purpose) ? row.purpose.summary : ''}`),
    `Evidence: ${evidence.join(', ') || 'none'}`,
    ...lines, ...(!lines.length ? ['No new sessions or cloud judgments today'] : [])] };
}
