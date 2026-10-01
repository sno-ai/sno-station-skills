import { appendFileSync, existsSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';
import {
  calendar, commands, defaultConfig, isObject, loadConfig, messages, storePath,
  validateConfig, validateRoots,
} from './config.ts';
import { harvest } from './harvest.ts';
import { readUserId } from './identity.ts';
import {
  atomicWrite, commitStore, emptyState, headRevision, initializeStore, parseState, privateDirectory,
  processAlive, readHead, readLock, readState, releaseLock, takeOverLock, writeState,
} from './store.ts';
import type { Lock, State } from './store.ts';
import { RealBackend, seedLoopHomes } from './backend.ts';
import type { Backend } from './backend.ts';
import { reflect } from './reflect.ts';
import { observe } from './observe.ts';
import { flushCloudVerdicts } from './cloud.ts';
import { buildReport } from './report.ts';
import { verdictCommand } from './adopt.ts';
import { firstMessageRecall, installHooksPrint, lessonDetail, recall } from './recall.ts';
import type { Harness } from './identity.ts';
import { readFileSync } from 'node:fs';

export interface CommandResult { code: number; lines: string[]; stderr?: string[] }

function held(lock: Lock): CommandResult {
  return { code: 0, lines: [`lock held by ${lock.command} ${lock.id} (pid ${lock.pid})`] };
}

// one SUCCESSFUL reflection per day. A run no-ops only when today already reached a
// terminal success ('no_action' is a successful reflection that proposed nothing); a day whose only
// run failed, timed out, or found no backend is not done, so a retry that day proceeds.
function succeededToday(state: State, date: string): boolean {
  const t = state.last_terminal;
  return !!t && t.date === date && (t.status === 'success' || t.status === 'no_action');
}

export function run(store: string, now: Date = new Date(), user?: string,
  backend: Backend = new RealBackend(undefined, { loopHomeBase: join(store, '.loop-home') }),
  clock: () => number = () => Date.now(), trigger: 'timer' | 'manual' = 'manual'): CommandResult {
  const started = clock();
  // Directory existence is not proof of a finished bootstrap: a first run killed after mkdir but
  // before config.json, or an empty directory the owner created, would send loadConfig straight
  // into a permanent "no config" error that no recovery path can reach. A store that has a commit
  // is established, so a config.json missing there stays the hard error it is meant to be.
  const bootstrapped = existsSync(join(store, 'config.json')) || headRevision(store) !== undefined;
  const fresh = !existsSync(store) || !bootstrapped;
  const config = fresh ? defaultConfig() : loadConfig(store);
  validateRoots(config, store);
  const start = calendar(now, config.time_zone);
  const prior = readLock(store);
  if (prior && processAlive(prior.pid)) return held(prior);
  let state = fresh ? emptyState() : readState(store);
  if (!fresh) flushCloudVerdicts(store);
  if (succeededToday(state, start.date)) return { code: 0, lines: [`no-op: ${state.last_terminal!.id} already succeeded on ${start.date}`] };
  privateDirectory(store);
  // Finish the bootstrap before recovery touches git. A first run killed mid-initialization can
  // leave a store with no repository, or one with a repository and no config.json — recovering
  // either would fail outright, or commit a HEAD that every later run rejects for a missing config.
  if (fresh) initializeStore(store, config, state);
  const userId = user ?? readUserId(store);
  const lock: Lock = { pid: process.pid, command: 'run', id: start.id };
  // A dead holder is a stale file, not an incident: take the lock over and run. Whatever the dead
  // run left behind is in the store's own git history, where it can be inspected or dropped.
  const notice = prior ? `previous run ${prior.id} did not finish` : '';
  if (!takeOverLock(store, lock)) {
    const holder = readLock(store);
    return holder ? held(holder) : { code: 0, lines: ['no-op: concurrent store writer; retry later'] };
  }
  // The same-day guard above ran before the lock existed, so a run that started and finished while
  // this one waited is invisible to it. Read the state again now that the lock is held: otherwise
  // the day runs twice and the second run writes back a state it read before the first.
  if (existsSync(join(store, 'state.json'))) {
    state = readState(store);
    if (succeededToday(state, start.date)) {
      releaseLock(store);
      return { code: 0, lines: [`no-op: ${state.last_terminal!.id} already succeeded on ${start.date}`] };
    }
  }
  return executeHarvest(store, config, state, start, now, userId, notice, backend, clock, started, trigger);
}

function executeHarvest(store: string, config: ReturnType<typeof defaultConfig>, state: State,
  start: ReturnType<typeof calendar>, now: Date, user: string, notice: string, backend: Backend,
  clock: () => number, started: number, trigger: 'timer' | 'manual'): CommandResult {
  let code = 0;
  let sessionsRead = 0;
  let lines: string[] = [];
  let committed = false;
  const runLog = join(store, 'staging', start.id, 'run.log');
  try {
    state.last_start = start;
    // Persist the date before initialization or harvest can change any other store data.
    writeState(store, state);
    initializeStore(store, config, state);
    atomicWrite(runLog, '');
    try {
      const result = harvest(store, config, state, user, now);
      sessionsRead = result.traces.length;
      lines = result.log;
      // Seed the isolated harness homes before the first model call; harvest spawns nothing.
      seedLoopHomes(store, config, lines);
      const reflection = reflect(store, config, start.id, backend, lines, now);
      state.last_terminal = { ...start, status: 'success' };
      const statusLines = lines.filter(line => line.includes('labeler-') || line.includes('credential file missing'));
      const report = buildReport({ store, config, runId: start.id, notice,
        labelerLines: statusLines, harvested: result.traces.length,
        reflectionReport: reflection.report });
      atomicWrite(join(store, 'staging', start.id, 'REPORT.md'), report);
    } catch (error) {
      code = 1;
      const message = error instanceof Error ? error.message : String(error);
      lines.push(`harvest failed: ${message}`);
      state.last_terminal = { ...start, status: 'failed' };
      atomicWrite(join(store, 'staging', start.id, 'REPORT.md'), `${notice ? `${notice}\n` : ''}Run ${start.id} failed\n${message}\n`);
    }
    appendFileSync(runLog, `${lines.join('\n')}\n`);
    writeState(store, state);
    commitStore(store, start.id);
    committed = true;
    observe('rsi.run', { sessions_read: sessionsRead, duration_ms: clock() - started, trigger,
      outcome: state.last_terminal?.status === 'success' || state.last_terminal?.status === 'no_action' ? 'ok' : 'fail' }, runLog);
    return { code, lines: [`${start.id} ${state.last_terminal?.status}`, ...lines] };
  } finally {
    // A failed commit keeps the lock and last_start as crash-recovery evidence.
    if (committed) releaseLock(store);
  }
}

export function heartbeatLine(output: string): string | undefined {
  return output.split('\n').find(line => /(?:^|\s)rem-reflect\s+\d+(?:\s|$)/.test(line));
}

function listedHeartbeat(): string {
  try {
    return execFileSync('heartbeat', ['--list'], {
      encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch { return ''; }
}

export function status(store: string, now: Date = new Date(), heartbeat: string = listedHeartbeat()): CommandResult {
  const revision = headRevision(store);
  const stateText = readHead(store, 'state.json', revision);
  const configText = readHead(store, 'config.json', revision);
  const state = stateText ? parseState(stateText) : emptyState();
  const config = configText ? validateConfig(JSON.parse(configText)) : defaultConfig();
  const lines: string[] = [];
  let code = 0;
  const terminal = state.last_terminal;
  if (!terminal) { lines.push(messages.noTerminal); code = 1; }
  else {
    lines.push(`${terminal.id} ${terminal.status} ${terminal.date}`);
    const today = calendar(now, config.time_zone).date;
    if ((Date.parse(today) - Date.parse(terminal.date)) / 86_400_000 > 2) {
      lines.push('last terminal run is older than two calendar days'); code = 1;
    }
    if (['failed', 'timed_out', 'no_backend'].includes(terminal.status)) code = 1;
  }
  const lock = readLock(store);
  if (lock) {
    const alive = processAlive(lock.pid);
    lines.push(`${alive ? 'lock held by' : 'dead lock holder'} ${lock.command} ${lock.id}`);
    if (!alive) code = 1;
  }
  const beat = heartbeatLine(heartbeat);
  lines.push(beat ?? messages.noHeartbeat);
  if (!beat) code = 1;
  return { code, lines };
}

function parseFlags(rest: string[]): { positional: string[]; opts: Record<string, string> } {
  const opts: Record<string, string> = {};
  const positional: string[] = [];
  for (let i = 0; i < rest.length; i++) {
    if (rest[i].startsWith('--')) { opts[rest[i].slice(2)] = rest[i + 1] ?? ''; i++; }
    else positional.push(rest[i]);
  }
  return { positional, opts };
}

function recallCommand(rest: string[]): CommandResult {
  const firstMessage = rest.includes('--first-message');
  const { opts } = parseFlags(rest.filter(arg => arg !== '--first-message'));
  const agent = opts.agent as Harness;
  if (agent !== 'claude-code' && agent !== 'codex') return { code: 2, lines: ['recall: --agent claude-code|codex is required'] };
  let session: string | undefined = opts.session;
  let cwd: string | undefined = opts.cwd;
  let prompt: string | undefined;
  if (firstMessage || !session || !cwd) {
    // the SessionStart hook pipes the harness's JSON on stdin; both harnesses pass session_id and cwd
    try {
      const value: unknown = JSON.parse(readFileSync(0, 'utf8'));
      if (isObject(value)) {
        if (!session && typeof value.session_id === 'string') session = value.session_id;
        if (!cwd && typeof value.cwd === 'string') cwd = value.cwd;
        if (typeof value.prompt === 'string') prompt = value.prompt;
      }
    } catch { /* no stdin available */ }
  }
  return firstMessage ? firstMessageRecall(storePath(), agent, { session_id: session, cwd, prompt })
    : recall(storePath(), agent, { session_id: session, cwd }, new Date(), listedHeartbeat());
}

function lessonCommand(rest: string[]): CommandResult {
  const { positional, opts } = parseFlags(rest);
  if (!positional.length) return { code: 2, lines: ['lesson: a lesson id is required'] };
  const agent = opts.agent as Harness | undefined;
  if (agent && agent !== 'claude-code' && agent !== 'codex') return { code: 2, lines: ['lesson: --agent must be claude-code or codex'] };
  return lessonDetail(storePath(), positional[0], { session: opts.session, cwd: opts.cwd, agent }, new Date());
}

export function main(args: string[] = process.argv.slice(2)): number {
  if (args.length === 0 || (args.length === 1 && (args[0] === '--help' || args[0] === '-h'))) {
    console.log(messages.help); return 0;
  }
  const [command, ...rest] = args;
  if (!commands.includes(command)) { console.error(messages.help); return 2; }
  const verdicts = ['accept', 'reject', 'tbd'];
  try {
    let result: CommandResult;
    if (command === 'run') {
      const opts: Record<string, string> = {};
      for (let i = 0; i < rest.length; i += 2) {
        const flag = rest[i];
        if (!['--now', '--trigger'].includes(flag) || !rest[i + 1] || flag in opts) {
          console.error(`run: unexpected argument ${flag}`); return 2;
        }
        opts[flag] = rest[i + 1];
      }
      const trigger = opts['--trigger'] ?? 'manual';
      if (trigger !== 'timer' && trigger !== 'manual') { console.error('run: --trigger requires timer|manual'); return 2; }
      const now = opts['--now'] ? new Date(opts['--now']) : new Date();
      if (Number.isNaN(now.getTime())) { console.error('run: --now requires a valid timestamp'); return 2; }
      const store = storePath();
      if (process.env.REM_SELFTEST && (!process.env.REM_REFLECT_STORE || !existsSync(store))) {
        throw new Error(`self-test store missing: ${process.env.REM_REFLECT_STORE || 'REM_REFLECT_STORE'}`);
      }
      result = run(store, now, undefined, undefined, undefined, trigger);
    }
    else if (command === 'status') { if (rest.length) { console.error(`status: unexpected argument ${rest[0]}`); return 2; } result = status(storePath()); }
    else if (verdicts.includes(command)) {
      const scopeFlags = ['--all-projects', '--this-project'];
      const flags = rest.filter(arg => scopeFlags.includes(arg));
      const ids = rest.filter(arg => !scopeFlags.includes(arg));
      if (flags.length > 1 || ids.length !== 1) { console.error(`${command}: one proposal id or lesson id is required`); return 2; }
      if (flags.length && (command !== 'accept' || !ids[0].startsWith('L-'))) {
        console.error(`${flags[0]} is valid only for lesson accept`); return 2;
      }
      result = verdictCommand(storePath(), command, ids[0], new Date(), flags[0] === '--all-projects', flags[0] === '--this-project');
      if (result.code === 0) {
        try {
          const sync = flushCloudVerdicts(storePath());
          if (sync.pending) result.lines.push(`${sync.pending} cloud verdict pending until full consent`);
        } catch (error) {
          result = { code: 1, lines: [...result.lines, `local decision persisted; cloud verdict pending: ${String(error)}`] };
        }
      }
    }
    else if (command === 'recall') result = recallCommand(rest);
    else if (command === 'lesson') result = lessonCommand(rest);
    else if (command === 'install-hooks') {
      if (rest[0] !== '--print') { console.error('install-hooks: only --print is supported'); return 2; }
      result = installHooksPrint();
    }
    else { console.error(messages.later); return 3; }
    if (result.lines.length) console.log(result.lines.join('\n'));
    if (result.stderr?.length) console.error(result.stderr.join('\n'));
    return result.code;
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error)); return 1;
  }
}

// Compare real paths: `import.meta.url` is symlink-resolved by Node, and the deployed skill lives under
// a symlinked harness root, so a raw resolve() of argv[1] would never match and main() would silently
// not run. realpathSync resolves the symlink on both sides.
if (process.argv[1] && pathToFileURL(realpathSync(process.argv[1])).href === import.meta.url) process.exitCode = main();
