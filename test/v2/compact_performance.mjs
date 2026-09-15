// Three-way full-call comparison. Each public call creates a fresh WASM instance.
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { performance } from "node:perf_hooks";
import os from "node:os";
import { admitProcessKernel, encodeInput, encodeResult } from "../../src/process_v2/index.mjs";

const [reference, candidate, fixtures, destination, pairsArg = "21", batchArg = "200",
  schedule = "batches"] = process.argv.slice(2);
assert.ok(destination, "reference kernel, candidate kernel, fixture directory, output JSON [pairs] [batch]");
const pairs = Number(pairsArg), batch = Number(batchArg), warmups = 5;
assert.ok(["batches", "interleaved"].includes(schedule));
assert.ok(Number.isSafeInteger(pairs) && pairs > 0 && Number.isSafeInteger(batch) && batch > 0);
const digest = bytes => createHash("sha256").update(bytes).digest("hex");
const median = values => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const kernels = await Promise.all([reference, candidate].map(path => readFile(path)));
const hosts = [], setupMs = [];
for (const bytes of kernels) {
  const start = performance.now();
  hosts.push(await admitProcessKernel(bytes, { expectedSha256: digest(bytes) }));
  setupMs.push(performance.now() - start);
}
const cases = [];
for (const [name, stem] of [
  ["small", "economy-1"], ["install-64", "economy-64"],
  ["retained-search", "source-queens-dfs"], ["install-128", "install-128"],
  ["stored-constant-64k", "constant-64k"],
]) {
  const [legacy, compact] = await Promise.all(["bpi2", "bpc1"].map(async extension =>
    new Uint8Array(await readFile(join(fixtures, `${stem}.${extension}`)))));
  cases.push({ name, images: [legacy, legacy, compact], base: { initialArgs: new Uint8Array() } });
}
const search = cases.find(value => value.name === "retained-search");
let parked = await hosts[0].run({ ...search.base, image: search.images[0] });
for (let index = 0; parked.kind === "Yielded" && index < 16; index++)
  parked = await hosts[0].run({ image: search.images[0], state: parked.state });
assert.equal(parked.kind, "Requested");
cases.push({ name: "saved-search-response", images: search.images, base: {
  state: parked.state,
  result: encodeResult(parked.request, Uint8Array.of(201, 0, 0, 0, 0, 0, 0, 0)),
} });
const rows = [];
for (const { name, images, base } of cases) {
  const inputs = images.map(image => ({ ...base, image }));
  const runners = [hosts[0], hosts[1], hosts[1]];
  const expected = await runners[0].run(inputs[0]);
  assert.notEqual(expected.kind, "NeedsCapacity");
  for (let which = 1; which < 3; which++)
    assert.deepEqual((await runners[which].run(inputs[which])).bytes, expected.bytes, name);
  for (let round = 0; round < warmups; round++) for (const which of [0, 1, 2])
    for (let repetition = 0; repetition < batch; repetition++) await runners[which].run(inputs[which]);
  const samplesMs = [[], [], []];
  // Every six observations gives every position and adjacent order equal representation.
  const orders = [[0, 1, 2], [2, 1, 0], [1, 2, 0], [0, 2, 1], [2, 0, 1], [1, 0, 2]];
  for (let sample = 0; sample < pairs; sample++) {
    if (schedule === "interleaved") {
      const totals = [0, 0, 0], outcomes = [];
      for (let repetition = 0; repetition < batch; repetition++) {
        for (const which of orders[(sample * batch + repetition) % orders.length]) {
          const start = performance.now();
          outcomes[which] = await runners[which].run(inputs[which]);
          totals[which] += performance.now() - start;
        }
      }
      for (const which of [0, 1, 2]) {
        samplesMs[which].push(totals[which] / batch);
        assert.deepEqual(outcomes[which].bytes, expected.bytes, name);
      }
      continue;
    }
    for (const which of orders[sample % orders.length]) {
    const start = performance.now();
    let outcome;
    for (let repetition = 0; repetition < batch; repetition++)
      outcome = await runners[which].run(inputs[which]);
    samplesMs[which].push((performance.now() - start) / batch);
    assert.deepEqual(outcome.bytes, expected.bytes, name);
    }
  }
  const mediansMs = samplesMs.map(median);
  const row = { name, imageBytes: images.map(image => image.length), imageSha256: images.map(digest),
    formats: images.map(image => new TextDecoder().decode(image.subarray(0, 8))),
    inputSha256: inputs.map(input => digest(encodeInput({ ...input, mode: "run" }))),
    outcome: expected.kind, outputBytes: expected.bytes.length, outputSha256: digest(expected.bytes),
    stateBytes: base.state?.length ?? 0, mediansMs,
    ratiosOfMedians: mediansMs.map(value => value / mediansMs[0]), samplesMs };
  rows.push(row);
  console.log(JSON.stringify({ name, mediansMs, ratios: row.ratiosOfMedians }));
}
await writeFile(destination, JSON.stringify({
  method: "Reference BPI2, candidate BPI2, candidate compact; rotating order; batch-average loaded-host run; fresh WASM instance each call",
  warmups, pairs, batch, schedule, harnessSha256: digest(await readFile(import.meta.filename)),
  environment: { date: new Date().toISOString(), node: process.version, platform: os.platform(),
    release: os.release(), cpu: os.cpus()[0].model },
  kernels: kernels.map((bytes, index) => ({ sha256: digest(bytes), bytes: bytes.length, setupMs: setupMs[index] })),
  rows,
}, null, 2) + "\n", { flag: "wx" });
