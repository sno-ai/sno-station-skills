import { reflectionFiles, skillRoots } from './config.ts';
import type { Config } from './config.ts';
import { basename, join } from 'node:path';
import { message } from './text.ts';
import { payloadInfo } from './catalogue.ts';
import { traceKey } from './evidence.ts';
import { existingTraces } from './harvest.ts';
import type { Trace } from './harvest.ts';
import { readLabels } from './labeler.ts';
import type { Label } from './labeler.ts';
import { readLedger } from './ledger.ts';
import { readLessons } from './lessons.ts';
import { readPages } from './pages.ts';
import { observe } from './observe.ts';

const DAY = 86_400_000;
interface Counts { traces: number; fail: number; unknown: number }
function countsText(c: Counts): string { return `{traces: ${c.traces}, fail: ${c.fail}, unknown: ${c.unknown}}`; }

// count trace versions that load `payload` and whose session started in [lo, hi), split by
// the labeler's outcome. `skills_loaded` holds the resolved payload path, so matching on the adopted
// payload path picks the exact payload, not the unit directory or a sibling payload.
function countLoaded(traces: readonly Trace[], labels: ReadonlyMap<string, Label>, payloads: readonly string[], lo: number, hi: number): Counts {
  const counts: Counts = { traces: 0, fail: 0, unknown: 0 };
  for (const trace of traces) {
    if (trace.source_mtime < lo || trace.source_mtime >= hi || !payloads.some(payload => trace.skills_loaded.includes(payload))) continue;
    counts.traces++;
    const outcome = labels.get(traceKey(trace))?.outcome ?? 'unknown';
    if (outcome === 'fail') counts.fail++;
    if (outcome === 'unknown') counts.unknown++;
  }
  return counts;
}

export interface Adoption { unit: string; id: string; target: string; at: number }
// Every unit this loop adopted into: an Accepted skill proposal, or an accepted skill-scoped lesson.
export function adoptions(ledger: readonly Record<string, unknown>[]): Adoption[] {
  const result: Adoption[] = [];
  for (const row of ledger) {
    const at = typeof row.at === 'string' ? Date.parse(row.at) : NaN;
    if (row.type === 'verdict' && row.verdict === 'Accepted' && typeof row.target === 'string' && Number.isFinite(at)) {
      result.push({ unit: basename(row.target), id: String(row.proposal_id ?? ''), target: row.target, at });
    }
    if (row.type === 'lesson-verdict' && row.status === 'accepted' && row.adopted === true && typeof row.target === 'string' && Number.isFinite(at)) {
      result.push({ unit: basename(row.target), id: String(row.lesson_id ?? ''), target: row.target, at });
    }
  }
  return result;
}

// the Skill impact subsection and the proposer's outcome summary share this shape.
export function skillImpact(roots: readonly string[], traces: readonly Trace[], labels: ReadonlyMap<string, Label>,
  ledger: readonly Record<string, unknown>[]): { unit: string; id: string; loaded_before: Counts; loaded_after: Counts }[] {
  return adoptions(ledger).map(adoption => {
    const payloads = roots.map(root => join(root, adoption.unit));
    const name = payloads.map(path => payloadInfo(path).name).find(Boolean);
    return {
      unit: name || adoption.unit, id: adoption.id,
      loaded_before: countLoaded(traces, labels, payloads, adoption.at - 14 * DAY, adoption.at),
      loaded_after: countLoaded(traces, labels, payloads, adoption.at, Number.MAX_SAFE_INTEGER),
    };
  });
}

// The last verdict recorded for a proposal id, with the date it was set.
function lastVerdict(ledger: readonly Record<string, unknown>[], id: string): { verdict: string; at: number; had: Set<string> } | undefined {
  const rows = ledger.filter(row => row.type === 'verdict' && row.proposal_id === id);
  if (!rows.length) return undefined;
  const last = rows[rows.length - 1];
  return { verdict: String(last.verdict), at: typeof last.at === 'string' ? Date.parse(last.at) : 0, had: new Set(rows.map(row => String(row.verdict))) };
}

