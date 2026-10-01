import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { sendCloudBatch } from './cloud.ts';
import { fixtureConfig, makeStore, tmp } from './test-helpers.ts';

test('a cloud that never answers ends the upload with a message and keeps the saved request for the next run', t => {
  const bin = tmp('sno-silent');
  writeFileSync(join(bin, 'sno'), '#!/bin/sh\nsleep 30\n');
  chmodSync(join(bin, 'sno'), 0o755);
  const before = process.env.PATH;
  process.env.PATH = `${bin}:${before ?? ''}`;
  t.after(() => { process.env.PATH = before; });
  const store = makeStore(fixtureConfig());
  const batch = { schema_version: 1, run_id: 'r-silent', halves: [], catalogue: [], usage_reads: [], usage_shown: [], outcome_summary: {} };
  const started = Date.now();
  assert.throws(() => sendCloudBatch(store, batch, 300), /gave no answer within 0 minutes; the saved request is resent on the next run/);
  assert.ok(Date.now() - started < 10_000, 'the wait ended at the limit, not when the CLI gave up');
  assert.equal(existsSync(join(store, 'staging', 'r-silent', 'cloud-request.json')), true, 'the request stays for the next run');
  assert.equal(existsSync(join(store, 'staging', 'r-silent', 'cloud-response.json')), false);
});
