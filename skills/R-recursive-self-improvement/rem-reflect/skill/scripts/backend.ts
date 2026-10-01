import { spawnSync } from 'node:child_process';
import type { SpawnSyncOptionsWithStringEncoding } from 'node:child_process';
import { chmodSync, copyFileSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { isObject } from './config.ts';
import type { Config } from './config.ts';
import type { Harness } from './identity.ts';
import { message } from './text.ts';
import { CeilingReached, ceilings } from './session.ts';

export type Cli = 'claude' | 'codex';
// `kind` records the call role without inferring it from the prompt shape.
export interface SpawnRequest { cli: Cli; model?: string; cwd: string; input: string; kind?: 'labeler' | 'model' | 'preflight' }
export interface Backend {
  spawn(request: SpawnRequest): { stdout: string };
  // A trivial health check of the CLI (optionally under a model). True when the CLI answered.
  preflight?(cli: Cli, cwd: string, model?: string): boolean;
}
export class BackendError extends Error {
  reason: 'labeler-timeout' | 'labeler-unavailable' | 'labeler-invalid-response';
  // `detail` (a spawn error code, or the exit status and a stderr head) goes into the message only, so
  // a log line explains the failure while `reason` stays the exact token labels and filters match on.
  constructor(reason: BackendError['reason'], detail?: string) { super(detail ? `${reason} (${detail})` : reason); this.reason = reason; }
}
export function otherCli(half: Harness): Cli { return half === 'claude-code' ? 'codex' : 'claude'; }

// Kill a child's whole process group so no grandchild outlives the run. A detached child is
// its own group leader, so its pgid equals its pid; -pid signals every member still alive.
function killGroup(pid: number | undefined): void {
  if (!pid) return;
  try { process.kill(-pid, 'SIGKILL'); } catch { /* the group is already gone */ }
}

// Copy each CLI's one credential file into its isolated home before the first model call:
// `.credentials.json` from the real Claude directory and `auth.json` from the real
// Codex directory, and nothing else — no `settings.json`, no `config.toml` — so no hook, plugin,
// output style, model pin, or web search of the owner's interactive setup reaches the loop's turns.
// The isolated directories are created 0700 (the store's own `.loop-home/`) and each copied file is
// written 0600. A missing source is not fatal: the empty directory makes that CLI fail preflight
// and its harness degrades; the run log names the missing file so the report can carry it.
// Credentials are copied every run so a rotated login is picked up.
export function seedLoopHomes(store: string, config: Config, log: string[]): void {
  const seeds = [
    { cli: 'claude', source: join(config.claude_home, '.credentials.json'), target: join(store, '.loop-home', 'claude', '.credentials.json') },
    { cli: 'codex', source: join(config.codex_home, 'auth.json'), target: join(store, '.loop-home', 'codex', 'auth.json') },
  ] as const;
  for (const { cli, source, target } of seeds) {
    if (!existsSync(source)) {
      // Remove any credential a prior run copied here, so a source that has gone away leaves an empty
      // isolated home: the CLI then fails preflight and its harness degrades, instead of the stale copy
      // silently keeping a removed login alive.
      rmSync(target, { force: true });
      log.push(message('credentialMissing', { cli, path: source }));
      continue;
    }
    mkdirSync(dirname(target), { recursive: true, mode: 0o700 });
    copyFileSync(source, target);
    chmodSync(target, 0o600);
  }
}

// The real CLI backend. Each call runs in its own process group with a per-call deadline;
// on timeout the group is killed and a `per-call-timeout` ceiling is thrown so the run stops with no
// child left behind. When `loopHomeBase` is set, each turn runs under the isolated harness home of
// `seedLoopHomes` populates those homes before the first call.
export class RealBackend implements Backend {
  private readonly perCallMs: number;
  private readonly loopHomeBase: string | undefined;
  constructor(perCallMs: number = ceilings.perCallMs, options: { loopHomeBase?: string } = {}) {
    this.perCallMs = perCallMs;
    this.loopHomeBase = options.loopHomeBase;
  }
  // A trivial health check: a one-word prompt under a short deadline. The CLI is healthy when the
  // CLI exits zero; a timeout or non-zero exit is a failed preflight.
  preflight(cli: Cli, cwd: string, model?: string): boolean {
    try { this.spawn({ cli, model, cwd, input: 'reply with ok', kind: 'preflight' }); return true; }
    catch (error) { if (error instanceof CeilingReached) throw error; return false; }
  }
  // A Claude turn sees only CLAUDE_CONFIG_DIR under the store's `.loop-home/claude`; a Codex turn only
  // CODEX_HOME under `.loop-home/codex`. The other CLI's variable is removed so a stale inherited one
  // cannot point a turn at the owner's real login. With no isolated base the process env is
  // inherited unchanged.
  private spawnEnv(cli: Cli): NodeJS.ProcessEnv | undefined {
    if (!this.loopHomeBase) return undefined;
    const env = { ...process.env };
    if (cli === 'claude') { env.CLAUDE_CONFIG_DIR = join(this.loopHomeBase, 'claude'); delete env.CODEX_HOME; }
    else { env.CODEX_HOME = join(this.loopHomeBase, 'codex'); delete env.CLAUDE_CONFIG_DIR; }
    return env;
  }
  // The prompt goes to the CLI on stdin, never as an argument: a reading-phase prompt bundles several
  // traces and pages (hundreds of KB) and one argv element is capped at 128 KB on Linux (E2BIG).
  // `claude -p` with no positional prompt reads stdin; `codex exec -` reads stdin.
  spawn({ cli, model, cwd, input }: SpawnRequest): { stdout: string } {
    const args = cli === 'claude'
      ? ['-p', '--output-format', 'text', '--allowedTools', 'Read,Grep,Glob']
      : ['exec', '--skip-git-repo-check', '-'];
    if (model) args.push('--model', model);
    const options = {
      cwd, env: this.spawnEnv(cli), encoding: 'utf8', input, timeout: this.perCallMs, killSignal: 'SIGKILL', detached: true,
      stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024,
    } satisfies SpawnSyncOptionsWithStringEncoding & { detached: boolean };
    const child = spawnSync(cli, args, options);
    if (child.error) {
      if (isObject(child.error) && child.error.code === 'ETIMEDOUT') { killGroup(child.pid); throw new CeilingReached('per-call-timeout'); }
      throw new BackendError('labeler-unavailable', isObject(child.error) && typeof child.error.code === 'string' ? child.error.code : String(child.error));
    }
    // A non-zero exit is a failed CLI, not usable output: a CLI that is not logged in exits non-zero
    // ("Not logged in" for Claude, HTTP 401 for Codex), which must fail preflight so its harness degrades.
    if (child.status !== 0) throw new BackendError('labeler-unavailable', `exit ${child.status}: ${(child.stderr ?? '').trim().split('\n')[0].slice(0, 200)}`);
    return { stdout: child.stdout ?? '' };
  }
}
