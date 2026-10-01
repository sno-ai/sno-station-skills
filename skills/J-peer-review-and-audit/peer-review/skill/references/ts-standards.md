# TypeScript Coding Standards

These are defaults for reviewing TypeScript. Where the project's own conventions or configuration say otherwise, the project wins.

Standards are organized by priority: Hard Rules > Design Patterns > Type System > Anti-Patterns > Delivery Checklist.

---

## Hard Rules (defaults)

1. **No `any` type** — Use `unknown` + narrowing.
2. **No `as` type assertions** — You're lying to the compiler. Use type guards or redesign. Exception: `as T` at Zod validation boundaries with comment.
3. **No `!` non-null assertions** — Narrow properly with conditionals.
4. **No `export default`** — Named exports only. Default exports break refactoring.
5. **Functions under 50 lines** — If longer, split by responsibility.
6. **Max 3 indentation levels** — Extract into guard clauses or helpers.
7. **Explicit return types on exports** — Prevents accidental API changes.
8. **Strict mode always** — `noEmit`, `strict`, `noUncheckedIndexedAccess`.
9. **Zod at external boundaries** — API responses, user input, config, DB rows.
10. **All timers/listeners cleaned up** in finally blocks.

## Project Rules

Use the repository's package manager, linter, type checker and logger. Read its
AGENTS.md, CLAUDE.md or README for local conventions.

---

## Design Patterns

### Eliminate branches with data
```typescript
const STATUS_COLOR = {
  pending: "yellow",
  active: "blue",
  done: "green",
} as const satisfies Record<Status, string>;

const color = STATUS_COLOR[status]; // type-safe, exhaustive, zero branches
```
`satisfies` + `as const` = literal types AND exhaustiveness.

### Discriminated unions for state
```typescript
type AsyncResult<T> =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "success"; data: T }
  | { status: "error"; error: Error; retryable: boolean };
```
Impossible states are unrepresentable. Can't have `data` without `status: "success"`.

### Generics: only when they eliminate duplication
```typescript
// Justified: return type flows from input
function groupBy<T, K extends string>(items: T[], key: (item: T) => K): Record<K, T[]>

// Unjustified: just use the concrete type
function process<T extends Widget>(widget: T): T  // use Widget directly
```
Test: if removing the generic forces duplicated code, keep it.

### Typed error results
```typescript
type Result<T, E = string> =
  | { ok: true; value: T }
  | { ok: false; error: E };
```
Reserve `throw` for programmer errors and unrecoverable states.

### Exhaustive switches
```typescript
function getLabel(state: CircuitState): string {
  switch (state) {
    case "closed": return "healthy";
    case "open": return "down";
    case "half-open": return "probing";
    default: {
      const _exhaustive: never = state;
      throw new Error(`Unexpected state: ${_exhaustive}`);
    }
  }
}
```

### Async: allSettled + cleanup
```typescript
const results = await Promise.allSettled(items.map(process));
const successes = results.filter(
  (r): r is PromiseFulfilledResult<T> => r.status === "fulfilled"
);
```
`Promise.all` fails fast. Use `allSettled` when you want all results. Always `unref()` timers and clean up in `finally`.

### Generic Zod boundary: preserving T through safeParse
```typescript
// RIGHT — cast at the validated boundary where it's safe
function validate<T>(schema: ZodSchema<T>, raw: unknown): Result<T> {
  const parsed = schema.safeParse(raw);
  if (!parsed.success) return { ok: false, error: parsed.error };
  return { ok: true, value: parsed.data as T }; // safe: Zod just validated it IS T
}
```
This is the ONE acceptable `as` cast — at a validation boundary. Comment it.

### AsyncGenerator: true streaming
```typescript
// RIGHT — yield as each completes via callback + queue
async function* processStream(items: Item[]): AsyncGenerator<ProgressEvent> {
  const queue: ProgressEvent[] = [];
  let resolve: (() => void) | undefined;
  const onEvent = (event: ProgressEvent) => { queue.push(event); resolve?.(); };
  const processing = runAll(items, onEvent);
  while (true) {
    if (queue.length > 0) { yield queue.shift()!; continue; }
    if (await isSettled(processing)) break;
    await new Promise<void>((r) => { resolve = r; });
  }
  yield* queue;
}
```
Don't batch-then-yield — push events into queue, drain in generator loop.

### Factory functions over constructors
```typescript
function createService(deps: { db: Database; logger: Logger }) {
  return {
    async findUser(id: string) {
      deps.logger.info("lookup", { id });
      return deps.db.query("SELECT * FROM users WHERE id = ?", [id]);
    },
  };
}
// Test: just pass stubs — no class mocking, no inheritance
const svc = createService({ db: testDb, logger: noopLogger });
```

### Configuration: options objects
```typescript
const DEFAULTS: RetryOptions = { maxAttempts: 3, baseDelay: 1000, maxDelay: 30000, jitter: true };

function withRetry(fn: () => Promise<unknown>, options?: Partial<RetryOptions>) {
  const opts = { ...DEFAULTS, ...options };
}
```

---

## Type System Rules

| Rule | Why |
|---|---|
| `unknown` over `any` | `any` disables the compiler. `unknown` forces narrowing |
| `as const` objects over `enum` | Enums have runtime bloat and nominal typing surprises |
| Named exports only | Default exports break refactoring |
| `T \| undefined` over `T \| null` | `undefined` is the language default. `null` = explicitly nothing |
| Zod at external boundaries | API responses, user input, config, DB rows |
| `z.infer<typeof Schema>` | Derive types from schemas — single source of truth |
| No `as` assertions | Type guards or redesign instead |
| No `!` non-null assertions | Narrow with conditionals |
| Explicit return types on exports | Prevents accidental API changes |

---

## Anti-Patterns (avoid these)

- **`any` type** — Use `unknown` + narrowing.
- **Class hierarchies > 1 level** — Favor composition and interfaces
- **Magic strings/numbers** — Extract to named constants or `as const` objects
- **Unhandled promise rejections** — Every async path needs error handling
- **Mutable shared state** — Race condition. Use immutable data or explicit sync
- **Leaked listeners/timers** — Always clean up in `finally`, `off()`, or `clearTimeout`
- **Verbose where concise works** — 3-line helper used once = inline it
- **`console.log` in production** — Use the project's logger

---

## Delivery Checklist

Before considering code complete, verify ALL:

1. Zero `any` types — search the file, confirm none
2. Zero TypeScript errors — `possibly undefined`, unchecked index access, generic T through Zod
3. All functions under 50 lines
4. Max 3 indentation levels
5. Named exports only (no `export default`)
6. Types prevent invalid states
7. Expected errors returned as typed results, not thrown
8. No `as` type assertions (except controlled Zod cast with comment)
9. No magic strings or numbers
10. All timers/listeners cleaned up in finally blocks
11. Total file size within target — single-concern: 50-150 lines, multi-concern: 200-400 lines

For advanced TypeScript patterns (type-safe builders, state machines as data, branded types, mapped type utilities, concurrency patterns), use these standards as the default baseline and load additional project-local guidance when available.
