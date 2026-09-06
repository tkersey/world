import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { admitProcessKernel, decodeRequest, encodeResult, encodeInput, decodeOutcome } from "../../src/process_v2/index.mjs";
import { wasmtimePeer } from "./wasmtime_peer.mjs";

if (process.argv.length !== 14 && process.argv.length !== 15) throw new Error("expected kernel, ten target fixtures, native embedding, and optional Wasmtime project paths");
const kernel = new Uint8Array(await readFile(process.argv[2]));
const image = new Uint8Array(await readFile(process.argv[3]));
const loop = new Uint8Array(await readFile(process.argv[4]));
const deep = new Uint8Array(await readFile(process.argv[5]));
const choice = new Uint8Array(await readFile(process.argv[6]));
const wasm = await admitProcessKernel(kernel, { expectedSha256: createHash("sha256").update(kernel).digest("hex") });
const peer = process.argv[14] ? await wasmtimePeer(process.argv[14], process.argv[2], wasm.sha256) : null;
let observations = 0;
async function compare(mode, input) {
  const encoded = encodeInput({ ...input, mode });
  const native = spawnSync(process.argv[13], [], { input: encoded, maxBuffer: 64 << 20 });
  let outcome;
  try { outcome = await wasm[mode](input); }
  catch (error) {
    assert.notEqual(native.status, 0);
    assert.ok(native.stderr.toString().includes(error.message));
    if (peer) await assert.rejects(peer.invoke(encoded), (other) => other.message === error.message);
    throw error;
  }
  assert.equal(native.status, 0, native.stderr?.toString());
  assert.deepEqual(outcome.bytes, new Uint8Array(native.stdout));
  if (peer) {
    const independent = await peer.invoke(encoded);
    assert.deepEqual(independent, outcome.bytes);
    if (observations++ % 2 === 0) return { ...decodeOutcome(independent), bytes: independent };
  }
  return outcome;
}
try {
  const host = { run: (input) => compare("run", input), advance: (input) => compare("advance", input) };
  const parked = await host.run({ image, initialArgs: new Uint8Array() });
  assert.equal(parked.kind, "Requested");
  assert.equal(decodeRequest(parked.request).semanticIdentity, "fixture.read");
  const transferred = await host.run({ image, state: parked.state });
  assert.deepEqual(transferred.bytes, parked.bytes);
  const result = encodeResult(parked.request, Uint8Array.of(7, 0, 0, 0, 0, 0, 0, 0));
  const yielded = await host.run({ image, state: parked.state, result });
  assert.equal(yielded.kind, "Yielded");
  const done = await host.run({ image, state: yielded.state });
  assert.equal(done.kind, "Completed");
  assert.equal(done.value[0], 7);
  const invalid = result.slice();
  invalid[20] ^= 1;
  await assert.rejects(host.run({ image, state: parked.state, result: invalid }), /InvalidResult/);
  assert.throws(() => encodeResult(parked.request, Uint8Array.of(7)), /InvalidValue/);
  const cancelled = await host.run({ image, state: parked.state, cancel: "stop" });
  assert.equal(cancelled.kind, "Cancelled");
  const counted = await host.run({ image: loop, initialArgs: Uint8Array.of(16, 39, 0, 0, 0, 0, 0, 0) });
  assert.equal(counted.kind, "Completed");
  assert.equal(counted.value[0], 0);
  const handled = await host.run({ image: deep, initialArgs: new Uint8Array() });
  assert.equal(handled.kind, "Completed");
  assert.equal(handled.value[0], 67);
  let position = await host.advance({ image: deep, initialArgs: new Uint8Array() });
  while (position.kind === "Progressed") position = await host.advance({ image: deep, state: position.state });
  assert.deepEqual(position.bytes, handled.bytes);
  const choices = await host.run({ image: choice, initialArgs: new Uint8Array() });
  assert.deepEqual(choices.value, Uint8Array.of(4, 0, 0, 0, 1, 1, 0, 1, 1));
  position = await host.advance({ image: choice, initialArgs: new Uint8Array() });
  while (position.kind === "Progressed") position = await host.advance({ image: choice, state: position.state });
  assert.deepEqual(position.bytes, choices.bytes);
  for (const [path, args, expected] of [
    [process.argv[7], [], [2, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]],
    [process.argv[8], [], [2, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0]],
    [process.argv[9], [0], [1]],
    [process.argv[10], [], [113, 0, 0, 0, 0, 0, 0, 0]],
  ]) {
    const program = new Uint8Array(await readFile(path));
    const completed = await host.run({ image: program, initialArgs: Uint8Array.from(args) });
    assert.deepEqual(completed.value, Uint8Array.from(expected));
    let checkpoint = await host.advance({ image: program, initialArgs: Uint8Array.from(args) });
    while (checkpoint.kind === "Progressed") checkpoint = await host.advance({ image: program, state: checkpoint.state });
    assert.deepEqual(checkpoint.bytes, completed.bytes);
  }
  const cleanupImage = new Uint8Array(await readFile(process.argv[11]));
  const waitingBody = await host.run({ image: cleanupImage, initialArgs: new Uint8Array() });
  let finalizer = await host.advance({ image: cleanupImage, state: waitingBody.state, result: encodeResult(waitingBody.request, Uint8Array.of(9)) });
  while (finalizer.kind === "Progressed") finalizer = await host.advance({ image: cleanupImage, state: finalizer.state });
  assert.deepEqual(decodeRequest(finalizer.request).payload.subarray(0, 3), Uint8Array.of(11, 1, 9));
  const acquiredResult = encodeResult(finalizer.request, Uint8Array.of(1));
  const rebound = await host.run({ image: cleanupImage, state: finalizer.state, cancel: "stop" });
  assert.deepEqual(decodeRequest(rebound.request).payload, decodeRequest(finalizer.request).payload);
  assert.notDeepEqual(rebound.request, finalizer.request);
  await assert.rejects(host.run({ image: cleanupImage, state: rebound.state, result: acquiredResult }), /InvalidResult/);
  const repeatedCancel = await host.run({ image: cleanupImage, state: rebound.state, cancel: "later" });
  assert.deepEqual(repeatedCancel.bytes, rebound.bytes);
  let outerCleanup = await host.advance({ image: cleanupImage, state: rebound.state, result: encodeResult(rebound.request, Uint8Array.of(1)) });
  while (outerCleanup.kind === "Progressed") outerCleanup = await host.advance({ image: cleanupImage, state: outerCleanup.state });
  assert.equal(decodeRequest(outerCleanup.request).payload[0], 22);
  let failed = await host.advance({ image: cleanupImage, state: outerCleanup.state, result: encodeResult(outerCleanup.request, Uint8Array.of(1)) });
  while (failed.kind === "Progressed") failed = await host.advance({ image: cleanupImage, state: failed.state });
  assert.equal(failed.kind, "Failed");
  assert.deepEqual(failed.value, Uint8Array.of(9));
  assert.deepEqual(failed.cleanupFailures, [Uint8Array.of(11), Uint8Array.of(22)]);
  assert.equal(failed.cancellation, "stop");
  const boundedImage = new Uint8Array(await readFile(process.argv[12]));
  const bounded = await host.run({ image: boundedImage, initialArgs: new Uint8Array() });
  assert.deepEqual(decodeRequest(bounded.request).payload, Uint8Array.of(2, 0xc3, 0xa9));
  const boundedTransfer = await host.run({ image: boundedImage, state: bounded.state });
  assert.deepEqual(boundedTransfer.bytes, bounded.bytes);
  assert.throws(() => encodeResult(bounded.request, Uint8Array.of(9)), /InvalidValue/);
  const arrayResponse = encodeResult(bounded.request, Uint8Array.of(9, 4));
  const shortArray = arrayResponse.slice(0, -1);
  shortArray[84] = 1;
  new DataView(shortArray.buffer).setBigUint64(12, BigInt(shortArray.length - 20), true);
  await assert.rejects(host.run({ image: boundedImage, state: bounded.state, result: shortArray }), /InvalidValue/);
  const arrayDone = await host.run({ image: boundedImage, state: bounded.state, result: arrayResponse });
  assert.deepEqual(arrayDone.value, Uint8Array.of(9, 8));
  console.log("native/WASM byte equality and transfers passed for handlers, regions, reentry, cleanup/cancellation rebinding, fixed arrays, bounded text, and 10,000 tail calls");
  if (peer) console.log(`Wasmtime ${peer.identity.wasmtime} matched target checkpoints, rejected stale results, and preserved cancellation rebinding`);
} finally { if (peer) await peer.close(); }
