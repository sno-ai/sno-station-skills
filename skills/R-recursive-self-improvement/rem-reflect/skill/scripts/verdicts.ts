import type { CallRecord } from './calls.ts';
import type { Evidence } from './evidence.ts';

// An external verdict is a test, type/lint check, build or git landing that code identifies in a session's
// calls; the model never decides one. Lessons cite one through `verdict_ref`.
export type VerdictKind = 'test' | 'typecheck_lint' | 'build' | 'landed';
export interface Verdict { line: number; kind: VerdictKind; passed: boolean; command: string }
export interface VerdictRef { line: number; kind: VerdictKind; passed: boolean }

const KINDS: Record<string, VerdictKind> = {
  pytest: 'test', vitest: 'test', jest: 'test', 'bun test': 'test', 'npm test': 'test', 'pnpm test': 'test',
  'bun run test': 'test', 'npm run test': 'test', 'pnpm run test': 'test',
  'cargo test': 'test', 'go test': 'test', bats: 'test', prove: 'test',
  tsc: 'typecheck_lint', ruff: 'typecheck_lint', eslint: 'typecheck_lint', mypy: 'typecheck_lint',
  shellcheck: 'typecheck_lint', biome: 'typecheck_lint',
  'pnpm typecheck': 'typecheck_lint', 'pnpm lint': 'typecheck_lint', 'pnpm run typecheck': 'typecheck_lint', 'pnpm run lint': 'typecheck_lint',
  'npm run typecheck': 'typecheck_lint', 'npm run lint': 'typecheck_lint', 'bun run typecheck': 'typecheck_lint', 'bun run lint': 'typecheck_lint',
  'npm run build': 'build', 'bun build': 'build', 'cargo build': 'build', make: 'build',
  'git commit': 'landed', 'git push': 'landed',
};
// Commands whose identity includes their first subcommand; only the package managers run a script as `run <name>`
// (`cargo run test` starts a program with an argument).
const MULTI = new Set(['bun', 'npm', 'pnpm', 'cargo', 'go', 'git']);
const RUN_SCRIPT = new Set(['bun', 'npm', 'pnpm']);
// A package script named `test:<suffix>` (`pnpm test:unit`, `npm run test:e2e`) runs tests.
const TEST_SCRIPT = /^(?:pnpm|(?:pnpm|npm|bun) run) test:\S/;
// Wrappers in front of the real command: dropped with their argument count.
const DROP_ONE = new Set(['env', 'nice', 'sudo', 'npx', 'bunx']);
const DROP_TWO = new Set(['cd', 'timeout', '-u', 'uv run', 'pnpm exec', 'npm exec', 'python3 -m', 'python -m']);
const PASS = /\b([1-9]\d*) (passed|passing)\b|Ran ([1-9]\d*) tests?|^ok [1-9]\d* /m;
// `fail` alone is bun's summary line (` 1 fail`), which comes with a `Ran N tests` line the pass expression matches.
const FAIL = /\b[1-9]\d* (failed|failing|fail)\b|^not ok /m;
const ANSI = /\x1b\[[0-9;]*m/g;

// Split a shell command at &&, ||, ;, | and newlines outside quotes.
export function segments(command: string): string[] {
  const out: string[] = [];
  let current = '';
  let quote: string | null = null;
  for (let i = 0; i < command.length; i++) {
    const ch = command[i];
    if (quote) {
      current += ch;
      if (ch === quote) quote = null;
      else if (ch === '\\' && quote === '"') current += command[++i] ?? '';
      continue;
    }
    if (ch === "'" || ch === '"') { quote = ch; current += ch; continue; }
    if (ch === '\\') { current += ch + (command[++i] ?? ''); continue; }
    if ((ch === '&' || ch === '|') && command[i + 1] === ch) { out.push(current); current = ''; i++; continue; }
    if (ch === ';' || ch === '|' || ch === '\n') { out.push(current); current = ''; continue; }
    current += ch;
  }
  out.push(current);
  return out.map(segment => segment.trim()).filter(Boolean);
}

function unwrapped(words: string[]): string[] {
  for (;;) {
    const [first, second] = words;
    if (first === undefined) return words;
    if (DROP_TWO.has(first) || DROP_TWO.has(`${first} ${second}`)) { words = words.slice(2); continue; }
    // A wrapper's own option (`npx --yes`, `sudo -E`) comes before the command word and is dropped with the wrapper.
    if (DROP_ONE.has(first) || first.startsWith('-') || /^[A-Za-z_]\w*=/.test(first)) { words = words.slice(1); continue; }
    // pnpm's workspace selector (`pnpm -F <pkg> exec vitest`, `pnpm --filter=<pkg> typecheck`) picks a package, not the command.
    if (first === 'pnpm' && (second === '-F' || second === '--filter')) { words = [first, ...words.slice(3)]; continue; }
    if (first === 'pnpm' && second?.startsWith('--filter=')) { words = [first, ...words.slice(2)]; continue; }
    // A secrets or environment runner (`<tool> run [options] -- command`) wraps the real command; a command's own `run` does not.
    const name = first.slice(first.lastIndexOf('/') + 1);
    if (second === 'run' && verdictKind(name) === null && !MULTI.has(name)) {
      const end = words.indexOf('--');
      words = end === -1 ? words.slice(2) : words.slice(end + 1);
      continue;
    }
    return words;
  }
}

// One segment's command word after its wrappers: the first word's file name, plus the first subcommand
// of a multi-path command (`npm run build`, `git push`). Null for a segment that is only wrappers.
export function commandWord(segment: string): string | null {
  // Words split at whitespace outside quotes, so `MSG='a b' cmd` is an assignment and a command.
  const words = segment.match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g) ?? [];
  const [first, second, third] = unwrapped(words);
  if (!first) return null;
  const name = first.slice(first.lastIndexOf('/') + 1);
  if (!MULTI.has(name) || !second) return name;
  return second === 'run' && third && RUN_SCRIPT.has(name) ? `${name} run ${third}` : `${name} ${second}`;
}

