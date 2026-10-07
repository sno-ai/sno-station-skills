import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { run } from './rem-reflect.ts';
import { readPages } from './pages.ts';
import { commands } from './config.ts';
import type { Config } from './config.ts';
import {
  hashListing, tmp, fixtureCheckout, fixtureConfig, makeStore, FixtureBackend, writeStationSettings,
  writeClaudeSession, claudeUser, claudeAssistant, writeCodexSession, codexMeta, codexUser, codexAssistant,
} from './test-helpers.ts';

const NOW = new Date('2026-09-08T00:00:00Z');
const MT = new Date('2026-09-07T00:00:00Z').getTime();
function cfg(): Config { return fixtureConfig({ claude_root: tmp('c'), codex_root: tmp('x') }); }
function bothHalves(config: Config, cwd = '/n'): void {
  writeClaudeSession(config.claude_root, 'proj', 'cc', [claudeUser(cwd, 'cc', 'do it'), claudeAssistant(cwd, 'cc', [{ type: 'text', text: 'ok' }])], MT);
  writeCodexSession(config.codex_root, 'cx', [codexMeta('cx', cwd), codexUser('do it'), codexAssistant('ok')], MT);
}
function cloudPageReply(t: import('node:test').TestContext): void {
  const bin = tmp('cloud-page-cli');
  const cli = join(bin, 'sno');
  writeFileSync(cli, [
    '#!/usr/bin/env node',
    "const fs = require('node:fs');",
    "const args = process.argv.slice(2).join(' ');",
    "if (args === 'station telemetry consent get') { console.log('full'); process.exit(0); }",
    "if (args !== 'rem judge') process.exit(2);",
    "const batch = JSON.parse(fs.readFileSync(0, 'utf8'));",
    'const halves = batch.halves.map(half => ({',
    '  harness: half.harness, attention: [], lessons: [], proposals: [], read_judgments: [],',
    "  log_entry: 'Grounded page returned',",
    '  pages: half.sessions.map(session => {',
    "    const line = session.chunks[0].text.split('\\n').find(text => /^\\d+: /.test(text));",
    "    if (!line) throw new Error('uploaded chunk has no numbered line');",
    "    const lineNumber = Number(line.split(':')[0]);",
    "    const pageId = '20260908-' + session.trace_id.replace(/[^a-zA-Z0-9_-]/g, '-');",
    "    return { judgment_id: 'judgment-' + pageId, page: { page_id: pageId, summary: 'Grounded ' + session.trace_id, class: 'EXECUTION_LAPSE',",
    "      root_cause: { subject: 'session', relation: 'shows', fact: line, valid_at: '2026-09-08', evidence_pages: [], evidence_traces: [session.trace_id] },",
    "      fix: 'Read the cited line', scenario: { task_type: 'repair', trigger: 'observed trace', tools: [] },",
    "      skills_used: [], skill_target: null, knowledge_used: [], outcome: session.local_outcome, agent_id: half.harness,",
    "      project_id: session.project_id, user_id: session.user_id, evidence: [],",
    '      citations: [{ trace_id: session.trace_id, line_start: lineNumber, line_end: lineNumber, quote: line }],',
    "      counter_examples: 'not searched', superseded: false, body: 'Evidence: ' + line, count: 1,",
    '      task_ids: [session.session_id], last_seen: new Date(session.source_mtime_ms).toISOString(), skills_observed: session.skills_loaded } };',
    '  }),',
    '}));',
    'console.log(JSON.stringify({schema_version:1,run_id:batch.run_id,history_acknowledged:true,history_links:[],halves}));',
  ].join('\n') + '\n');
  chmodSync(cli, 0o755);
  const originalPath = process.env.PATH;
  process.env.PATH = `${bin}:${originalPath ?? ''}`;
  t.after(() => { if (originalPath === undefined) delete process.env.PATH; else process.env.PATH = originalPath; });
  // Only the enhanced mode writes the cloud's pages into the local store.
  const originalProfile = process.env.SNO_PROFILE_DIR;
  process.env.SNO_PROFILE_DIR = writeStationSettings('rem-enhanced');
  t.after(() => { if (originalProfile === undefined) delete process.env.SNO_PROFILE_DIR; else process.env.SNO_PROFILE_DIR = originalProfile; });
}
function reportOf(store: string): string {
  const runId = readdirSync(join(store, 'staging')).filter(n => /^\d/.test(n)).sort().pop()!;
  return readFileSync(join(store, 'staging', runId, 'REPORT.md'), 'utf8');
}
// Every file with the given name anywhere under root (used to prove a name never appears).
function filesNamed(root: string, name: string): string[] {
  const out: string[] = [];
  const walk = (dir: string): void => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) walk(path);
      else if (entry.name === name) out.push(path);
    }
  };
  walk(root);
  return out;
}

test('a cloud-authored page carries a cited root cause and is listed in the ordinary report', t => {
  cloudPageReply(t);
  const config = cfg();
  const store = makeStore(config);
  bothHalves(config);
  const r = run(store, NOW, 'u', new FixtureBackend());
  assert.equal(r.code, 0, r.lines.join('\n'));
  const created = readPages(store);
  assert.ok(created.length >= 1, 'a page was written');
  const rc = created[0].root_cause;
  for (const field of ['subject', 'relation', 'fact', 'valid_at', 'evidence_pages', 'evidence_traces'] as const) {
    assert.ok(field in rc && rc[field] !== undefined, `root_cause carries ${field}`);
  }
  const report = reportOf(store);
  assert.match(report, /Pages written: 2/, 'the report counts both cloud pages');
  assert.ok(report.includes(`${created[0].page_id}: ${created[0].summary}`), 'the report names the saved page');
  assert.equal(created[0].citations[0].trace_id, 'cc.v1', 'the stored page cites the uploaded trace');
});

test('a cloud-page day keeps the local page store without a separate fact-status ledger', t => {
  cloudPageReply(t);
  const config = cfg();
  const store = makeStore(config);
  bothHalves(config);
  const r = run(store, NOW, 'u', new FixtureBackend());
  assert.equal(r.code, 0, r.lines.join('\n'));
  assert.deepEqual(filesNamed(store, 'facts.jsonl'), [], 'no facts.jsonl exists anywhere in the store');
  assert.ok(!commands.includes('fact'), 'there is no command that changes a fact status');
});

test('a cloud-page run leaves the source checkout and root CLAUDE.md byte-identical', t => {
  cloudPageReply(t);
  const config = cfg();
  const store = makeStore(config);
  const project = fixtureCheckout();
  bothHalves(config, project);
  writeFileSync(join(project, 'CLAUDE.md'), '# fixture repo rules\n');
  const before = hashListing(project);
  const r = run(store, NOW, 'u', new FixtureBackend());
  assert.equal(r.code, 0, r.lines.join('\n'));
  assert.ok(readPages(store).length >= 1, 'the cloud reply was applied before comparing the checkout');
  assert.equal(hashListing(project), before, 'the project directory (including CLAUDE.md) is untouched by a page-creating run');
});
