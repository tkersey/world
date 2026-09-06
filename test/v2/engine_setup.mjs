// One fresh V8 process: module compilation precedes all instance samples.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { performance } from 'node:perf_hooks';
const bytes = await readFile(process.argv[2]);
let started = performance.now();
const module = new WebAssembly.Module(bytes);
const compileMs = performance.now() - started;
const instantiateMs = [];
let memoryBytes;
for (let i = 0; i < 26; i++) {
  started = performance.now();
  const instance = new WebAssembly.Instance(module, {});
  const elapsed = performance.now() - started;
  assert.equal(instance.exports.world_process_v2_abi_version(), 2);
  memoryBytes = instance.exports.memory.buffer.byteLength;
  if (i >= 5) instantiateMs.push(elapsed);
}
console.log(JSON.stringify({ compileMs, instantiateMs, memoryBytes }));
