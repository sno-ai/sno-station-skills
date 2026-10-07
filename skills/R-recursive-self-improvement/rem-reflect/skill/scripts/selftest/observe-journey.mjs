// the usage-statistics rows rem-reflect sends through `sno observe append`,
// driven through the real CLI entry (`rem-reflect.ts run|accept|reject`) on the fixture store.
// With the recording `sno` shim first on PATH, every call lands as one argv line (after `observe`) in
// REM_OBSERVE_CAPTURE; with no `sno` on PATH at all, the commands must exit as they
// did before the emitters existed and the run's run.log must name the missing program once.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { skillRoots } from '../config.ts';
import { existingTraces } from '../harvest.ts';
import { readLabels } from '../labeler.ts';
import { readLedger } from '../ledger.ts';
import { skillImpact } from '../report.ts';
import {
  tmp, makeConfig, makeStore, writeInstalledSkill, stationSettings,
  writeClaudeSession, claudeUser, claudeAssistant, writeCodexSession, codexMeta, codexUser, codexAssistant,
} from '../test-helpers.ts';

const CLI = fileURLToPath(new URL('../rem-reflect.ts', import.meta.url));
const BIN = fileURLToPath(new URL('./bin', import.meta.url));
const DAY1 = '2026-09-15T00:00:00Z', DAY2 = '2026-09-16T00:00:00Z', DAY3 = '2026-09-17T00:00:00Z';
const RUN1 = '20260915-0000', RUN2 = '20260916-0000', RUN3 = '20260917-0000';
const SRC_MT = new Date('2026-09-14T00:00:00Z').getTime();
const SELF_MT = new Date('2026-09-15T06:00:00Z').getTime();
// `run --now 2026-09-15T00:00:00Z` on a fresh store and `accept <run>/claude-code` on a store
// holding that pending proposal. The consent read fails first in both, as it did then.
const NO_SNO_RUN_EXIT = 0;
const NO_SNO_ACCEPT_EXIT = 0;
const cleanup = [];

// One fixture: a HOME whose .claude/.codex are the harvest roots, three sessions per harness,
// three installed skills per harness, logged-in CLIs, the Sno Station settings file, and a pre-made store.
function fixture() {
  const home = tmp('observe-home');
  const claudeHome = join(home, '.claude'), codexHome = join(home, '.codex');
  for (const name of ['heartbeat', 'second-skill', 'nested-skill']) {
    writeInstalledSkill(claudeHome, name);
    writeInstalledSkill(codexHome, name);
  }
  writeFileSync(join(claudeHome, '.credentials.json'), '{"claude":"fixture-token"}');
  writeFileSync(join(codexHome, 'auth.json'), '{"codex":"fixture-token"}');
  mkdirSync(join(home, '.sno'), { recursive: true });
  writeFileSync(join(home, '.sno', 'settings.json'), stationSettings('rem-enhanced'));
  const config = makeConfig({
    claude_home: claudeHome, codex_home: codexHome,
    claude_root: join(claudeHome, 'projects'), codex_root: join(codexHome, 'sessions'),
    project_names: {}, time_zone: 'UTC',
  });
  for (let i = 0; i < 3; i++) {
    writeClaudeSession(config.claude_root, 'proj', `cc${i}`,
      [claudeUser('/n', `cc${i}`, 'do it'), claudeAssistant('/n', `cc${i}`, [{ type: 'text', text: 'ok' }])], SRC_MT + i);
    writeCodexSession(config.codex_root, `cx${i}`,
      [codexMeta(`cx${i}`, '/n'), codexUser('do it'), codexAssistant('ok')], SRC_MT + i, `2026/09/1${i + 4}`, `2026-09-1${i + 4}T00-00-00`);
  }
  const store = makeStore(config);
  cleanup.push(home, store);
  return { home, config, store, capture: join(home, 'observe.log') };
}

// A PATH holding node, git, the shell tools the loop reaches and the claude/codex shims,
// but no `sno` of any kind.
function noSnoBin() {
  const dir = tmp('observe-nosno-bin');
  cleanup.push(dir);
  for (const prog of ['git', 'sh', 'bash', 'env', 'cat', 'uname', 'dirname', 'basename', 'mkdir', 'rm', 'cp', 'mv',
    'ln', 'chmod', 'mktemp', 'date', 'sort', 'grep', 'sed', 'head', 'tail', 'wc', 'tr', 'cut', 'readlink']) {
    const real = spawnSync('bash', ['-c', `command -v ${prog}`], { encoding: 'utf8' }).stdout.trim();
    if (real) symlinkSync(real, join(dir, prog));
  }
  symlinkSync(process.execPath, join(dir, 'node'));
  for (const shim of ['claude', 'codex', 'shim-core.cjs']) copyFileSync(join(BIN, shim), join(dir, shim));
  const probe = spawnSync(join(dir, 'bash'), ['-c', 'command -v sno'], { env: { PATH: dir }, encoding: 'utf8' });
  assert.notEqual(probe.status, 0, `the no-sno PATH still resolves sno: ${probe.stdout}`);
  return dir;
}

