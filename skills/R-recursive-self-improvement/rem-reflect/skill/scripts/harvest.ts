import { closeSync, existsSync, openSync, readFileSync, readdirSync, readSync, statSync } from 'node:fs';
import { basename, join } from 'node:path';
import { isObject, isWithin, limits, messages, paths, skillRoots, validateRoots } from './config.ts';
import type { Config } from './config.ts';
import { gitRemote, resolveIdentity } from './identity.ts';
import type { Harness, Identity } from './identity.ts';
import { atomicWrite } from './store.ts';
import type { State } from './store.ts';
import { readCatalogue, resolveSkill } from './catalogue.ts';
import type { CatalogueEntry } from './catalogue.ts';

// Node cannot build a string longer than 0x1fffffe8 chars, so a session file at or above that many
// bytes cannot be read with readFileSync(utf8) — the attempt throws and, unguarded, crashes the whole
// harvest. Such a file (a pathological multi-hundred-MB session) is skipped so one giant session never
// kills the daily run; it never shrinks, so it is marked done rather than retried every run.
const MAX_SESSION_BYTES = 0x1fffffe8;

export interface StoredRecord {
  line_number: number;
  source_line: number;
  record: Record<string, unknown>;
  user_text?: string;
}
export interface Trace extends Identity {
  trace_id: string;
  session_id: string;
  version: number;
  source_path: string;
  source_line_range: [number, number];
  source_mtime: number;
  records: StoredRecord[];
  skipped_records: number;
  skipped_blocks: number;
  redactions: number;
  trivial: boolean;
  skills_loaded: string[];
  verdict_line?: { text: string; line_number: number };
}
export interface ParsedLine { source_line: number; record: Record<string, unknown> }
export type ParsedSession = { ok: true; lines: ParsedLine[]; complete_lines: number }
  | { ok: false; invalid_line: number; complete_lines: number };
export interface HistoryEntry { sessionId: string; timestamp: string | number; display: string; project?: string }

export function parseSession(text: string): ParsedSession {
  const last = text.lastIndexOf('\n');
  const complete = last < 0 ? [] : text.slice(0, last).split('\n');
  const lines: ParsedLine[] = [];
  for (const [index, line] of complete.entries()) {
    let record: unknown;
    try { record = JSON.parse(line); }
    catch { return { ok: false, invalid_line: index + 1, complete_lines: complete.length }; }
    // Valid JSON of an unknown shape is an unknown record, not a JSON failure.
    lines.push({ source_line: index + 1, record: isObject(record) ? record : { type: 'unknown' } });
  }
  return { ok: true, lines, complete_lines: complete.length };
}

export function redact(text: string): { text: string; count: number } {
  let count = 0;
  const patterns = [
    /-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----[\s\S]*?-----END (?:[A-Z]+ )?PRIVATE KEY-----/g,
    /\bBearer\s+[A-Za-z0-9._~+\/-]+=*/gi,
    /\bsk-[A-Za-z0-9_-]+/g,
    /\b(?:AKIA|ASIA)[A-Z0-9]{16}\b/g,
    /\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|AIza[A-Za-z0-9_-]{20,})\b/g,
    /\b(?:api[_-]?key|access[_-]?token|secret[_-]?key)["']?\s*[:=]\s*["']?([A-Za-z0-9_./+\-=]{8,})["']?/gi,
  ];
  for (const pattern of patterns) text = text.replace(pattern, () => { count++; return messages.redacted; });
  return { text, count };
}

export function redactValue(value: unknown): { value: unknown; count: number } {
  if (typeof value === 'string') {
    const result = redact(value);
    return { value: result.text, count: result.count };
  }
  if (Array.isArray(value)) {
    const values = value.map(redactValue);
    return { value: values.map(item => item.value), count: values.reduce((sum, item) => sum + item.count, 0) };
  }
  if (!isObject(value)) return { value, count: 0 };
  const output: Record<string, unknown> = {};
  let count = 0;
  for (const [key, item] of Object.entries(value)) {
    if (/^(?:api[_-]?key|access[_-]?token|secret[_-]?key|authorization)$/i.test(key) && typeof item === 'string' && item) {
      output[key] = messages.redacted; count++;
    } else {
      const result = redactValue(item);
      output[key] = result.value; count += result.count;
    }
  }
  return { value: output, count };
}

