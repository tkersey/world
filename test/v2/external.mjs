// New source is compiled as a separate package after the recorded kernel freeze.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir, mkdtemp, cp, symlink } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { wasmtimePeer } from './wasmtime_peer.mjs';
import { sha256, json } from '../../scripts/v2/assets.mjs';

const [boundaryArg, kernelArg, nativeArg, outputArg, runtimeArg] = process.argv.slice(2);
assert.ok(outputArg && [6, 7].includes(process.argv.length), 'expected Boundary source, frozen kernel, native embedding (or -), output and optional verified runtime');
const boundary = resolve(boundaryArg), kernelPath = resolve(kernelArg), native = nativeArg === '-' ? null : resolve(nativeArg), output = resolve(outputArg), world = resolve(import.meta.dirname, '../..');
const { admitProcessKernel, encodeInput, decodeOutcome } = await import(pathToFileURL(resolve(runtimeArg ?? world, 'src/process_v2/index.mjs')));
const freeze = JSON.parse(await readFile(join(world, 'test/v2/external/freeze.json')));
const kernel = await readFile(kernelPath);
assert.equal(sha256(kernel), freeze.kernelSha256, 'kernel changed: author another unrelated consumer after a new freeze');
await mkdir(output, { recursive: true });
const scratch = await mkdtemp(join(output, 'consumer-'));
await cp(join(world, 'test/v2/external/clamp'), join(scratch, 'clamp'), {
  recursive: true,
});
await symlink(boundary, join(scratch, 'boundary'), 'dir');
function compile(source) {
  const result = spawnSync('zig', ['build', 'emit', `-Dsource=${source}`, '--cache-dir', join(scratch, 'local'), '--global-cache-dir', join(scratch, 'global')],
    { cwd: join(scratch, 'clamp'), timeout: 180000, maxBuffer: 16 << 20 });
  assert.equal(result.status, 0, result.stderr.toString());
  return result.stdout;
}
const image = compile(false), sourceBytes = compile(true), source = JSON.parse(sourceBytes);
const { execute } = await import(pathToFileURL(join(boundary, 'test/v2/source_oracle.mjs')));
const host = await admitProcessKernel(kernel, { expectedSha256: freeze.kernelSha256 });
const peer = await wasmtimePeer(join(world, 'test/v2/wasmtime'), kernelPath, freeze.kernelSha256);
const records = [];
async function compare(input, mode) {
  const encoded = encodeInput({ ...input, mode });
  const js = await host[mode](input), wasm = await peer.invoke(encoded);
  assert.deepEqual(wasm, js.bytes);
  const candidates = [{ name: 'javascript', bytes: js.bytes }, { name: 'wasmtime', bytes: wasm }];
  if (native) {
    const nativeRun = spawnSync(native, [], { input: encoded, timeout: 30000, maxBuffer: 16 << 20 });
    assert.equal(nativeRun.status, 0, nativeRun.stderr.toString());
    assert.deepEqual(js.bytes, new Uint8Array(nativeRun.stdout));
    candidates.push({ name: 'native', bytes: new Uint8Array(nativeRun.stdout) });
  }
  const { name: producer, bytes } = candidates[records.length % candidates.length];
  records.push({ producer, input: Buffer.from(encoded).toString('base64'), output: Buffer.from(bytes).toString('base64') });
  return { ...decodeOutcome(bytes), bytes };
}
function expected([initial, firstA, firstB, secondA, secondB]) {
  const clamp = (value, a, b) => {
    const ordered = [value, a, b].sort((left, right) => left < right ? -1 : left > right ? 1 : 0);
    return ordered[1];
  };
  const first = clamp(initial, firstA, firstB), second = clamp(first, secondA, secondB);
  const value = Buffer.alloc(16);
  value.writeBigUInt64LE(first, 0);
  value.writeBigUInt64LE(second, 8);
  return { kind: 'Completed', value: [...value], trace: [{ kind: 'Yielded' }] };
}
try {
  const maximum = (1n << 64n) - 1n, highBit = 1n << 63n;
  for (const values of [
    [0n, 0n, 0n, maximum, 0n],
    [5n, 3n, 9n, 6n, 8n],
    [42n, 0n, 10n, 10n, 0n],
    [highBit, 0n, maximum, highBit + 1n, maximum],
    [maximum, highBit, 0n, 7n, 1n],
    [123456789n, 987654321n, 5n, maximum, maximum],
  ]) {
    const initialArgs = Buffer.alloc(40);
    values.forEach((value, index) => initialArgs.writeBigUInt64LE(value, index * 8));
    const oracle = execute(source, [...initialArgs]), wanted = expected(values);
    assert.equal(oracle.kind, wanted.kind);
    assert.deepEqual(oracle.trace, wanted.trace);
    assert.deepEqual(oracle.value, wanted.value);
    const boundaries = [];
    let input = { image, initialArgs }, terminal;
    for (let steps = 0; steps < 1000; steps++) {
      const result = await compare(input, 'advance');
      if (result.kind !== 'Progressed') boundaries.push(result);
      if (['Completed', 'Failed'].includes(result.kind)) { terminal = result; break; }
      assert.ok(['Progressed', 'Yielded'].includes(result.kind));
      input = { image, state: result.state };
    }
    assert.ok(terminal, 'finite external witness exceeded its test horizon');
    assert.equal(terminal.kind, oracle.kind);
    assert.deepEqual(terminal.value, Uint8Array.from(oracle.value));
    input = { image, initialArgs };
    for (const expected of boundaries) {
      const result = await compare(input, 'run');
      assert.deepEqual(result.bytes, expected.bytes);
      if (result.kind === 'Yielded') input = { image, state: result.state };
    }
  }
} finally { await peer.close(); }
assert.equal(sha256(await readFile(kernelPath)), freeze.kernelSha256);
await writeFile(join(output, 'clamp.bpi2'), image);
await writeFile(join(output, 'clamp-source.json'), sourceBytes);
await writeFile(join(output, 'external.json'), json({
  format: 'world-v2-external-consumer/v1', freeze, checkedAt: new Date().toISOString(),
  consumer: 'clamp',
  consumerSourceSha256: sha256(await readFile(join(world, 'test/v2/external/clamp/main.zig'))),
  imageSha256: sha256(image), imageBytes: image.length, sourceSha256: sha256(sourceBytes),
  kernelSha256: freeze.kernelSha256, nativeSha256: native ? sha256(await readFile(native)) : null,
  embeddings: native ? ['native', 'javascript', 'wasmtime'] : ['javascript', 'wasmtime'],
  observations: [
    'new operation and deep handler compiled using only the public Boundary module',
    'independent source semantics and unsigned median-of-three expectations agreed',
    'fresh producers alternated through every advance boundary',
    'run matched advance records; chained clamps retained both u64 results through yield',
    'zero, reversed, equal, full-width and high-bit bounds preserved exact results',
  ], records,
}));
console.log(`post-freeze clamp consumer: ${records.length} exact records under ` +
  freeze.kernelSha256);
