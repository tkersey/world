import assert from "node:assert/strict";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { encodeInput } from "../../src/process_v2/index.mjs";

const [boundary, currentProbe, legacyProbe, lift, outputArgument] = process.argv.slice(2);
assert.ok(outputArgument, "expected Boundary source, native v2/v1 probes, lifter and output directory");
const output = resolve(outputArgument);
await mkdir(output, { recursive: true });
const hash = bytes => createHash("sha256").update(bytes).digest("hex");
function command(file, args, input) {
  const result = spawnSync(file, args, { input, maxBuffer: 64 << 20, timeout: 60000 });
  assert.equal(result.status, 0, result.stderr?.toString());
  return new Uint8Array(result.stdout);
}
const json = bytes => JSON.parse(new TextDecoder().decode(bytes));
const u32 = n => { const value = new Uint8Array(4); new DataView(value.buffer).setUint32(0, n, true); return value; };
const workloads = [];
for (const [name, fixture, initial] of [
  ["integer-boolean", "v1.8.2-integer-boolean", new Uint8Array()],
  ["collections", "v1.8.2-algebraic-collections", new Uint8Array()],
  ["portable-values", "v1.8.2-portable-values", new Uint8Array()],
  ["recursion-0", "recursion-complete", u32(0)],
  ["recursion-32", "recursion-complete", u32(32)],
  ["residual", "v1.8.2-one-effect", u32(17)],
  ["yield", "explicit-yield", u32(17)],
]) {
  const file = join(boundary, "test/v2/legacy", `${fixture}.bpi1`);
  const initialFile = join(output, `${name}.args`);
  await writeFile(initialFile, initial);
  const before = json(command(legacyProbe, [file, initialFile]));
  const oldImage = new Uint8Array(await readFile(file));
  const image = command(lift, [], oldImage);
  const converted = command(lift, ["--value", file, "to-v2", "initial"], initial);
  const after = json(command(currentProbe, [], encodeInput({ image, initialArgs: converted, mode: "run" })));
  assert.equal(before.pointer_bytes, after.pointer_bytes);
  assert.equal(before.platform, after.platform);
  const ratio = after.peak_working_payload_bytes / before.mandatory_validation_workspace_bytes;
  assert.ok(ratio <= 2, `${name} exceeds twice the v1 mandatory workspace alone`);
  workloads.push({ name, imageSha256: hash(oldImage), liftedSha256: hash(image), initialSha256: hash(initial), before, after, ratioToV1MandatoryWorkspace: ratio });
}
const features = [];
for (const [file, initial] of [
  ["source-deep.bpi2", []], ["source-choices-all.bpi2", []],
  ["source-state-local.bpi2", []], ["source-state-shared.bpi2", []],
  ["source-reentrant.bpi2", []], ["source-cloned.bpi2", []],
  ["source-queens-dfs.bpi2", []], ["source-queens-bfs.bpi2", []],
  ["source-scheduler.bpi2", []], ["source-recursive.bpi2", [16, 39, 0, 0, 0, 0, 0, 0]],
  ["economy-1.bpi2", []], ["economy-8.bpi2", []], ["economy-64.bpi2", []],
]) {
  const image = new Uint8Array(await readFile(join(boundary, "zig-out/v2", file)));
  const input = encodeInput({ image, initialArgs: Uint8Array.from(initial), mode: "run" });
  features.push({ file, imageBytes: image.length, imageSha256: hash(image), ...json(command(currentProbe, [], input)) });
}
const report = {
  format: "world-v2-working-memory/v1",
  method: "same native pointer width and inputs; v2 exact peak simultaneously live allocator payload includes PKI2 decoding, admission, execution, snapshot and PKO2 encoding; allocator metadata demand is separately a lower bound; v1 mandatory ValidationWorkspace is an unconditional working-allocation lower bound, excluding its additionally measured buffer demands; unused backing reservations are reported separately",
  probes: { v1Sha256: hash(await readFile(legacyProbe)), v2Sha256: hash(await readFile(currentProbe)) },
  workloads, features,
};
await writeFile(join(output, "working-memory.json"), JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify({ matchedWorkloads: workloads.length, worstRatioToV1MandatoryWorkspace: Math.max(...workloads.map(row => row.ratioToV1MandatoryWorkspace)), features: features.length, largestFeaturePeakBytes: Math.max(...features.map(row => row.peak_working_payload_bytes)) }));
