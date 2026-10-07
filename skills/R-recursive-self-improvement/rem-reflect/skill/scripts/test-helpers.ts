// Test-owned helpers. Build a disposable store, fixture session roots shaped like
// the real Claude Code and Codex logs, and flat installed skill roots. No mocks: the
// real parser, real filesystem, and real git run against these fixtures.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, realpathSync, rmSync, statSync, utimesSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, relative } from 'node:path';
import type { Config } from './config.ts';
import { initializeStore, emptyState, writeJson, git } from './store.ts';

// Test directories live on the home disk, never under the system temp directory, which on this machine is the shared RAM disk.
export const testTempRoot = join(homedir(), '.cache', 'rem-reflect-tests');
mkdirSync(testTempRoot, { recursive: true });
// Every temp directory a test process creates is removed when that process exits.
const madeDirs: string[] = [];
process.once('exit', () => { for (const dir of madeDirs) rmSync(dir, { recursive: true, force: true }); });
function makeTempDir(prefix: string): string {
  const dir = mkdtempSync(join(testTempRoot, prefix));
  madeDirs.push(dir);
  return dir;
}

// Unit tests never reach this machine's installed `sno`: at load, a stand-in goes first on PATH.
// It answers consent full (labeling and upload only run at full), an empty cloud verdict, and accepts every
// `observe append`; it refuses anything else. A test that prepends its own stand-in later still wins.
if (!process.env.REM_SELFTEST) {
  const bin = makeTempDir('rem-sno-default-');
  writeFileSync(join(bin, 'sno'), [
    '#!/usr/bin/env node',
    "const args = process.argv.slice(2).join(' ');",
    "if (args.startsWith('observe append ')) process.exit(0);",
    "if (args === 'station telemetry consent get') { console.log(process.env.REM_TEST_CONSENT || 'full'); process.exit(0); }",
    "if (args === 'skills get rem-reflect-local-writer') { const binary = process.env.REM_TEST_SNO_CLI; if (!binary) { process.stdout.write('Read one finished coding-agent session and decide whether it teaches one lesson worth keeping.\\n'); process.exit(0); } const result = require('node:child_process').spawnSync(binary, process.argv.slice(2), {encoding:'utf8'}); process.stdout.write(result.stdout || ''); process.stderr.write(result.stderr || ''); process.exit(result.status === null ? 1 : result.status); }",
    "if (args === 'heartbeat' || args.startsWith('heartbeat ')) { const binary = process.env.REM_TEST_SNO_CLI || require('node:path').join(require('node:os').homedir(), '.local/bin/sno'); const result = require('node:child_process').spawnSync(binary, process.argv.slice(2), {encoding:'utf8'}); if (result.error) { console.error(String(result.error.message)); process.exit(1); } process.stdout.write(result.stdout || ''); process.stderr.write(result.stderr || ''); process.exit(result.status === null ? 1 : result.status); }",
    "if (args !== 'rem judge') { console.error('unexpected sno command: ' + args); process.exit(2); }",
    "const batch = JSON.parse(require('node:fs').readFileSync(0, 'utf8'));",
    "if (process.env.REM_TEST_CONSENT && process.env.REM_TEST_CONSENT !== 'full') { console.error('upload rejected: consent ' + process.env.REM_TEST_CONSENT); process.exit(1); }",
    "console.log(JSON.stringify({ schema_version: 1, run_id: batch.run_id, history_acknowledged: true, history_links: [],",
    "  halves: batch.halves.map(half => ({ harness: half.harness, attention: [], pages: [], lessons: [], proposals: [], read_judgments: [], log_entry: 'no supported change' })) }));",
  ].join('\n') + '\n', { mode: 0o755 });
  process.env.PATH = `${bin}:${process.env.PATH ?? ''}`;
}

export function tmp(prefix: string): string {
  return makeTempDir(`remtest-${prefix}-`);
}

// A Sno Station settings file with this skill's three rows, shaped like the shipped defaults: R2 labels
// on the host, R3 and R4 go to the Sno cloud, all off under local-first. Tests read a disposable profile
// root through SNO_PROFILE_DIR, never this machine's ~/.sno.
export function stationSettings(mode = 'agent-native', rows: Record<string, Record<string, string>> = {}): string {
  return JSON.stringify({ mode, modelCalls: {
    R2: { 'local-first': 'off', 'agent-native': 'host', 'rem-enhanced': 'host' },
    R3: { 'local-first': 'off', 'agent-native': 'sno-gpu', 'rem-enhanced': 'sno-gpu' },
    R4: { 'local-first': 'off', 'agent-native': 'sno-gpu', 'rem-enhanced': 'sno-gpu' },
    R5: { 'local-first': 'host', 'agent-native': 'off', 'rem-enhanced': 'off' },
    ...rows,
  } });
}
export function writeStationSettings(mode = 'agent-native', rows: Record<string, Record<string, string>> = {}): string {
  const profile = makeTempDir('remtest-profile-');
  writeFileSync(join(profile, 'settings.json'), stationSettings(mode, rows));
  return profile;
}
if (!process.env.REM_SELFTEST) process.env.SNO_PROFILE_DIR = writeStationSettings();

