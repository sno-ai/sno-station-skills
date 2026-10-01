// Local validation of cloud-authored skill proposals.
import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { sizeCaps } from './config.ts';
import { message } from './text.ts';
import { frontmatter, payloadInfo, readCatalogue, remindersRegion, REMINDERS_START, REMINDERS_END } from './catalogue.ts';
import type { PayloadInfo } from './catalogue.ts';
import { proposerLedger, unifiedDiff } from './ledger.ts';
import { reference, validateSchema } from './model-json.ts';
import { patchBody } from './pages.ts';
import type { Page } from './pages.ts';

const CREATE_UNIT = /^[a-z0-9][a-z0-9-]{1,40}$/;
const EXPERTISE_FIELDS = ['task_type', 'trigger'] as const;

export interface Proposal {
  kind: 'create' | 'patch' | 'no_action'; target?: string; region?: 'body' | 'reminders';
  class?: string; purpose: { summary: string; page_ids: string[] };
  scenario?: { task_type: string; trigger: string; tools: string[] };
  skills_used?: string[]; skill_target?: string | null; knowledge_used?: string[]; outcome?: string;
  evidence?: string[]; skill_md?: string; ops?: { op: string; target?: string; text: string }[];
  line?: string; replace_line?: string;
}
export interface Validated {
  kind: 'create' | 'patch' | 'no_action'; target: string | null; region: 'body' | 'reminders' | null;
  skillMd?: string; newBytes?: string; reminderLine?: string; replaceLine?: string;
  ops?: Proposal['ops']; diff: string; proposal: Proposal; targetHashes?: Record<string, string>;
}

const norm = (s: string): string => s.replace(/\s+/g, ' ').trim();
// Joins the fields of a proposal signature. A NUL byte would also work, but it makes `file` report
// the source as binary and makes grep skip this whole file, which silently hides it from searches.
const SEPARATOR = ' \u2020 ';
// A content signature for byte-identical content after whitespace normalisation: each text
// piece is normalised on its own, so indentation or trailing-space differences do not matter.
export function proposalSignature(p: Proposal): string {
  if (p.kind === 'no_action') return `no_action \u2020 ${norm(p.purpose?.summary ?? '')}`;
  const parts: string[] = [p.kind, p.target ?? '', p.region ?? ''];
  if (p.skill_md !== undefined) parts.push('skill_md', norm(p.skill_md));
  for (const op of p.ops ?? []) parts.push(op.op, norm(op.target ?? ''), norm(op.text));
  if (p.line !== undefined) parts.push('line', norm(p.line));
  if (p.replace_line !== undefined) parts.push('replace_line', norm(p.replace_line));
  return parts.join(SEPARATOR);
}

export function applyReminders(text: string, line: string, replaceLine: string | undefined): string {
  const start = text.indexOf(REMINDERS_START);
  const end = text.indexOf(REMINDERS_END);
  if (start < 0 || end < 0) {
    // adoption creates the markers at the end; model the same shape for the growth check
    const suffix = text.endsWith('\n') ? '' : '\n';
    return `${text}${suffix}${REMINDERS_START}\n${line}\n${REMINDERS_END}\n`;
  }
  const inner = text.slice(start + REMINDERS_START.length, end);
  const lines = inner.split('\n');
  if (replaceLine !== undefined) {
    const idx = lines.findIndex(l => l.trim() === replaceLine.trim());
    if (idx < 0) throw new Error(message('replaceLineMissing'));
    lines[idx] = lines[idx].replace(replaceLine, line);
  } else {
    lines.splice(lines.length - 1, 0, line);
  }
  return text.slice(0, start + REMINDERS_START.length) + lines.join('\n') + text.slice(end);
}

function countPatch(body: string, ops: Proposal['ops']): void {
  for (const op of ops ?? []) {
    if (op.op === 'append') continue;
    const target = op.target ?? '';
    const occurrences = target ? body.split(target).length - 1 : 0;
    if (occurrences !== 1) throw new Error(message('targetCount', { count: occurrences }));
  }
}

