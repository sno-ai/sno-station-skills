import { reflectionFiles, limits, isObject } from './config.ts';
import { message } from './text.ts';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { BackendError } from './backend.ts';
import { CeilingReached } from './session.ts';
import type { Backend, Cli } from './backend.ts';
import type { Harness } from './identity.ts';
import { sameSession, traceKey, validateEvidence, validateRange } from './evidence.ts';
import type { Evidence } from './evidence.ts';
import type { Trace } from './harvest.ts';
import { checkContract, firstObject, reference } from './model-json.ts';
import { loadRenderBudgets, renderHeader, renderTrace, truncate } from './render.ts';
import { readCalls } from './calls.ts';
import { loadLocalSettings } from './local-settings.ts';
import { privateDirectory, writeJson } from './store.ts';

export type Outcome = 'success' | 'fail' | 'unknown';
export interface KeyRange { line_start: number; line_end: number; why: string }
export interface Label { decision: 'keep' | 'drop'; outcome: Outcome; reason: string; evidence: Evidence[]; key_ranges: KeyRange[]; labeled_by: string; model: string }
export interface LabelOutput extends Omit<Label, 'labeled_by' | 'model'> { notes: string }

export function labelPaths(store: string): Map<string, string> {
  const paths = new Map<string, string>();
  function walk(directory: string): void {
    if (!existsSync(directory)) return;
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) walk(path);
      else if (/\.v\d+\.json$/.test(entry.name)) {
        const trace: Trace = JSON.parse(readFileSync(path, 'utf8'));
        paths.set(traceKey(trace), path.replace(/\.json$/, '.label.json'));
      }
    }
  }
  walk(join(store, reflectionFiles.raw));
  return paths;
}
export function readLabels(store: string): Map<string, Label> {
  const labels = new Map<string, Label>();
  for (const [key, path] of labelPaths(store)) if (existsSync(path)) labels.set(key, JSON.parse(readFileSync(path, 'utf8')));
  return labels;
}
export function validateLabel(value: unknown, trace: Trace, earlier: readonly Trace[]): LabelOutput {
  checkContract(value, 'labeler');
  // The shipped contract checks the complete external shape before this assertion.
  const output = value as LabelOutput;
  validateEvidence(output.evidence, [trace, ...earlier]);
  for (const range of output.key_ranges) validateRange(trace, range.line_start, range.line_end);
  return output;
}
function previousHeader(trace: Trace, all: readonly Trace[], labels: ReadonlyMap<string, Label>): { traces: Trace[]; text: string } {
  const traces = all.filter(item => sameSession(trace, item) && item.version < trace.version).sort((a, b) => a.version - b.version);
  const previous = traces.map(item => ({ trace_id: item.trace_id,
    typed_lines: renderTrace(item, loadRenderBudgets()).records.filter(record => {
      if (record.harness_shaped) return false;
      const source = item.records.find(row => row.line_number === record.line_number);
      if (!source) return false;
      const payload = item.agent_id === 'codex' ? source.record.payload : source.record.message;
      if (!payload || typeof payload !== 'object' || !('role' in payload) || payload.role !== 'user') return false;
      const content = 'content' in payload ? payload.content : undefined;
      return typeof source.user_text === 'string' || typeof content === 'string'
        || (Array.isArray(content) && content.every(block => block && typeof block === 'object'
          && 'type' in block && ['text', 'input_text', 'output_text'].includes(String(block.type))));
    }),
    label: labels.get(traceKey(item)) ?? null }));
  return { traces, text: truncate(JSON.stringify(previous), limits.chunkCharacters) };
}
export function eventLines(trace: Trace): Set<number> {
  const lines = new Set(readCalls(trace).filter(call => call.failed).map(call => call.line_end));
  const rendered = renderTrace(trace, loadRenderBudgets());
  const records = new Map(trace.records.map(record => [record.line_number, record]));
  for (const row of rendered.records) {
    const item = records.get(row.line_number);
    const message = item?.record[trace.agent_id === 'codex' ? 'payload' : 'message'];
    if (!isObject(message) || message.role !== 'user' || row.harness_shaped) continue;
    if (Array.isArray(message.content) && message.content.some(block => isObject(block) && block.type === 'tool_result')) continue;
    lines.add(row.line_number);
  }
  return lines;
}