export const DAY = 86_400_000;

export function writeInstalledSkill(home: string, name: string, body = 'Body.\n'): string {
  const payload = join(home, 'skills', name);
  mkdirSync(payload, { recursive: true });
  writeFileSync(join(payload, 'SKILL.md'), `---\nname: ${name}\ndescription: "fixture ${name}."\n---\n# ${name}\n\n${body}`);
  return payload;
}

export function fixtureHarnessHomes(names = ['heartbeat', 'second-skill', 'nested-skill']): {
  claudeHome: string; codexHome: string;
} {
  const claudeHome = tmp('claude-home');
  const codexHome = tmp('codex-home');
  for (const name of names) {
    writeInstalledSkill(claudeHome, name);
    writeInstalledSkill(codexHome, name);
  }
  return { claudeHome, codexHome };
}

// A fixture checkout with a real git remote, so identity.gitRemote resolves a project id.
export function fixtureCheckout(remote = 'git@github.com:example/project.git'): string {
  const dir = tmp('repo');
  git(dir, ['init', '--quiet']);
  git(dir, ['remote', 'add', 'origin', remote]);
  git(dir, ['config', 'user.email', 'rem@test']);
  git(dir, ['config', 'user.name', 'rem test']);
  // A minimal skill catalogue the harvest can resolve skills_loaded against.
  for (const name of ['heartbeat', 'second-skill', 'nested-skill']) {
    const payload = name === 'nested-skill' ? join(dir, 'skills', 'nested-skill', 'skill') : join(dir, 'skills', name, 'skill');
    mkdirSync(payload, { recursive: true });
    writeFileSync(join(payload, 'SKILL.md'), `---\nname: ${name}\ndescription: "fixture ${name}."\n---\n# ${name}\n`);
  }
  writeFileSync(join(dir, 'README.md'), '# fixture checkout\n');
  // Commit, so the fixture is a real checkout with tracked files exactly as the live one is.
  git(dir, ['add', '-A']);
  git(dir, ['commit', '--quiet', '-m', 'fixture']);
  return dir;
}

export function makeConfig(over: Partial<Config> & { claude_root: string; codex_root: string }): Config {
  return {
    claude_home: over.claude_home ?? tmp('claude-home'),
    codex_home: over.codex_home ?? tmp('codex-home'),
    project_names: over.project_names ?? {},
    time_zone: over.time_zone ?? 'UTC',
    ...over,
  } as Config;
}

export function fixtureConfig(over: Partial<Config> = {}): Config {
  const { claudeHome, codexHome } = fixtureHarnessHomes();
  return makeConfig({
    claude_home: claudeHome,
    codex_home: codexHome,
    claude_root: tmp('claude-sessions'),
    codex_root: tmp('codex-sessions'),
    ...over,
  });
}

// Pre-create a store whose config points at fixture roots, with a local git identity so commits
// succeed under any HOME. run()/status() then read this config instead of the real home dirs.
export function makeStore(config: Config): string {
  const store = tmp('store');
  initializeStore(store, config, emptyState());
  git(store, ['config', 'user.email', 'rem@test']);
  git(store, ['config', 'user.name', 'rem test']);
  git(store, ['add', '--all']);
  git(store, ['commit', '--quiet', '-m', 'init']);
  return store;
}

function setMtime(path: string, whenMs: number): void {
  utimesSync(path, whenMs / 1000, whenMs / 1000);
}

export interface ClaudeRecord { type: string; [k: string]: unknown }

// Write a Claude Code session file at <root>/<slug>/<id>.jsonl; session id = file stem.
export function writeClaudeSession(root: string, slug: string, id: string, records: ClaudeRecord[], mtimeMs: number): string {
  const dir = join(root, slug);
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `${id}.jsonl`);
  writeFileSync(path, records.map(r => JSON.stringify(r)).join('\n') + '\n');
  setMtime(path, mtimeMs);
  return path;
}

export function claudeUser(cwd: string, id: string, text: string, timestamp = '2026-09-01T00:00:00.000Z'): ClaudeRecord {
  return { type: 'user', cwd, gitBranch: 'dev', sessionId: id, timestamp, isSidechain: false, message: { role: 'user', content: text } };
}
export function claudeAssistant(cwd: string, id: string, blocks: unknown[], timestamp = '2026-09-01T00:00:01.000Z'): ClaudeRecord {
  return { type: 'assistant', cwd, gitBranch: 'dev', sessionId: id, timestamp, isSidechain: false, message: { role: 'assistant', model: 'claude-x', content: blocks } };
}

