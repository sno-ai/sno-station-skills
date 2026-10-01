import { sameSession } from './evidence.ts';
import type { Trace } from './harvest.ts';
import type { Harness } from './identity.ts';

const THREE_DAYS = 3 * 86_400_000;

export interface EligiblePool {
  halves: Record<Harness, Trace[]>;
  superseded: Trace[];
  expired: Trace[];
}

export function eligibleTraces(traces: readonly Trace[], now: number): EligiblePool {
  const newest = traces.filter(trace => !traces.some(other => sameSession(trace, other) && other.version > trace.version));
  const selected = new Set(newest);
  const halves: EligiblePool['halves'] = { 'claude-code': [], codex: [] };
  const expired: Trace[] = [];
  for (const trace of newest) {
    if (trace.source_mtime <= now - THREE_DAYS) expired.push(trace);
    else halves[trace.agent_id].push(trace);
  }
  return { halves, expired, superseded: traces.filter(trace => !selected.has(trace)) };
}
