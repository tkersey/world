// Copyright (c) 2026 World contributors. MIT license.
// Portable, fixed resource/restore witness. The second process receives only State.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { Kernel, decodeOutcome, decodeRequest, encodeResult } from "../embedding/index.mjs";

const [root, expectedSha256, mode] = process.argv.slice(2);
const bytes = new Uint8Array(await readFile(join(root, "runtime/world-kernel.wasm")));
const image = new Uint8Array(await readFile(join(root, "smoke/resource.bpi3")));
const k = await Kernel.create({ bytes, expectedSha256 });
k.setLimits({ input: 65536, working: 1048576, output: 65536 });
if (mode === "resume") {
  const data = JSON.parse((await new Promise((resolve, reject) => {
    let input = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", chunk => { input += chunk; if (input.length > 2 << 20) reject(new Error("smoke state too large")); });
    process.stdin.on("end", () => resolve(input));
  })));
  const p = k.prepare(image), s = k.restore(p, Buffer.from(data.state, "base64"));
  k.releasePrepared(p);
  let control = "reply", value = Buffer.from(data.reply, "base64");
  for (let round = 0; round < 8; round++) {
    const outcome = decodeOutcome(k.drive(s, { control, value, checkpoint: true }));
    if (outcome.kind === "completed") {
      assert.deepEqual(outcome.value, Uint8Array.of(42, 0, 0, 0, 0, 0, 0, 0));
      k.close(s);
      console.log(JSON.stringify({ result: 42, restored: true }));
      process.exit(0);
    }
    assert.equal(outcome.kind, "requested");
    const request = await decodeRequest(outcome.request);
    assert.ok(["example/resource-use", "example/resource-release"].includes(request.semanticIdentity));
    control = "reply"; value = await encodeResult(outcome.request, new Uint8Array());
  }
  throw new Error("smoke did not complete");
}
const p = k.prepare(image), s = k.start(p);
k.releasePrepared(p);
const first = decodeOutcome(k.drive(s, { checkpoint: true }));
assert.equal(first.kind, "requested");
const request = await decodeRequest(first.request);
assert.equal(request.semanticIdentity, "example/resource-acquire");
const response = await encodeResult(first.request, Uint8Array.of(41, 0, 0, 0, 0, 0, 0, 0));
const state = k.checkpoint(s, { transfer: true });
assert.deepEqual(state, first.state);
const child = spawnSync(process.execPath, [import.meta.filename, root, expectedSha256, "resume"], {
  input: JSON.stringify({ state: Buffer.from(state).toString("base64"), reply: Buffer.from(response).toString("base64") }),
  encoding: "utf8", timeout: 20000, env: { PATH: process.env.PATH },
});
if (child.status !== 0) throw new Error(`fresh-process restore failed: ${child.stderr || child.error || child.status}`);
assert.deepEqual(JSON.parse(child.stdout), { result: 42, restored: true });
console.log(JSON.stringify({ check: "resource request and fresh-process restore", request: request.semanticIdentity, result: 42 }));