export function contentText(content: unknown): string {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.filter(isObject).map(block => typeof block.text === 'string' ? block.text : '').filter(Boolean).join('\n');
}

export function payload(record: Record<string, unknown>, harness: Harness): Record<string, unknown> {
  const value = harness === 'codex' ? record.payload : record.message;
  return isObject(value) ? value : {};
}

export function skillsLoaded(records: readonly StoredRecord[], harness: Harness, catalogue: readonly CatalogueEntry[]): string[] {
  const names: string[] = [];
  for (const item of records) {
    const message = payload(item.record, harness);
    if (harness === 'codex' && message.role === 'user') {
      const match = /^<skill>\s*<name>([^<]+)<\/name>/.exec(contentText(message.content).trimStart());
      if (match) names.push(match[1].trim());
    }
    if (harness === 'claude-code' && Array.isArray(message.content)) {
      for (const block of message.content.filter(isObject)) {
        if (block.type === 'tool_use' && block.name === 'Skill' && isObject(block.input) && typeof block.input.skill === 'string') names.push(block.input.skill);
      }
    }
  }
  return [...new Set(names.map(name => resolveSkill(name, catalogue)))];
}

export function verdictLine(records: readonly StoredRecord[], pattern: string): Trace['verdict_line'] {
  const regex = new RegExp(pattern);
  let found: Trace['verdict_line'];
  for (const item of records) {
    const message = payload(item.record, 'codex');
    if (message.role !== 'assistant') continue;
    for (const line of contentText(message.content).split('\n')) {
      if (regex.test(line)) found = { text: line, line_number: item.line_number };
    }
  }
  return found;
}

export function isTrivial(records: readonly StoredRecord[], harness: Harness): boolean {
  let assistants = 0;
  for (const item of records) {
    const message = payload(item.record, harness);
    if (message.role === 'assistant' || item.record.type === 'assistant') assistants++;
    if (message.type === 'function_call' || message.type === 'custom_tool_call') return false;
    if (Array.isArray(message.content) && message.content.filter(isObject).some(block => block.type === 'tool_use' || block.type === 'server_tool_use')) return false;
  }
  return assistants <= 2;
}

export function readHistory(home: string): HistoryEntry[] {
  const path = join(home, 'history.jsonl');
  if (!existsSync(path)) return [];
  const entries: HistoryEntry[] = [];
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    let value: unknown;
    try { value = JSON.parse(line); } catch { continue; }
    if (isObject(value) && typeof value.sessionId === 'string' && typeof value.display === 'string'
      && (typeof value.timestamp === 'string' || typeof value.timestamp === 'number')) {
      entries.push({ sessionId: value.sessionId, display: value.display, timestamp: value.timestamp,
        ...(typeof value.project === 'string' ? { project: value.project } : {}) });
    }
  }
  return entries;
}

export function historyPrompt(history: readonly HistoryEntry[], session: string, timestamp: unknown): string | undefined {
  const time = (value: unknown): number => typeof value === 'number' ? value : Date.parse(String(value));
  return history.find(item => item.sessionId === session && time(item.timestamp) === time(timestamp))?.display;
}

