import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { verdictCommand } from './adopt.ts';
import { installedCatalogue } from './catalogue.ts';
import { applyCloudResponse } from './cloud.ts';
import { skillRoots } from './config.ts';
import { appendLedger, readLedger } from './ledger.ts';
import { writeJson } from './store.ts';
import {
  fixtureHarnessHomes, makeConfig, makeStore, tmp,
} from './test-helpers.ts';

const RUN_ID = '20260908-0000';
const PROPOSAL_ID = `${RUN_ID}/codex`;
const NOW = new Date('2026-09-08T00:00:00Z');

function skillMd(home: string, name: string): string {
  return join(home, 'skills', name, 'SKILL.md');
}

function filesBelow(root: string): string[] {
  if (!existsSync(root)) return [];
  const found: string[] = [];
  const walk = (dir: string): void => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) walk(path);
      else found.push(path);
    }
  };
  walk(root);
  return found;
}

function patchProposal(target: string) {
  return { proposal: {
    kind: 'patch', target, region: 'body',
    purpose: { summary: 'add a guard', page_ids: ['20260908-db-lock-held-1'] },
    scenario: { task_type: 'w', trigger: 't', tools: [] },
    skills_used: [], skill_target: null, knowledge_used: [], outcome: 'fail', evidence: [],
    ops: [{ op: 'append', text: 'One installed guard line.\n' }],
  } };
}

function stagePatch(store: string, config: ReturnType<typeof makeConfig>, target: string): void {
  const pageId = '20260908-db-lock-held-1';
  writeJson(join(store, 'staging', RUN_ID, 'cloud-request.json'), {
    schema_version: 1, run_id: RUN_ID, halves: [], catalogue: installedCatalogue(skillRoots(config)),
    usage_reads: [], outcome_summary: {},
  });
  applyCloudResponse(store, config, {
    schema_version: 1, run_id: RUN_ID, history_acknowledged: true, history_links: [],
    halves: [{ harness: 'codex', attention: [], lessons: [], read_judgments: [], log_entry: 'A cited fix is ready',
      pages: [{ judgment_id: 'cloud-page', page: {
        page_id: pageId, summary: 'The installed guard is absent', class: 'SKILL_DEFECT',
        root_cause: { subject: 'heartbeat', relation: 'lacks', fact: 'the guard', valid_at: '2026-09-08', evidence_pages: [], evidence_traces: [] },
        fix: 'Add the guard', scenario: { task_type: 'w', trigger: 't', tools: [] }, skills_used: [],
        skill_target: target, knowledge_used: [], outcome: 'fail', agent_id: 'codex', project_id: 'p',
        user_id: 'fixture-user', evidence: [], citations: [], counter_examples: 'not searched', superseded: false,
        body: 'The guard was absent', count: 1, task_ids: ['p0'], last_seen: NOW.toISOString(), skills_observed: [],
      } }],
      proposals: [{ judgment_id: 'cloud-proposal', ...patchProposal(join(target, 'SKILL.md')) }],
    }],
  });
}