function cli(fx, args, path, extra = {}) {
  const env = { ...process.env, PATH: path, HOME: fx.home, CLAUDE_CONFIG_DIR: join(fx.home, '.claude'),
    CODEX_HOME: join(fx.home, '.codex'), SNO_PROFILE_DIR: join(fx.home, '.sno'), REM_REFLECT_STORE: fx.store, REM_SHIM_MTIME: String(SELF_MT),
    REM_OBSERVE_CAPTURE: fx.capture, REM_SNO_CAPTURE: join(fx.home, 'cloud-requests.jsonl') };
  delete env.REM_SELFTEST;
  delete env.CLAUDECODE;
  Object.assign(env, extra);
  const result = spawnSync(process.execPath, ['--experimental-strip-types', CLI, ...args],
    { env, encoding: 'utf8', timeout: 120_000 });
  return { code: result.status, out: `${result.stdout}${result.stderr}` };
}

// The `sno observe append` rows captured since the previous call, as { event, fields }.
function reader(fx) {
  let seen = 0;
  return () => {
    const text = existsSync(fx.capture) ? readFileSync(fx.capture, 'utf8') : '';
    const fresh = text.slice(seen);
    seen = text.length;
    return fresh.split('\n').filter(Boolean).map(line => {
      const [sub, event, ...args] = line.split(' ');
      assert.equal(sub, 'append', `unexpected observe call: ${line}`);
      return { event, fields: Object.fromEntries(args.map(arg => {
        const match = /^--([a-z_]+)=(.*)$/.exec(arg);
        assert.ok(match, `argument is not --field=value: ${arg} in ${line}`);
        return [match[1], match[2]];
      })) };
    });
  };
}
const only = (rows, event) => rows.filter(row => row.event === event).map(row => row.fields);
const show = (rows) => JSON.stringify(rows);
const status = (store) => JSON.parse(readFileSync(join(store, 'state.json'), 'utf8')).last_terminal?.status;

// --- with `sno` on PATH -------------------------------------------------------------------------
const withSno = `${BIN}:${process.env.PATH}`;
const a = fixture();
const fresh = reader(a);

const run1 = cli(a, ['run', '--trigger', 'timer', '--now', DAY1], withSno);
assert.equal(run1.code, 0, `run --trigger timer exits 0:\n${run1.out}`);
assert.ok(['success', 'no_action'].includes(status(a.store)), `day one terminal is success or no_action, got ${status(a.store)}`);
let rows = fresh();
const harvested = existingTraces(a.store).length;
assert.equal(harvested, 6, 'the fixture harvest read six sessions');
const [runRow, ...extraRuns] = only(rows, 'rsi.run');
assert.ok(runRow && !extraRuns.length, `one rsi.run row: ${show(rows)}`);
assert.deepEqual(Object.keys(runRow).sort(), ['agent', 'duration_ms', 'outcome', 'sessions_read', 'trigger'], show(rows));
assert.ok(rows.every(row => row.fields.agent === 'codex'), `every row outside Claude Code names codex: ${show(rows)}`);
assert.equal(runRow.trigger, 'timer');
assert.equal(runRow.outcome, 'ok');
assert.equal(runRow.sessions_read, String(harvested), 'sessions_read is the harvested count');
assert.match(runRow.duration_ms, /^[1-9][0-9]*$/, 'duration_ms is a whole number above 0');

const pending = readLedger(a.store).filter(row => row.type === 'proposal' && row.run_id === RUN1 && row.verdict === 'pending');
assert.equal(pending.length, 2, 'the fixture cloud answer staged one proposal per half');
assert.deepEqual(only(rows, 'rsi.proposal'), [{
  agent: 'codex', level: 'user', proposal_count: String(pending.length), skills_touched: String(new Set(pending.map(row => row.target)).size),
}], `one rsi.proposal row counting this run's pending proposals and distinct targets: ${show(rows)}`);
const response = JSON.parse(readFileSync(join(a.store, 'staging', RUN1, 'cloud-response.json'), 'utf8'));
const issued = response.halves.reduce((sum, half) => sum + half.lessons.length, 0);
assert.deepEqual(only(rows, 'rsi.lesson'), [{ agent: 'codex', level: 'user', count: String(issued) }],
  `one rsi.lesson row per run counting the lessons the cloud issued (${issued}): ${show(rows)}`);

const accept = cli(a, ['accept', `${RUN1}/claude-code`], withSno, { CLAUDECODE: '1' });
assert.equal(accept.code, 0, `accept exits 0:\n${accept.out}`);
const afterAccept = fresh();
assert.deepEqual(only(afterAccept, 'rsi.verdict'),
  [{ agent: 'claude-code', level: 'user', accepted: '1', rejected: '0', tbd: '0' }], show(afterAccept));
