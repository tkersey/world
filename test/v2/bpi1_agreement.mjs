// Legacy execution belongs to isolated World conformance tooling. The v2
// kernel receives only lifted BPI2; this host compares first-order observations.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { admitProcessKernel as admitV1, decodeEffectRequest, encodeEffectResult } from "./legacy/process_v1/index.mjs";
import { admitProcessKernel, encodeInput, decodeOutcome, decodeRequest, encodeResult } from "../../src/process_v2/index.mjs";
import { wasmtimePeer } from "./wasmtime_peer.mjs";

const [kernelPath, nativePath, oldKernelPath, liftPath, fixtures, project] = process.argv.slice(2);
assert.ok(project, "expected v2 kernel, native embedding, frozen v1 kernel, lifter, fixtures, and Wasmtime project");
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const kernel = new Uint8Array(await readFile(kernelPath));
const current = await admitProcessKernel(kernel, { expectedSha256: digest(kernel) });
const frozen = await admitV1(new Uint8Array(await readFile(oldKernelPath)));
const peer = await wasmtimePeer(project, kernelPath, current.sha256);
const manifest = JSON.parse(await readFile(join(fixtures, "inputs.json"), "utf8"));
const u32 = (n) => { const bytes = new Uint8Array(4); new DataView(bytes.buffer).setUint32(0, n, true); return bytes; };
function command(args, input) {
  const result = spawnSync(liftPath, args, { input, maxBuffer: 16 << 20 });
  assert.equal(result.status, 0, result.stderr?.toString());
  return new Uint8Array(result.stdout);
}
const converted = (file, direction, selector, bytes) => command(["--value", file, direction, selector], bytes);
let observations = 0;
async function v2(input) {
  const encoded = encodeInput({ ...input, mode: "run" });
  const native = spawnSync(nativePath, [], { input: encoded, maxBuffer: 16 << 20 });
  assert.equal(native.status, 0, native.stderr?.toString());
  const result = await current.run(input);
  assert.deepEqual(result.bytes, new Uint8Array(native.stdout));
  const independent = await peer.invoke(encoded);
  assert.deepEqual(independent, result.bytes);
  observations++;
  return { ...decodeOutcome(independent), bytes: independent };
}
async function v1(input) {
  let result = await frozen.advance(input);
  let steps = 0;
  while (result.kind === "Progressed") {
    assert.ok(steps++ < 1000, "legacy fixture harness limit");
    result = await frozen.advance({ image: input.image, instance: { state: result.state } });
  }
  return result;
}
const cases = [
  ["authored-failure-v1", []],
  ["authored-failure-v2-success", [8, 2]],
  ["authored-failure-v2-success", [128, 255]],
  ["authored-failure-v2-success", [8, 0]],
  ["authored-failure-v2-bad-math", [1]],
  ["authored-failure-v2-bad-math", [0]],
  ...["effect-morphism", "explicit-yield", "initial-progress", "typed-effect-initial", "v1.8.2-one-effect"].map((name) => [name, u32(17)]),
  ["recursion-complete", u32(4)],
  ["recursion-complete", u32(0)],
  ["v1.8.2-enum-tag", u32(2)],
  ["v1.8.2-enum-tag", u32(47)],
  ["v1.8.2-derived-copy", []],
  ...["portable-values", "integer-boolean", "algebraic-collections", "remainder-i8", "remainder-i16", "remainder-i32", "remainder-i64"].map((name) => [`v1.8.2-${name}`, []]),
];
for (const index of [0, 1, 2, 3, 0xffffffff]) {
  cases.push(["v1.8.2-text-byte-at", [3, 0, 0, 0, 0xc3, 0xa9, 0x22, ...u32(index)]]);
  cases.push(["v1.8.2-bytes-byte-at", [3, 0, 0, 0, 0xff, 0, 0x80, ...u32(index)]]);
}
const images = new Map();
try {
  for (const file of manifest.files) {
    const image = new Uint8Array(await readFile(join(fixtures, file.file)));
    assert.equal(image.length, file.bytes);
    assert.equal(digest(image), file.sha256);
    const lifted = command([], image);
    images.set(file.file.replace(/\.bpi1$/, ""), { image, lifted, path: join(fixtures, file.file) });
  }
  for (const [name, input] of cases) {
    const { image, lifted, path } = images.get(name);
    const initial = Uint8Array.from(input);
    let before = await v1({ image, instance: { initialArgs: initial } });
    let after = await v2({ image: lifted, initialArgs: converted(path, "to-v2", "initial", initial) });
    const trace = [];
    let count = 0;
    for (;;) {
      assert.ok(count++ < 100, "observable fixture harness limit");
      if (before.kind === "Requested") {
        assert.equal(after.kind, "Requested", name);
        const a = decodeEffectRequest(before.request), b = decodeRequest(after.request);
        assert.equal(a.effectSemanticIdentity, b.semanticIdentity, name);
        // These immutable legacy fixtures each declare one residual operation.
        assert.deepEqual(a.payload, converted(path, "to-v1", "payload:0", b.payload), name);
        trace.push({ effect: a.effectSemanticIdentity, payload: [...a.payload] });
        const answer = u32(42);
        before = await v1({ image, instance: { state: before.state }, effectResult: encodeEffectResult({ request: before.request, resume: answer }) });
        after = await v2({ image: lifted, state: after.state, result: encodeResult(after.request, converted(path, "to-v2", "resume:0", answer)) });
      } else if (before.kind === "ExplicitlyYielded") {
        assert.equal(after.kind, "Yielded", name);
        trace.push({ yield: true });
        before = await v1({ image, instance: { state: before.state } });
        after = await v2({ image: lifted, state: after.state });
      } else {
        const failed = before.kind === "AuthoredFailure";
        assert.equal(before.kind, failed ? "AuthoredFailure" : "Completed", name);
        assert.equal(after.kind, failed ? "Failed" : "Completed", name);
        const actual = converted(path, "to-v1", failed ? "failure" : "result", after.value);
        assert.deepEqual(actual, failed ? before.failure : before.result, name);
        if (failed) assert.deepEqual(after.cleanupFailures, []);
        console.log(`${name}: ${after.kind}; ${trace.length} observable suspensions; exact legacy value agreement`);
        break;
      }
    }
  }
  assert.deepEqual(new Set(cases.map(([name]) => name)), new Set(images.keys()), "every frozen image is executed");
  console.log(`${cases.length} legacy cases, ${observations} native/JS/Wasmtime checkpoints; frozen v1 ${frozen.sha256}; v2 ${current.sha256}`);
} finally { await peer.close(); }