test('accepted patch updates both installed copies and keeps evidence in the loop store', () => {
  const { claudeHome, codexHome } = fixtureHarnessHomes(['heartbeat']);
  writeFileSync(skillMd(claudeHome, 'heartbeat'), readFileSync(skillMd(claudeHome, 'heartbeat'), 'utf8') + 'Claude-only baseline.\n');
  writeFileSync(skillMd(codexHome, 'heartbeat'), readFileSync(skillMd(codexHome, 'heartbeat'), 'utf8') + 'Codex-only baseline.\n');
  writeFileSync(join(claudeHome, 'skills', 'heartbeat', 'PUBLISHED.json'), '{"version":"1.2.3"}\n');
  writeFileSync(join(codexHome, 'skills', 'heartbeat', 'PUBLISHED.json'), '{"version":"1.2.3"}\n');
  const config = makeConfig({
    claude_home: claudeHome, codex_home: codexHome,
    claude_root: tmp('claude-sessions'), codex_root: tmp('codex-sessions'),
  });
  const store = makeStore(config);
  const target = join(claudeHome, 'skills', 'heartbeat');

  stagePatch(store, config, target);
  const result = verdictCommand(store, 'accept', PROPOSAL_ID, NOW);

  assert.equal(result.code, 0, result.lines.join('\n'));
  assert.match(readFileSync(skillMd(claudeHome, 'heartbeat'), 'utf8'), /Claude-only baseline.[\s\S]*One installed guard line\./);
  assert.match(readFileSync(skillMd(codexHome, 'heartbeat'), 'utf8'), /Codex-only baseline.[\s\S]*One installed guard line\./);
  const stagedFiles = filesBelow(join(store, 'staging', RUN_ID, 'codex'));
  assert.ok(stagedFiles.some(path => path.endsWith('PURPOSE.md')), 'the purpose evidence stays under the loop store');
  const stagedText = stagedFiles.map(path => readFileSync(path, 'utf8')).join('\n');
  assert.match(stagedText, /Claude-only baseline\./, 'the Claude copy has its own backup');
  assert.match(stagedText, /Codex-only baseline\./, 'the Codex copy has its own backup');
  assert.equal(filesBelow(join(claudeHome, 'skills', 'heartbeat')).some(path => path.includes('docs/evidence')), false);
  assert.equal(filesBelow(join(codexHome, 'skills', 'heartbeat')).some(path => path.includes('docs/evidence')), false);
  const accepted = readLedger(store).find(row => row.type === 'verdict' && row.verdict === 'Accepted');
  assert.ok(accepted, 'the accepted verdict is persisted');
  assert.deepEqual(accepted.library_versions, {
    [join(claudeHome, 'skills', 'heartbeat')]: { version: '1.2.3' },
    [join(codexHome, 'skills', 'heartbeat')]: { version: '1.2.3' },
  }, 'the evidence records the library version for each installed copy');
  assert.deepEqual(accepted.adopted_roots, [
    join(claudeHome, 'skills', 'heartbeat'),
    join(codexHome, 'skills', 'heartbeat'),
  ]);
  assert.deepEqual(accepted.refused_roots, []);
  assert.ok(stagedFiles.some(path => path.endsWith('ledger-row.json')),
    'the accepted ledger evidence is copied into staging');
});

