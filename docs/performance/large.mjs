import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { performance } from 'node:perf_hooks';
const [world, baseline, candidate, fixtures, output] = process.argv.slice(2);
assert.ok(output, 'expected World source, baseline/candidate kernels, fixtures and output');
const { admitProcessKernel, encodeInput } = await import(pathToFileURL(join(world, 'src/process_v2/index.mjs')));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const kernels = await Promise.all([baseline, candidate].map(path => fs.readFile(path)));
const hosts = await Promise.all(kernels.map(bytes => admitProcessKernel(bytes, { expectedSha256: hash(bytes) })));
const scalar = value => { const bytes = Buffer.alloc(8); bytes.writeBigUInt64LE(BigInt(value)); return bytes; };
const cases = [["install-128", "economy-128", []], ["large-stored-constant", "large-constant", []]];
const median = xs => xs.toSorted((a,b) => a-b)[Math.floor(xs.length / 2)];
const rows = [];
for (const [name, file, args, mode = 'run'] of cases) {
  const image = new Uint8Array(await fs.readFile(join(fixtures, `${file}.bpi2`)));
  const input = { image, initialArgs: Uint8Array.from(args) };
  const checkpointHashes = [];
  async function invoke(which, verify = false) {
    let result = await hosts[which][mode](input), steps = 0;
    for (;;) {
      if (verify) {
        const digest = hash(result.bytes);
        if (which === 0) checkpointHashes.push(digest);
        else assert.equal(digest, checkpointHashes[steps], `${name} checkpoint ${steps}`);
      }
      steps++;
      if (mode !== 'advance' || result.kind !== 'Progressed') break;
      assert.ok(steps < 1000, 'finite fixture verification horizon');
      result = await hosts[which].advance({ image, state: result.state });
    }
    if (verify && which === 1) assert.equal(steps, checkpointHashes.length);
    return result;
  }
  const expected = await invoke(0, true);
  assert.notEqual(expected.kind, 'NeedsCapacity');
  assert.deepEqual((await invoke(1, true)).bytes, expected.bytes);
  const repetitions = mode === 'advance' || name === 'recursive-10000' ? 1 : 200;
  for (let warmup = 0; warmup < 5; warmup++) for (const which of [0,1])
    for (let n = 0; n < repetitions; n++) await invoke(which);
  const samples = [[], []];
  for (let sample = 0; sample < 21; sample++) for (const which of sample % 2 ? [1,0] : [0,1]) {
    const start = performance.now();
    let result;
    for (let n = 0; n < repetitions; n++) result = await invoke(which);
    samples[which].push((performance.now() - start) / repetitions);
    assert.deepEqual(result.bytes, expected.bytes);
  }
  const mediansMs = samples.map(median);
  const row = { name, mode, repetitions, imageBytes: image.length, imageSha256: hash(image), inputSha256: hash(encodeInput({ ...input, mode })),
    checkpointHashes, outputBytes: expected.bytes.length, outputSha256: hash(expected.bytes), mediansMs,
    ratio: mediansMs[1] / mediansMs[0], samplesMs: samples };
  rows.push(row);
  await fs.writeFile(output, JSON.stringify({ status: 'in progress', rows }, null, 2) + '\n');
  console.log(JSON.stringify({ name, mediansMs, ratio: row.ratio }));
}
await fs.writeFile(output, JSON.stringify({ method: 'secondary regressions; five warmup batches and 21 paired AB/BA samples; fresh guest per public call; repeated advance includes every preparation and portable state',
  date: new Date().toISOString(), harnessSha256: hash(await fs.readFile(import.meta.filename)), kernels: kernels.map(hash), rows }, null, 2) + '\n');
