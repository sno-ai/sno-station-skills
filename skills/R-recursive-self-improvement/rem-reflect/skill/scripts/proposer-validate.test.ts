import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { validateProposal, proposalSignature } from './proposer.ts';
import type { Proposal } from './proposer.ts';
import { appendLedger } from './ledger.ts';
import type { Page } from './pages.ts';
import { tmp, fixtureConfig, fixtureHarnessHomes, makeStore, writeInstalledSkill } from './test-helpers.ts';

const HOMES = fixtureHarnessHomes([]);
const ROOTS = [join(HOMES.claudeHome, 'skills'), join(HOMES.codexHome, 'skills')];
const HEARTBEAT = writeInstalledSkill(HOMES.claudeHome, 'heartbeat', 'Body line.\n<!-- reminders:start -->\n<!-- reminders:end -->\n');
writeInstalledSkill(HOMES.codexHome, 'heartbeat', 'Body line.\n<!-- reminders:start -->\n<!-- reminders:end -->\n');

function ctx(store: string, pages: Page[], roots = ROOTS): { store: string; pages: Page[]; roots: string[] } {
  return { store, pages, roots };
}
function page(id: string, cls: 'SKILL_DEFECT' | 'EXECUTION_LAPSE'): Page {
  return { page_id: id, summary: 's', class: cls, root_cause: { fact: 'f' } as Page['root_cause'], fix: 'x',
    body: '', count: 2, task_ids: [], last_seen: '2026-09-01', skills_observed: [], citations: [], skills_used: [] } as unknown as Page;
}
function base(over: Partial<Proposal>): Proposal {
  const merged: Record<string, unknown> = { kind: 'patch', target: HEARTBEAT, region: 'body', purpose: { summary: 'fix it', page_ids: ['pg-sd'] },
    scenario: { task_type: 'write', trigger: 'x', tools: [] }, skills_used: [], skill_target: null, knowledge_used: [],
    outcome: 'fail', evidence: [], ops: [{ op: 'append', text: 'one more line\n' }], ...over };
  // an explicit `undefined` key would fail the array/string schema checks; drop them
  for (const k of Object.keys(merged)) if (merged[k] === undefined) delete merged[k];
  return merged as unknown as Proposal;
}

const served = new Set([HEARTBEAT]);

// a create/patch missing a PURPOSE page id or an expertise field is refused ---
test('a patch with no PURPOSE page id, and one with an empty scenario.task_type, are refused', () => {
  const store = makeStore(fixtureConfig({ ...HOMES, claude_home: HOMES.claudeHome, codex_home: HOMES.codexHome }));
  const c = ctx(store, [page('pg-sd', 'SKILL_DEFECT')]);
  assert.throws(() => validateProposal(base({ purpose: { summary: 's', page_ids: [] } }), c, served), /page id/);
  assert.throws(() => validateProposal(base({ scenario: { task_type: '', trigger: 't', tools: [] } }), c, served), /expertise/);
});

// class routing and the reminders region rules ---
test('SKILL_DEFECT routes to a body patch and EXECUTION_LAPSE to a reminders patch', () => {
  const store = makeStore(fixtureConfig({ claude_home: HOMES.claudeHome, codex_home: HOMES.codexHome }));
  const c = ctx(store, [page('pg-sd', 'SKILL_DEFECT'), page('pg-el', 'EXECUTION_LAPSE')]);
  assert.doesNotThrow(() => validateProposal(base({}), c, served));
  // a body patch against an EXECUTION_LAPSE page is refused
  assert.throws(() => validateProposal(base({ region: 'body', purpose: { summary: 's', page_ids: ['pg-el'] } }), c, served), /disagrees/);
  // an EXECUTION_LAPSE reminders patch adds one line
  const rem = base({ region: 'reminders', ops: undefined, line: 'Always close the handle.', purpose: { summary: 's', page_ids: ['pg-el'] } });
  assert.doesNotThrow(() => validateProposal(rem, c, served));
});

test('a reminders line duplicate, and a replace_line not in the region, are refused', () => {
  const homes = fixtureHarnessHomes([]);
  const hb = writeInstalledSkill(homes.claudeHome, 'hb', '<!-- reminders:start -->\nExisting reminder line.\n<!-- reminders:end -->\n');
  const roots = [join(homes.claudeHome, 'skills'), join(homes.codexHome, 'skills')];
  const store = makeStore(fixtureConfig({ claude_home: homes.claudeHome, codex_home: homes.codexHome }));
  const c = ctx(store, [page('pg-el', 'EXECUTION_LAPSE')], roots);
  const s = new Set([hb]);
  const dup = base({ target: hb, region: 'reminders', ops: undefined, line: 'Existing reminder line.', purpose: { summary: 's', page_ids: ['pg-el'] } });
  assert.throws(() => validateProposal(dup, c, s), /byte-identical/);
  const badReplace = base({ target: hb, region: 'reminders', ops: undefined, line: 'New line.', replace_line: 'Not present.', purpose: { summary: 's', page_ids: ['pg-el'] } });
  assert.throws(() => validateProposal(badReplace, c, s), /not in the reminders/);
  const okReplace = base({ target: hb, region: 'reminders', ops: undefined, line: 'Replacement line.', replace_line: 'Existing reminder line.', purpose: { summary: 's', page_ids: ['pg-el'] } });
  assert.doesNotThrow(() => validateProposal(okReplace, c, s));
});

