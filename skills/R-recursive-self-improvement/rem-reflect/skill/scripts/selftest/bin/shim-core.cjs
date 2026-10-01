'use strict';
// Test fixture. A stand-in for the real `claude` and `codex` CLIs, spawned by the loop
// through the real RealBackend during the fixture journey and the self-test. It is
// deterministic and stateless: it answers only preflight and own-CLI filter prompts. It reads
// its login from the isolated directory selected by CLAUDE_CONFIG_DIR / CODEX_HOME and writes
// one session file into that directory on every turn —
// so a turn's session lands under .loop-home when the loop isolates it, and in the harvest root when
// the isolation is dropped (the planted defect). Optionally records every exec for the
// allowlist check in EXEC_LOG. Plain CommonJS so it runs as a bare `node <file>` with
// no compile step and no dependency on the .ts loader.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

function configDir(cli) {
  if (cli === 'claude') return process.env.CLAUDE_CONFIG_DIR || path.join(process.env.HOME || '', '.claude');
  return process.env.CODEX_HOME || path.join(process.env.HOME || '', '.codex');
}

// One session file per turn, into the directory the loop pointed this CLI at. Its mtime is pinned to
// REM_SHIM_MTIME (the test's clock) so a harvest driven by an injected `now` treats it consistently.
function writeSession(cli) {
  const dir = configDir(cli);
  const uniq = `${process.pid}-${crypto.randomBytes(5).toString('hex')}`;
  const id = `loopself-${uniq}`;
  const cwd = process.cwd();
  const mtimeMs = Number(process.env.REM_SHIM_MTIME || Date.now());
  let file;
  if (cli === 'claude') {
    const projects = path.join(dir, 'projects', 'loop-own');
    fs.mkdirSync(projects, { recursive: true });
    file = path.join(projects, `${id}.jsonl`);
    const stamp = new Date(mtimeMs).toISOString();
    const records = [
      { type: 'user', cwd, gitBranch: 'dev', sessionId: id, timestamp: stamp, isSidechain: false, message: { role: 'user', content: 'loop own turn' } },
      { type: 'assistant', cwd, gitBranch: 'dev', sessionId: id, timestamp: stamp, isSidechain: false, message: { role: 'assistant', model: 'claude-x', content: [{ type: 'text', text: 'loop own answer' }] } },
    ];
    fs.writeFileSync(file, records.map(r => JSON.stringify(r)).join('\n') + '\n');
  } else {
    const sessions = path.join(dir, 'sessions', '2026', '09', '07');
    fs.mkdirSync(sessions, { recursive: true });
    file = path.join(sessions, `rollout-2026-09-07T00-00-00-${id}.jsonl`);
    const records = [
      { type: 'session_meta', payload: { id, cwd, git: { repository_url: 'git@github.com:example/project.git', branch: 'dev' }, cli_version: '0.153.2', model_provider: 'openai' } },
      { type: 'response_item', payload: { type: 'message', role: 'user', content: [{ type: 'input_text', text: 'loop own turn' }] } },
      { type: 'response_item', payload: { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'loop own answer' }] } },
    ];
    fs.writeFileSync(file, records.map(r => JSON.stringify(r)).join('\n') + '\n');
  }
  const secs = mtimeMs / 1000;
  fs.utimesSync(file, secs, secs);
}

function labelerReply() {
  return { decision: 'keep', outcome: 'fail', reason: 'fixture fail', evidence: [], key_ranges: [], notes: '' };
}

module.exports = function main(cli) {
  // The loop sends the prompt on stdin (RealBackend), as the real CLIs read it.
  const input = fs.readFileSync(0, 'utf8');
  // Record only the program name, one per line: a prompt can contain newlines, which would
  // otherwise split into fake entries in the allowlist check.
  if (process.env.EXEC_LOG) {
    try { fs.appendFileSync(process.env.EXEC_LOG, `${cli}\n`); } catch { /* record best-effort */ }
  }
  // A CLI that is not logged in exits non-zero; the loop's preflight then degrades that half.
  const cred = cli === 'claude' ? '.credentials.json' : 'auth.json';
  if (!fs.existsSync(path.join(configDir(cli), cred))) { process.stderr.write('Not logged in\n'); process.exit(1); }
  // Every turn writes one session file into the isolated (or, under the defect, the real) home.
  try { writeSession(cli); } catch (e) { process.stderr.write(`shim session write failed: ${String(e)}\n`); }
  // Preflight is an exact one-word health check; all other calls must be local filtering.
  if (input === 'reply with ok') {
    process.stdout.write('ok'); process.exit(0);
  }
  if (!/previous_versions:/.test(input)) { process.stderr.write('unexpected local role\n'); process.exit(2); }
  process.stdout.write(JSON.stringify(labelerReply()));
  process.exit(0);
};