const reject = cli(a, ['reject', `${RUN1}/codex`], withSno);
assert.equal(reject.code, 0, `reject exits 0:\n${reject.out}`);
const afterReject = fresh();
assert.deepEqual(only(afterReject, 'rsi.verdict'),
  [{ agent: 'codex', level: 'user', accepted: '0', rejected: '1', tbd: '0' }], show(afterReject));

// The run report or acceptance step records rsi.impact. Either way,
// accept plus the next run carry exactly one row per adopted unit, with skillImpact()'s counts.
const run2 = cli(a, ['run', '--trigger', 'timer', '--now', DAY2], withSno);
assert.equal(run2.code, 0, `day two exits 0:\n${run2.out}`);
const afterRun2 = fresh();
const impactRows = [...afterAccept, ...afterReject, ...afterRun2].filter(row => row.fields.agent === 'codex');
const expected = [...new Map(skillImpact(skillRoots(a.config), existingTraces(a.store), readLabels(a.store), readLedger(a.store))
  .map(row => [row.unit, {
    agent: 'codex', level: 'user', skill_name: row.unit,
    before_sessions: String(row.loaded_before.traces), before_failures: String(row.loaded_before.fail),
    after_sessions: String(row.loaded_after.traces), after_failures: String(row.loaded_after.fail),
  }])).values()];
assert.deepEqual(expected.map(row => row.skill_name), ['heartbeat'], 'the accepted proposal adopted one unit');
assert.deepEqual(only(impactRows, 'rsi.impact'), expected, `one rsi.impact per adopted unit: ${show(impactRows)}`);
assert.equal(only(afterRun2, 'rsi.run')[0]?.trigger, 'timer', show(afterRun2));

const run3 = cli(a, ['run', '--now', DAY3], withSno);
assert.equal(run3.code, 0, `a run without --trigger exits 0:\n${run3.out}`);
const afterRun3 = fresh();
assert.equal(only(afterRun3, 'rsi.run')[0]?.trigger, 'manual', `--trigger defaults to manual: ${show(afterRun3)}`);
for (const id of [RUN1, RUN2, RUN3]) {
  const log = readFileSync(join(a.store, 'staging', id, 'run.log'), 'utf8');
  assert.doesNotMatch(log, /not found/, `a run with sno on PATH logs no missing program (${id})`);
}

// --- with `sno observe append` exiting 2 for rsi.run -----------------------------------------------------
const d = fixture();
const runD = cli(d, ['run', '--trigger', 'timer', '--now', DAY1], withSno, { REM_OBSERVE_FAIL: 'rsi.run' });
const e = fixture();
const runE = cli(e, ['run', '--trigger', 'timer', '--now', DAY1], withSno);
const normal = (fx, out) => out.replaceAll(fx.home, '<home>').replaceAll(fx.store, '<store>');
assert.equal(runD.code, runE.code, `a failed append leaves the exit code:\n${runD.out}`);
assert.equal(normal(d, runD.out), normal(e, runE.out), 'a failed append leaves the output unchanged');
const logD = readFileSync(join(d.store, 'staging', RUN1, 'run.log'), 'utf8');
const logE = readFileSync(join(e.store, 'staging', RUN1, 'run.log'), 'utf8');
assert.equal(logD.split('\n').length - logE.split('\n').length, 1, `the failed append adds one log line:\n${logD}`);
assert.equal(readFileSync(d.capture, 'utf8').split('\n').some(line => line.startsWith('append error')), false,
  'rem-reflect sends no error event of its own');

// --- with no `sno` anywhere on PATH -------------------------------------------------------------
const noSno = noSnoBin();
const b = fixture();
const runB = cli(b, ['run', '--trigger', 'timer', '--now', DAY1], noSno);
assert.equal(runB.code, NO_SNO_RUN_EXIT, `run without sno exits as before the emitters (${NO_SNO_RUN_EXIT}):\n${runB.out}`);
const logB = readFileSync(join(b.store, 'staging', RUN1, 'run.log'), 'utf8');
// A failed upload no longer stops the run, so both the rsi.proposal and the rsi.run rows reach the missing program.
assert.equal(logB.split('\n').filter(line => line.includes('sno: not found')).length, 2,
  `run.log carries one "sno: not found" line per emitted row:\n${logB}`);

const c = fixture();
const runC = cli(c, ['run', '--trigger', 'timer', '--now', DAY1], withSno);
assert.equal(runC.code, 0, `staging a pending proposal for the no-sno accept:\n${runC.out}`);
const acceptC = cli(c, ['accept', `${RUN1}/claude-code`], noSno);
assert.equal(acceptC.code, NO_SNO_ACCEPT_EXIT, `accept without sno exits as before the emitters (${NO_SNO_ACCEPT_EXIT}):\n${acceptC.out}`);

for (const dir of cleanup) rmSync(dir, { recursive: true, force: true });
console.log('OBSERVE JOURNEY OK');
