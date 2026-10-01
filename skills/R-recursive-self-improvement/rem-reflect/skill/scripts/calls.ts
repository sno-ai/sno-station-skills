import { isObject } from './config.ts';
import { contentText, payload } from './harvest.ts';
import type { StoredRecord, Trace } from './harvest.ts';

export interface CallRecord {
  call_id: string;
  line_start: number;
  line_end: number;
  turn: string | null;
  tool: string;
  target: string | null;
  started_at: string | null;
  ended_at: string | null;
  failed: boolean;
  failure_kind: 'exit_nonzero' | 'tool_error' | 'denied' | 'interrupted' | 'timeout' | 'edit_mismatch' | 'script_error' | 'hook_block' | null;
  exit_code: number | null;
  benign_nonzero: boolean;
  error_excerpt: string | null;
}

const head = (value: unknown): string | null => typeof value === 'string' && value ? value.slice(0, 200) : null;
const time = (value: unknown): string | null => typeof value === 'string' ? value : typeof value === 'number' ? new Date(value).toISOString() : null;
const tail = (value: string): string | null => value ? value.slice(-600) : null;
const outputText = (value: unknown): string => Array.isArray(value) ? contentText(value) : typeof value === 'string' ? value : '';

export function readCalls(trace: Trace): CallRecord[] {
  const calls: CallRecord[] = [];
  if (trace.agent_id === 'claude-code') {
    const uses = new Map<string, { item: StoredRecord; block: Record<string, unknown> }>();
    for (const item of trace.records) {
      const message = payload(item.record, 'claude-code');
      if (!Array.isArray(message.content)) continue;
      for (const block of message.content.filter(isObject)) {
        if (block.type === 'tool_use' && typeof block.id === 'string') uses.set(block.id, { item, block });
        if (block.type !== 'tool_result' || typeof block.tool_use_id !== 'string') continue;
        const use = uses.get(block.tool_use_id);
        const result = outputText(block.content);
        const structured = item.record.toolUseResult;
        const benign = isObject(structured) && 'returnCodeInterpretation' in structured;
        const exit = /^(?:Error: )?Exit code (-?\d+)/.exec(result)?.[1]
          ?? (typeof structured === 'string' ? /^(?:Error: )?Exit code (-?\d+)/.exec(structured)?.[1] : undefined);
        const exitCode = exit === undefined ? null : Number(exit);
        const failed = block.is_error === true && !benign;
        const denial = item.record.toolDenialKind;
        const kind = !failed ? null : denial === 'interrupted' || (isObject(structured) && structured.interrupted === true) || result.includes('[Request interrupted by user]')
          ? 'interrupted' : typeof denial === 'string' ? 'denied'
          : result.startsWith('PreToolUse:') ? 'hook_block'
          : result.includes('Command timed out after') ? 'timeout'
          : result.includes('Failed to find expected lines') ? 'edit_mismatch'
          : exitCode !== null ? 'exit_nonzero' : 'tool_error';
        const input = use?.block.input;
        const fields = isObject(input) ? input : {};
        calls.push({ call_id: block.tool_use_id, line_start: use?.item.line_number ?? item.line_number,
          line_end: item.line_number, turn: typeof item.record.promptId === 'string' ? item.record.promptId : null,
          tool: typeof use?.block.name === 'string' ? use.block.name : 'unknown',
          target: head(fields.file_path ?? fields.command ?? fields.url ?? fields.pattern),
          started_at: time(use?.item.record.timestamp), ended_at: time(item.record.timestamp), failed,
          failure_kind: kind, exit_code: exitCode, benign_nonzero: benign,
          error_excerpt: failed ? tail(result || (typeof structured === 'string' ? structured : '')) : null });
      }
    }
    return calls;
  }

  const scripts = new Map<string, { item: StoredRecord; input: string; turn: string | null }>();
  const cells = new Map<string, string>();
  const waits = new Map<string, string>();
  for (const item of trace.records) {
    const record = payload(item.record, 'codex');
    if (item.record.type === 'event_msg' && record.type === 'item_completed' && isObject(record.item)) {
      const step = record.item;
      if (!['CommandExecution', 'FileChange', 'McpToolCall'].includes(String(step.type)) || step.source === 'user_shell') continue;
      const exit = typeof step.exit_code === 'number' ? step.exit_code : null;
      const failed = step.status === 'failed' || step.status === 'declined' || exit !== null && exit !== 0
        || isObject(step.result) && step.result.isError === true;
      const error = outputText(step.aggregated_output ?? step.stderr ?? (isObject(step.result) ? step.result.content : ''));
      const command = Array.isArray(step.parsed_cmd) && isObject(step.parsed_cmd[0]) ? step.parsed_cmd[0].cmd : null;
      const target = step.type === 'CommandExecution' ? head(command)
        : step.type === 'FileChange' && isObject(step.changes) ? head(Object.keys(step.changes)[0])
          : head(`${String(step.server ?? '')}/${String(step.tool ?? '')}`);
      calls.push({ call_id: String(step.id ?? `item-${item.line_number}`), line_start: item.line_number,
        line_end: item.line_number, turn: typeof record.turn_id === 'string' ? record.turn_id : null,
        tool: step.type === 'CommandExecution' ? 'shell' : step.type === 'FileChange' ? 'edit' : String(step.tool ?? 'mcp'),
        target, started_at: time(record.started_at_ms), ended_at: time(record.completed_at_ms), failed,
        failure_kind: !failed ? null : step.status === 'declined' ? 'denied' : exit === 124 ? 'timeout'
          : exit !== null && exit !== 0 ? 'exit_nonzero' : 'tool_error',
        exit_code: exit, benign_nonzero: false, error_excerpt: failed ? tail(error) : null });
      continue;
    }
    if (record.type === 'custom_tool_call' && typeof record.call_id === 'string') {
      scripts.set(record.call_id, { item, input: String(record.input ?? ''),
        turn: isObject(record.internal_chat_message_metadata_passthrough)
          && typeof record.internal_chat_message_metadata_passthrough.turn_id === 'string'
          ? record.internal_chat_message_metadata_passthrough.turn_id : null });
      continue;
    }
    if (record.type === 'function_call' && record.name === 'wait' && typeof record.call_id === 'string'
      && typeof record.arguments === 'string') {
      try {
        const args: unknown = JSON.parse(record.arguments);
        if (isObject(args) && typeof args.cell_id === 'string') waits.set(record.call_id, args.cell_id);
      } catch { /* an unparseable wait has no cell to join */ }
      continue;
    }
    if (!['custom_tool_call_output', 'function_call_output'].includes(String(record.type))) continue;
    const output = outputText(record.output);
    const direct = typeof record.call_id === 'string' ? scripts.get(record.call_id) : undefined;
    const cell = /Script running with cell ID ([^\s]+)/.exec(output)?.[1];
    if (cell && direct && typeof record.call_id === 'string') cells.set(cell, record.call_id);
    const waitCell = typeof record.call_id === 'string' ? cells.get(waits.get(record.call_id) ?? '') : undefined;
    const script = direct ?? (waitCell ? scripts.get(waitCell) : undefined);
    if (!script || !/^(Script failed|Script terminated|aborted by user)/m.test(output)) continue;
    const kind = output.includes('apply_patch verification failed') ? 'edit_mismatch'
      : output.includes('Command blocked by PreToolUse hook') ? 'hook_block'
        : /Script terminated|aborted by user/.test(output) ? 'interrupted' : 'script_error';
    calls.push({ call_id: direct ? String(record.call_id) : String(waitCell), line_start: script.item.line_number,
      line_end: item.line_number, turn: script.turn, tool: 'exec', target: head(script.input),
      started_at: time(script.item.record.timestamp), ended_at: time(item.record.timestamp), failed: true,
      failure_kind: kind, exit_code: null, benign_nonzero: false, error_excerpt: tail(output) });
  }
  return calls;
}
