import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { testTempRoot } from './test-helpers.ts';
import { join } from 'node:path';
import { installedCatalogue } from './catalogue.ts';

test('cloud catalogue carries the complete body of every installed skill in both harness roots', t => {
  const root = mkdtempSync(join(testTempRoot, 'rsi-catalogue-'));
  t.after(() => rmSync(root, { recursive: true }));
  const claude = join(root, 'claude');
  const codex = join(root, 'codex');
  const bodies = [
    '---\nname: alpha\ndescription: "First purpose."\n---\n# Alpha\nPRIVATE-LONG-BODY\n',
    '---\nname: beta\ndescription: "Second purpose."\n---\n# Beta\nDifferent body.\n',
  ];
  for (const [index, home] of [claude, codex].entries()) {
    const skill = join(home, 'skills', index === 0 ? 'alpha' : 'beta');
    mkdirSync(skill, { recursive: true });
    writeFileSync(join(skill, 'SKILL.md'), bodies[index]);
    if (index === 0) writeFileSync(join(skill, 'SKILL.md.sha256'), 'protected\n');
  }

  assert.deepEqual(installedCatalogue([join(claude, 'skills'), join(codex, 'skills')]), [
    { path: join(claude, 'skills', 'alpha', 'SKILL.md'), name: 'alpha', description: 'First purpose.', sealed: true, skill_md: bodies[0] },
    { path: join(codex, 'skills', 'beta', 'SKILL.md'), name: 'beta', description: 'Second purpose.', sealed: false, skill_md: bodies[1] },
  ]);
});
