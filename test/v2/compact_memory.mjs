// Existing native probes, identical invocations, and the unchanged reservations.
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { admitProcessKernel, encodeInput, encodeResult } from "../../src/process_v2/index.mjs";

const [referenceDir, candidateDir, fixtures, destination] = process.argv.slice(2);
assert.ok(destination, "reference zig-out, candidate zig-out, fixtures, output JSON");
const digest = bytes => createHash("sha256").update(bytes).digest("hex");
const kernel = await readFile(join(referenceDir, "world-process-kernel-v2.wasm"));
const host = await admitProcessKernel(kernel, { expectedSha256: digest(kernel) });
const cases = [];
for (const name of ["economy-1", "economy-8", "economy-64", "install-128", "source-queens-dfs",
  "mixed-64", "irregular-64", "constant-64k"]) {
  const images = await Promise.all(["bpi2", "bpc1"].map(async extension =>
    new Uint8Array(await readFile(join(fixtures, `${name}.${extension}`)))));
  cases.push({ name, images, base: { initialArgs: new Uint8Array() } });
}
const search = cases.find(value => value.name === "source-queens-dfs");
let parked = await host.run({ ...search.base, image: search.images[0] });
for (let index = 0; parked.kind === "Yielded" && index < 16; index++)
  parked = await host.run({ image: search.images[0], state: parked.state });
assert.equal(parked.kind, "Requested");
cases.push({ name: "saved-search-response", images: search.images, base: {
  state: parked.state, result: encodeResult(parked.request, Uint8Array.of(201, 0, 0, 0, 0, 0, 0, 0)),
} });
const rows = [];
for (const { name, images, base } of cases) {
  const observations = [];
  for (const [dir, image] of [[referenceDir, images[0]], [candidateDir, images[0]], [candidateDir, images[1]]]) {
    const input = encodeInput({ ...base, image, mode: "run" });
    const invoke = JSON.parse(execFileSync(join(dir, "bin/v2-economy-probe"), { input }));
    const decode = JSON.parse(execFileSync(join(dir, "bin/v2-decode-probe"), { input: image }));
    observations.push({ imageBytes: image.length, imageSha256: digest(image), inputSha256: digest(input),
      invocation: invoke, decoder: decode });
  }
  assert.equal(observations[0].invocation.output_sha256, observations[1].invocation.output_sha256);
  assert.equal(observations[0].invocation.output_sha256, observations[2].invocation.output_sha256);
  rows.push({ name, observations });
  console.log(JSON.stringify({ name, peaks: observations.map(row => row.invocation.peak_working_payload_bytes),
    retained: observations.map(row => row.decoder.rows[0].retained) }));
}
const probes = [];
for (const dir of [referenceDir, candidateDir]) for (const name of ["v2-economy-probe", "v2-decode-probe"]) {
  const path = join(dir, "bin", name);
  probes.push({ path, sha256: digest(await readFile(path)) });
}
await writeFile(destination, JSON.stringify({
  method: "Reference BPI2, candidate BPI2, candidate compact; existing 16 MiB invocation and 1 MiB decoder reservations; allocator-requested bytes, not RSS",
  date: new Date().toISOString(), harnessSha256: digest(await readFile(import.meta.filename)), probes, rows,
}, null, 2) + "\n", { flag: "wx" });