function labelTrace(trace: Trace, all: readonly Trace[], labels: ReadonlyMap<string, Label>, backend: Backend, cwd: string, cli: Cli,
  maxChars: number, windowLines: number): LabelOutput {
  const previous = previousHeader(trace, all, labels);
  const prefix = `${reference('labeler.md')}\n${reference('labeler.schema.json')}\n${renderHeader(trace)}\nprevious_versions: ${previous.text}\n`;
  const rendered = renderTrace(trace, loadRenderBudgets());
  const events = eventLines(trace);
  const ordered = [...events].sort((a, b) => a - b);
  let event = 0;
  const full = rendered.body.length + prefix.length <= maxChars;
  const selected = rendered.records.filter(row => {
    if (full || !ordered.length) return true;
    while (event < ordered.length && ordered[event] < row.line_number - windowLines) event++;
    return ordered[event] <= row.line_number + windowLines;
  });
  const inputs: string[] = [];
  let body = '';
  for (const row of selected) {
    const line = row.text.length > maxChars - prefix.length ? truncate(row.text, maxChars - prefix.length - 40) : row.text;
    if (body && prefix.length + body.length + line.length > maxChars) { inputs.push(prefix + body); body = ''; }
    body += line;
  }
  if (body || !inputs.length) inputs.push(prefix + body);
  const outputs: LabelOutput[] = [];
  for (const [index, input] of inputs.entries()) {
    writeJson(join(cwd, reflectionFiles.labelerInput), { trace_id: trace.trace_id, window: index, input });
    const stdout = backend.spawn({ cli, cwd, input, kind: 'labeler' }).stdout;
    writeJson(join(cwd, reflectionFiles.labelerOutput), { trace_id: trace.trace_id, window: index, stdout });
    try { outputs.push(validateLabel(firstObject(stdout), trace, previous.traces)); }
    catch (error) { throw new BackendError('labeler-invalid-response', String(error)); }
  }
  return { decision: outputs.some(output => output.decision === 'keep') ? 'keep' : 'drop',
    outcome: outputs.some(output => output.outcome === 'fail') ? 'fail'
      : outputs.some(output => output.outcome === 'success') ? 'success' : 'unknown',
    reason: outputs.map(output => output.reason).join('; '), notes: outputs.map(output => output.notes).join('; '),
    evidence: outputs.flatMap(output => output.evidence), key_ranges: outputs.flatMap(output => output.key_ranges) };
}
export interface LabelWrite { path: string; label: Label }
// Return every new decision for the caller to persist beside its trace before cloud upload.
// With `labelerOn` false no CLI runs: each pending session is kept with an unknown outcome, the same
// shape a failed labeler leaves, so the upload can still send it.
export function labelHalf(store: string, runId: string, half: Harness | null, cli: Cli | null, traces: readonly Trace[],
  backend: Backend, log: string[], allTraces: readonly Trace[] = traces, labelerOn = true): { labels: Map<string, Label>; writes: LabelWrite[] } {
  const working = readLabels(store);
  const targets = labelPaths(store);
  const labels = new Map<string, Label>();
  const writes: LabelWrite[] = [];
  const settings = loadLocalSettings(store, log);
  const pending = traces.filter(item => (half === null || item.agent_id === half) && !working.get(traceKey(item))?.decision)
    .map(trace => ({ trace, priority: eventLines(trace).size }))
    .sort((a, b) => b.priority - a.priority).map(item => item.trace);
  const available = new Map<Cli, boolean>();
  for (const trace of pending) {
    const selectedCli: Cli = cli ?? (trace.agent_id === 'codex' ? 'codex' : 'claude');
    const key = traceKey(trace);
    const path = targets.get(key);
    if (!path) throw new Error(message('rawPathMissing', { key }));
    let label: Label;
    if (!labelerOn) {
      label = { decision: 'keep', outcome: 'unknown', reason: 'labeler-off', evidence: [], key_ranges: [], labeled_by: '', model: '' };
      writes.push({ path, label });
      labels.set(key, label); working.set(key, label);
      continue;
    }
    const cwd = join(store, reflectionFiles.staging, runId, trace.agent_id);
    privateDirectory(cwd);
    if (!available.has(selectedCli)) available.set(selectedCli, !backend.preflight || backend.preflight(selectedCli, cwd));
    try {
      if (!available.get(selectedCli)) throw new BackendError('labeler-unavailable');
      const output = labelTrace(trace, allTraces, working, backend, cwd, selectedCli,
        settings.labeler_input_max_chars, settings.labeler_event_window_lines);
      const { notes: _notes, ...fields } = output;
      label = { ...fields, labeled_by: selectedCli, model: '' };
    } catch (error) {
      if (!(error instanceof BackendError) && !(error instanceof CeilingReached)) throw error;
      const reason = error instanceof BackendError ? error.reason : error.ceiling;
      label = { decision: 'keep', outcome: 'unknown', reason, evidence: [], key_ranges: [], labeled_by: selectedCli, model: '' };
      log.push(`${trace.trace_id}: ${label.reason}; labeler_${selectedCli}`);
    }
    writes.push({ path, label });
    labels.set(key, label); working.set(key, label);
  }
  return { labels, writes };
}
