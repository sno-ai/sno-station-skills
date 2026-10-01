import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { reflectionFiles, readingLimits, isObject } from './config.ts';
import { appendRows } from './lessons.ts';

// The append-only skill-impact ledger. Code writes every row; cloud replies have no direct write path.
export interface ProposalRow {
  type: 'proposal';
  run_id: string;
  half: string;
  backend: string;
  kind: 'create' | 'patch' | 'no_action';
  target: string | null;
  region: 'body' | 'reminders' | null;
  diff: string;
  expertise: Record<string, unknown>;
  purpose: { summary: string; page_ids: string[] };
  verdict: 'pending' | 'logged';
  evidence: string[];
}

export function readLedger(store: string): Record<string, unknown>[] {
  const path = join(store, reflectionFiles.ledger);
  if (!existsSync(path)) return [];
  return readFileSync(path, 'utf8').split('\n').filter(Boolean).map(line => {
    const value: unknown = JSON.parse(line);
    if (!isObject(value)) throw new Error('skill-impact.jsonl: a row is not an object');
    return value;
  });
}

export function appendLedger(store: string, row: Record<string, unknown>): void {
  appendRows(join(store, reflectionFiles.ledger), [row]);
}

// The proposal validator reads recent rows and rejected proposals to refuse an identical repeat.
export interface ProposerLedger { recent: Record<string, unknown>[]; rejected: Record<string, unknown>[] }
export function proposerLedger(store: string): ProposerLedger {
  const rows = readLedger(store);
  const rejected = rows.filter(row => row.verdict === 'Rejected');
  return { recent: rows.slice(-readingLimits.ledgerRows), rejected };
}

// A coarse unified diff between the current file and the proposed content. The ledger needs a
// human-readable record of the change; adoption applies the real bytes.
export function unifiedDiff(before: string, after: string, path: string): string {
  if (before === after) return '';
  const a = before.length ? before.split('\n') : [];
  const b = after.length ? after.split('\n') : [];
  const head = `--- a/${path}\n+++ b/${path}\n`;
  return head + a.map(line => `-${line}`).concat(b.map(line => `+${line}`)).join('\n') + '\n';
}
