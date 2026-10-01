import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export interface Config {
  claude_home: string;
  codex_home: string;
  claude_root: string;
  codex_root: string;
  project_names: Record<string, string>;
  time_zone: string;
}

export const paths = {
  identity: join(homedir(), '.sno', 'identity.json'),
  references: fileURLToPath(new URL('../references/', import.meta.url)),
};
// `cloudWaitMs`: how long one nightly upload waits for the cloud's answer, so a stalled cloud cannot hold
// the run silently for as long as the scheduler allows.
export const limits = { firstDays: 7, quietMinutes: 30, chunkCharacters: 40_000, cloudWaitMs: 6 * 3_600_000 };
export const readingLimits = { ledgerRows: 200 };
export const sizeCaps = { skillMdLines: 30, descriptionChars: 200, reminderLines: 12 };
export const reflectionFiles = {
  raw: 'raw', staging: 'staging', pages: 'wiki/patterns', index: 'wiki/index.md', logs: 'wiki/logs.md',
  lessons: 'wiki/lessons.jsonl', usage: 'ledger/usage.jsonl', ledger: 'ledger/skill-impact.jsonl',
  labelerInput: 'labeler-input.json', labelerOutput: 'labeler-output.json',
  proposal: 'proposal.json', skillMd: 'SKILL.md', patch: 'patch.json', purpose: 'PURPOSE.md',
  report: 'REPORT.md', runLog: 'run.log',
};
export const commands = ['run', 'accept', 'reject', 'tbd', 'recall', 'lesson', 'status', 'install-hooks'];
export const messages = {
  later: 'command not implemented',
  noHeartbeat: 'no heartbeat',
  noTerminal: 'no terminal run',
  redacted: '[REDACTED]',
  help: 'Usage: rem-reflect run [--now <timestamp>] [--trigger timer|manual]|accept|reject|tbd|recall [--first-message]|lesson|status|install-hooks',
};

export function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function storePath(env: NodeJS.ProcessEnv = process.env): string {
  return resolve(env.REM_REFLECT_STORE ?? join(homedir(), '.sno', 'experience'));
}

export type StationCell = 'off' | 'host' | 'sno-gpu';
export class SettingsUnavailable extends Error {}

// Where one of this skill's model calls goes under the mode in the Sno Station settings file:
// R2 labels sessions, R3 uploads them nightly, R4 looks up a lesson on the first prompt. Read on
// every call, never cached; a missing file, mode, row or value throws and says which, with no default.
export function stationCell(id: 'R2' | 'R3' | 'R4', env: NodeJS.ProcessEnv = process.env): StationCell {
  const path = join(env.SNO_PROFILE_DIR ?? join(homedir(), '.sno'), 'settings.json');
  const fail = (reason: string): never => { throw new SettingsUnavailable(`settings unavailable: ${path}: ${reason}; run sno setup`); };
  if (!existsSync(path)) return fail('file missing');
  let settings: unknown;
  try { settings = JSON.parse(readFileSync(path, 'utf8')); } catch { return fail('not valid JSON'); }
  const file = isObject(settings) ? settings : {};
  const mode = file.mode;
  if (mode !== 'local-first' && mode !== 'agent-native' && mode !== 'rem-enhanced') return fail('mode is missing or unknown');
  const row = isObject(file.modelCalls) ? file.modelCalls[id] : undefined;
  if (!isObject(row)) return fail(`modelCalls.${id} is missing`);
  const cell = row[mode];
  if (cell !== 'off' && cell !== 'host' && cell !== 'sno-gpu') return fail(`modelCalls.${id}.${mode} is not off, host or sno-gpu`);
  return cell;
}

export function defaultConfig(home: string = homedir()): Config {
  const claude_home = join(home, '.claude');
  const codex_home = join(home, '.codex');
  return {
    claude_home, codex_home,
    claude_root: join(claude_home, 'projects'),
    codex_root: join(codex_home, 'sessions'),
    project_names: {},
    time_zone: Intl.DateTimeFormat().resolvedOptions().timeZone,
  };
}

export function validateConfig(value: unknown): Config {
  if (!isObject(value)) throw new Error('config.json: expected an object');
  const result = defaultConfig();
  for (const key of ['claude_home', 'codex_home', 'claude_root', 'codex_root', 'time_zone'] as const) {
    const field = value[key];
    if (typeof field !== 'string' || !field.trim()) throw new Error(`config.json: invalid ${key}`);
    if (key !== 'time_zone' && !isAbsolute(field)) throw new Error(`config.json: ${key} must be absolute`);
    result[key] = field;
  }
  if (!isObject(value.project_names)) throw new Error('config.json: invalid project_names');
  for (const [directory, name] of Object.entries(value.project_names)) {
    if (!isAbsolute(directory) || typeof name !== 'string' || !name.trim()) {
      throw new Error('config.json: invalid project_names entry');
    }
    result.project_names[directory] = name;
  }
  try { new Intl.DateTimeFormat('en', { timeZone: result.time_zone }).format(); }
  catch { throw new Error('config.json: invalid time_zone'); }
  return result;
}

export function loadConfig(store: string): Config {
  let value: unknown;
  try { value = JSON.parse(readFileSync(join(store, 'config.json'), 'utf8')); }
  catch { throw new Error('config.json: missing or unparsable; repair it before running'); }
  return validateConfig(value);
}

export function canonicalPath(path: string): string {
  const absolute = resolve(path);
  if (existsSync(absolute)) return realpathSync(absolute);
  const parent = dirname(absolute);
  return join(canonicalPath(parent), relative(parent, absolute));
}

export function isWithin(parent: string, child: string): boolean {
  const suffix = relative(canonicalPath(parent), canonicalPath(child));
  return suffix === '' || (!suffix.startsWith('../') && suffix !== '..' && !isAbsolute(suffix));
}

export function skillRoots(config: Config): string[] {
  return [join(config.claude_home, 'skills'), join(config.codex_home, 'skills')];
}

export function validateRoots(config: Config, store: string): void {
  for (const key of ['claude_root', 'codex_root'] as const) {
    if (isWithin(store, config[key])) throw new Error(`config.json: ${key} lies inside store: ${config[key]}`);
  }
}

export function calendar(now: Date, timeZone: string): { date: string; id: string } {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(now);
  const part = (name: string): string => parts.find(item => item.type === name)?.value ?? '';
  const date = `${part('year')}-${part('month')}-${part('day')}`;
  return { date, id: `${date.replaceAll('-', '')}-${part('hour')}${part('minute')}` };
}