export function verdictKind(id: string | null): VerdictKind | null {
  if (!id) return null;
  return KINDS[id] ?? (id.endsWith('.t') || TEST_SCRIPT.test(id) ? 'test' : null);
}

// The verdict identity of a whole command: its verdict-carrying segments must all be one family (they
// merge into one, `git commit && git push` → `git push`); two families in one command give no identity,
// because the aggregated output cannot be attributed to either.
export function commandId(command: string): string | null {
  const judged = segments(command).map(commandWord).filter(word => verdictKind(word) !== null);
  if (new Set(judged.map(verdictKind)).size !== 1) return null;
  return judged[judged.length - 1];
}

// Whether any segment runs a test, verdict or not: a later test call disqualifies a success lesson even when the
// combination rule dropped its verdict, because it may have failed.
export function runsTest(command: string): boolean {
  return segments(command).some(segment => verdictKind(commandWord(segment)) === 'test');
}

export function externalVerdicts(calls: readonly CallRecord[]): Verdict[] {
  const verdicts: Verdict[] = [];
  for (const call of calls) {
    if (call.command_text === null) continue;
    const kind = verdictKind(commandId(call.command_text));
    if (!kind) continue;
    const verdict = { line: call.line_end, kind, command: call.command_text };
    if (kind !== 'test') { verdicts.push({ ...verdict, passed: !call.failed }); continue; }
    // A test verdict needs a summary line with a non-zero count; a test call without one is no verdict.
    const text = (call.result_excerpt ?? '').replace(ANSI, '');
    if (call.failed || FAIL.test(text)) verdicts.push({ ...verdict, passed: false });
    else if (PASS.test(text)) verdicts.push({ ...verdict, passed: true });
  }
  return verdicts;
}

export interface VerdictClaim { polarity: 'from_failure' | 'from_success'; verdict_line: unknown; evidence: readonly Pick<Evidence, 'line_start' | 'line_end'>[] }
// The verdict a lesson may cite, or the reason it may not. A success lesson cites a passed test after which
// no test-identity call ran (a later test may have failed without a verdict); a failure lesson cites a failed
// test, check or build within 60 lines of one of its evidence ranges. Nothing is chosen for the model.
export function verdictRef(claim: VerdictClaim, verdicts: readonly Verdict[], calls: readonly CallRecord[]): { ref: VerdictRef } | { reason: string } {
  const verdict = verdicts.find(item => item.line === claim.verdict_line);
  if (!verdict) return { reason: `verdict_line ${String(claim.verdict_line)} names no external verdict` };
  const ref = { line: verdict.line, kind: verdict.kind, passed: verdict.passed };
  if (claim.polarity === 'from_success') {
    if (verdict.kind !== 'test' || !verdict.passed) return { reason: `from_success cites a ${verdict.passed ? 'passed' : 'failed'} ${verdict.kind} verdict at line ${verdict.line}` };
    const later = calls.find(call => call.line_end > verdict.line && call.command_text !== null && runsTest(call.command_text));
    if (later) return { reason: `from_success cites line ${verdict.line} but a test ran later at line ${later.line_end}` };
    return { ref };
  }
  if (verdict.passed || verdict.kind === 'landed') return { reason: `from_failure cites a ${verdict.passed ? 'passed' : 'failed'} ${verdict.kind} verdict at line ${verdict.line}` };
  if (!claim.evidence.some(item => verdict.line >= item.line_start - 60 && verdict.line <= item.line_end + 60)) {
    return { reason: `from_failure cites line ${verdict.line}, more than 60 lines from every evidence range` };
  }
  return { ref };
}
