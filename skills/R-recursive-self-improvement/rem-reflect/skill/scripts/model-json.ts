import { message } from './text.ts';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { isObject, paths } from './config.ts';

/** Take the first object, including inside a code fence, without swallowing a bad first object. */
export function firstObject(text: string): unknown {
  const start = text.indexOf('{');
  if (start < 0) throw new Error(message('jsonMissing'));
  let depth = 0;
  let quoted = false;
  let escaped = false;
  for (let index = start; index < text.length; index++) {
    const character = text[index];
    if (quoted) {
      if (escaped) escaped = false;
      else if (character === '\\') escaped = true;
      else if (character === '"') quoted = false;
    } else if (character === '"') quoted = true;
    else if (character === '{') depth++;
    else if (character === '}' && --depth === 0) return JSON.parse(text.slice(start, index + 1));
  }
  throw new Error(message('jsonIncomplete'));
}

/** The schema subset used by the two shipped contracts; unsupported keywords are not needed. */
export function validateSchema(value: unknown, schema: unknown, location: string = '$', root: unknown = schema): void {
  if (!isObject(schema)) throw new Error(message('schemaInvalid'));
  if (typeof schema.$ref === 'string') {
    const name = /^#\/\$defs\/(\w+)$/.exec(schema.$ref)?.[1];
    if (!name || !isObject(root) || !isObject(root.$defs)) throw new Error(message('schemaInvalid'));
    validateSchema(value, root.$defs[name], location, root);
  }
  if (Array.isArray(schema.allOf)) for (const branch of schema.allOf) validateSchema(value, branch, location, root);
  if (Array.isArray(schema.oneOf)) {
    const matches = schema.oneOf.filter(branch => {
      try { validateSchema(value, branch, location, root); return true; } catch { return false; }
    });
    if (matches.length !== 1) throw new Error(`${location}: oneOf`);
  }
  if ('const' in schema && value !== schema.const) throw new Error(`${location}: const`);
  if (Array.isArray(schema.enum) && !schema.enum.includes(value)) throw new Error(`${location}: enum`);
  if (schema.type === 'object' && !isObject(value)) throw new Error(`${location}: object`);
  if (schema.type === 'array' && !Array.isArray(value)) throw new Error(`${location}: array`);
  if (schema.type === 'string' && typeof value !== 'string') throw new Error(`${location}: string`);
  if (schema.type === 'boolean' && typeof value !== 'boolean') throw new Error(`${location}: boolean`);
  if (schema.type === 'integer' && !Number.isInteger(value)) throw new Error(`${location}: integer`);
  if (schema.type === 'null' && value !== null) throw new Error(`${location}: null`);
  if (typeof value === 'number' && typeof schema.minimum === 'number' && value < schema.minimum) throw new Error(`${location}: minimum`);
  if (typeof value === 'string' && typeof schema.minLength === 'number' && value.length < schema.minLength) throw new Error(`${location}: minLength`);
  if (typeof value === 'string' && typeof schema.pattern === 'string' && !new RegExp(schema.pattern).test(value)) throw new Error(`${location}: pattern`);
  if (Array.isArray(value)) {
    if (typeof schema.minItems === 'number' && value.length < schema.minItems) throw new Error(`${location}: minItems`);
    if (schema.items) value.forEach((item, index) => validateSchema(item, schema.items, `${location}[${index}]`, root));
  }
  if (!isObject(value)) return;
  if (Array.isArray(schema.required)) for (const key of schema.required) {
    if (typeof key === 'string' && !(key in value)) throw new Error(`${location}.${key}: required`);
  }
  if (!isObject(schema.properties)) return;
  for (const [key, item] of Object.entries(value)) {
    if (key in schema.properties) validateSchema(item, schema.properties[key], `${location}.${key}`, root);
    else if (schema.additionalProperties === false) throw new Error(`${location}.${key}: unknown field`);
  }
}
export function checkContract(value: unknown, name: 'labeler'): void {
  validateSchema(value, JSON.parse(readFileSync(join(paths.references, `${name}.schema.json`), 'utf8')));
}
export function reference(name: string): string { return readFileSync(join(paths.references, name), 'utf8'); }
