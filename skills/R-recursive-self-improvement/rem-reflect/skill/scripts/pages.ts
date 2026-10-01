import { reflectionFiles, isObject } from './config.ts';
import { message } from './text.ts';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { Evidence } from './evidence.ts';
import type { Trace } from './harvest.ts';
import type { Harness } from './identity.ts';
import type { Outcome } from './labeler.ts';
import { atomicWrite } from './store.ts';

export interface Scenario { task_type: string; trigger: string; tools: string[] }
export type CounterExamples = 'not searched' | { searched: boolean; [key: string]: unknown };
export interface Operation { op: 'append' | 'replace' | 'insert_after'; target?: string; text: string }
export interface PageFields {
  summary: string; class: 'SKILL_DEFECT' | 'EXECUTION_LAPSE';
  root_cause: { subject: string; relation: string; fact: string; valid_at: string; evidence_pages: string[]; evidence_traces: string[] };
  fix: string; scenario: Scenario; skills_used: string[]; skill_target: string | null; knowledge_used: string[];
  outcome: Outcome; agent_id: Harness; project_id: string; user_id: string; evidence: string[];
  citations: Evidence[]; counter_examples: CounterExamples; superseded: boolean;
  possible_duplicate_of?: string | null; solved_by?: string | null;
}
export interface Page extends PageFields { page_id: string; body: string; count: number; task_ids: string[]; last_seen: string; skills_observed: string[]; backend?: string; judgment_id?: string }
export function patchBody(body: string, ops: readonly Operation[], isNew: boolean = false): string {
  for (const operation of ops) {
    if (operation.op === 'append') { body += operation.text; continue; }
    if (isNew) throw new Error(message('newAppend'));
    const target = operation.target;
    if (!target || !body.includes(target)) throw new Error(message('patchSubstring'));
    const index = body.indexOf(target);
    const replacement = operation.op === 'insert_after' ? target + operation.text : operation.text;
    body = body.slice(0, index) + replacement + body.slice(index + target.length);
  }
  return body;
}

// JSON values on individual YAML fields form the store's canonical frontmatter format.
export function serializePage(page: Page): string {
  const { body, ...fields } = page;
  return `---\n${Object.entries(fields).map(([key, value]) => `${key}: ${JSON.stringify(value)}`).join('\n')}\n---\n${body}`;
}
export function parsePage(text: string): Page {
  const match = /^---\n([\s\S]*?)\n---\n([\s\S]*)$/.exec(text);
  if (!match) throw new Error(message('frontmatterMissing'));
  const fields: Record<string, unknown> = {};
  for (const line of match[1].split('\n')) {
    const separator = line.indexOf(': ');
    if (separator < 0) throw new Error(message('frontmatterInvalid'));
    fields[line.slice(0, separator)] = JSON.parse(line.slice(separator + 2));
  }
  if (typeof fields.page_id !== 'string' || typeof fields.summary !== 'string' || !Array.isArray(fields.citations)
    || !isObject(fields.root_cause) || typeof fields.root_cause.fact !== 'string' || typeof fields.count !== 'number'
    || typeof fields.last_seen !== 'string') throw new Error(message('storedPageInvalid'));
  return { ...fields, body: match[2] } as unknown as Page;
}
export function readPages(store: string): Page[] {
  const directory = join(store, reflectionFiles.pages);
  if (!existsSync(directory)) return [];
  return readdirSync(directory).filter(file => file.endsWith('.md')).sort().map(file => {
    const page = parsePage(readFileSync(join(directory, file), 'utf8'));
    if (`${page.page_id}.md` !== file) throw new Error(message('pageFilename'));
    return page;
  });
}
export function writePage(store: string, page: Page): void {
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]*$/.test(page.page_id)) throw new Error(message('pageIdInvalid'));
  atomicWrite(join(store, reflectionFiles.pages, `${page.page_id}.md`), serializePage(page));
}
export function citedTraces(page: Pick<Page, 'citations'>, traces: readonly Trace[]): Trace[] {
  const ids = new Set(page.citations.map(item => item.trace_id));
  return traces.filter(trace => ids.has(trace.trace_id));
}
export function renderIndex(pages: readonly Page[], traces: readonly Trace[]): string {
  return pages.map(page => {
    const skills = new Map<string, number>();
    for (const trace of citedTraces(page, traces)) for (const skill of trace.skills_loaded) skills.set(skill, (skills.get(skill) ?? 0) + 1);
    const top = [...skills].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0, 3).map(([skill]) => skill);
    return message('indexLine', { id: page.page_id, summary: page.summary, count: page.count, seen: page.last_seen,
      solved: page.solved_by ? message('solvedBy', { unit: page.solved_by }) : message('unsolved'), skills: top.join(', ') || message('none') });
  }).join('\n') + (pages.length ? '\n' : '');
}
