import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { isObject, paths } from './config.ts';
import { writeJson } from './store.ts';

export interface LocalSettings {
  version: string;
  labeler_input_max_chars: number;
  labeler_event_window_lines: number;
  recall_timeout_ms: number;
}

function checked(value: unknown): LocalSettings {
  if (!isObject(value) || typeof value.version !== 'string' || !value.version
    || !['labeler_input_max_chars', 'labeler_event_window_lines', 'recall_timeout_ms']
      .every(key => Number.isInteger(value[key]) && Number(value[key]) > 0)) {
    throw new Error('local settings: invalid response');
  }
  return value as unknown as LocalSettings;
}

export function loadLocalSettings(store: string, log: string[]): LocalSettings {
  const stored = join(store, 'settings.local.json');
  const path = existsSync(stored) ? stored : join(paths.references, 'local-settings.json');
  const settings = checked(JSON.parse(readFileSync(path, 'utf8')));
  log.push(`local settings: ${path === stored ? 'store' : 'shipped'} version ${settings.version}`);
  return settings;
}

export function saveLocalSettings(store: string, response: unknown): void {
  if (!isObject(response) || !isObject(response.local) || typeof response.settings_version !== 'string') return;
  writeJson(join(store, 'settings.local.json'), checked({ version: response.settings_version, ...response.local }));
}
