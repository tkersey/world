// Paired full loaded-host calls: each invocation creates a fresh guest instance.
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { performance } from "node:perf_hooks";
import os from "node:os";
import { admitProcessKernel, encodeInput, encodeResult } from "../../src/process_v2/index.mjs";

const [baseline, candidate, fixtures, output] = process.argv.slice(2);
assert.ok(output && process.argv.length === 6, "expected baseline kernel, candidate kernel, fixtures, output JSON");
const digest = bytes => createHash("sha256").update(bytes).digest("hex");
const median = values => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const kernels = await Promise.all([baseline, candidate].map(path => readFile(path)));
const setup = [];
const hosts = [];
for (const bytes of kernels) {
  const start = performance.now();
  hosts.push(await admitProcessKernel(bytes, { expectedSha256: digest(bytes) }));
  setup.push(performance.now() - start);
}
const cases = [];
for (const [name, file] of [
  ["scalar", "economy-1.bpi2"],
  ["install-64", "economy-64.bpi2"],
  ["retained-search", "source-queens-dfs.bpi2"],
]) {
  const image = new Uint8Array(await readFile(join(fixtures, file)));
  cases.push({ name, input: { image, initialArgs: new Uint8Array() } });
}
const search = cases[2].input;
let parked = await hosts[0].run(search);
assert.deepEqual((await hosts[1].run(search)).bytes, parked.bytes);
for (let i = 0; parked.kind === "Yielded" && i < 16; i++) {
  const input = { image: search.image, state: parked.state };
  parked = await hosts[0].run(input);
  assert.deepEqual((await hosts[1].run(input)).bytes, parked.bytes);
}
assert.equal(parked.kind, "Requested");
cases.push({ name: "saved-search-response", input: { image: search.image, state: parked.state,
  result: encodeResult(parked.request, Uint8Array.of(201, 0, 0, 0, 0, 0, 0, 0)) } });
const rows = [];
for (const { name, input } of cases) {
  const expected = await hosts[0].run(input);
  assert.notEqual(expected.kind, "NeedsCapacity");
  assert.deepEqual((await hosts[1].run(input)).bytes, expected.bytes, name);
  const repetitions = 20;
  for (let i = 0; i < 5 * repetitions; i++) for (const host of hosts) await host.run(input);
  const times = [[], []];
  for (let sample = 0; sample < 21; sample++) {
    for (const which of sample % 2 ? [1, 0] : [0, 1]) {
      const start = performance.now();
      let result;
      for (let i = 0; i < repetitions; i++) result = await hosts[which].run(input);
      times[which].push((performance.now() - start) / repetitions);
      assert.deepEqual(result.bytes, expected.bytes, name);
    }
  }
  const mediansMs = times.map(median);
  const row = { name, imageBytes: input.image.length, imageSha256: digest(input.image),
    inputSha256: digest(encodeInput({ ...input, mode: "run" })),
    outcome: expected.kind, outputBytes: expected.bytes.length, outputSha256: digest(expected.bytes),
    mediansMs, ratio: mediansMs[1] / mediansMs[0], samplesMs: times };
  rows.push(row);
  console.log(JSON.stringify({ name, mediansMs, ratio: row.ratio }));
}
await writeFile(output, JSON.stringify({
  method: "five warmup batches, 21 paired AB/BA samples, 20 calls per batch; full loaded-host run; fresh WASM instance every call",
  environment: { date: new Date().toISOString(), node: process.version,
    platform: os.platform(), release: os.release(), cpu: os.cpus()[0].model },
  kernels: kernels.map((bytes, i) => ({ sha256: digest(bytes), bytes: bytes.length, setupMs: setup[i] })),
  rows,
}, null, 2) + "\n");
