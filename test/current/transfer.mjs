import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { Kernel } from "../../src/embedding/kernel.mjs";
import { encodeInput, decodeOutcome, encodeResult, decodeRequest } from "../../src/embedding/codec.mjs";
import { wasmtimePeer } from "./peer.mjs";
const [kernelPath, fixtures] = process.argv.slice(2);
const bytes = new Uint8Array(await readFile(kernelPath));
const expectedSha256 = createHash("sha256").update(bytes).digest("hex");
const peer = await wasmtimePeer(kernelPath, expectedSha256);
let boundaries = 0;
try {
  for (const name of ["resource", "generator", "reentrant", "custody"]) {
    const image = new Uint8Array(execFileSync(fixtures, ["image", name]));
    const k = await Kernel.create({ bytes, expectedSha256 });
    k.setLimits({ input: 2 << 20, working: 8 << 20, output: 2 << 20 });
    const p = k.prepare(image), s = k.start(p);
    const initial = k.checkpoint(s, { transfer: true });
    k.releasePrepared(p);
    const prepared = await peer.call("prepare", { bytes: image });
    const started = await peer.call("restore", { handle: prepared.prepared, bytes: initial });
    await peer.call("release_prepared", { handle: prepared.prepared });
    let state = initial, control = 0, value = new Uint8Array();
    for (let round = 0; ; round++) {
      assert.ok(round < 256);
      const names = ["none", "reply", "resume_yield"];
      const command = encodeInput({ image, state, control: names[control], value, quantum: 17 });
      const native = new Uint8Array(execFileSync(fixtures, ["invoke"], { input: command }));
      const actual = await peer.call("drive", { handle: started.session, control, bytes: value, quantum: 17, checkpoint: true });
      assert.deepEqual(actual.bytes, native, `${name} Wasmtime boundary ${round}`);
      const outcome = decodeOutcome(actual.bytes);
      boundaries++;
      if (["completed", "failed", "cancelled"].includes(outcome.kind)) {
        const closed = await peer.call("close", { handle: started.session });
        assert.equal(closed.working_live, 0);
        break;
      }
      state = outcome.state;
      const restored = k.prepare(image), successor = k.restore(restored, state);
      assert.deepEqual(k.checkpoint(successor, { transfer: true }), state);
      k.releasePrepared(restored);
      if (outcome.kind === "requested") {
        const request = await decodeRequest(outcome.request);
        const result = request.semanticIdentity === "example/resource-acquire" ? Uint8Array.of(41, 0, 0, 0, 0, 0, 0, 0) : new Uint8Array();
        value = await encodeResult(outcome.request, result); control = 1;
      } else { control = outcome.kind === "yielded" ? 2 : 0; value = new Uint8Array(); }
    }
  }
  console.log(JSON.stringify({ check: "Node/Wasmtime/native ABI 3 transfer", boundaries, ...peer.identity }));
} finally { await peer.close(); }
