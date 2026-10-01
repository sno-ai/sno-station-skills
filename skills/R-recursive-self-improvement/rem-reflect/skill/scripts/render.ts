import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { isObject, paths } from './config.ts';
import { contentText, historyPrompt, payload } from './harvest.ts';
import type { HistoryEntry, StoredRecord, Trace } from './harvest.ts';

export interface RenderBudgets { tool_arguments: number; tool_results: number; skill_blocks: number; harness_user_tags?: string[] }
export interface RenderCounts { system_reminder: number; thinking: number; reasoning: number }
export interface RenderedRecord { line_number: number; text: string; harness_shaped: boolean }
export interface Rendering { body: string; records: RenderedRecord[]; dropped: RenderCounts; skills_loaded: string[] }

export function loadRenderBudgets(path: string = join(paths.references, 'render.json')): RenderBudgets {
  const value: unknown = JSON.parse(readFileSync(path, 'utf8'));
  if (!isObject(value)) throw new Error('render.json: expected an object');
  const result: RenderBudgets = { tool_arguments: 0, tool_results: 0, skill_blocks: 0 };
  for (const key of ['tool_arguments', 'tool_results', 'skill_blocks'] as const) {
    const budget = value[key];
    if (typeof budget !== 'number' || !Number.isInteger(budget) || budget < 2) throw new Error(`render.json: invalid ${key}`);
    result[key] = budget;
  }
  if (!Array.isArray(value.harness_user_tags) || !value.harness_user_tags.every(tag => typeof tag === 'string')) throw new Error('render.json: invalid harness_user_tags');
  result.harness_user_tags = value.harness_user_tags;
  return result;
}

export function truncate(text: string, budget: number): string {
  if (text.length <= budget) return text;
  // Never cut inside a surrogate pair: a lone half is invalid JSON for the `sno` CLI.
  const low = (index: number): boolean => /[\uDC00-\uDFFF]/.test(text[index] ?? '');
  let head = Math.ceil(budget / 2);
  if (low(head)) head -= 1;
  let tailStart = text.length - Math.floor(budget / 2);
  if (low(tailStart)) tailStart += 1;
  return `${text.slice(0, head)}[… ${tailStart - head} characters omitted …]${text.slice(tailStart)}`;
}

export function stripReminders(text: string): { text: string; count: number } {
  let count = 0;
  const clean = text.replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, () => { count++; return ''; });
  return { text: clean, count };
}

