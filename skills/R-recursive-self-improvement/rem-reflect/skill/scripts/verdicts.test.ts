import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { readCalls } from './calls.ts';
import type { CallRecord } from './calls.ts';
import type { Trace } from './harvest.ts';
import { commandId, externalVerdicts, verdictRef } from './verdicts.ts';

// Real records copied out of this machine's sessions (paths and ids redacted), kept in their raw nested shape.
const fixtures = JSON.parse(readFileSync(fileURLToPath(new URL('./selftest/fixtures/verdict-traces.json', import.meta.url)), 'utf8')) as Record<string, Trace>;

function call(line: number, command: string, failed: boolean, result: string | null = null): CallRecord {
  return { call_id: `c${line}`, line_start: line - 1, line_end: line, turn: null, tool: 'Bash', target: command.slice(0, 200),
    started_at: null, ended_at: null, failed, failure_kind: failed ? 'exit_nonzero' : null, exit_code: failed ? 1 : null,
    benign_nonzero: false, error_excerpt: failed ? result : null, command_text: command, result_excerpt: result };
}
const brief = (calls: readonly CallRecord[]) => externalVerdicts(calls).map(item => [item.line, item.kind, item.passed]);

test('commandId finds the verdict command behind the wrappers real sessions put in front of it', () => {
  assert.equal(commandId('cd /x && npx vitest run a'), 'vitest');
  assert.equal(commandId('timeout 300 infisical run -- bun test'), 'bun test');
  assert.equal(commandId('S=/tmp; python3 -m pytest -q'), 'pytest');
  assert.equal(commandId('git status && git push origin main'), 'git push');
  assert.equal(commandId('ls -la'), null);
  assert.equal(commandId('infisical run -p app -c dev -- npx vitest run tests/a.test.ts'), 'vitest');
  assert.equal(commandId('env -u HTTPS_PROXY -u HTTP_PROXY timeout 300 npx vitest run a'), 'vitest');
  assert.equal(commandId('./node_modules/.bin/vitest run'), 'vitest');
  assert.equal(commandId('.venv/bin/pytest -q'), 'pytest');
  assert.equal(commandId('uv run python -m pytest test/a.py -q'), 'pytest');
  assert.equal(commandId('bash tests/release.t'), null, 'a .t script is a test only as the command itself');
  assert.equal(commandId('tests/release.t'), 'release.t');
  assert.equal(commandId("rg -n 'foo|bar' src && npm test"), 'npm test', 'a | inside quotes is not a pipe');
  assert.equal(commandId('git add -A && git commit -m x && git push'), 'git push', 'same-family segments merge');
  assert.equal(commandId('pytest a.py && npm run build && pytest b.py'), null, 'two verdict families in one command');
  // A wrapper's own option is dropped, `run test` is a test only for the package managers.
  assert.equal(commandId('npx --yes vitest run a'), 'vitest');
  assert.equal(commandId('npx -y jest'), 'jest');
  assert.equal(commandId('pnpm run test'), 'pnpm run test');
  assert.equal(commandId('cargo run test'), null);
  assert.equal(commandId('sudo -E make'), 'make');
});

test('workspace selectors and package scripts produce external verdicts', () => {
  assert.deepEqual(brief([
    call(10, 'pnpm -F @acme/api exec vitest run x.test.ts', false, 'Tests  3 passed (3)'),
    call(11, 'pnpm -F web typecheck', true, 'error TS2322'),
    call(12, 'pnpm typecheck', false),
    call(13, 'pnpm lint', false),
    call(14, 'pnpm run lint', false),
    call(15, 'npm run typecheck', false),
    call(16, 'bun run lint', false),
    call(17, 'pnpm --filter=@acme/api run lint', false),
    call(18, 'pnpm test:unit', false, '4 passed'),
    call(19, 'npm run test:e2e', false, '1 failed'),
    call(20, 'pnpm -F web run test:e2e', false, '2 passed'),
    call(21, 'pnpm test:unit', false, 'No tests found'),
    call(22, 'pnpm test:unit', true, 'Failed to load test configuration'),
    call(23, 'pnpm -F web dev', true),
  ]), [
    [10, 'test', true], [11, 'typecheck_lint', false], [12, 'typecheck_lint', true],
    [13, 'typecheck_lint', true], [14, 'typecheck_lint', true], [15, 'typecheck_lint', true],
    [16, 'typecheck_lint', true], [17, 'typecheck_lint', true], [18, 'test', true],
    [19, 'test', false], [20, 'test', true], [22, 'test', false],
  ]);
  assert.equal(commandId('pnpm --filter @acme/api exec vitest run'), 'vitest');
  assert.equal(commandId('pnpm --filter=@acme/api exec vitest run'), 'vitest');
  assert.equal(commandId('pnpm -F web test'), 'pnpm test');
  assert.equal(commandId('pnpm test'), 'pnpm test');
  assert.equal(commandId('pnpm exec vitest run'), 'vitest');
});

test('the four real excerpts yield two, two, zero and zero verdicts', () => {
  const vitest = readCalls(fixtures.claude_vitest);
  assert.ok(vitest.length > 0, 'the instrument sees the Claude Code calls');
  assert.deepEqual(brief(vitest), [[184, 'test', false], [202, 'test', true]]);
  assert.deepEqual(brief(readCalls(fixtures.codex_pytest)), [[710, 'test', false], [720, 'test', true]]);
  assert.deepEqual(brief(readCalls(fixtures.claude_ls)), []);
  // unittest's own zero-count summary, as the real one at a Codex line 1169 printed it, on a pytest call that exited 0.
  assert.deepEqual(brief([call(30, 'python3 -m pytest -q tests/', false, '----------------------------------------------------------------------\nRan 0 tests in 1.117s\n\nOK\n')]), []);
});

