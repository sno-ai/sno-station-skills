import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, rmSync, rmdirSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { isObject, loadConfig, reflectionFiles, sizeCaps, skillRoots } from './config.ts';
import type { Config } from './config.ts';
import { message } from './text.ts';
import { remindersRegion } from './catalogue.ts';
import { patchBody } from './pages.ts';
import { applyReminders } from './proposer.ts';
import { appendLedger, readLedger } from './ledger.ts';
import { appendRows, readLessons } from './lessons.ts';
import type { Lesson } from './lessons.ts';
import {
  atomicWrite, commitStore, privateDirectory,
} from './store.ts';
import type { CommandResult } from './rem-reflect.ts';
import { lessonProject, observe } from './observe.ts';

const VERDICT: Record<string, 'Accepted' | 'Rejected' | 'TBD'> = { accept: 'Accepted', reject: 'Rejected', tbd: 'TBD' };

// Prepare, back up, then move a set of {dst -> newBytes}. If a write fails part-way, the writes
// already made are rolled back from their backups; a create (no prior file) is removed.
interface Move { dst: string; backup: string; bytes: string; existed: boolean }
function applyMoves(moves: Move[]): void {
  const done: Move[] = [];
  try {
    for (const move of moves) {
      privateDirectory(dirname(move.backup));
      if (move.existed) atomicWrite(move.backup, readFileSync(move.dst));
      mkdirSync(dirname(move.dst), { recursive: true });
      // Track the move before replacement so every attempted create or patch is rolled back.
      done.push(move);
      atomicWrite(move.dst, move.bytes);
    }
  } catch (error) {
    for (const move of done.reverse()) {
      if (move.existed) atomicWrite(move.dst, readFileSync(move.backup));
      else {
        rmSync(move.dst, { force: true });
        try { rmdirSync(dirname(move.dst)); } catch { /* keep a non-empty directory */ }
      }
    }
    throw error;
  }
}

function installedTargets(config: Config, name: string): string[] {
  return [...new Set(skillRoots(config).map(root => join(root, name)))];
}

function sha256(bytes: string): string {
  return createHash('sha256').update(bytes).digest('hex');
}

function libraryVersion(payload: string): unknown | null {
  const path = join(payload, 'PUBLISHED.json');
  return existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) as unknown : null;
}

function backupPath(staging: string, index: number): string {
  return join(staging, 'backup', `root-${index + 1}`, 'SKILL.md');
}

function targetName(target: string): string {
  return basename(target.replace(/\/SKILL\.md$/, ''));
}

function adoptProposal(store: string, config: Config, runId: string, half: string, row: Record<string, unknown>, date: string): CommandResult {
  const stagingHalf = join(store, reflectionFiles.staging, runId, half);
  const proposalId = `${runId}/${half}`;
  const target = String(row.target ?? '');
  const name = targetName(target);
  const payloads = installedTargets(config, name);
  const libraryVersions: Record<string, unknown | null> = {};
  const adopted: string[] = [];
  const refusedRoots: string[] = [];
  const refusalDetails: string[] = [];

  if (row.kind === 'create') {
    const conflicts = payloads.filter(existsSync);
    if (conflicts.length) {
      const reason = `adoption-refused: target exists: ${conflicts.join(', ')}`;
      appendLedger(store, { type: 'verdict', proposal_id: proposalId, verdict: 'refused', reason, at: date });
      return { code: 1, lines: [`${proposalId}: ${reason}`] };
    }
    const bytes = readFileSync(join(stagingHalf, reflectionFiles.skillMd), 'utf8');
    try {
      applyMoves(payloads.map((payload, index) => ({
        dst: join(payload, 'SKILL.md'), backup: backupPath(stagingHalf, index), bytes, existed: false,
      })));
      for (const payload of payloads) { adopted.push(payload); libraryVersions[payload] = null; }
    } catch (error) {
      const reason = `adoption-failed: ${String(error)}`;
      appendLedger(store, { type: 'verdict', proposal_id: proposalId, verdict: 'adoption-failed', reason, at: date });
      return { code: 1, lines: [`${proposalId}: ${reason}`] };
    }
  } else {
    const hashes = isObject(row.target_hashes) ? row.target_hashes : {};
    const patch: unknown = JSON.parse(readFileSync(join(stagingHalf, reflectionFiles.patch), 'utf8'));
    if (!isObject(patch)) throw new Error('patch.json invalid');
    for (const [index, payload] of payloads.entries()) {
      const skillMd = join(payload, 'SKILL.md');
      if (!existsSync(skillMd)) continue;
      const current = readFileSync(skillMd, 'utf8');
      if (hashes[payload] !== sha256(current)) {
        refusedRoots.push(payload);
        refusalDetails.push(`${payload}: target changed after staging`);
        continue;
      }
      try {
        const version = libraryVersion(payload);
        const bytes = patch.region === 'reminders'
          ? applyReminders(current, String(patch.line), typeof patch.replace_line === 'string' ? patch.replace_line : undefined)
          : patchBody(current, (patch.ops ?? []) as { op: 'append' | 'replace' | 'insert_after'; target?: string; text: string }[], false);
        applyMoves([{ dst: skillMd, backup: backupPath(stagingHalf, index), bytes, existed: true }]);
        adopted.push(payload);
        libraryVersions[payload] = version;
      } catch (error) {
        refusedRoots.push(payload);
        refusalDetails.push(`${payload}: ${String(error)}`);
      }
    }
    if (!adopted.length) {
      const reason = refusalDetails.length ? refusalDetails.join('; ') : `adoption-refused: unit-missing: ${name}`;
      appendLedger(store, { type: 'verdict', proposal_id: proposalId, verdict: 'refused', reason, at: date });
      return { code: 1, lines: [`${proposalId}: ${reason}`] };
    }
  }

  const evidence = { ...row, library_versions: libraryVersions };
  atomicWrite(join(stagingHalf, 'ledger-row.json'), `${JSON.stringify(evidence, null, 2)}\n`);
  appendLedger(store, { type: 'verdict', proposal_id: proposalId, verdict: 'Accepted', target, kind: row.kind,
    adopted_roots: adopted, refused_roots: refusedRoots, library_versions: libraryVersions, at: date });
  const suffix = refusalDetails.length ? `; refused: ${refusalDetails.join('; ')}` : '';
  return { code: 0, lines: [`${proposalId}: Accepted${suffix}`] };
}

