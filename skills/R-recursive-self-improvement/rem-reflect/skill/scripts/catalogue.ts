import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

export interface CatalogueEntry { name: string; path: string }
export const REMINDERS_START = '<!-- reminders:start -->';
export const REMINDERS_END = '<!-- reminders:end -->';

function directories(path: string): string[] {
  if (!existsSync(path)) return [];
  return readdirSync(path, { withFileTypes: true }).filter(entry => entry.isDirectory()).map(entry => entry.name).sort();
}

export function readCatalogue(roots: readonly string[]): CatalogueEntry[] {
  const entries: CatalogueEntry[] = [];
  for (const root of roots) {
    for (const name of directories(root)) {
      const payload = join(root, name);
      const path = join(payload, 'SKILL.md');
      if (!existsSync(path)) continue;
      const frontmatter = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(readFileSync(path, 'utf8'));
      const field = frontmatter && /^name:\s*(.*?)\s*$/m.exec(frontmatter[1]);
      if (!field) throw new Error(`catalogue: missing name in ${path}`);
      entries.push({ name: field[1].replace(/^(['"])(.*)\1$/, '$2'), path: payload });
    }
  }
  return entries;
}

export interface CloudCatalogueEntry {
  path: string; name: string; description: string; sealed: boolean; skill_md: string;
}

export function installedCatalogue(roots: readonly string[]): CloudCatalogueEntry[] {
  return readCatalogue(roots).map(entry => {
    const path = join(entry.path, 'SKILL.md');
    const skill_md = readFileSync(path, 'utf8');
    return { path, ...frontmatter(skill_md), sealed: existsSync(`${path}.sha256`), skill_md };
  });
}

export function resolveSkill(name: string, catalogue: readonly CatalogueEntry[]): string {
  return catalogue.find(entry => entry.name === name)?.path ?? `unresolved:${name}`;
}

export function frontmatter(text: string): { name: string; description: string } {
  const match = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(text);
  const body = match ? match[1] : '';
  const field = (key: string): string => {
    const m = new RegExp(`^${key}:\\s*(.*?)\\s*$`, 'm').exec(body);
    return m ? m[1].replace(/^(['"])(.*)\1$/, '$2') : '';
  };
  return { name: field('name'), description: field('description') };
}

export function remindersRegion(text: string): string[] | null {
  const start = text.indexOf(REMINDERS_START);
  const end = text.indexOf(REMINDERS_END);
  if (start < 0 || end < 0 || end < start) return null;
  return text.slice(start + REMINDERS_START.length, end).split('\n').map(line => line.trim()).filter(Boolean);
}

export interface PayloadInfo {
  path: string; exists: boolean;
  text: string; name: string; description: string; reminders: string[] | null;
}
// Read an installed payload's SKILL.md and the facts the validator needs.
export function payloadInfo(payloadPath: string): PayloadInfo {
  const absolute = payloadPath.replace(/\/SKILL\.md$/, '');
  const skillMdPath = join(absolute, 'SKILL.md');
  const exists = existsSync(skillMdPath);
  const text = exists ? readFileSync(skillMdPath, 'utf8') : '';
  const fm = exists ? frontmatter(text) : { name: '', description: '' };
  return {
    path: absolute, exists,
    text, name: fm.name, description: fm.description,
    reminders: exists ? remindersRegion(text) : null,
  };
}

