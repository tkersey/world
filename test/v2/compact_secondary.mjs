// Three image configurations using the existing secondary workload and checkpoint oracle.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { performance } from 'node:perf_hooks';
const [world, baseline, candidate, fixtures, output] = process.argv.slice(2);
assert.ok(output, 'expected World source, baseline/candidate kernels, fixtures and output');
await fs.writeFile(output, JSON.stringify({status:'in progress',rows:[]})+'\n', {flag:'wx'});
const { admitProcessKernel, encodeInput } = await import(pathToFileURL(join(world, 'src/process_v2/index.mjs')));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const kernels = await Promise.all([baseline, candidate].map(path => fs.readFile(path)));
const hosts = await Promise.all(kernels.map(bytes => admitProcessKernel(bytes, { expectedSha256: hash(bytes) })));
const scalar = value => { const bytes = Buffer.alloc(8); bytes.writeBigUInt64LE(BigInt(value)); return bytes; };
const cases = [
  ['install-8', 'economy-8', []],
  ['retained-bfs', 'source-queens-bfs', []],
  ['reentrant', 'source-reentrant', []],
  ['large-blob-capture', 'economy-0', Buffer.concat([Buffer.from([0x80, 0x80, 0x04]), Buffer.alloc(65536, 0x61)])],
  ['lexical', 'source-lexical', scalar(40)], ['local-state', 'source-state-local', []],
  ['shared-state', 'source-state-shared', []], ['shallow-multishot', 'source-shallow-resumptions', []],
  ['owned-generator', 'source-generator', []], ['scheduler', 'source-scheduler', []],
  ['cleanup-owned-result', 'source-cleanup-disposal-owned', []],
  ['recursive-10000', 'source-recursive', scalar(10000)],
  ['repeated-advance-64', 'economy-64', [], 'advance'],
];
const median = xs => xs.toSorted((a,b) => a-b)[Math.floor(xs.length / 2)];
const rows = [];
for (const [name, file, args, mode = 'run'] of cases) {
  const legacy = new Uint8Array(await fs.readFile(join(fixtures, `${file}.bpi2`)));
  const compact = new Uint8Array(await fs.readFile(join(fixtures, `${file}.bpc1`)));
  const images = [legacy, legacy, compact];
  const inputs = images.map(image => ({ image, initialArgs: Uint8Array.from(args) }));
  const checkpointHashes = [];
  async function invoke(which, verify = false) {
    const host = hosts[which === 0 ? 0 : 1];
    let result = await host[mode](inputs[which]), steps = 0;
    for (;;) {
      if (verify) {
        const digest = hash(result.bytes);
        if (which === 0) checkpointHashes.push(digest);
        else assert.equal(digest, checkpointHashes[steps], `${name} checkpoint ${steps}`);
      }
      steps++;
      if (mode !== 'advance' || result.kind !== 'Progressed') break;
      assert.ok(steps < 1000, 'finite fixture verification horizon');
      result = await host.advance({ image: images[which], state: result.state });
    }
    if (verify && which !== 0) assert.equal(steps, checkpointHashes.length);
    return result;
  }
  const expected = await invoke(0, true);
  assert.notEqual(expected.kind, 'NeedsCapacity');
  for (const which of [1, 2]) assert.deepEqual((await invoke(which, true)).bytes, expected.bytes);
  const repetitions = mode === 'advance' || name === 'recursive-10000' ? 1 : 200;
  for (let warmup = 0; warmup < 5; warmup++) for (const which of [0,1,2])
    for (let n = 0; n < repetitions; n++) await invoke(which);
  const samples = [[], [], []];
  for (let sample = 0; sample < 21; sample++) for (const which of [[0,1,2],[2,1,0],[1,2,0],[0,2,1],[2,0,1],[1,0,2]][sample % 6]) {
    const start = performance.now();
    let result;
    for (let n = 0; n < repetitions; n++) result = await invoke(which);
    samples[which].push((performance.now() - start) / repetitions);
    assert.deepEqual(result.bytes, expected.bytes);
  }
  const mediansMs = samples.map(median);
  const row = { name, mode, repetitions, imageBytes: images.map(image => image.length), imageSha256: images.map(hash), inputSha256: inputs.map(input => hash(encodeInput({ ...input, mode }))),
    checkpointHashes, outputBytes: expected.bytes.length, outputSha256: hash(expected.bytes), mediansMs,
    ratios: mediansMs.map(value => value / mediansMs[0]), samplesMs: samples };
  rows.push(row);
  await fs.writeFile(output, JSON.stringify({ status: 'in progress', rows }, null, 2) + '\n');
  console.log(JSON.stringify({ name, mediansMs, ratios: row.ratios }));
}
await fs.writeFile(output, JSON.stringify({ method: 'secondary regressions; five warmup batches and 21 rotating-order samples across reference BPI2, candidate BPI2 and candidate compact; fresh guest per public call; repeated advance includes every preparation and portable state',
  date: new Date().toISOString(), harnessSha256: hash(await fs.readFile(import.meta.filename)), kernels: kernels.map(hash), rows }, null, 2) + '\n');
