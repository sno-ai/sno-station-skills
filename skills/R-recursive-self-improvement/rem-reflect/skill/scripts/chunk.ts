import { limits } from './config.ts';
import type { Rendering, RenderedRecord } from './render.ts';

export interface Chunk {
  id: string;
  trace_id: string;
  index: number;
  total: number;
  line_range: [number, number];
  oversized: boolean;
  header: string;
  body: string;
  text: string;
}

export function chunkRendering(traceId: string, rendering: Rendering, size: number = limits.chunkCharacters): Chunk[] {
  if (!Number.isInteger(size) || size <= 0) throw new Error('chunk size must be a positive integer');
  const groups: RenderedRecord[][] = [];
  let group: RenderedRecord[] = [];
  let length = 0;
  for (const record of rendering.records) {
    if (group.length && length + record.text.length > size) {
      groups.push(group); group = []; length = 0;
    }
    group.push(record); length += record.text.length;
    if (length > size) { groups.push(group); group = []; length = 0; }
  }
  if (group.length || groups.length === 0) groups.push(group);
  const chunks = groups.map((records, index): Chunk => {
    const body = records.map(record => record.text).join('');
    const line_range: [number, number] = [records[0]?.line_number ?? 0, records.at(-1)?.line_number ?? 0];
    const oversized = body.length > size;
    const header = `${traceId} chunk ${index + 1} of ${groups.length} lines ${line_range[0]}-${line_range[1]}${oversized ? ' oversized' : ''}`;
    return { id: `${traceId}#${index + 1}`, trace_id: traceId, index: index + 1, total: groups.length,
      line_range, oversized, header, body, text: `${header}\n${body}` };
  });
  if (chunks.map(chunk => chunk.body).join('') !== rendering.body) throw new Error('rendering body does not match its records');
  return chunks;
}

export function reassembleChunks(chunks: readonly Chunk[]): string {
  for (const [index, chunk] of chunks.entries()) {
    if (chunk.index !== index + 1 || chunk.total !== chunks.length || chunk.trace_id !== chunks[0]?.trace_id) {
      throw new Error('chunks must be complete, in order, and from one trace');
    }
  }
  return chunks.map(chunk => chunk.text.slice(chunk.text.indexOf('\n') + 1)).join('');
}