export function validateProposal(raw: unknown, ctx: { store: string; roots: readonly string[]; pages: readonly Page[] }, servedSkillReads: ReadonlySet<string>): Validated {
  const schema: unknown = JSON.parse(reference('proposal.schema.json'));
  validateSchema(raw, schema, '$', schema);
  const p = raw as Proposal;
  if (p.kind === 'no_action') return { kind: 'no_action', target: null, region: null, diff: '', proposal: p };

  if (!p.purpose.page_ids.length) throw new Error(message('missingPurposePage'));
  for (const field of EXPERTISE_FIELDS) {
    if (!p.scenario || !p.scenario[field] || !p.scenario[field].trim()) throw new Error(message('missingExpertise', { field }));
  }
  const { rejected } = proposerLedger(ctx.store);
  const signature = proposalSignature(p);
  const clash = rejected.find(row => typeof row.signature === 'string' && row.signature === signature);
  if (clash) throw new Error(message('rejectedRepeat', { id: String(clash.proposal_id ?? clash.run_id ?? '') }));

  const targetPath = (p.target ?? '').replace(/\/SKILL\.md$/, '');
  if (p.kind === 'create') {
    const unit = targetPath;
    if (!CREATE_UNIT.test(unit)) throw new Error(message('createTargetPath'));
    if (ctx.roots.some(root => existsSync(join(root, unit)))) throw new Error(message('createUnitExists', { path: unit }));
    if (typeof p.skill_md !== 'string' || !p.skill_md.trim()) throw new Error(message('createFrontmatter', { why: 'no skill_md' }));
    const fm = frontmatter(p.skill_md);
    if (fm.name !== unit) throw new Error(message('createFrontmatter', { why: 'name must equal the unit' }));
    if (!fm.description.trim()) throw new Error(message('createFrontmatter', { why: 'empty description' }));
    const fmBlock = /^---\r?\n([\s\S]*?)\r?\n---/.exec(p.skill_md)?.[1] ?? '';
    for (const key of ['name', 'description']) if ((fmBlock.match(new RegExp(`^${key}:`, 'mg')) ?? []).length !== 1) throw new Error(message('createFrontmatter', { why: `duplicate or missing ${key}` }));
    const nameClash = readCatalogue(ctx.roots).some(entry => entry.name === unit);
    if (nameClash) throw new Error(message('createNameExists', { name: unit }));
    const diff = unifiedDiff('', p.skill_md, `${unit}/SKILL.md`);
    return { kind: 'create', target: targetPath, region: null, skillMd: p.skill_md, newBytes: p.skill_md, diff, proposal: p };
  }

  // patch
  const info: PayloadInfo = payloadInfo(targetPath);
  if (!ctx.roots.some(root => resolve(dirname(targetPath)) === resolve(root)) || !info.exists) throw new Error(message('patchTargetPath'));
  if (!servedSkillReads.has(targetPath)) throw new Error(message('patchNeedsRead', { target: targetPath }));
  const region: 'body' | 'reminders' = p.region === 'reminders' ? 'reminders' : 'body';
  // region must agree with the cited page class
  const cited = ctx.pages.filter(page => p.purpose.page_ids.includes(page.page_id));
  for (const page of cited) {
    const want = page.class === 'SKILL_DEFECT' ? 'body' : 'reminders';
    if (want !== region) throw new Error(message('regionMismatch', { region, cls: page.class }));
  }
  let newBytes: string;
  if (region === 'body') {
    countPatch(info.text, p.ops);
    newBytes = patchBody(info.text, (p.ops ?? []) as { op: 'append' | 'replace' | 'insert_after'; target?: string; text: string }[], false);
  } else {
    const line = p.line ?? '';
    if (!line.trim()) throw new Error(message('missingExpertise', { field: 'line' }));
    const current = info.reminders ?? [];
    if (current.some(existing => existing.replace(/\s+/g, ' ').trim() === line.replace(/\s+/g, ' ').trim())) throw new Error(message('reminderDuplicate'));
    newBytes = applyReminders(info.text, line, p.replace_line);
    const region2 = remindersRegion(newBytes) ?? [];
    if (region2.length > sizeCaps.reminderLines) throw new Error(message('growReminders', { cap: sizeCaps.reminderLines }));
  }
  // name must not be renamed or removed
  if (frontmatter(newBytes).name !== info.name) throw new Error(message('nameRename'));
  // SKILL.md line-growth and description-growth caps
  const grow = newBytes.split('\n').length - info.text.split('\n').length;
  if (grow > sizeCaps.skillMdLines) throw new Error(message('growLines', { cap: sizeCaps.skillMdLines }));
  if (frontmatter(newBytes).description.length - info.description.length > sizeCaps.descriptionChars) throw new Error(message('growDescription', { cap: sizeCaps.descriptionChars }));
  return {
    kind: 'patch', target: targetPath, region, newBytes,
    reminderLine: region === 'reminders' ? p.line : undefined, replaceLine: p.replace_line, ops: p.ops,
    diff: unifiedDiff(info.text, newBytes, `${targetPath}/SKILL.md`), proposal: p,
    targetHashes: Object.fromEntries(ctx.roots.flatMap(root => {
      const path = join(root, basename(targetPath));
      const sibling = payloadInfo(path);
      return sibling.exists ? [[path, createHash('sha256').update(sibling.text).digest('hex')]] : [];
    })),
  };
}