test('a copy changed after staging is refused while the unchanged installed copy is adopted', () => {
  const { claudeHome, codexHome } = fixtureHarnessHomes(['heartbeat']);
  const config = makeConfig({
    claude_home: claudeHome, codex_home: codexHome,
    claude_root: tmp('claude-sessions'), codex_root: tmp('codex-sessions'),
  });
  const store = makeStore(config);
  stagePatch(store, config, join(claudeHome, 'skills', 'heartbeat'));
  const manuallyEdited = readFileSync(skillMd(claudeHome, 'heartbeat'), 'utf8') + 'Owner edit after staging.\n';
  writeFileSync(skillMd(claudeHome, 'heartbeat'), manuallyEdited);

  const result = verdictCommand(store, 'accept', PROPOSAL_ID, NOW);

  assert.match(readFileSync(skillMd(codexHome, 'heartbeat'), 'utf8'), /One installed guard line\./,
    'the unchanged copy is adopted');
  assert.equal(readFileSync(skillMd(claudeHome, 'heartbeat'), 'utf8'), manuallyEdited,
    'the changed copy is refused without overwriting the owner edit');
  assert.match(result.lines.join('\n'), new RegExp(claudeHome.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
    'the refusal names the changed installed root');
  const accepted = readLedger(store).find(row => row.type === 'verdict' && row.verdict === 'Accepted');
  assert.deepEqual(accepted?.adopted_roots, [join(codexHome, 'skills', 'heartbeat')]);
  assert.deepEqual(accepted?.refused_roots, [join(claudeHome, 'skills', 'heartbeat')]);
});

test('accepted create writes the new skill into both fixed installed roots without a source repository', () => {
  const { claudeHome, codexHome } = fixtureHarnessHomes([]);
  const config = makeConfig({
    claude_home: claudeHome, codex_home: codexHome,
    claude_root: tmp('claude-sessions'), codex_root: tmp('codex-sessions'),
  });
  const store = makeStore(config);
  const half = join(store, 'staging', RUN_ID, 'codex');
  mkdirSync(half, { recursive: true });
  const created = '---\nname: example-new\ndescription: "a new skill."\n---\n# example-new\n';
  writeFileSync(join(half, 'SKILL.md'), created);
  writeFileSync(join(half, 'PURPOSE.md'), 'create example-new\nPages: pg\n');
  appendLedger(store, {
    type: 'proposal', proposal_id: PROPOSAL_ID, run_id: RUN_ID, half: 'codex', kind: 'create',
    target: 'example-new', region: null,
    purpose: { summary: 'create example-new', page_ids: ['pg'] }, verdict: 'pending',
  });

  const result = verdictCommand(store, 'accept', PROPOSAL_ID, NOW);

  assert.equal(result.code, 0, result.lines.join('\n'));
  assert.equal(readFileSync(skillMd(claudeHome, 'example-new'), 'utf8'), created);
  assert.equal(readFileSync(skillMd(codexHome, 'example-new'), 'utf8'), created);
});

test('create is all-or-nothing when the skill already exists in one installed root', () => {
  const { claudeHome, codexHome } = fixtureHarnessHomes([]);
  mkdirSync(join(codexHome, 'skills', 'example-new'), { recursive: true });
  writeFileSync(skillMd(codexHome, 'example-new'), 'owner copy\n');
  const config = makeConfig({
    claude_home: claudeHome, codex_home: codexHome,
    claude_root: tmp('claude-sessions'), codex_root: tmp('codex-sessions'),
  });
  const store = makeStore(config);
  const half = join(store, 'staging', RUN_ID, 'codex');
  mkdirSync(half, { recursive: true });
  writeFileSync(join(half, 'SKILL.md'), '---\nname: example-new\ndescription: "a new skill."\n---\n# example-new\n');
  writeFileSync(join(half, 'PURPOSE.md'), 'create example-new\nPages: pg\n');
  appendLedger(store, {
    type: 'proposal', proposal_id: PROPOSAL_ID, run_id: RUN_ID, half: 'codex', kind: 'create',
    target: 'example-new', region: null,
    purpose: { summary: 'create example-new', page_ids: ['pg'] }, verdict: 'pending',
  });

  const result = verdictCommand(store, 'accept', PROPOSAL_ID, NOW);

  assert.equal(result.code, 1);
  assert.equal(existsSync(skillMd(claudeHome, 'example-new')), false, 'no partial create in the empty root');
  assert.equal(readFileSync(skillMd(codexHome, 'example-new'), 'utf8'), 'owner copy\n', 'the existing skill is untouched');
  assert.match(result.lines.join('\n'), new RegExp(codexHome.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
    'the conflict names the root that already holds the skill');
});

test('an obsolete repo_path key is ignored and never appears in output', () => {
  const { claudeHome, codexHome } = fixtureHarnessHomes(['heartbeat']);
  const obsolete = tmp('obsolete-repository');
  const bait = join(obsolete, 'skills', 'bait', 'skill');
  mkdirSync(bait, { recursive: true });
  writeFileSync(join(bait, 'SKILL.md'), 'missing frontmatter so a catalogue read fails loudly\n');
  const obsoleteBefore = filesBelow(obsolete).map(path => [path, readFileSync(path, 'utf8')]);
  const config = {
    ...makeConfig({
      claude_home: claudeHome, codex_home: codexHome,
      claude_root: tmp('claude-sessions'), codex_root: tmp('codex-sessions'),
    }),
    repo_path: obsolete,
  };
  const store = makeStore(config);
  stagePatch(store, config, join(claudeHome, 'skills', 'heartbeat'));
  const result = verdictCommand(store, 'accept', PROPOSAL_ID, NOW);

  assert.match(readFileSync(skillMd(claudeHome, 'heartbeat'), 'utf8'), /One installed guard line\./);
  assert.deepEqual(filesBelow(obsolete).map(path => [path, readFileSync(path, 'utf8')]), obsoleteBefore,
    'malformed bait in the obsolete repository is neither read nor changed');
  assert.doesNotMatch(result.lines.join('\n'), /repo_path|obsolete-repository/);
});
