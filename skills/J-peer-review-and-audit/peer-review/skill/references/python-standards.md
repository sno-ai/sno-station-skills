# Python Coding Standards

These are defaults for reviewing Python. Where the project's own conventions, configuration, or supported Python version say otherwise, the project wins.

Default target: Python 3.14+.

Standards are organized by priority: Hard Rules > Design Patterns > Type System > Anti-Patterns > Delivery Checklist.

---

## Hard Rules (defaults)

1. **No `Any` type** — Use `object` + narrowing, `TypedDict`, or generics. Default: none.
2. **No `print()` in production code** — Use `logging.getLogger(__name__)`.
3. **No bare `except:`** — Always catch specific exceptions. `except Exception:` at minimum.
4. **No `from __future__ import annotations`** — Python 3.14+ evaluates annotations lazily by default (PEP 649). The future import stringifies everything, breaking Pydantic, dataclasses, and FastAPI at runtime.
5. **Functions under 50 lines** — If longer, split by responsibility.
6. **Max 3 indentation levels** — Extract into guard clauses or helpers.
7. **Complete type annotations** on all public APIs with explicit return types.
8. **`__all__` for public API** — Every module declares what it exports.
9. **All resources cleaned up** via context managers or `finally` blocks.
10. **No mutable default arguments** — `def f(items: list[str] | None = None)` with factory inside.

## Project Rules

Read the repository's AGENTS.md, CLAUDE.md or README for its logging, import,
configuration, lint and type-check conventions. Use its declared check commands.

---

## Design Patterns

### Eliminate branches with data
```python
STATUS_COLOR: dict[Status, str] = {
    "pending": "yellow",
    "active": "blue",
    "done": "green",
}
color = STATUS_COLOR[status]  # KeyError on unknown = caught by Literal type
```
When `Status = Literal["pending", "active", "done"]`, the type checker ensures exhaustiveness.

### TypedDict: split required from optional
```python
class _ResponseRequired(TypedDict):
    content: str
    model: str

class LLMResponse(_ResponseRequired, total=False):
    usage: TokenUsage
    error: str
    retryable: bool
```
Prevents `response["content"]` from being `str | Missing`.

### Protocol for interfaces
```python
class TelemetryProvider(Protocol):
    async def track(self, event: EventData) -> None: ...

def create_client(telemetry: TelemetryProvider | None = None) -> Client: ...
```
Structural subtyping — no base class required. Test: pass a stub with the same method signature.

### dataclass for value objects
```python
@dataclass(frozen=True, slots=True)
class CircuitBreakerConfig:
    failure_threshold: int = 3
    recovery_timeout: float = 60.0
    success_threshold: int = 1
```
`frozen=True` = hashable + immutable. `slots=True` = ~40% memory savings.

### Exception hierarchies
```python
class LLMConfigError(Exception): ...
class ConfigNotFoundError(LLMConfigError): ...
class SecurityError(LLMConfigError): ...
```
Enables both broad and narrow `except` clauses.

### Async: TaskGroup for structured concurrency
```python
async def process_batch(items: list[Item]) -> list[Result]:
    results: list[Result] = []
    async with asyncio.TaskGroup() as tg:
        for item in items:
            tg.create_task(process_one(item, results))
    return results  # All tasks complete or all cancelled on first error
```
Replaces `gather()` — handles cancellation properly.

### CPU-bound: InterpreterPoolExecutor (3.14+)
```python
from concurrent.futures import InterpreterPoolExecutor

def compute_embeddings(texts: list[str]) -> list[list[float]]:
    with InterpreterPoolExecutor() as executor:
        return list(executor.map(embed_single, texts))
```
Lightweight sub-interpreters with true parallelism. Prefer over `ProcessPoolExecutor`.

### Template strings for safe interpolation (3.14+)
```python
name = "O'Malley"
query = t"SELECT * FROM users WHERE name = {name}"
# Template object — process to escape values safely
```

### Factory functions over constructors
```python
def create_embedding_client(
    *,
    model: str,
    dimension: int = 1024,
    cache: EmbeddingCache | None = None,
) -> EmbeddingClient: ...
```
Keyword-only args (`*`), caller controls dependencies. Test: just pass stubs.