test('combined commands: one verdict family per command, and only tests need a summary line', () => {
  assert.deepEqual(brief([call(10, 'git add -A && git commit -m x', false, '[main abc] x\n 1 file changed')]), [[10, 'landed', true]]);
  assert.deepEqual(brief([call(11, 'git commit -m x && git push', false, 'To github.com:a/b.git\n   abc..def  main -> main')]), [[11, 'landed', true]]);
  assert.deepEqual(brief([call(12, 'npm run build && npm test', true, 'src/a.ts(3,1): error TS2322\nnpm ERR! code ELIFECYCLE')]), [],
    'build and test in one command: the failure cannot be attributed');
  assert.deepEqual(brief([call(13, 'pytest -q', true, 'ImportError while loading conftest')]), [[13, 'test', false]],
    'a failed call with a test identity is a failed test verdict even without a summary line');
  assert.deepEqual(brief([call(14, 'pytest -q', false, 'collected 0 items')]), [],
    'a test identity that neither failed nor printed a summary line is no verdict');
  assert.deepEqual(brief([call(19, 'pytest a.py && npm run build && pytest b.py', true, '12 passed in 0.3s\nerror: build failed')]), []);
  assert.deepEqual(brief([call(15, 'cd x && npx vitest run', false, ' Test Files  2 passed (2)\n      Tests  12 passed (12)')]), [[15, 'test', true]]);
  assert.deepEqual(brief([call(16, 'cd x && npx vitest run 2>&1 | tail -5', false, '      Tests  3 failed | 9 passed (12)')]), [[16, 'test', false]],
    'a failing summary line is a failed verdict even when the pipe exited 0');
  assert.deepEqual(brief([call(17, 'pytest -q', false, '\x1b[32m\x1b[1m2 passed\x1b[0m\x1b[32m in 1.27s\x1b[0m')]), [[17, 'test', true]], 'colour codes do not hide the count');
  assert.deepEqual(brief([call(18, 'cd x && tsc --noEmit', false, '')]), [[18, 'typecheck_lint', true]]);
  assert.deepEqual(brief([call(21, 'bun test 2>&1 | tee test.log', false, ' 1 pass\n 1 fail\nRan 2 tests across 1 file. [0.31s]')]), [[21, 'test', false]],
    "bun's own fail line is a failed verdict even when the pipe exited 0");
  assert.deepEqual(brief([call(22, 'bun test', false, ' 2 pass\n 0 fail\nRan 2 tests across 1 file. [0.31s]')]), [[22, 'test', true]]);
});

test('a success lesson may cite a passed test only when no test ran after it', () => {
  const calls = [
    call(20, 'pytest a.py', false, '3 passed in 0.2s'),
    call(40, 'pytest a.py && npm run build', true, '1 failed, 2 passed in 0.2s\nbuild skipped'),
  ];
  const verdicts = externalVerdicts(calls);
  assert.deepEqual(verdicts.map(item => [item.line, item.kind, item.passed]), [[20, 'test', true]], 'the second call carries two families and no verdict');
  const evidence = [{ line_start: 21, line_end: 22 }];
  const refused = verdictRef({ polarity: 'from_success', verdict_line: 20, evidence }, verdicts, calls);
  assert.ok('reason' in refused && /test ran later at line 40/.test(refused.reason), JSON.stringify(refused));
  assert.deepEqual(verdictRef({ polarity: 'from_success', verdict_line: 20, evidence }, verdicts, calls.slice(0, 1)), { ref: { line: 20, kind: 'test', passed: true } });
  // A failure lesson cites a failed test, check or build near its evidence; never a landing, never a far line.
  const failing = [call(100, 'tsc --noEmit', true, 'error TS2322'), call(300, 'git push', true, 'rejected')];
  const failed = externalVerdicts(failing);
  assert.deepEqual(verdictRef({ polarity: 'from_failure', verdict_line: 100, evidence: [{ line_start: 150, line_end: 150 }] }, failed, failing), { ref: { line: 100, kind: 'typecheck_lint', passed: false } });
  assert.match(String((verdictRef({ polarity: 'from_failure', verdict_line: 100, evidence: [{ line_start: 161, line_end: 161 }] }, failed, failing) as { reason: string }).reason), /more than 60 lines/);
  assert.match(String((verdictRef({ polarity: 'from_failure', verdict_line: 300, evidence: [{ line_start: 300, line_end: 300 }] }, failed, failing) as { reason: string }).reason), /landed/);
  assert.match(String((verdictRef({ polarity: 'from_failure', verdict_line: 7, evidence }, failed, failing) as { reason: string }).reason), /names no external verdict/);
});

test('the whole command text identifies a test that the 200-character target cuts off', () => {
  const [long] = readCalls(fixtures.claude_long_prefix);
  assert.ok(long.command_text !== null && long.command_text.indexOf('bun test') > 200, 'the real prefix is longer than the target cut');
  assert.equal(long.target?.length, 200);
  assert.equal(commandId(long.command_text ?? ''), 'bun test');
  assert.equal(commandId(long.target ?? ''), null);
});