test('a 13th reminder line is refused (region cap of 12)', () => {
  const twelve = Array.from({ length: 12 }, (_, i) => `Reminder number ${i}.`).join('\n');
  const homes = fixtureHarnessHomes([]);
  const hb = writeInstalledSkill(homes.claudeHome, 'hb', `<!-- reminders:start -->\n${twelve}\n<!-- reminders:end -->\n`);
  const roots = [join(homes.claudeHome, 'skills'), join(homes.codexHome, 'skills')];
  const store = makeStore(fixtureConfig({ claude_home: homes.claudeHome, codex_home: homes.codexHome }));
  const c = ctx(store, [page('pg-el', 'EXECUTION_LAPSE')], roots);
  const thirteenth = base({ target: hb, region: 'reminders', ops: undefined, line: 'One too many.', purpose: { summary: 's', page_ids: ['pg-el'] } });
  assert.throws(() => validateProposal(thirteenth, c, new Set([hb])), /reminders block at the end of SKILL.md past/);
});

// the validator refusals and the two accepts ---
test('size, path, and create rules are each refused; a clean patch and create pass the validator', () => {
  const store = makeStore(fixtureConfig({ claude_home: HOMES.claudeHome, codex_home: HOMES.codexHome }));
  const c = ctx(store, [page('pg-sd', 'SKILL_DEFECT'), page('pg-el', 'EXECUTION_LAPSE')]);
  const sd = { page_ids: ['pg-sd'], summary: 's' };
  // 31-line growth
  assert.throws(() => validateProposal(base({ ops: [{ op: 'append', text: 'x\n'.repeat(31) }] }), c, served), /lines/);
  // 201-char description growth (replace the description line with a much longer one)
  assert.throws(() => validateProposal(base({ ops: [{ op: 'replace', target: 'fixture heartbeat.', text: 'd'.repeat(260) }] }), c, served), /description/);
  // rename name
  assert.throws(() => validateProposal(base({ ops: [{ op: 'replace', target: 'name: heartbeat', text: 'name: renamed' }] }), c, served), /name/);
  // replace target occurs nowhere
  assert.throws(() => validateProposal(base({ ops: [{ op: 'replace', target: 'NOT-THERE', text: 'y' }] }), c, served), /occurs 0 times|not once/);
  // patch a deployed copy / path outside skills/<unit>
  assert.throws(() => validateProposal(base({ target: tmp('outside') }), c, served), /patch must target/);
  // create naming the existing unit heartbeat
  const createBase = { kind: 'create' as const, target: 'heartbeat', purpose: sd, scenario: { task_type: 'w', trigger: 't', tools: [] },
    skills_used: [], skill_target: null, knowledge_used: [], outcome: 'fail' as const, evidence: [],
    skill_md: `---\nname: heartbeat\ndescription: "new one."\n---\n# x\n` };
  assert.throws(() => validateProposal(createBase, c, served), /already exists/);
  // create with a bad unit name
  assert.throws(() => validateProposal({ ...createBase, target: 'Bad_Name', skill_md: `---\nname: Bad_Name\ndescription: "d."\n---\n#x\n` }, c, served), /create target/);
  // create missing description
  assert.throws(() => validateProposal({ ...createBase, target: 'example-new', skill_md: `---\nname: example-new\n---\n#x\n` }, c, served), /frontmatter/);
  // create name != path
  assert.throws(() => validateProposal({ ...createBase, target: 'example-new', skill_md: `---\nname: other-name\ndescription: "d."\n---\n#x\n` }, c, served), /frontmatter/);
  // clean accepts: a modest body patch, and a valid create
  assert.doesNotThrow(() => validateProposal(base({ ops: [{ op: 'append', text: 'one clean line\n' }] }), c, served));
  assert.doesNotThrow(() => validateProposal({ ...createBase, target: 'example-new', skill_md: `---\nname: example-new\ndescription: "a brand new skill."\n---\n# example-new\n` }, c, served));
});

// The validator: a proposal byte-identical to a Rejected ledger row is refused, id recorded ---
test('a proposal byte-identical to a Rejected row is refused naming the row; a reworded one passes', () => {
  const store = makeStore(fixtureConfig({ claude_home: HOMES.claudeHome, codex_home: HOMES.codexHome }));
  const c = ctx(store, [page('pg-sd', 'SKILL_DEFECT')]);
  const rejected = base({ ops: [{ op: 'append', text: 'the rejected change\n' }] });
  appendLedger(store, { type: 'proposal', proposal_id: '20260901-0000/codex', verdict: 'Rejected', signature: proposalSignature(rejected) });
  // same change, only indentation/trailing-space differences -> refused
  const restyled = base({ ops: [{ op: 'append', text: '  the rejected change  \n' }] });
  assert.throws(() => validateProposal(restyled, c, served), /Rejected proposal: 20260901-0000\/codex/);
  // one word changed -> staged
  assert.doesNotThrow(() => validateProposal(base({ ops: [{ op: 'append', text: 'the accepted change\n' }] }), c, served));
});