function walk(root: string, recursive: boolean): string[] {
  if (!existsSync(root)) return [];
  const files: string[] = [];
  for (const entry of readdirSync(root, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const path = join(root, entry.name);
    if (entry.isFile()) files.push(path);
    else if (entry.isDirectory() && recursive) files.push(...walk(path, true));
  }
  return files;
}

// Every stored session, all versions. `withText` picks the traces that keep their records; every other
// trace comes back with `records: []`, so a store of gigabytes of session text is never in memory at once.
// A caller passes `() => false` only when it reads a trace's summary fields, never its text.
export function existingTraces(store: string, withText: (trace: Trace) => boolean = () => true): Trace[] {
  return walk(join(store, 'raw'), true).filter(path => /\.v\d+\.json$/.test(path)).map(path => {
    const value: unknown = JSON.parse(readFileSync(path, 'utf8'));
    if (!isObject(value) || typeof value.session_id !== 'string' || typeof value.version !== 'number'
      || !Array.isArray(value.source_line_range) || !Array.isArray(value.records)) throw new Error(`raw: invalid trace ${path}`);
    // Store-owned immutable format; reject missing identity before indexing it.
    if (value.agent_id !== 'claude-code' && value.agent_id !== 'codex') throw new Error(`raw: invalid agent_id ${path}`);
    const trace = value as unknown as Trace;
    if (!withText(trace)) trace.records = [];
    return trace;
  });
}

type TraceVersion = Pick<Trace, 'session_id' | 'agent_id' | 'user_id' | 'version' | 'source_line_range' | 'source_path' | 'source_mtime'>;

function firstLine(path: string): string {
  const fd = openSync(path, 'r');
  const chunks: Buffer[] = [];
  const buffer = Buffer.alloc(8192);
  try {
    for (;;) {
      const length = readSync(fd, buffer);
      if (!length) break;
      const newline = buffer.subarray(0, length).indexOf(10);
      chunks.push(Buffer.from(buffer.subarray(0, newline < 0 ? length : newline)));
      if (newline >= 0) break;
    }
    return Buffer.concat(chunks).toString('utf8');
  } finally { closeSync(fd); }
}

function traceVersions(store: string): TraceVersion[] {
  return walk(join(store, 'raw'), true).filter(path => /\.v\d+\.json$/.test(path)).map(path => {
    const header: unknown = JSON.parse(firstLine(path).replace(/,"records":\[$/, '}'));
    if (!isObject(header) || typeof header.session_id !== 'string' || typeof header.user_id !== 'string'
      || (header.agent_id !== 'claude-code' && header.agent_id !== 'codex')
      || typeof header.version !== 'number' || !Number.isInteger(header.version) || header.version < 1
      || !Array.isArray(header.source_line_range) || header.source_line_range.length !== 2
      || !header.source_line_range.every(line => Number.isInteger(line) && line >= 1)
      || typeof header.source_path !== 'string' || typeof header.source_mtime !== 'number') {
      throw new Error(`raw: invalid version header ${path}`);
    }
    return { session_id: header.session_id, user_id: header.user_id, agent_id: header.agent_id,
      version: header.version, source_line_range: [header.source_line_range[0], header.source_line_range[1]],
      source_path: header.source_path, source_mtime: header.source_mtime };
  });
}

function knownRecords(lines: readonly ParsedLine[], harness: Harness): { records: StoredRecord[]; skipped: number; blocks: number } {
  const records: StoredRecord[] = [];
  let skipped = 0;
  let blocks = 0;
  for (const line of lines) {
    const known = harness === 'claude-code' ? ['user', 'assistant'] : ['session_meta', 'response_item', 'turn_context', 'event_msg'];
    if (!known.includes(String(line.record.type))) { skipped++; continue; }
    if (line.record.type === 'event_msg') {
      const event = payload(line.record, 'codex');
      if (event.type !== 'turn_aborted' && (event.type !== 'item_completed' || !isObject(event.item)
        || !['CommandExecution', 'FileChange', 'McpToolCall'].includes(String(event.item.type)))) {
        skipped++; continue;
      }
    }
    const record = structuredClone(line.record);
    const message = payload(record, harness);
    if (Array.isArray(message.content)) {
      message.content = message.content.filter(block => {
        const accepted = isObject(block) && ['text', 'input_text', 'output_text', 'tool_use', 'tool_result', 'image', 'thinking', 'reasoning', 'server_tool_use', 'advisor_tool_result'].includes(String(block.type));
        if (!accepted) blocks++;
        return accepted;
      });
    }
    records.push({ line_number: records.length + 2, source_line: line.source_line, record });
  }
  return { records, skipped, blocks };
}

export function serializeTrace(trace: Trace): string {
  const { records, ...metadata } = trace;
  // Metadata occupies line 1; each stored record occupies exactly one subsequent line.
  return `${JSON.stringify(metadata).slice(0, -1)},"records":[\n${records.map(item => JSON.stringify(item)).join(',\n')}${records.length ? '\n' : ''}]}\n`;
}

function pathPart(value: string): string {
  return value.split('/').map(part => part === '.' || part === '..' || !part ? encodeURIComponent(part).replaceAll('.', '%2E') || '%00' : encodeURIComponent(part)).join('/');
}

function sessionDetails(lines: readonly ParsedLine[], harness: Harness, path: string): { id: string; cwd: string; remote?: string; originator?: string; role?: string } {
  const metadata = lines.find(line => line.record.type === 'session_meta')?.record.payload;
  const meta = isObject(metadata) ? metadata : {};
  const first = lines.find(line => typeof line.record.cwd === 'string')?.record ?? {};
  const id = harness === 'claude-code' ? basename(path, '.jsonl') : meta.id;
  if (typeof id !== 'string' || !id || /[\/\\\0]/.test(id) || id === '.' || id === '..') throw new Error(`session: invalid session id in ${path}`);
  const cwd = harness === 'codex' ? meta.cwd : first.cwd;
  const remote = isObject(meta.git) ? meta.git.repository_url : undefined;
  const role = harness === 'codex' ? meta.role : first.role;
  return { id, cwd: typeof cwd === 'string' ? cwd : '',
    ...(typeof remote === 'string' ? { remote } : {}),
    ...(typeof meta.originator === 'string' ? { originator: meta.originator } : {}),
    ...(typeof role === 'string' ? { role } : {}) };
}

export interface HarvestResult { traces: Trace[]; log: string[] }

export function harvest(store: string, config: Config, state: State, user: string, now: Date = new Date()): HarvestResult {
  validateRoots(config, store);
  const [claudeSkills, codexSkills] = skillRoots(config);
  const catalogues: Record<Harness, CatalogueEntry[]> = {
    'claude-code': readCatalogue([claudeSkills]),
    codex: readCatalogue([codexSkills]),
  };
  const history = readHistory(config.claude_home);
  const signals: unknown = JSON.parse(readFileSync(join(paths.references, 'signals.json'), 'utf8'));
  if (!isObject(signals) || Object.keys(signals).length !== 1 || typeof signals.codex_exec_verdict !== 'string') throw new Error('signals.json: expected one codex_exec_verdict regex');
  const existing = traceVersions(store);
  // The newest source mtime already harvested per session file. A file whose mtime is unchanged has no
  // new lines, so it is skipped without re-reading — real session files reach hundreds of MB and
  // re-parsing the whole 7-day window every run otherwise dominates the run.
  const harvestedMtime = new Map<string, number>();
  for (const v of existing) {
    const prev = harvestedMtime.get(v.source_path);
    if (prev === undefined || v.source_mtime > prev) harvestedMtime.set(v.source_path, v.source_mtime);
  }
  const traces: Trace[] = [];
  const log = ['harvested sessions under store: 0'];
  const floor = now.getTime() - limits.firstDays * 86_400_000;
  const quiet = now.getTime() - limits.quietMinutes * 60_000;
  const inputs: { path: string; harness: Harness; mtime: number }[] = [];
  for (const [root, harness] of [[config.claude_root, 'claude-code'], [config.codex_root, 'codex']] as const) {
    const candidates = harness === 'codex' ? walk(root, true).filter(path => /^rollout-.*\.jsonl$/.test(basename(path)))
      : (existsSync(root) ? readdirSync(root, { withFileTypes: true }).filter(entry => entry.isDirectory()).flatMap(entry => walk(join(root, entry.name), false).filter(path => path.endsWith('.jsonl'))) : []);
    const pending = Object.keys(state.pending).filter(path => isWithin(root, path));
    for (const path of new Set([...candidates, ...pending])) {
      if (isWithin(store, path)) continue;
      if (!existsSync(path)) { log.push(`pending missing: ${path}`); continue; }
      inputs.push({ path, harness, mtime: statSync(path).mtimeMs });
    }
  }
  const startingCursors = { ...state.cursors };
  for (const input of inputs.sort((a, b) => a.mtime - b.mtime || a.path.localeCompare(b.path))) {
    const { path, harness, mtime } = input;
    const pending = state.pending[path];
    if (pending?.status === 'unparseable' || mtime > quiet) continue;
    const earliest = Math.min(floor, ...Object.values(startingCursors));
    if (!pending && mtime < earliest) continue;
    // Already harvested and unchanged since (same mtime, no appended lines): skip without re-reading.
    if (!pending && harvestedMtime.get(path) === mtime) continue;
    const size = statSync(path).size;
    if (size >= MAX_SESSION_BYTES) {
      // One more failed attempt, like a parse failure below: state.json requires failures >= 1.
      state.pending[path] = { failures: (pending?.failures ?? 0) + 1, status: 'unparseable' };
      log.push(`oversized: ${path} is ${size} bytes; skipped (over the ${MAX_SESSION_BYTES}-byte readable limit)`);
      continue;
    }
    const parsed = parseSession(readFileSync(path, 'utf8'));
    if (statSync(path).mtimeMs !== mtime) { log.push(`session changed during harvest: ${path}`); continue; }
    if (!parsed.ok) {
      const failures = (pending?.failures ?? 0) + 1;
      state.pending[path] = { failures, status: failures >= 3 ? 'unparseable' : 'pending' };
      log.push(`${state.pending[path].status}: ${path} invalid line ${parsed.invalid_line}; failures ${failures}`);
      continue;
    }
    if (!parsed.complete_lines) continue;
    const detail = sessionDetails(parsed.lines, harness, path);
    const missingCwd = detail.cwd && !existsSync(detail.cwd) ? detail.cwd : undefined;
    if (missingCwd && harness === 'claude-code') detail.cwd = history.find(item => item.sessionId === detail.id && item.project && existsSync(item.project))?.project ?? '';
    const identity = resolveIdentity({ user_id: user, harness, cwd: detail.cwd, remote: detail.remote ?? gitRemote(detail.cwd),
      project_names: config.project_names, originator: detail.originator, role: detail.role });
    if (missingCwd) identity.missing_cwd = missingCwd;
    const key = `${harness}:${identity.project_id}`;
    const cursor = startingCursors[key] ?? floor;
    state.cursors[key] ??= cursor;
    if (!pending && mtime < cursor) continue;
    const versions = existing.filter(trace => trace.session_id === detail.id && trace.agent_id === harness && trace.user_id === user);
    const lastLine = Math.max(0, ...versions.map(trace => trace.source_line_range[1]));
    if (parsed.complete_lines <= lastLine) { delete state.pending[path]; continue; }
    const sessionRecords = knownRecords(parsed.lines, harness);
    const selected = lastLine ? knownRecords(parsed.lines.filter(line => line.source_line > lastLine), harness) : sessionRecords;
    const trivial = isTrivial(sessionRecords.records, harness);
    const loaded = skillsLoaded(sessionRecords.records, harness, catalogues[harness]);
    let redactions = 0;
    for (const item of selected.records) {
      if (harness === 'claude-code' && item.record.type === 'user') {
        const typed = historyPrompt(history, detail.id, item.record.timestamp);
        if (typed !== contentText(payload(item.record, harness).content)) item.user_text = typed;
      }
      const result = redactValue(item);
      if (!isObject(result.value) || !isObject(result.value.record)) throw new Error('redaction: record shape changed');
      item.record = result.value.record;
      if (typeof result.value.user_text === 'string') item.user_text = result.value.user_text;
      redactions += result.count;
    }
    const version = Math.max(0, ...versions.map(trace => trace.version)) + 1;
    const trace: Trace = { ...identity, trace_id: `${detail.id}.v${version}`, session_id: detail.id, version,
      source_path: path, source_line_range: [lastLine + 1, parsed.complete_lines], source_mtime: mtime,
      records: selected.records, skipped_records: selected.skipped, skipped_blocks: selected.blocks, redactions,
      trivial, skills_loaded: loaded };
    if (trace.originator === 'codex_exec') trace.verdict_line = verdictLine(trace.records, signals.codex_exec_verdict);
    const target = join(store, 'raw', pathPart(user), pathPart(identity.project_id), harness, `${encodeURIComponent(detail.id)}.v${version}.json`);
    if (existsSync(target)) throw new Error(`raw: refusing to replace ${target}`);
    atomicWrite(target, serializeTrace(trace));
    existing.push(trace); traces.push(trace);
    state.cursors[key] = Math.max(state.cursors[key], mtime);
    delete state.pending[path];
    log.push(`harvested ${trace.trace_id}; skipped records ${trace.skipped_records}; skipped blocks ${trace.skipped_blocks}`);
  }
  return { traces, log };
}
