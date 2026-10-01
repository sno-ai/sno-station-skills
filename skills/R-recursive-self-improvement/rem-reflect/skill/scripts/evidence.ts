import { message } from './text.ts';
import type { Trace } from './harvest.ts';
import { loadRenderBudgets, renderTrace } from './render.ts';

export interface Evidence { trace_id: string; line_start: number; line_end: number; quote: string }
export function sameSession(a: Trace, b: Trace): boolean {
  return a.session_id === b.session_id && a.user_id === b.user_id && a.agent_id === b.agent_id;
}
export function traceKey(trace: Trace): string { return `${trace.user_id}/${trace.agent_id}/${trace.trace_id}`; }
export function validateRange(trace: Trace, start: number, end: number): void {
  const lines = new Set(trace.records.map(record => record.line_number));
  if (!Number.isInteger(start) || !Number.isInteger(end) || start > end || !lines.has(start) || !lines.has(end)) {
    throw new Error(message('rangeOutside', { id: trace.trace_id }));
  }
}
export function validateEvidence(evidence: readonly Evidence[], traces: readonly Trace[]): void {
  for (const item of evidence) {
    const matches = traces.filter(trace => trace.trace_id === item.trace_id);
    if (matches.length !== 1) throw new Error(message('traceMissing', { id: item.trace_id }));
    const trace = matches[0];
    validateRange(trace, item.line_start, item.line_end);
    const text = renderTrace(trace, loadRenderBudgets()).records
      .filter(record => record.line_number >= item.line_start && record.line_number <= item.line_end)
      .map(record => record.text).join('');
    if (!item.quote || !text.includes(item.quote)) throw new Error(message('quoteAbsent', { id: item.trace_id }));
  }
}
