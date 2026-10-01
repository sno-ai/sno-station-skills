import { createHash, randomUUID } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, resolve } from 'node:path';
import { isObject, paths } from './config.ts';
import { atomicWrite } from './store.ts';

export type Harness = 'claude-code' | 'codex';
export interface Identity {
  user_id: string;
  project_id: string;
  agent_id: Harness;
  source_harness: Harness;
  originator: string;
  role?: string;
  missing_cwd?: string;
}

export function userId(value: unknown): string {
  if (!isObject(value) || typeof value.user_cuid !== 'string' || !value.user_cuid.trim()) {
    throw new Error('identity.json: missing user_cuid');
  }
  return value.user_cuid;
}

export function readUserId(store: string, stationPath: string = paths.identity): string {
  if (existsSync(stationPath)) return userId(JSON.parse(readFileSync(stationPath, 'utf8')) as unknown);
  const localPath = join(store, 'identity.json');
  if (existsSync(localPath)) return userId(JSON.parse(readFileSync(localPath, 'utf8')) as unknown);
  const generated = randomUUID();
  atomicWrite(localPath, `${JSON.stringify({ user_cuid: generated }, null, 2)}\n`);
  return generated;
}

export function normalizeRemote(remote: string | undefined): string | undefined {
  if (!remote) return undefined;
  const scp = /^(?:[^@/:]+@)?([^/:]+):([^/].*)$/.exec(remote);
  let host: string;
  let path: string;
  if (!remote.includes('://') && scp) {
    host = scp[1]; path = scp[2];
  } else {
    let url: URL;
    try { url = new URL(remote); } catch { return undefined; }
    if (!url.hostname || url.protocol === 'file:') return undefined;
    host = url.hostname; path = url.pathname;
  }
  path = path.replace(/^\/+|\/+$/g, '').replace(/\.git$/, '');
  if (!path || path.split('/').some(part => part === '.' || part === '..')) return undefined;
  return `${host.toLowerCase()}/${path}`;
}

export function projectId(cwd: string, remote: string | undefined, names: Record<string, string>): string {
  const origin = normalizeRemote(remote);
  if (origin) return origin;
  if (!cwd) return 'user-level';
  const directory = resolve(cwd);
  const named = names[directory];
  if (named) return named;
  const project = gitTop(directory) ?? directory;
  return `dir:${createHash('sha256').update(project).digest('hex').slice(0, 16)}`;
}

function gitTop(cwd: string): string | undefined {
  if (!existsSync(cwd)) return undefined;
  try {
    return resolve(execFileSync('git', ['-C', cwd, 'rev-parse', '--show-toplevel'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 5000,
    }).trim());
  } catch { return undefined; }
}

export function gitRemote(cwd: string): string | undefined {
  if (!cwd || !existsSync(cwd)) return undefined;
  try {
    return execFileSync('git', ['-C', cwd, 'remote', 'get-url', 'origin'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 5000,
    }).trim();
  } catch { return undefined; }
}

export function resolveIdentity(input: {
  user_id: string; harness: Harness; cwd: string; remote?: string;
  project_names: Record<string, string>; originator?: string; role?: string;
}): Identity {
  const result: Identity = {
    user_id: input.user_id,
    project_id: projectId(input.cwd, input.remote, input.project_names),
    agent_id: input.harness, source_harness: input.harness,
    originator: input.originator ?? input.harness,
  };
  if (input.role) result.role = input.role;
  return result;
}
