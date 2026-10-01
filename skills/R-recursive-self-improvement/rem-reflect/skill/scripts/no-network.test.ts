import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Only off and metadata-only consent prohibit network; full consent uploads through sno rem judge.

const SCRIPTS = dirname(fileURLToPath(import.meta.url));

// Trace connect(2) under strace and keep only outbound inet connects (not loopback, not AF_UNIX/NETLINK).
function outboundConnects(straceLogPath: string): string[] {
  if (!existsSync(straceLogPath)) throw new Error(`strace produced no log at ${straceLogPath}`);
  return readFileSync(straceLogPath, 'utf8').split('\n')
    .filter(line => line.includes('connect('))
    .filter(line => /sa_family=AF_INET6?\b/.test(line))
    .filter(line => !/inet_addr\("127\./.test(line) && !/inet_pton\(AF_INET6, "::1"/.test(line) && !/sin6_addr=.*"::1"/.test(line));
}

test('off and metadata-only ordinary runs open zero outbound sockets, and the trace instrument can see one', t => {
  if (process.platform !== 'linux' || spawnSync('strace', ['--version']).error) {
    t.skip('strace is unavailable; socket tracing requires Linux and strace');
    return;
  }
  const dir = mkdtempSync(join(tmpdir(), 'remtest-net-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const consentCli = join(dir, 'sno');
  writeFileSync(consentCli, '#!/bin/sh\nif [ "$*" = "station telemetry consent get" ]; then echo "$REM_TEST_CONSENT"; else exit 2; fi\n');
  chmodSync(consentCli, 0o755);
  const driver = join(dir, 'driver.ts');
  const H = JSON.stringify(join(SCRIPTS, 'test-helpers.ts'));
  const R = JSON.stringify(join(SCRIPTS, 'rem-reflect.ts'));
  const HV = JSON.stringify(join(SCRIPTS, 'harvest.ts'));
  writeFileSync(driver, [
    `const h = await import(${H});`,
    `const { run } = await import(${R});`,
    `const { existingTraces } = await import(${HV});`,
    `const { readFileSync, existsSync } = await import('node:fs');`,
    `const { join } = await import('node:path');`,
    `const config = h.fixtureConfig({ claude_root: h.tmp('c'), codex_root: h.tmp('x') });`,
    `const store = h.makeStore(config);`,
    `const MT = new Date('2026-09-07T00:00:00Z').getTime();`,
    `h.writeClaudeSession(config.claude_root, 'proj', 'cc', [h.claudeUser('/n','cc','do it'), h.claudeAssistant('/n','cc',[{ type:'text', text:'ok' }])], MT);`,
    `h.writeCodexSession(config.codex_root, 'cx', [h.codexMeta('cx','/n'), h.codexUser('do it'), h.codexAssistant('ok')], MT);`,
    `const r = run(store, new Date('2026-09-08T00:00:00Z'), 'u', new h.FixtureBackend());`,
    `if (r.code !== 0) { console.error(r.lines.join('\\n')); process.exit(3); }`,
    `const traces = existingTraces(store);`,
    `if (traces.length !== 2) { console.error('expected 2 harvested traces, got ' + traces.length); process.exit(4); }`,
    `const report = readFileSync(join(store,'staging','20260908-0000','REPORT.md'),'utf8');`,
    `if (!report.includes('Kept: 2') || !report.includes('Uploaded: 0') || !report.includes('No-upload: consent ' + process.env.REM_TEST_CONSENT)) { console.error(report); process.exit(5); }`,
    `if (existsSync(join(store,'staging','20260908-0000','cloud-request.json'))) process.exit(6);`,
    `console.log('journey ok');`,
  ].join('\n'));

  for (const consent of ['off', 'metadata-only']) {
    const runLog = join(dir, `strace-run-${consent}.log`);
    const out = execFileSync('strace', ['-f', '-e', 'trace=connect', '-o', runLog,
      process.execPath, '--experimental-strip-types', driver], {
      encoding: 'utf8', env: { ...process.env, PATH: `${dir}:${process.env.PATH ?? ''}`, REM_TEST_CONSENT: consent },
    });
    assert.match(out, /journey ok/, `${consent} completed harvest and conservative local judgment`);
    assert.deepEqual(outboundConnects(runLog), [], `${consent} opened no outbound socket`);
  }

  // Positive control: the same parser flags a real outbound connect, so the empty result above is a
  // fact, not a broken instrument. 192.0.2.1 is TEST-NET-1 (RFC 5737): the connect(2) is issued and
  // traced, but the address is reserved and unroutable, so nothing leaves the host.
  const probe = join(dir, 'probe.ts');
  writeFileSync(probe, [
    `import net from 'node:net';`,
    `const s = net.connect({ host: '192.0.2.1', port: 80 });`,
    `s.on('error', () => process.exit(0));`,
    `setTimeout(() => { s.destroy(); process.exit(0); }, 300);`,
  ].join('\n'));
  const probeLog = join(dir, 'strace-probe.log');
  execFileSync('strace', ['-f', '-e', 'trace=connect', '-o', probeLog,
    process.execPath, '--experimental-strip-types', probe], { encoding: 'utf8' });
  assert.ok(outboundConnects(probeLog).length >= 1,
    'the trace instrument detects a genuine outbound connect (positive control)');
});
