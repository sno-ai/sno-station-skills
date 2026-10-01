import {
  appendFileSync, chmodSync, closeSync, existsSync, fsyncSync, linkSync, mkdirSync, openSync,
  readFileSync, renameSync, unlinkSync, writeFileSync,
} from 'node:fs';
import { dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { isObject, loadConfig } from './config.ts';
import type { Config } from './config.ts';

export type TerminalStatus = 'success' | 'no_action' | 'failed' | 'timed_out' | 'no_backend';
export interface RunStart { id: string; date: string }
export interface Terminal extends RunStart { status: TerminalStatus }
export interface Pending { failures: number; status: 'pending' | 'unparseable' }
export interface State {
  cursors: Record<string, number>;
  pending: Record<string, Pending>;
  last_start: RunStart | null;
  last_terminal: Terminal | null;
}
export interface Lock {
  pid: number;
  command: string;
  id: string;
}

export function emptyState(): State {
  return { cursors: {}, pending: {}, last_start: null, last_terminal: null };
}

export function privateDirectory(path: string): void {
  if (!existsSync(path)) {
    privateDirectory(dirname(path));
    mkdirSync(path, { mode: 0o700 });
  }
}

export function atomicWrite(path: string, bytes: string | Buffer): void {
  privateDirectory(dirname(path));
  const temporary = join(dirname(path), `.tmp-${randomUUID()}`);
  const fd = openSync(temporary, 'wx', 0o600);
  try { writeFileSync(fd, bytes); fsyncSync(fd); }
  finally { closeSync(fd); }
  try { renameSync(temporary, path); }
  finally { if (existsSync(temporary)) unlinkSync(temporary); }
}

export function writeJson(path: string, value: unknown): void {
  atomicWrite(path, `${JSON.stringify(value, null, 2)}\n`);
}

export function git(store: string, args: string[]): string {
  return execFileSync('git', [
    '-C', store, '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgSign=false',
    '-c', 'user.name=rem-reflect', '-c', 'user.email=rem-reflect@localhost', ...args,
  ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 30_000, maxBuffer: 256 * 1024 * 1024 });
}

export function headRevision(store: string): string | undefined {
  if (!existsSync(join(store, '.git'))) return undefined;
  try { return git(store, ['rev-parse', '--verify', 'HEAD']).trim(); }
  catch { return undefined; }
}

export function readHead(store: string, path: string, revision: string | undefined = headRevision(store)): string | undefined {
  if (!revision) return undefined;
  const files = git(store, ['ls-tree', '-r', '--name-only', '-z', revision]).split('\0');
  if (!files.includes(path)) return undefined;
  return git(store, ['show', `${revision}:${path}`]);
}

function isStart(value: unknown): value is RunStart {
  return isObject(value) && typeof value.id === 'string' && /^\d{8}-\d{4}$/.test(value.id)
    && typeof value.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value.date);
}

// Read what is readable and drop what is not. This file is the loop's own bookkeeping, so a single
// malformed entry is dropped so re-harvesting one session does not stop later runs.
export function parseState(text: string): State {
  const value: unknown = JSON.parse(text);
  const state = emptyState();
  if (!isObject(value)) return state;
  if (isObject(value.cursors)) {
    for (const [key, cursor] of Object.entries(value.cursors)) {
      if (typeof cursor === 'number' && Number.isFinite(cursor)) state.cursors[key] = cursor;
    }
  }
  if (isObject(value.pending)) {
    for (const [key, pending] of Object.entries(value.pending)) {
      if (!isObject(pending) || !['pending', 'unparseable'].includes(String(pending.status))) continue;
      const failures = typeof pending.failures === 'number' && Number.isInteger(pending.failures) && pending.failures > 0 ? pending.failures : 1;
      state.pending[key] = { failures, status: pending.status as Pending['status'] };
    }
  }
  if (isStart(value.last_start)) state.last_start = value.last_start;
  const terminal = value.last_terminal;
  if (isStart(terminal) && isObject(terminal)
    && ['success', 'no_action', 'failed', 'timed_out', 'no_backend'].includes(String(terminal.status))) {
    state.last_terminal = { ...terminal, status: terminal.status as TerminalStatus };
  }
  return state;
}

