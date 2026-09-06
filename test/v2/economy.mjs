// Matched portable execution measurements. Compiler timing is a separate lane.
import assert from "node:assert/strict";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import os from "node:os";
import { performance } from "node:perf_hooks";
import { admitProcessKernel as admitV1, decodeProcessOutcome, decodeEffectRequest } from "./legacy/process_v1/index.mjs";
import { admitProcessKernel, encodeInput, decodeOutcome, decodeRequest } from "../../src/process_v2/index.mjs";

const [kernelPath, legacyKernelPath, liftPath, boundaryPath, outputPath] = process.argv.slice(2);
assert.ok(outputPath, "expected v2 kernel, frozen v1 kernel, lifter, Boundary source, and output directory");
await mkdir(outputPath, { recursive: true });
const digest = bytes => createHash("sha256").update(bytes).digest("hex");
const command = (file, args, input) => {
  const result = spawnSync(file, args, { input, maxBuffer: 32 << 20 });
  assert.equal(result.status, 0, result.stderr?.toString());
  return new Uint8Array(result.stdout);
};
const kernel = new Uint8Array(await readFile(kernelPath));
const legacyKernel = new Uint8Array(await readFile(legacyKernelPath));
const current = await admitProcessKernel(kernel, { expectedSha256: digest(kernel) });
const frozen = await admitV1(legacyKernel); // Authenticates the published 1.8.2 digest.
const beforeModule = await WebAssembly.compile(legacyKernel);
const afterModule = await WebAssembly.compile(kernel);
const before = (await WebAssembly.instantiate(beforeModule, {})).exports;
const after = (await WebAssembly.instantiate(afterModule, {})).exports;
function oldStep(image, initial, state) {
  const value = state ?? initial;
  const length = before.boundary_process_kernel_prepare_input(state ? 1 : 0, BigInt(image.length), BigInt(value.length), 0, 0n);
  assert.equal(length, 40 + image.length + value.length);
  const payload = new Uint8Array(before.memory.buffer, before.boundary_process_kernel_input_payload_ptr(), image.length + value.length);
  payload.set(image); payload.set(value, image.length);
  assert.equal(before.boundary_process_kernel_execute(length), 0);
  assert.equal(before.boundary_process_kernel_error_len(), 0);
  return decodeProcessOutcome(new Uint8Array(before.memory.buffer, before.boundary_process_kernel_output_ptr(), Number(before.boundary_process_kernel_output_len())).slice());
}
function oldRun(image, initial) {
  let result = oldStep(image, initial);
  let steps = 0;
  while (result.kind === "Progressed") {
    assert.ok(steps++ < 10000, "finite benchmark harness limit");
    result = oldStep(image, initial, result.state);
  }
  return result;
}
function newRun(input) {
  assert.equal(after.world_process_v2_prepare_input(BigInt(input.length)), 0);
  new Uint8Array(after.memory.buffer, after.world_process_v2_input_ptr(), input.length).set(input);
  const status = after.world_process_v2_execute(BigInt(input.length));
  assert.equal(status, 0, new TextDecoder().decode(new Uint8Array(after.memory.buffer, after.world_process_v2_error_ptr(), Number(after.world_process_v2_error_len()))));
  return decodeOutcome(new Uint8Array(after.memory.buffer, after.world_process_v2_output_ptr(), Number(after.world_process_v2_output_len())).slice());
}
const u32 = n => { const result = new Uint8Array(4); new DataView(result.buffer).setUint32(0, n, true); return result; };
const cases = [
  ["integer-boolean", "v1.8.2-integer-boolean", new Uint8Array()],
  ["collections", "v1.8.2-algebraic-collections", new Uint8Array()],
  ["portable-values", "v1.8.2-portable-values", new Uint8Array()],
  ["recursion-0", "recursion-complete", u32(0)],
  ["recursion-32", "recursion-complete", u32(32)],
  ["residual", "v1.8.2-one-effect", u32(17)],
  ["yield", "explicit-yield", u32(17)],
];
const warmups = 5, samples = 21, repetitions = 20;
const result = {
  format: "world-v2-economy/v1",
  environment: { date: new Date().toISOString(), node: process.version, platform: os.platform(), release: os.release(), architecture: os.arch(), cpu: os.cpus()[0].model, cores: os.cpus().length, memoryBytes: os.totalmem(), zig: new TextDecoder().decode(command("zig", ["version"])).trim() },
  method: { warmups, samples, repetitions, unit: "ms/invocation", mode: "same admitted program to first observable boundary; warmed modules and reused stateless instances; input copy, admission, execution and output copy included; compilation and instantiation excluded", optimization: "ReleaseSmall", maximumMemoryPages: 4096 },
  kernels: { before: { sha256: frozen.sha256, bytes: legacyKernel.length, ...frozen.inspection.memory }, after: { sha256: current.sha256, bytes: kernel.length, ...current.inspection.memory } },
  workloads: [],
};
for (const [name, fixture, initial] of cases) {
  const file = join(boundaryPath, "test/v2/legacy", `${fixture}.bpi1`);
  const image = new Uint8Array(await readFile(file));
  const lifted = command(liftPath, [], image);
  const converted = command(liftPath, ["--value", file, "to-v2", "initial"], initial);
  const input = encodeInput({ image: lifted, initialArgs: converted, mode: "run" });
  const a = oldRun(image, initial), b = newRun(input);
  if (a.kind === "Completed") {
    assert.equal(b.kind, "Completed");
    assert.deepEqual(a.result, command(liftPath, ["--value", file, "to-v1", "result"], b.value));
  } else if (a.kind === "Requested") {
    assert.equal(b.kind, "Requested");
    const x = decodeEffectRequest(a.request), y = decodeRequest(b.request);
    assert.equal(x.effectSemanticIdentity, y.semanticIdentity);
    assert.deepEqual(x.payload, command(liftPath, ["--value", file, "to-v1", "payload:0"], y.payload));
  } else {
    assert.equal(a.kind, "ExplicitlyYielded");
    assert.equal(b.kind, "Yielded");
  }
  const functions = [() => oldRun(image, initial), () => newRun(input)];
  for (let i = 0; i < warmups; i++) for (const fn of functions) fn();
  const times = [[], []];
  for (let i = 0; i < samples; i++) for (const which of (i % 2 ? [1, 0] : [0, 1])) {
    const start = performance.now();
    for (let j = 0; j < repetitions; j++) functions[which]();
    times[which].push((performance.now() - start) / repetitions);
  }
  const median = values => [...values].sort((x, y) => x - y)[Math.floor(values.length / 2)];
  const ratio = median(times[1]) / median(times[0]);
  for (const [index, label] of ["before", "after"].entries()) await writeFile(join(outputPath, `${name}-${label}.txt`), times[index].join("\n") + "\n");
  const row = { name, fixture, imageSha256: digest(image), liftedSha256: digest(lifted), initialSha256: digest(initial), beforeImageBytes: image.length, afterImageBytes: lifted.length, beforeMedianMs: median(times[0]), afterMedianMs: median(times[1]), warmRatio: ratio, peakLinearMemoryBytes: { before: before.memory.buffer.byteLength, after: after.memory.buffer.byteLength }, samples: { before: times[0], after: times[1] } };
  result.workloads.push(row);
  console.log(JSON.stringify({ workload: name, beforeMs: row.beforeMedianMs, afterMs: row.afterMedianMs, ratio }));
}
await writeFile(join(outputPath, "warm-execution.json"), JSON.stringify(result, null, 2) + "\n");
for (const row of result.workloads) assert.ok(row.warmRatio <= 2, `${row.name}: warm execution exceeds 2x (${row.warmRatio})`);
