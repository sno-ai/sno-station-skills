import { reflectionFiles, isObject } from './config.ts';
import { message } from './text.ts';
import { closeSync, existsSync, fsyncSync, openSync, readFileSync, writeSync } from 'node:fs';
import { dirname, join } from 'node:path';
import type { Evidence } from './evidence.ts';
import type { CounterExamples, Scenario } from './pages.ts';
import { privateDirectory } from './store.ts';

export interface LessonInput {
  situation: Scenario; advice: string; because: string; applies_to: string;
  polarity: 'from_failure' | 'from_success'; evidence: Evidence[]; counter_examples: CounterExamples;
}
export interface Lesson extends LessonInput {
  lesson_id: string; page_id: string; status: 'candidate' | 'accepted' | 'rejected' | 'tbd' | 'under_review';
  count: number; helped: number; harmful: number; measured: boolean; created_run: string;
  project_id: string; agent_id: string; user_id: string; skill_target: string | null; scenario: Scenario;
  listed?: boolean; judgment_id?: string; verification?: { accepted?: boolean };
}
export function appendRows(path: string, rows: readonly unknown[]): void {
  if (!rows.length) return;
  privateDirectory(dirname(path));
  const fd = openSync(path, 'a', 0o600);
  try { for (const row of rows) writeSync(fd, `${JSON.stringify(row)}\n`); fsyncSync(fd); }
  finally { closeSync(fd); }
}
// Last-row-wins over an append-only lessons file. `readLessons` reads the working file;
// recall reads the same shape from a HEAD snapshot, so the parse lives here.
export function lessonsFrom(text: string): Lesson[] {
  const current = new Map<string, Lesson>();
  for (const line of text.split('\n').filter(Boolean)) {
    const value: unknown = JSON.parse(line);
    if (!isObject(value) || typeof value.lesson_id !== 'string' || typeof value.status !== 'string') throw new Error(message('lessonRow'));
    current.set(value.lesson_id, value as unknown as Lesson);
  }
  return [...current.values()];
}
export function readLessons(store: string): Lesson[] {
  const path = join(store, reflectionFiles.lessons);
  if (!existsSync(path)) return [];
  return lessonsFrom(readFileSync(path, 'utf8'));
}
export interface LessonRead { session_id: string; lesson_id: string }
export function readLessonReads(store: string, log: string[]): LessonRead[] {
  const path = join(store, reflectionFiles.usage);
  if (!existsSync(path)) return [];
  const reads: LessonRead[] = [];
  for (const line of readFileSync(path, 'utf8').split('\n').filter(Boolean)) {
    let value: unknown;
    try { value = JSON.parse(line); } catch { log.push(message('usageMalformed')); continue; }
    if (isObject(value) && value.type === 'read' && typeof value.session_id === 'string' && typeof value.lesson_id === 'string') {
      reads.push({ session_id: value.session_id, lesson_id: value.lesson_id });
    }
  }
  return reads;
}
export interface LessonsShown { session_id: string; lesson_ids: string[] }
// Lessons each session was shown (session-start list and first-message recall), merged per session.
export function readLessonsShown(store: string, log: string[]): LessonsShown[] {
  const path = join(store, reflectionFiles.usage);
  if (!existsSync(path)) return [];
  const shown = new Map<string, Set<string>>();
  for (const line of readFileSync(path, 'utf8').split('\n').filter(Boolean)) {
    let value: unknown;
    try { value = JSON.parse(line); } catch { log.push(message('usageMalformed')); continue; }
    if (!isObject(value) || value.type !== 'shown' || typeof value.session_id !== 'string' || !Array.isArray(value.lesson_ids)) continue;
    const ids = shown.get(value.session_id) ?? new Set<string>();
    for (const id of value.lesson_ids) if (typeof id === 'string') ids.add(id);
    shown.set(value.session_id, ids);
  }
  return [...shown].filter(([, ids]) => ids.size > 0).map(([session_id, ids]) => ({ session_id, lesson_ids: [...ids] }));
}