### Configuration: Pydantic BaseSettings
```python
class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=None, extra="ignore")
    DATABASE_URL: str                           # Required — no default
    OPENAI_API_KEY: str = Field(min_length=1)   # Required
    USE_CACHE: bool = False                     # Feature flag — disabled
    MAX_RETRIES: int = 3                        # Tuning — conservative
```

### Early returns for guard clauses
```python
def process(item: Item) -> Result:
    if not item.is_valid:
        return Result(error="invalid")
    if item.is_cached:
        return item.cached_result
    return compute(item)  # Happy path at lowest indentation
```

### Use collections and itertools
```python
from collections import Counter, defaultdict
from itertools import product, chain

counts = Counter(items)                                    # not manual dict counting
groups: defaultdict[str, list[Item]] = defaultdict(list)   # not setdefault
for a, b in product(rows, cols):                           # not nested for loops
```

---

## Type System Rules

| Rule | Why |
|---|---|
| No `from __future__ import annotations` | 3.14 has native lazy annotations (PEP 649) |
| `if TYPE_CHECKING:` for heavy imports | Avoids circular imports, reduces startup time |
| `Literal["a", "b"]` over `str` | Constrains values at the type level |
| `TypedDict` over `dict[str, Any]` | Each key has a known type |
| `Protocol` over `ABC` | Structural typing — no inheritance required |
| `@dataclass(frozen=True, slots=True)` | Immutable, memory-efficient value objects |
| `T \| None` over `Optional[T]` | Modern syntax (3.10+) |
| Pydantic at external boundaries | API requests, config, DB rows. Internal calls trust types |
| Explicit return types on public functions | Prevents accidental API changes |
| `Sequence`/`Mapping`/`Iterable` in parameters | Accept abstract, return concrete |
| `Self` for methods returning self | Proper subclass support (3.11+) |
| `type` statement for aliases | `type Vector = list[float]` — modern syntax (3.12+) |
| `TypeVar` with defaults | `T = TypeVar("T", default=int)` — sensible defaults (3.14+) |
| `cast()` only at validated boundaries | Like Pydantic `.model_validate()` results. Comment why |
| `@overload` for narrowable unions | Return type depends on argument |

---

## Anti-Patterns (avoid these)

- **`Any` type** — Use `object` + narrowing, `TypedDict`, or generics
- **`print()` in production** — Use `logging.getLogger(__name__)`
- **Bare `except:`** — Always catch specific exceptions
- **Wide `try` blocks** — Wrap only the line that can raise, not the whole function
- **Mutable default arguments** — `def f(items=[])` mutates across calls
- **Class hierarchies > 1 level** — Favor composition and `Protocol`
- **Manual dict counting/grouping** — Use `Counter`, `defaultdict`
- **f-string in log messages** — Use `%s` formatting or `extra={}` for structured data
- **`os.getenv()` in application code** — Use validated config (Pydantic BaseSettings)
- **Global mutable state without locks** — Race condition (especially with 3.14 free-threading)
- **Nested loops for combinatorics** — Use `itertools.product`
- **Leaked resources** — Connections, files, locks must use context managers
- **`ProcessPoolExecutor` for CPU-bound** — Use `InterpreterPoolExecutor` (3.14+)
- **Multiple exit points** — Prefer early returns then single happy path

---

## Delivery Checklist

Before considering code complete, verify ALL:

1. Zero `Any` types — search the file, confirm none
2. Zero Pyright errors
3. All functions under 50 lines
4. Max 3 indentation levels
5. Public API declared via `__all__`
6. Types prevent invalid states
7. Expected errors use exception hierarchies
8. No mutable default arguments
9. No magic strings or numbers — use constants or `Literal` types
10. All resources cleaned up via context managers or `finally`
11. Logging uses `logger`, never `print()`
12. Total file size within target — single-concern: 50-200 lines, multi-concern: 200-400 lines

For advanced patterns (generic protocols, async generators, thread-safe singletons, custom decorators with ParamSpec, sentinel objects, ContextVar, enum with behavior), see `references/python-advanced-patterns.md`.
