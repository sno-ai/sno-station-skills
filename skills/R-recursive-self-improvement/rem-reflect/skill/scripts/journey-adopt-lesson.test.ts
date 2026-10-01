import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { verdictCommand } from './adopt.ts';
import { readLedger } from './ledger.ts';
import { remindersRegion } from './catalogue.ts';
import { appendRows } from './lessons.ts';
import { reflectionFiles } from './config.ts';
import { fixtureHarnessHomes, makeConfig, makeStore, tmp, writeInstalledSkill } from './test-helpers.ts';

const NOW = new Date('2026-09-08T00:00:00Z');

function fixture(reminderLines: number) {
  const { claudeHome, codexHome } = fixtureHarnessHomes([]);
  const region = Array.from({ length: reminderLines }, (_, i) => `- keep an eye on thing ${i + 1}`).join('\n');
  const body = `Body line.\n\n<!-- reminders:start -->\n${region}${reminderLines ? '\n' : ''}<!-- reminders:end -->\n\nAfter the region.\n`;
  const target = writeInstalledSkill(claudeHome, 'heartbeat', body);
  writeInstalledSkill(codexHome, 'heartbeat', body);
  const config = makeConfig({ claude_home: claudeHome, codex_home: codexHome,
    claude_root: tmp('c'), codex_root: tmp('x') });
  return { config, target, copies: [join(claudeHome, 'skills/heartbeat'), join(codexHome, 'skills/heartbeat')] };
}

function seedLesson(store: string, target: string, over: Record<string, unknown> = {}): void {
  const scenario = { task_type: 'debug', trigger: 'the heartbeat stalled', tools: [] as string[] };
  appendRows(join(store, reflectionFiles.lessons), [{
    lesson_id: 'L-hb1', page_id: 'hb1', status: 'candidate', count: 4, helped: 0, harmful: 0,
    measured: false, created_run: '20260908-1200', project_id: 'p', agent_id: 'codex', user_id: 'u',
    skill_target: null, scenario, situation: scenario, advice: 'stop the stale heartbeat before arming a new one',
    because: 'a stale one masks the new', applies_to: `skill:${target}`,
    polarity: 'from_failure', evidence: [], counter_examples: 'not searched', listed: true, ...over,
  }]);
}

test('accepting a listed skill lesson updates both installed copies and stores its evidence', () => {
  const { config, target, copies } = fixture(0);
  const store = makeStore(config);
  seedLesson(store, target);

  const result = verdictCommand(store, 'accept', 'L-hb1', NOW, true);

  assert.equal(result.code, 0, result.lines.join('\n'));
  for (const copy of copies) {
    const lines = remindersRegion(readFileSync(join(copy, 'SKILL.md'), 'utf8')) ?? [];
    assert.equal(lines.length, 1);
    assert.match(lines[0], /stop the stale heartbeat/);
    assert.equal(existsSync(join(copy, 'docs')), false, 'no evidence is written into an installed skill');
  }
  const row = readLedger(store).find(x => x.type === 'lesson-verdict' && x.status === 'accepted');
  assert.deepEqual(row?.adopted_roots, copies);
  assert.deepEqual(row?.refused_roots, []);
  assert.ok(existsSync(join(store, reflectionFiles.staging, 'lessons', 'L-hb1', 'lesson.json')),
    'lesson evidence stays in the loop store');
});

test('a full reminders region refuses both copies and a repeated accept works after both have room', () => {
  const { config, target, copies } = fixture(12);
  const store = makeStore(config);
  seedLesson(store, target);
  const before = copies.map(copy => readFileSync(join(copy, 'SKILL.md'), 'utf8'));
  const first = verdictCommand(store, 'accept', 'L-hb1', NOW, true);
  assert.equal(first.code, 1, first.lines.join('\n'));
  assert.ok(readLedger(store).some(x => x.type === 'lesson-verdict' && String(x.reason).includes('region-full')));
  assert.deepEqual(copies.map(copy => readFileSync(join(copy, 'SKILL.md'), 'utf8')), before,
    'the refused accept changes neither installed copy');

  for (const copy of copies) {
    const path = join(copy, 'SKILL.md');
    writeFileSync(path, readFileSync(path, 'utf8').replace('- keep an eye on thing 1\n', ''));
  }
  const second = verdictCommand(store, 'accept', 'L-hb1', NOW, true);
  assert.equal(second.code, 0, second.lines.join('\n'));
  for (const copy of copies) {
    assert.match(readFileSync(join(copy, 'SKILL.md'), 'utf8'), /stop the stale heartbeat/,
      'the retry writes the accepted reminder into each installed copy');
  }
});