// a TBD proposal is flagged when, since its verdict, a page was created or patched whose
// skill_target is the unit or a `fail` trace lists the unit in skills_loaded.
function newEvidence(config: Config, traces: readonly Trace[], labels: ReadonlyMap<string, Label>,
  target: string, since: number, pages: readonly { skill_target: string | null; last_seen: string }[]): string[] {
  const ids: string[] = [];
  const targets = skillRoots(config).map(root => join(root, basename(target)));
  for (const trace of traces) {
    if (trace.source_mtime <= since || !targets.some(path => trace.skills_loaded.includes(path))) continue;
    if ((labels.get(traceKey(trace))?.outcome ?? 'unknown') === 'fail') ids.push(trace.trace_id);
  }
  for (const page of pages) {
    if (page.skill_target === target && Date.parse(page.last_seen) > since) ids.push('page');
  }
  return ids;
}

export interface ReportInput {
  store: string; config: Config; runId: string; notice: string; ceiling?: string | null;
  labelerLines: readonly string[]; harvested: number; reflectionReport: readonly string[];
}
export function buildReport(input: ReportInput): string {
  const { store, config } = input;
  const ledger = readLedger(store);
  const labels = readLabels(store);
  const traces = existingTraces(store, () => false);
  const lessons = readLessons(store);
  const pages = readPages(store).map(page => ({ skill_target: page.skill_target, last_seen: page.last_seen }));

  // TBD queue: proposals whose latest verdict is TBD, then lessons parked at tbd.
  const tbd: string[] = [];
  const proposalIds = [...new Set(ledger.filter(row => row.type === 'proposal').map(row => String(row.proposal_id)))];
  for (const id of proposalIds) {
    const last = lastVerdict(ledger, id);
    if (!last || last.verdict !== 'TBD') continue;
    const proposal = ledger.filter(row => row.type === 'proposal' && row.proposal_id === id).pop()!;
    const target = String(proposal.target ?? '');
    const ids = target ? newEvidence(config, traces, labels, target, last.at, pages) : [];
    tbd.push(message('tbdProposalLine', { id, kind: String(proposal.kind ?? ''), target,
      evidence: ids.length ? message('tbdNewEvidence', { ids: ids.join(', ') }) : '' }));
  }
  for (const lesson of lessons.filter(row => row.status === 'tbd')) {
    const reason = String(ledger.filter(row => row.type === 'lesson-verdict' && row.lesson_id === lesson.lesson_id).pop()?.reason ?? '');
    tbd.push(message('tbdLessonLine', { id: lesson.lesson_id, status: 'tbd', reason, evidence: '' }));
  }

  // Skill impact subsection.
  const impactRows = skillImpact(skillRoots(config), traces, labels, ledger);
  for (const row of new Map(impactRows.map(row => [row.unit, row])).values()) {
    observe('rsi.impact', { level: 'user', skill_name: row.unit,
      before_sessions: row.loaded_before.traces, before_failures: row.loaded_before.fail,
      after_sessions: row.loaded_after.traces, after_failures: row.loaded_after.fail,
    }, join(store, reflectionFiles.staging, input.runId, reflectionFiles.runLog));
  }
  const impact = impactRows.map(row =>
    message('skillImpactLine', { unit: row.unit, id: row.id, before: countsText(row.loaded_before), after: countsText(row.loaded_after) }));

  // Re-check list: proposals adopted then re-parked, and lessons under review.
  const recheck: string[] = [];
  for (const id of proposalIds) {
    const last = lastVerdict(ledger, id);
    if (last && last.verdict === 'TBD' && last.had.has('Accepted')) recheck.push(message('recheckProposal', { id, status: 'TBD' }));
  }
  for (const lesson of lessons.filter(row => row.status === 'under_review')) recheck.push(message('recheckLesson', { id: lesson.lesson_id }));

  // status block order: interruption notice, then the ceiling that stopped the run.
  const lines = [
    ...(input.notice ? [input.notice, ''] : []),
    ...(input.ceiling ? [message('ceilingStopped', { ceiling: input.ceiling }), ''] : []),
    `# Run ${input.runId}`, '',
    ...input.labelerLines, ...(input.labelerLines.length ? [''] : []),
    `Harvested trace versions: ${input.harvested}`, '',
    ...input.reflectionReport,
    message('tbdHeading'), ...(tbd.length ? tbd : [message('none')]), '',
    message('skillImpactHeading'), ...(impact.length ? impact : [message('none')]), '',
    message('recheckHeading'), ...(recheck.length ? recheck : [message('none')]), '',
  ];
  return lines.join('\n');
}