export function readState(store: string): State {
  const path = join(store, 'state.json');
  return existsSync(path) ? parseState(readFileSync(path, 'utf8')) : emptyState();
}

export function writeState(store: string, state: State): void {
  writeJson(join(store, 'state.json'), state);
}

export function initializeStore(store: string, config: Config, state: State): void {
  chmodSync(store, 0o700);
  for (const directory of ['raw', 'wiki/patterns', 'ledger', 'staging', '.loop-home/claude', '.loop-home/codex']) {
    privateDirectory(join(store, directory));
    chmodSync(join(store, directory), 0o700);
  }
  if (!existsSync(join(store, '.git'))) git(store, ['init', '--quiet']);
  if (!existsSync(join(store, '.gitignore'))) atomicWrite(join(store, '.gitignore'), 'run.lock\n.recovery-lock\n.tmp-*\n.loop-home/\n');
  if (!existsSync(join(store, 'config.json'))) writeJson(join(store, 'config.json'), config);
  if (!existsSync(join(store, 'state.json'))) writeState(store, state);
}

export function processAlive(pid: number): boolean {
  try { process.kill(pid, 0); return true; }
  catch (error) {
    if (isObject(error) && error.code === 'ESRCH') return false;
    return true;
  }
}

export function readLock(store: string): Lock | undefined {
  let text: string;
  try { text = readFileSync(join(store, 'run.lock'), 'utf8'); }
  catch (error) {
    if (isObject(error) && error.code === 'ENOENT') return undefined;
    throw error;
  }
  const value: unknown = JSON.parse(text);
  if (!isObject(value) || !Number.isInteger(value.pid) || typeof value.pid !== 'number' || value.pid <= 0
    || typeof value.command !== 'string' || typeof value.id !== 'string') throw new Error('run.lock: invalid holder');
  return { pid: value.pid, command: value.command, id: value.id };
}

// A lock whose holder is gone is stale. Delete it and let the next reflection run take over.
export function takeOverLock(store: string, lock: Lock): boolean {
  const prior = readLock(store);
  if (prior && !processAlive(prior.pid)) { try { unlinkSync(join(store, 'run.lock')); } catch { /* already gone */ } }
  return tryLock(store, lock);
}

export function tryLock(store: string, lock: Lock): boolean {
  const temporary = join(store, `.tmp-${randomUUID()}`);
  atomicWrite(temporary, `${JSON.stringify(lock)}\n`);
  try { linkSync(temporary, join(store, 'run.lock')); return true; }
  catch (error) {
    if (isObject(error) && error.code === 'EEXIST') return false;
    throw error;
  } finally { unlinkSync(temporary); }
}

export function releaseLock(store: string): void {
  const lock = readLock(store);
  if (lock?.pid !== process.pid) throw new Error('run.lock: ownership changed; refusing release');
  unlinkSync(join(store, 'run.lock'));
}

export function commitStore(store: string, message: string, command: string = 'run', files: string[] = []): boolean {
  try {
    if (command === 'run') {
      const owned = ['raw', 'wiki', 'ledger', 'staging', 'state.json', 'config.json', 'identity.json', '.gitignore']
        .filter(path => existsSync(join(store, path)));
      git(store, ['add', '--all', '--', ...owned]);
    }
    else if (files.length) {
      if (files.includes('ledger/usage.jsonl')) throw new Error('verdict command cannot stage ledger/usage.jsonl');
      git(store, ['add', '--', ...files]);
    }
    if (!git(store, ['diff', '--cached', '--name-only']).trim()) return false;
    git(store, ['commit', '--quiet', '-m', message]);
    return true;
  } catch (error) {
    const stderr = isObject(error) && typeof error.stderr === 'string' ? error.stderr : '';
    if (/index\.lock|another git process/.test(stderr)) return false;
    throw error;
  }
}
