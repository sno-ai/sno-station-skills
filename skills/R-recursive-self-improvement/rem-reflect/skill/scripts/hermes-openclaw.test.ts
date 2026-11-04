import { test } from 'node:test';
import type { TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { harvest, existingTraces } from './harvest.ts';
import { defaultConfig, skillRoots, loadConfig } from './config.ts';
import { RealBackend } from './backend.ts';
import { run } from './rem-reflect.ts';
import { emptyState, git } from './store.ts';
import { readLessons, appendRows } from './lessons.ts';
import { readLedger } from './ledger.ts';
import { buildCloudBatch, applyCloudResponse } from './cloud.ts';
import { readLabels } from './labeler.ts';
import { readCalls } from './calls.ts';
import { tmp, fixtureConfig, makeStore, fixtureCheckout, writeInstalledSkill, writeStationSettings,
  writeClaudeSession, writeCodexSession, claudeUser, claudeAssistant, codexMeta, codexUser, codexAssistant } from './test-helpers.ts';

const NOW = new Date('2026-10-09T08:00:00Z');
const MT = Date.parse('2026-10-08T07:00:00Z');
const ENTRY = join(import.meta.dirname, 'rem-reflect.ts');

function homes() {
  return fixtureConfig({ hermes_home: tmp('hermes-home'), openclaw_home: tmp('openclaw-home') });
}

// The recorded Hermes exports use epoch seconds, JSON-encoded tool_calls and nullable ended_at.
// `failedTest` adds a failed pytest before the owner's correction: the external verdict a Local First lesson cites.
function database(home: string, cwd: string, failedTest = false): void {
  mkdirSync(home, { recursive: true });
  execFileSync('python3', ['-c', `
import json, sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.executescript('CREATE TABLE sessions(id TEXT PRIMARY KEY, source TEXT, model TEXT, started_at REAL, ended_at REAL, cwd TEXT, billing_provider TEXT); CREATE TABLE messages(id INTEGER PRIMARY KEY, session_id TEXT, role TEXT, content TEXT, tool_calls TEXT, tool_call_id TEXT, tool_name TEXT, timestamp REAL);')
base = float(sys.argv[3]) / 1000
for sid, when, prompt in [('hermes-work', base, 'Fix the report'), ('hermes-trivial', base, 'Hello'), ('hermes-oneshot', base, '[sno-oneshot] Station one-shot run, not a user session.\\nJudge this'), ('hermes-live', base + 89000, 'Still working'), ('hermes-old', base - 864000, 'Old task')]:
 db.execute('INSERT INTO sessions VALUES (?, ?, ?, ?, NULL, ?, ?)', (sid, 'cli', 'sno-test-model-a', base - 1000000, sys.argv[2], 'openai-codex'))
 db.execute('INSERT INTO messages(session_id,role,content,timestamp) VALUES (?, ?, ?, ?)', (sid, 'user', prompt, when))
 db.execute('INSERT INTO messages(session_id,role,content,timestamp) VALUES (?, ?, ?, ?)', (sid, 'assistant', 'Hello', when + 1))
calls = [{'id': 'skill-1', 'type': 'function', 'function': {'name': 'skill_view', 'arguments': json.dumps({'name': 'heartbeat'})}}]
db.execute('INSERT INTO messages(session_id,role,content,tool_calls,timestamp) VALUES (?, ?, ?, ?, ?)', ('hermes-work','assistant','Reading',json.dumps(calls),base + 2))
db.execute('INSERT INTO messages(session_id,role,content,tool_call_id,tool_name,timestamp) VALUES (?, ?, ?, ?, ?, ?)', ('hermes-work','tool','Body.','skill-1','skill_view',base + 3))
if sys.argv[4] == '1':
 tests = [{'id': 'test-1', 'type': 'function', 'function': {'name': 'terminal', 'arguments': json.dumps({'command': 'python3 -m pytest -q tests'})}}]
 db.execute('INSERT INTO messages(session_id,role,content,tool_calls,timestamp) VALUES (?, ?, ?, ?, ?)', ('hermes-work','assistant','Testing',json.dumps(tests),base + 3.2))
 db.execute('INSERT INTO messages(session_id,role,content,tool_call_id,tool_name,timestamp) VALUES (?, ?, ?, ?, ?, ?)', ('hermes-work','tool',json.dumps({'output': '1 failed, 2 passed in 0.41s', 'exit_code': 1}),'test-1','terminal',base + 3.4))
db.execute('INSERT INTO messages(session_id,role,content,timestamp) VALUES (?, ?, ?, ?)', ('hermes-work','user','No, verify it first. sk-secret12345678',base + 4))
db.commit()
`, join(home, 'state.db'), cwd, String(MT), failedTest ? '1' : '0'], { timeout: 5000 });
}

// Event fields match export-trajectory's transcript/runtime wire shapes; private identities are omitted.
function events(cwd: string, trivial = false, failedTest = false): string {
  const data = [
    { type: 'session.started', source: 'runtime', data: { workspaceDir: cwd } },
    { type: 'user.message', source: 'transcript', data: { message: { role: 'user', content: 'Fix the report' } } },
    { type: 'assistant.message', source: 'transcript', data: { message: { role: 'assistant', content: [{ type: 'text', text: 'Reading' }] } } },
    ...(!trivial ? [
      { type: 'tool.call', source: 'runtime', data: { toolCallId: 'skill-2', name: 'skills', arguments: { name: 'heartbeat' } } },
      { type: 'tool.result', source: 'runtime', data: { toolCallId: 'skill-2', name: 'skills', output: 'Exit code 1: missing file', isError: true } },
      ...(failedTest ? [
      { type: 'tool.call', source: 'runtime', data: { toolCallId: 'test-2', name: 'exec', arguments: { command: 'python3 -m pytest -q tests' } } },
      { type: 'tool.result', source: 'runtime', data: { toolCallId: 'test-2', name: 'exec', output: '1 failed, 2 passed in 0.41s', isError: true } },
      ] : []),
      { type: 'user.message', source: 'transcript', data: { message: { role: 'user', content: 'No, verify it first.' } } },
    ] : []),
    { type: 'session.ended', source: 'runtime', data: { status: 'success' } },
  ];
  return data.map((row, i) => JSON.stringify({ traceSchema: 'openclaw-trajectory', schemaVersion: 1,
    seq: i + 1, ts: new Date(MT + i * 1000).toISOString(), provider: 'openai', modelId: 'sno-test-model-a', workspaceDir: cwd, ...row })).join('\n') + '\n';
}

function openclaw(t: TestContext, cwd: string, failedTest = false): string {
  const bin = tmp('openclaw-bin');
  const capture = join(bin, 'commands.jsonl');
  writeFileSync(join(bin, 'events.jsonl'), events(cwd, false, failedTest));
  writeFileSync(join(bin, 'trivial.jsonl'), events(cwd, true));
  writeFileSync(join(bin, 'openclaw'), `#!/usr/bin/env node
const fs = require('node:fs'); const path = require('node:path'); const a = process.argv.slice(2);
fs.appendFileSync(${JSON.stringify(capture)}, JSON.stringify(a) + '\\n');
if (a[0] === 'sessions' && a[1] === 'list') {
 console.log(JSON.stringify({sessions:[
  {key:'agent:main:ordinary',sessionId:'openclaw-work',updatedAt:${MT + 10000},model:'sno-test-model-a',modelProvider:'openai',agentId:'main'},
  {key:'agent:main:trivial',sessionId:'openclaw-trivial',updatedAt:${MT + 10000}},
  {key:'agent:main:broken',sessionId:'openclaw-broken',updatedAt:${MT + 10000}},
  {key:'agent:main:explicit:sno-oneshot-test',sessionId:'openclaw-oneshot',updatedAt:${MT + 10000}},
  {key:'agent:main:live',sessionId:'openclaw-live',updatedAt:${NOW.getTime() - 60000}},
  {key:'agent:main:old',sessionId:'openclaw-old',updatedAt:${MT - 864000000}}
 ]})); process.exit(0);
}
if (a[0] === 'sessions' && a[1] === 'export-trajectory') {
 const key = a[a.indexOf('--session-key') + 1]; if (key.endsWith(':broken')) {console.error('fixture export failed'); process.exit(1);}
 const dir = path.join(a[a.indexOf('--workspace') + 1], '.openclaw/trajectory-exports/export'); fs.mkdirSync(dir,{recursive:true});
 fs.copyFileSync(path.join(__dirname,key.endsWith(':trivial') ? 'trivial.jsonl' : 'events.jsonl'),path.join(dir,'events.jsonl'));
 console.log(JSON.stringify({outputDir:dir})); process.exit(0);
}
if (a[0] === 'agent') {
 console.log(JSON.stringify({status:'ok',runId:'fixture',summary:'completed',result:{payloads:[{text:JSON.stringify({decision:'keep',outcome:'fail',reason:'fixture failure',evidence:[],key_ranges:[],notes:''})}]}})); process.exit(0);
}
console.error('unexpected command'); process.exit(2);
`, { mode: 0o755 });
  const before = process.env.PATH;
  process.env.PATH = `${bin}:${before ?? ''}`;
  t.after(() => { process.env.PATH = before; });
  return capture;
}

test('harvest collects quiet Hermes database and OpenClaw exports, skills and tools, skips Station one-shots, and appends versions', t => {
  const config = homes(); const cwd = fixtureCheckout(); const store = makeStore(config);
  database(config.hermes_home, cwd);
  writeInstalledSkill(config.hermes_home, 'heartbeat'); writeInstalledSkill(config.openclaw_home, 'heartbeat');
  const capture = openclaw(t, cwd); const state = emptyState();
  const first = harvest(store, config, state, 'u', NOW);
  assert.deepEqual(first.traces.map(row => row.session_id).sort(), ['hermes-trivial', 'hermes-work', 'openclaw-trivial', 'openclaw-work']);
  const h = first.traces.find(row => row.session_id === 'hermes-work');
  const o = first.traces.find(row => row.session_id === 'openclaw-work');
  assert.equal(h?.agent_id, 'hermes'); assert.equal(o?.agent_id, 'openclaw');
  assert.equal(h?.project_id, 'github.com/example/project'); assert.equal(o?.project_id, 'github.com/example/project');
  assert.deepEqual(h?.skills_loaded, [join(config.hermes_home, 'skills/heartbeat')]);
  assert.deepEqual(o?.skills_loaded, [join(config.openclaw_home, 'skills/heartbeat')]);
  assert.equal(h?.records.length, 6); assert.equal(o?.records.length, 8);
  assert.equal(h?.redactions, 1);
  assert.equal(h?.trivial, false); assert.equal(o?.trivial, false);
  assert.deepEqual(first.traces.filter(row => row.trivial).map(row => row.session_id).sort(), ['hermes-trivial', 'openclaw-trivial']);
  assert.match(JSON.stringify(h?.records), /No, verify it first\. \[REDACTED\]/);
  assert.match(first.log.join('\n'), /openclaw.*agent:main:broken.*fixture export failed/);
  assert.equal(existingTraces(store).length, 4);
  const commands = readFileSync(capture, 'utf8');
  assert.doesNotMatch(commands, /--session-key","agent:main:(live|old|explicit)/);
  assert.equal(harvest(store, config, state, 'u', NOW).traces.length, 0);
  execFileSync('python3', ['-c', "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute(\"INSERT INTO messages(session_id,role,content,timestamp) VALUES ('hermes-work','assistant','Verified',?)\",(float(sys.argv[2]),)); c.commit()", join(config.hermes_home, 'state.db'), String(MT / 1000 + 20)], { timeout: 5000 });
  const next = harvest(store, config, state, 'u', NOW);
  assert.equal(next.traces.length, 1); assert.equal(next.traces[0].version, 2);
  assert.deepEqual(next.traces[0].source_line_range, [7, 7]);
  assert.equal(next.traces[0].records[0].record.type, 'assistant');
  assert.match(JSON.stringify(next.traces[0].records), /Verified/);
});

test('config honours the new homes and includes all four installed skill roots', t => {
  const before = { hermes: process.env.HERMES_HOME, openclaw: process.env.OPENCLAW_STATE_DIR };
  t.after(() => { for (const [key, value] of [['HERMES_HOME', before.hermes], ['OPENCLAW_STATE_DIR', before.openclaw]] as const) {
    if (value === undefined) delete process.env[key]; else process.env[key] = value;
  } });
  process.env.HERMES_HOME = '/fixtures/hermes'; process.env.OPENCLAW_STATE_DIR = '/fixtures/openclaw';
  const config = defaultConfig('/fixtures/user');
  assert.deepEqual(skillRoots(config), ['/fixtures/user/.claude/skills', '/fixtures/user/.codex/skills', '/fixtures/hermes/skills', '/fixtures/openclaw/skills']);
  const stored = homes(); const store = makeStore(stored);
  assert.equal(loadConfig(store).hermes_home, stored.hermes_home);
  assert.equal(loadConfig(store).openclaw_home, stored.openclaw_home);
});

test('Hermes terminal failures from the recorded JSON tool format keep literal exit codes', t => {
  const config = homes(); const cwd = fixtureCheckout(); const store = makeStore(config);
  database(config.hermes_home, cwd); openclaw(t, cwd);
  execFileSync('python3', ['-c', `
import sqlite3,json,sys
c=sqlite3.connect(sys.argv[1])
c.execute('INSERT INTO messages(session_id,role,content,tool_calls,timestamp) VALUES (?,?,?,?,?)',('hermes-work','assistant','Checking',json.dumps([{'id':'terminal-1','function':{'name':'terminal','arguments':json.dumps({'command':'false'})}}]),float(sys.argv[2])))
c.execute('INSERT INTO messages(session_id,role,content,tool_call_id,tool_name,timestamp) VALUES (?,?,?,?,?,?)',('hermes-work','tool',json.dumps({'output':'Failed check','exit_code':1,'error':None}),'terminal-1','terminal',float(sys.argv[2])+1))
c.commit()
`, join(config.hermes_home, 'state.db'), String(MT / 1000 + 20)], { timeout: 5000 });
  const trace = harvest(store, config, emptyState(), 'u', NOW).traces.find(row => row.session_id === 'hermes-work');
  assert.ok(trace);
  const call = readCalls(trace).find(row => row.tool === 'terminal');
  assert.equal(call?.exit_code, 1); assert.equal(call?.failed, true);
  assert.equal(call?.failure_kind, 'exit_nonzero'); assert.equal(call?.target, 'false');
});

test('new-agent backend reports failed answers and times out instead of returning usable output', t => {
  const bin = tmp('failed-model'); const before = process.env.PATH;
  process.env.PATH = `${bin}:${before ?? ''}`; t.after(() => { process.env.PATH = before; });
  writeFileSync(join(bin, 'openclaw'), '#!/usr/bin/env node\nconsole.log(JSON.stringify({status:"error",result:{payloads:[{text:"unavailable"}]}}));\n', { mode: 0o755 });
  assert.throws(() => new RealBackend(5000).spawn({ cli: 'openclaw', cwd: bin, input: 'test' }), /labeler-invalid-response/);
  writeFileSync(join(bin, 'hermes'), '#!/usr/bin/env node\nsetTimeout(()=>console.log("too late"),10000);\n', { mode: 0o755 });
  assert.throws(() => new RealBackend(50).spawn({ cli: 'hermes', cwd: bin, input: 'test' }), /per-call-timeout/);
});

test('labeling and cloud halves keep Hermes/OpenClaw identity and tool failures', t => {
  const config = homes(); const cwd = fixtureCheckout(); const store = makeStore(config);
  database(config.hermes_home, cwd); openclaw(t, cwd);
  const bin = tmp('hermes-labeler'); const before = process.env.PATH;
  process.env.PATH = `${bin}:${before ?? ''}`; t.after(() => { process.env.PATH = before; });
  writeFileSync(join(bin, 'hermes'), '#!/usr/bin/env node\nrequire("node:fs").readFileSync(0,"utf8"); console.log(JSON.stringify({decision:"keep",outcome:"fail",reason:"fixture failure",evidence:[],key_ranges:[],notes:""}));\n', { mode: 0o755 });
  const result = run(store, NOW, 'u', new RealBackend(5000, { loopHomeBase: join(store, '.loop-home') }));
  assert.equal(result.code, 0, result.lines.join('\n'));
  const labels = [...readLabels(store).values()];
  assert.deepEqual(labels.map(row => row.labeled_by).sort(), ['hermes', 'hermes', 'openclaw', 'openclaw']);
  const batch = buildCloudBatch(store, config, 'fixture', existingTraces(store), readLabels(store), false);
  assert.deepEqual(batch.halves.map(row => row.harness), ['hermes', 'openclaw']);
  const calls = batch.halves.find(row => row.harness === 'openclaw')?.sessions.find(row => row.session_id === 'openclaw-work')?.calls;
  assert.equal(calls?.length, 1); assert.equal(calls?.[0].tool, 'skills'); assert.equal(calls?.[0].failed, true);
  assert.equal(calls?.[0].failure_kind, 'exit_nonzero'); assert.equal(calls?.[0].exit_code, 1);
  const saved = join(store, 'staging', 'fixture'); mkdirSync(saved, { recursive: true });
  writeFileSync(join(saved, 'cloud-request.json'), '{"catalogue":[]}');
  applyCloudResponse(store, config, { schema_version: 1, run_id: 'fixture', history_acknowledged: true, history_links: [],
    halves: [{ harness: 'hermes', pages: [], lessons: [], proposals: [], read_judgments: [] },
      { harness: 'openclaw', pages: [], lessons: [], proposals: [], read_judgments: [] }] });
  assert.equal(existsSync(join(store, 'wiki/index.md')), true);
});

test('existing Claude and Codex traces keep their original records, roots, and cursor behavior', () => {
  const config = fixtureConfig(); const store = makeStore(config); const cwd = fixtureCheckout();
  writeClaudeSession(config.claude_root, 'project', 'claude-original', [claudeUser(cwd, 'claude-original', 'hello'),
    claudeAssistant(cwd, 'claude-original', [{ type: 'text', text: 'ready' }])], MT);
  writeCodexSession(config.codex_root, 'codex-original', [codexMeta('codex-original', cwd), codexUser('hello'), codexAssistant('ready')], MT);
  const state = emptyState(); const collected = harvest(store, config, state, 'u', NOW);
  assert.deepEqual(collected.traces.map(row => row.agent_id).sort(), ['claude-code', 'codex']);
  assert.equal(collected.traces.find(row => row.agent_id === 'claude-code')?.records.length, 2);
  assert.equal(collected.traces.find(row => row.agent_id === 'codex')?.records.length, 3);
  assert.deepEqual(collected.traces.map(row => row.project_id), ['github.com/example/project', 'github.com/example/project']);
  assert.equal(harvest(store, config, state, 'u', NOW).traces.length, 0);
});

test('recorded host exports survive the real database and trajectory readers with literal content and restored project identity', t => {
  const config = homes(); const cwd = fixtureCheckout(); const store = makeStore(config);
  const fixtures = join(import.meta.dirname, 'selftest/fixtures');
  database(config.hermes_home, cwd);
  execFileSync('python3', ['-c', `
import sqlite3,json,sys
c=sqlite3.connect(sys.argv[1]); c.execute('DELETE FROM messages'); c.execute('DELETE FROM sessions')
for line in open(sys.argv[2]):
 s=json.loads(line)
 c.execute('INSERT INTO sessions VALUES (?,?,?,?,?,?,?)',tuple(s[k] for k in ['id','source','model','started_at','ended_at','cwd','billing_provider']))
 for m in s['messages']:
  c.execute('INSERT INTO messages(session_id,role,content,tool_calls,tool_call_id,tool_name,timestamp) VALUES (?,?,?,?,?,?,?)',(s['id'],m['role'],m['content'],json.dumps(m['tool_calls']) if m['tool_calls'] else None,m['tool_call_id'],m['tool_name'],m['timestamp']))
c.commit()
`, join(config.hermes_home, 'state.db'), join(fixtures, 'hermes-session-export.jsonl')], { timeout: 5000 });
  const capture = openclaw(t, cwd);
  writeFileSync(join(dirname(capture), 'events.jsonl'), readFileSync(join(fixtures, 'openclaw-events.jsonl')));
  config.project_names[join(config.openclaw_home, 'workspace')] = 'recorded-openclaw-project';
  const collected = harvest(store, config, emptyState(), 'u', NOW);
  const h = collected.traces.find(row => row.session_id === '20261009_044642_0bb1b0');
  const oneshot = collected.traces.find(row => row.session_id === '20261009_044111_b24ca7');
  const o = collected.traces.find(row => row.session_id === 'openclaw-work');
  assert.equal(collected.traces.length, 4);
  assert.equal(h?.records.length, 6); assert.equal(h?.trivial, true); assert.equal(h?.project_id, 'user-level');
  assert.match(JSON.stringify(h?.records), /Reply with exactly ONE/);
  assert.equal(oneshot?.records.length, 3); assert.match(JSON.stringify(oneshot?.records), /Reply with exactly ISO-19219/);
  assert.equal(o?.records.length, 9); assert.equal(o?.skipped_records, 6); assert.equal(o?.trivial, true);
  assert.equal(o?.project_id, 'recorded-openclaw-project'); assert.match(JSON.stringify(o?.records), /"text":"TWO"/);
  const count = execFileSync('python3', ['-c', 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute("SELECT COUNT(*) FROM messages").fetchone()[0])', join(config.hermes_home, 'state.db')], { encoding: 'utf8', timeout: 5000 });
  assert.equal(count.trim(), '7');
});

test('Hermes and OpenClaw backend use isolated Station one-shots with own login and parse the answer', t => {
  const bin = tmp('model-bin'); const capture = join(bin, 'calls.jsonl');
  const before = process.env.PATH; process.env.PATH = `${bin}:${before ?? ''}`;
  t.after(() => { process.env.PATH = before; });
  for (const cli of ['hermes', 'openclaw']) writeFileSync(join(bin, cli), `#!/usr/bin/env node
const fs=require('node:fs'); const args=process.argv.slice(2);
const input=${JSON.stringify(cli)}==='hermes'?fs.readFileSync(0,'utf8'):args[args.indexOf('-m')+1];
fs.appendFileSync(${JSON.stringify(capture)},JSON.stringify({cli:${JSON.stringify(cli)},args,input,home:process.env.HOME,hermes:process.env.HERMES_HOME,openclaw:process.env.OPENCLAW_STATE_DIR})+'\\n');
console.log(${JSON.stringify(cli)}==='hermes'?'answer':JSON.stringify({result:{payloads:[{text:'answer'}]},runId:'fixture',status:'ok',summary:'completed'}));
`, { mode: 0o755 });
  const backend = new RealBackend(5000, { loopHomeBase: join(bin, 'isolated') });
  assert.equal(backend.spawn({ cli: 'hermes', cwd: bin, input: 'Label this' }).stdout.trim(), 'answer');
  assert.equal(backend.spawn({ cli: 'openclaw', cwd: bin, input: 'Write this' }).stdout, 'answer');
  const rows = readFileSync(capture, 'utf8').trim().split('\n').map(row => JSON.parse(row));
  assert.deepEqual(rows[0].args, ['chat', '--query-file', '-', '--oneshot', '-Q', '--ignore-user-config', '--ignore-rules']);
  assert.equal(rows[0].input, '[sno-oneshot] Station one-shot run, not a user session.\nLabel this');
  assert.equal(rows[1].input, '[sno-oneshot] Station one-shot run, not a user session.\nWrite this');
  assert.equal(rows[1].args[0], 'agent'); assert.equal(rows[1].args[2], 'main');
  assert.match(rows[1].args[4], /^sno-oneshot-/); assert.equal(rows[1].args.at(-1), '--json');
  assert.equal(rows[0].home, process.env.HOME); assert.equal(rows[1].home, process.env.HOME);
  assert.equal(rows[0].hermes, process.env.HERMES_HOME); assert.equal(rows[1].openclaw, process.env.OPENCLAW_STATE_DIR);
});

test('Local First writes lessons and accepted reminders to the new agents skill folders', t => {
  const profile = writeStationSettings('local-first'); const before = process.env.SNO_PROFILE_DIR;
  process.env.SNO_PROFILE_DIR = profile; t.after(() => { process.env.SNO_PROFILE_DIR = before; });
  const config = homes(); const cwd = fixtureCheckout(); const store = makeStore(config);
  database(config.hermes_home, cwd, true); openclaw(t, cwd, true);
  writeInstalledSkill(config.hermes_home, 'heartbeat'); writeInstalledSkill(config.openclaw_home, 'heartbeat');
  const result = run(store, NOW, 'u', { spawn({ input, cli }) {
    const line = Number(/^(\d+): .*No, verify it first\./m.exec(input)?.[1]);
    const verdictLine = Number(/^(\d+) test failed /m.exec(input)?.[1]);
    if (!line) return { stdout: '{"lesson":null}' };
    const target = join(cli === 'hermes' ? config.hermes_home : config.openclaw_home, 'skills/heartbeat');
    return { stdout: JSON.stringify({ lesson: { summary: 'Verify before completion', class: 'EXECUTION_LAPSE',
      situation: { task_type: 'report', trigger: 'report completion', tools: [] }, advice: 'Verify the report.',
      expected_result: 'The report is verified before completion.', success_criteria: 'The report read-back matches the request.', memory_fact_ids: [],
      because: 'The owner requested verification.', polarity: 'from_failure', evidence: [{ line_start: line, line_end: line, quote: 'No, verify it first.' }],
      skill_target: target, reminder_line: 'Verify the report before declaring completion.', verdict_line: verdictLine } }) };
  } });
  assert.equal(result.code, 0, result.lines.join('\n'));
  assert.deepEqual(readLessons(store).map(row => row.agent_id).sort(), ['hermes', 'openclaw']);
  assert.deepEqual(readLedger(store).filter(row => row.type === 'proposal').map(row => row.half).sort(), ['hermes', 'openclaw']);
  const accepted = spawnSync(process.execPath, ['--experimental-strip-types', ENTRY, 'accept', '20261009-0800/hermes'],
    { encoding: 'utf8', timeout: 10000, env: { ...process.env, REM_REFLECT_STORE: store } });
  assert.equal(accepted.status, 0, accepted.stderr + accepted.stdout);
  assert.match(readFileSync(join(config.hermes_home, 'skills/heartbeat/SKILL.md'), 'utf8'), /Verify the report before declaring completion\./);
  assert.match(readFileSync(join(config.openclaw_home, 'skills/heartbeat/SKILL.md'), 'utf8'), /Verify the report before declaring completion\./);
});

test('recall and lesson accept both new agents and the printed Hermes hook only emits first-turn context', () => {
  const config = homes(); const store = makeStore(config); const cwd = fixtureCheckout();
  appendRows(join(store, 'wiki/lessons.jsonl'), [{ lesson_id: 'L-fixture', page_id: 'page', status: 'accepted', listed: true,
    applies_to: 'general', project_id: 'p', agent_id: 'hermes', user_id: 'u', count: 1, helped: 0, harmful: 0,
    measured: false, created_run: 'fixture', skill_target: null, situation: { task_type: 'report', trigger: 'a report', tools: [] },
    scenario: { task_type: 'report', trigger: 'a report', tools: [] }, advice: 'Verify the report.', because: 'A correction.',
    polarity: 'from_failure', evidence: [], counter_examples: 'not searched' }]);
  git(store, ['add', '--all']); git(store, ['commit', '--quiet', '-m', 'lesson']);
  const env = { ...process.env, REM_REFLECT_STORE: store };
  for (const agent of ['hermes', 'openclaw']) {
    const index = execFileSync(process.execPath, ['--experimental-strip-types', ENTRY, 'recall', '--agent', agent, '--session', 'later', '--cwd', cwd], { env, encoding: 'utf8', timeout: 10000 });
    assert.match(index, /L-fixture · general · a report — Verify the report\./);
    const detail = execFileSync(process.execPath, ['--experimental-strip-types', ENTRY, 'lesson', 'L-fixture', '--agent', agent, '--session', 'later', '--cwd', cwd], { env, encoding: 'utf8', timeout: 10000 });
    assert.match(detail, /advice: Verify the report\./);
  }
  const printed = execFileSync(process.execPath, ['--experimental-strip-types', ENTRY, 'install-hooks', '--print'], { env, encoding: 'utf8', timeout: 10000 });
  assert.match(printed, /~\/\.hermes\/config\.yaml/); assert.match(printed, /hooks:\n  pre_llm_call:\n    - command: sno rem-reflect recall --agent hermes/);
  assert.match(printed, /OpenClaw.*Sno memory plugin/);
  const hook = (first: boolean) => spawnSync(process.execPath, ['--experimental-strip-types', ENTRY, 'recall', '--agent', 'hermes'], { env, encoding: 'utf8', timeout: 10000,
    input: JSON.stringify({ hook_event_name: 'pre_llm_call', session_id: 'hook', cwd, extra: { is_first_turn: first } }) });
  assert.match(JSON.parse(hook(true).stdout).context, /Verify the report\./);
  assert.equal(hook(false).stdout, '');
});
