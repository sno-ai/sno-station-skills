// Test fixture. A stand-in for a program that spawns python3 once (negative control).
// Default: spawn `python3` by name — under the allowlist-only PATH it is absent, so this exec fails and
// the error names python3, which run-selftest.sh asserts. With PY_ABS set, spawn that absolute path
// instead: it bypasses the PATH allowlist and runs, which the strace execve recorder must still catch.
import { execFileSync } from 'node:child_process';
const target = process.env.PY_ABS || 'python3';
try {
  execFileSync(target, ['-c', 'print(1)'], { stdio: 'ignore' });
  console.log('python3 ran'); // reached only for the absolute-path bypass case
  process.exit(0);
} catch (e) {
  process.stderr.write(`${(e && e.message) || String(e)}\n`);
  process.exit(7);
}