function proposalVerdict(store: string, config: Config, command: string, id: string, date: string): CommandResult {
  const [runId, half] = id.split('/');
  const rows = readLedger(store).filter(row => row.type === 'proposal' && row.proposal_id === id);
  const proposal = rows[rows.length - 1];
  if (!proposal) return { code: 1, lines: [`${id}: no such proposal`] };
  const verdicts = readLedger(store).filter(row => row.type === 'verdict' && row.proposal_id === id);
  const last = verdicts[verdicts.length - 1];
  if (command === 'accept') {
    if (last && last.verdict === 'Accepted') return { code: 0, lines: [`${id}: already adopted`] };
    return adoptProposal(store, config, runId, half, proposal, date);
  }
  appendLedger(store, { type: 'verdict', proposal_id: id, verdict: VERDICT[command], from: last ? last.verdict : proposal.verdict, at: date });
  return { code: 0, lines: [`${id}: ${VERDICT[command]}`] };
}

// render one reminder line from the advice and adopt it into the payload's SKILL.md through
// the sequence (backup, all-or-nothing, evidence copy, 12-line region cap).
// A refused adoption records the lesson `tbd`; a repeated accept renders the line again and retries.
function adoptLesson(store: string, config: Config, lesson: Lesson, date: string): CommandResult {
  const payloadPath = lesson.applies_to.slice('skill:'.length);
  const name = targetName(payloadPath);
  const payloads = installedTargets(config, name);
  const stagingLesson = join(store, reflectionFiles.staging, 'lessons', lesson.lesson_id);
  const line = lesson.advice.replace(/\s+/g, ' ').trim();
  atomicWrite(join(stagingLesson, 'adopt', 'reminder.txt'), `${line}\n`);
  const refuse = (reason: string): CommandResult => {
    appendRows(join(store, reflectionFiles.lessons), [{ ...lesson, status: 'tbd' }]);
    appendLedger(store, { type: 'lesson-verdict', lesson_id: lesson.lesson_id, status: 'tbd', reason, at: date });
    return { code: 1, lines: [message('lessonAdoptRefused', { id: lesson.lesson_id, reason })] };
  };
  const adopted: string[] = [];
  const refusedRoots: string[] = [];
  const refusalDetails: string[] = [];
  const libraryVersions: Record<string, unknown | null> = {};
  for (const [index, payload] of payloads.entries()) {
    const skillMd = join(payload, 'SKILL.md');
    if (!existsSync(skillMd)) continue;
    try {
      const version = libraryVersion(payload);
      const newBytes = applyReminders(readFileSync(skillMd, 'utf8'), line, undefined);
      if ((remindersRegion(newBytes) ?? []).length > sizeCaps.reminderLines) {
        refusedRoots.push(payload);
        refusalDetails.push(`${payload}: region-full`);
        continue;
      }
      applyMoves([{ dst: skillMd, backup: backupPath(stagingLesson, index), bytes: newBytes, existed: true }]);
      adopted.push(payload);
      libraryVersions[payload] = version;
    } catch (error) {
      refusedRoots.push(payload);
      refusalDetails.push(`${payload}: ${String(error)}`);
    }
  }
  if (!adopted.length) return refuse(refusalDetails.length ? refusalDetails.join('; ') : 'adoption-refused: unit-missing');
  atomicWrite(join(stagingLesson, 'lesson.json'), `${JSON.stringify({ ...lesson, library_versions: libraryVersions }, null, 2)}\n`);
  appendRows(join(store, reflectionFiles.lessons), [{ ...lesson, applies_to: 'general', status: 'accepted', measured: false }]);
  appendLedger(store, { type: 'lesson-verdict', lesson_id: lesson.lesson_id, status: 'accepted', target: payloadPath,
    applies_to: 'general', adopted: true, adopted_roots: adopted, refused_roots: refusedRoots,
    library_versions: libraryVersions, at: date });
  const suffix = refusalDetails.length ? `; refused: ${refusalDetails.join('; ')}` : '';
  return { code: 0, lines: [`${message('lessonAdopted', { id: lesson.lesson_id, target: payloadPath })}${suffix}`] };
}