// Write a Codex rollout file at <root>/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl; id = session_meta.payload.id.
export function writeCodexSession(root: string, id: string, records: ClaudeRecord[], mtimeMs: number, day = '2026/09/01', ts = '2026-09-01T00-00-00'): string {
  const dir = join(root, ...day.split('/'));
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `rollout-${ts}-${id}.jsonl`);
  writeFileSync(path, records.map(r => JSON.stringify(r)).join('\n') + '\n');
  setMtime(path, mtimeMs);
  return path;
}

export function codexMeta(id: string, cwd: string, over: Record<string, unknown> = {}): ClaudeRecord {
  return { type: 'session_meta', payload: { id, cwd, git: { repository_url: 'git@github.com:example/project.git', branch: 'dev' }, cli_version: '0.153.2', model_provider: 'openai', ...over } };
}
export function codexUser(text: string): ClaudeRecord {
  return { type: 'response_item', payload: { type: 'message', role: 'user', content: [{ type: 'input_text', text }] } };
}
export function codexAssistant(text: string): ClaudeRecord {
  return { type: 'response_item', payload: { type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] } };
}

export { setMtime };

// A deterministic stand-in for the local labeler CLIs. No model runs.
import type { Backend, SpawnRequest, Cli } from './backend.ts';

export interface FixtureOptions {
  label?: (traceId: string) => Record<string, unknown>;
  preflight?: (cli: Cli, model?: string) => boolean;
}

export class FixtureBackend implements Backend {
  readonly calls: { kind: string; cli: Cli; input: string }[] = [];
  private opts: FixtureOptions;
  constructor(opts: FixtureOptions = {}) {
    this.opts = opts;
  }
  preflight(cli: Cli, _cwd: string, model?: string): boolean {
    this.calls.push({ kind: 'preflight', cli, input: model ?? '' });
    return this.opts.preflight ? this.opts.preflight(cli, model) : true;
  }
  spawn(req: SpawnRequest): { stdout: string } {
    const input = req.input;
    if (input.includes('previous_versions:')) {
      this.calls.push({ kind: 'labeler', cli: req.cli, input });
      const traceId = /"trace_id":"([^"]+)"/.exec(input)?.[1] ?? '';
      const label = this.opts.label ? this.opts.label(traceId)
        : { decision: 'keep', outcome: 'fail', reason: 'fixture fail', evidence: [], key_ranges: [], notes: '' };
      return { stdout: JSON.stringify(label) };
    }
    // The Local First nightly writer: a model that finds nothing worth keeping.
    if (input.includes('one lesson worth keeping')) {
      this.calls.push({ kind: 'writer', cli: req.cli, input });
      return { stdout: '{"lesson":null}' };
    }
    throw new Error('unexpected model input');
  }
}

// A sorted hash listing of every file under `root`, for tests that assert a tree did not change.
// Symlinks are recorded by their target; git bookkeeping and the loop's own `.loop-home/` are skipped.
function mode(path: string): string { return (statSync(path).mode & 0o7777).toString(8); }
export function hashListing(root: string, skip: (rel: string) => boolean = () => false): string {
  if (!existsSync(root)) return '';
  const lines: string[] = [];
  const seen = new Set<string>();
  const top = realpathSync(root);
  // A link's target is followed only when it lies inside this tree. A link out to live state (a
  // registry under ~/.local/state, say) is written by other tools all day; its content is outside
  // the trees the gate watches, while the link itself stays in the listing so re-pointing it is caught.
  const inside = (real: string): boolean => real === top || real.startsWith(`${top}/`);
  const walk = (dir: string): void => {
    const key = realpathSync(dir);
    if (seen.has(key)) return;
    seen.add(key);
    for (const entry of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      if (dir === root && (entry.name === '.git' || entry.name === '.loop-home')) continue;
      const path = join(dir, entry.name);
      if (skip(relative(root, path))) continue;
      // A symlink is recorded by a hash of its target (not followed): a rogue new or repointed link
      // changes the listing without matching isFile()/isDirectory(), so it must be caught here. The
      // uniform `<relpath> <hash>` shape keeps the listing parseable when a path contains spaces; the
      // `symlink:` prefix keeps a link distinct from a file whose bytes equal the link target.
      if (entry.isSymbolicLink()) {
        lines.push(`${relative(root, path)} link ${createHash('sha256').update(`symlink:${readlinkSync(path)}`).digest('hex')}`);
        // The harness roots are deployed through links, so a write that reaches a skill through one
        // changes nothing about the link itself. The target's content is hashed as well; `seen`
        // holds real paths, so a link pointing back inside the tree cannot loop.
        if (!existsSync(path) || !inside(realpathSync(path))) continue;
        if (statSync(path).isDirectory()) walk(path);
        else lines.push(`${relative(root, path)} target ${mode(path)} ${createHash('sha256').update(readFileSync(path)).digest('hex')}`);
        continue;
      }
      else if (entry.isDirectory()) walk(path);
      else if (entry.isFile()) lines.push(`${relative(root, path)} ${mode(path)} ${createHash('sha256').update(readFileSync(path)).digest('hex')}`);
    }
  };
  walk(root);
  return lines.join('\n');
}