export function stripCodexPreamble(text: string): { text: string; harness_shaped: boolean } {
  let remaining = text;
  const wrapper = /^\s*<(environment_context|INSTRUCTIONS|user_instructions)>[\s\S]*?<\/\1>\s*/;
  for (;;) {
    const match = wrapper.exec(remaining);
    if (!match) break;
    remaining = remaining.slice(match[0].length);
  }
  return { text: remaining, harness_shaped: /^[<#/]/.test(remaining.trimStart()) };
}

export function resolveUserText(trace: Trace, item: StoredRecord, history: readonly HistoryEntry[] = []): {
  text: string; harness_shaped: boolean; reminders: number;
} {
  const own = stripReminders(contentText(payload(item.record, trace.agent_id).content));
  if (trace.agent_id === 'codex') return { ...stripCodexPreamble(own.text), reminders: own.count };
  const typed = item.user_text ?? historyPrompt(history, trace.session_id, item.record.timestamp);
  const clean = typed === undefined ? own : stripReminders(typed);
  return { text: clean.text, harness_shaped: false, reminders: own.count + (typed === undefined ? 0 : clean.count) };
}

function printable(value: unknown): string {
  if (typeof value === 'string') return value;
  return JSON.stringify(value) ?? '';
}

function toolSkills(trace: Trace): Set<string> {
  const ids = new Set<string>();
  for (const item of trace.records) {
    const content = payload(item.record, trace.agent_id).content;
    if (!Array.isArray(content)) continue;
    for (const block of content.filter(isObject)) {
      if (block.type === 'tool_use' && block.name === 'Skill' && typeof block.id === 'string') ids.add(block.id);
    }
  }
  return ids;
}

function renderBlock(block: Record<string, unknown>, budgets: RenderBudgets, skillIds: Set<string>, counts: RenderCounts): string {
  const type = String(block.type ?? 'unknown');
  if (type === 'thinking' || type === 'reasoning') {
    counts[type]++;
    return `[${type} dropped: 1]`;
  }
  if (['text', 'input_text', 'output_text'].includes(type)) {
    const clean = stripReminders(typeof block.text === 'string' ? block.text : '');
    counts.system_reminder += clean.count;
    return clean.text;
  }
  if (type === 'tool_use' || type === 'server_tool_use') {
    const clean = stripReminders(printable(block.input));
    counts.system_reminder += clean.count;
    return `${String(block.name)} ${truncate(clean.text, budgets.tool_arguments)}`;
  }
  if (type === 'tool_result' || type === 'advisor_tool_result') {
    const skill = block.name === 'Skill' || skillIds.has(String(block.tool_use_id));
    const text = Array.isArray(block.content) ? contentText(block.content) : printable(block.content);
    const clean = stripReminders(text);
    counts.system_reminder += clean.count;
    return `${type} ${truncate(clean.text, skill ? budgets.skill_blocks : budgets.tool_results)}`;
  }
  return type;
}

function renderRecord(trace: Trace, item: StoredRecord, budgets: RenderBudgets, history: readonly HistoryEntry[], skillIds: Set<string>, counts: RenderCounts): RenderedRecord {
  const message = payload(item.record, trace.agent_id);
  const role = message.role ?? item.record.type;
  let text: string;
  let harness_shaped = false;
  if (role === 'user') {
    const user = resolveUserText(trace, item, history);
    counts.system_reminder += user.reminders;
    harness_shaped = user.harness_shaped || trace.agent_id === 'claude-code' && (item.record.isMeta === true || item.record.isCompactSummary === true || (budgets.harness_user_tags ?? [])
      .some(tag => user.text.trimStart().startsWith(`<${tag}>`)));
    // Tool results are user-role messages in Claude logs, not typed prompts.
    const content = message.content;
    const blocks = Array.isArray(content) ? content.filter(isObject) : [];
    const nonText = blocks.filter(block => !['text', 'input_text', 'output_text'].includes(String(block.type)));
    const body = trace.agent_id === 'codex' && /^\s*<skill>/.test(user.text)
      ? truncate(user.text, budgets.skill_blocks) : user.text;
    text = `user${harness_shaped ? ' [harness-shaped]' : ''} ${body}`;
    if (nonText.length) text += ` ${nonText.map(block => renderBlock(block, budgets, skillIds, counts)).join(' | ')}`;
  } else if (message.type === 'custom_tool_call') {
    const clean = stripReminders(printable(message.input));
    counts.system_reminder += clean.count;
    text = `exec ${truncate(clean.text, budgets.tool_arguments)}`;
  } else if (message.type === 'custom_tool_call_output') {
    const output = Array.isArray(message.output) ? contentText(message.output) : printable(message.output);
    const clean = stripReminders(output);
    counts.system_reminder += clean.count;
    text = `custom_tool_call_output ${truncate(clean.text, budgets.tool_results)}`;
  } else if (item.record.type === 'event_msg' && message.type === 'item_completed' && isObject(message.item)
    && message.item.type === 'CommandExecution') {
    const step = message.item;
    const command = Array.isArray(step.parsed_cmd) && isObject(step.parsed_cmd[0]) ? step.parsed_cmd[0].cmd : null;
    const output = typeof step.aggregated_output === 'string' ? step.aggregated_output : '';
    text = `command ${truncate(String(command ?? ''), budgets.tool_arguments)} exit ${String(step.exit_code ?? 'null')} ${truncate(output, budgets.tool_results)}`;
  } else if (message.type === 'function_call') {
    const clean = stripReminders(printable(message.arguments));
    counts.system_reminder += clean.count;
    text = `${String(message.name)} ${truncate(clean.text, budgets.tool_arguments)}`;
  } else if (message.type === 'function_call_output') {
    const clean = stripReminders(printable(message.output));
    counts.system_reminder += clean.count;
    text = `function_call_output ${truncate(clean.text, budgets.tool_results)}`;
  } else if (message.type === 'reasoning') {
    counts.reasoning++; text = '[reasoning dropped: 1]';
  } else if (role === 'assistant') {
    const content = message.content;
    if (Array.isArray(content)) text = content.filter(isObject).map(block => renderBlock(block, budgets, skillIds, counts)).join(' | ');
    else {
      const clean = stripReminders(contentText(content));
      counts.system_reminder += clean.count;
      text = clean.text;
    }
    text = `assistant ${text}`;
  } else text = String(message.type ?? item.record.type ?? 'unknown');
  return { line_number: item.line_number, text: `${item.line_number}: ${text.replaceAll('\r', '\\r').replaceAll('\n', '\\n')}\n`, harness_shaped };
}

export function renderTrace(trace: Trace, budgets: RenderBudgets, history: readonly HistoryEntry[] = []): Rendering {
  const dropped: RenderCounts = { system_reminder: 0, thinking: 0, reasoning: 0 };
  const ids = toolSkills(trace);
  const records = trace.records.map(item => {
    const before = dropped.system_reminder;
    const rendered = renderRecord(trace, item, budgets, history, ids, dropped);
    const removed = dropped.system_reminder - before;
    if (removed) rendered.text = `${rendered.text.slice(0, -1)} [system-reminder dropped: ${removed}]\n`;
    return rendered;
  });
  return { body: records.map(record => record.text).join(''), records, dropped, skills_loaded: [...trace.skills_loaded] };
}

export function renderHeader(trace: Trace): string {
  return JSON.stringify({ trace_id: trace.trace_id, skills_loaded: trace.skills_loaded, trivial: trace.trivial,
    ...(trace.verdict_line ? { verdict_line: trace.verdict_line } : {}) });
}

// extends the consumer header with label evidence and lesson reads.
