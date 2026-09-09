import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { admitProcessKernel, encodeInput } from "../../src/process_v2/index.mjs";
import { wasmtimePeer } from "./wasmtime_peer.mjs";

const [kernelPath, nativePath, fixtures, project] = process.argv.slice(2);
assert.ok(project, "expected kernel, native embedding, Boundary economy fixtures and Wasmtime project");
const kernel = new Uint8Array(await readFile(kernelPath));
const digest = createHash("sha256").update(kernel).digest("hex");
const host = await admitProcessKernel(kernel, { expectedSha256: digest });
const peer = await wasmtimePeer(project, kernelPath, digest);
try {
  for (const count of [0, 1, 8, 64]) {
    const image = new Uint8Array(await readFile(join(fixtures, `economy-${count}.bpi2`)));
    const initialArgs = count === 0 ? new Uint8Array(65539).fill(0x5a) : new Uint8Array();
    if (count === 0) initialArgs.set([0x80, 0x80, 0x04]);
    const input = { image, initialArgs, mode: "run" };
    const encoded = encodeInput(input);
    const result = await host.run(input);
    const native = spawnSync(nativePath, [], { input: encoded, maxBuffer: 4 << 20 });
    assert.equal(native.status, 0, native.stderr?.toString());
    assert.deepEqual(result.bytes, new Uint8Array(native.stdout));
    assert.deepEqual(result.bytes, await peer.invoke(encoded));
    assert.equal(result.kind, "Completed");
    assert.equal(new DataView(result.value.buffer, result.value.byteOffset).getBigUint64(0, true), BigInt(count === 0 ? 65537 : count * (count + 1) / 2));
  }
  console.log(`economy workloads passed native/JS/Wasmtime under one kernel ${digest}`);
} finally { await peer.close(); }