function lessonVerdict(store: string, config: Config, command: string, id: string, date: string,
  allProjects: boolean, thisProject: boolean): CommandResult {
  const lesson = readLessons(store).find(row => row.lesson_id === id);
  if (!lesson) return { code: 1, lines: [`${id}: no such lesson`] };
  if (command !== 'accept') {
    const status = command === 'reject' ? 'rejected' : 'tbd';
    appendRows(join(store, reflectionFiles.lessons), [{ ...lesson, status }]);
    appendLedger(store, { type: 'lesson-verdict', lesson_id: id, status, at: date });
    return { code: 0, lines: [`${id}: ${status}`] };
  }
  // Plain accept keeps the user-wide or project layer the cloud gave; any other scope, such as a skill lesson,
  // becomes a lesson of its project. The owner moves a lesson with --all-projects or --this-project.
  const project = `project:${lesson.project_id}`;
  const layered = lesson.applies_to === 'general' || lesson.applies_to.startsWith('project:');
  const appliesTo = allProjects ? 'general' : thisProject || !layered ? project : lesson.applies_to;
  if (lesson.status === 'accepted' && appliesTo === lesson.applies_to) {
    return { code: 0, lines: [`${id}: already adopted`] };
  }
  // The latest stored row must be listed before acceptance.
  if (lesson.listed !== true) {
    return { code: 1, lines: [message('lessonNotListed', { id, reason: `not listed (count ${lesson.count})` })] };
  }
  if (lesson.applies_to.startsWith('skill:') && allProjects) return adoptLesson(store, config, lesson, date);
  appendRows(join(store, reflectionFiles.lessons), [{ ...lesson, applies_to: appliesTo,
    status: 'accepted', measured: false }]);
  appendLedger(store, { type: 'lesson-verdict', lesson_id: id, status: 'accepted', applies_to: appliesTo, at: date });
  return { code: 0, lines: [appliesTo === lesson.applies_to ? `${id}: accepted` : `${id}: accepted for ${appliesTo}`] };
}

// The owner's verdict command routes a proposal id or lesson id and commits what it wrote.
export function verdictCommand(store: string, command: string, id: string, now: Date = new Date(),
  allProjects: boolean = false, thisProject: boolean = false): CommandResult {
  if (!(command in VERDICT)) return { code: 2, lines: [`unknown verdict: ${command}`] };
  if (!id) return { code: 2, lines: ['a proposal id or lesson id is required'] };
  if (!existsSync(store)) return { code: 1, lines: ['no store'] };
  const config = loadConfig(store);
  const isLesson = /^L-/.test(id);
  const date = now.toISOString().slice(0, 10);
  const result = isLesson ? lessonVerdict(store, config, command, id, date, allProjects, thisProject)
    : proposalVerdict(store, config, command, id, date);
  if (result.code === 0) {
    const item = isLesson ? readLessons(store).find(row => row.lesson_id === id)
      : readLedger(store).filter(row => row.type === 'proposal' && row.proposal_id === id).pop();
    const judgmentId = item?.judgment_id ?? readLedger(store)
      .find(row => row.type === 'cloud-link' && row.kind === (isLesson ? 'lesson' : 'proposal') && row.local_id === id)?.judgment_id;
    if (typeof judgmentId === 'string') {
      const previous = readLedger(store).filter(row => row.type === 'cloud-verdict' && row.judgment_id === judgmentId).pop();
      if (previous?.verdict !== command || previous?.applies_to !== (allProjects ? 'general' : undefined)) {
        appendLedger(store, { type: 'cloud-verdict', judgment_id: judgmentId,
          item_id: id, verdict: command, status: 'pending', ...(allProjects ? { applies_to: 'general' } : {}), at: date });
      }
    }
  }
  commitStore(store, `${VERDICT[command]} ${id}`, command, gatherWrites(store));
  if (result.code === 0) {
    const project = isLesson ? lessonProject(readLessons(store).find(row => row.lesson_id === id)?.applies_to, config) : undefined;
    observe('rsi.verdict', {
      ...(project === undefined ? { level: 'user' } : { level: 'project', project }),
      accepted: Number(command === 'accept'), rejected: Number(command === 'reject'), tbd: Number(command === 'tbd'),
    }, join(store, reflectionFiles.runLog));
  }
  return result;
}

// The files a verdict command may stage (never ledger/usage.jsonl).
function gatherWrites(store: string): string[] {
  return [reflectionFiles.ledger, reflectionFiles.lessons, reflectionFiles.staging].filter(rel => existsSync(join(store, rel)));
}
