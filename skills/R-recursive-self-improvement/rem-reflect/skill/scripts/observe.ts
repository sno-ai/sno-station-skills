import { execFileSync } from 'node:child_process';
import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { isObject, reflectionFiles, storePath } from './config.ts';
import type { Config } from './config.ts';

export function lessonProject(appliesTo: unknown, config: Config): string | undefined {
  if (typeof appliesTo !== 'string' || !appliesTo.startsWith('project:') || appliesTo === 'project:user-level') return undefined;
  const id = appliesTo.slice('project:'.length);
  return Object.entries(config.project_names).find(([, name]) => name === id)?.[0] ?? id;
}

export function observe(eventType: string, fields: Record<string, string | number | boolean>,
  logPath: string = join(storePath(), reflectionFiles.runLog)): void {
  try {
    const agent = process.env.CLAUDECODE !== undefined ? 'claude-code' : 'codex';
    execFileSync('sno-observe', ['append', eventType, `--agent=${agent}`,
      ...Object.entries(fields).map(([key, value]) => `--${key}=${value}`)], { stdio: 'ignore' });
  } catch (error) {
    const reason = isObject(error) && error.code === 'ENOENT' ? 'sno-observe: not found' : String(error);
    try {
      mkdirSync(dirname(logPath), { recursive: true });
      appendFileSync(logPath, `${eventType}: ${reason.replace(/[\r\n]+/g, ' ')}\n`);
    } catch { /* An unavailable log must not change the command's result or output. */ }
  }
}
