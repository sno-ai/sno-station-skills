import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { isObject, paths } from './config.ts';

const resource: unknown = JSON.parse(readFileSync(join(paths.references, 'text.json'), 'utf8'));
if (!isObject(resource) || !Object.values(resource).every(value => typeof value === 'string')) throw new Error('text.json');
const messages = resource;
export function message(key: string, values: Record<string, string | number> = {}): string {
  const template = messages[key];
  if (typeof template !== 'string') throw new Error(`text.json:${key}`);
  return template.replace(/\{(\w+)\}/g, (_match: string, name: string) => {
    if (!(name in values)) throw new Error(`text.json:${key}:${name}`);
    return String(values[name]);
  });
}
