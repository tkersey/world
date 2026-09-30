import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
const [embedding, kernelPath, corpus, output] = process.argv.slice(2);
const world = await import(pathToFileURL(embedding));
const bytes = readFileSync(kernelPath);
const expectedSha256 = createHash("sha256").update(bytes).digest("hex");
const rows = [];
for (const family of ["H", "Q"]) for (const depth of family === "H" ? [1,16,64,256,1024] : [1,64,256,1024]) {
  const image = readFileSync(`${corpus}/${family}.bpi3`);
  const initialArgs = Buffer.alloc(8); initialArgs.writeBigUInt64LE(BigInt(depth));
  const k = await world.Kernel.create({bytes, expectedSha256});
  // Common stress limits for valid retained histories; kernel defaults unchanged.
  k.setLimits({input: 2 << 20, working: 32 << 20, output: 2 << 20});
  let peak = 0;
  const sample = fn => { try { return fn(); } finally { peak = Math.max(peak, Number(k.usage().workingPeak)); } };
  const p = sample(() => k.prepare(image));
  const s = sample(() => k.start(p, initialArgs));
  let out = world.decodeOutcome(sample(() => k.drive(s)));
  assert.equal(out.kind, family === "H" ? "yielded" : "requested");
  const pauseLive = Number(k.usage().workingLive);
  if (family === "H") {
    sample(() => k.drive(s, {control:"resume_yield", quantum:0n}));
    for (let n = 0; n < 64; n++) assert.equal(world.decodeOutcome(sample(() => k.drive(s,{quantum:1n}))).kind,"progressed");
    out = world.decodeOutcome(sample(() => k.drive(s)));
  }
  let next = family === "Q" ? 0n : 1n;
  while (out.kind === "requested") {
    const request = await world.decodeRequest(out.request);
    assert.equal(Buffer.from(request.payload).readBigUInt64LE(), next++);
    const value = Buffer.alloc(8); value.writeBigUInt64LE(7n);
    const reply = await world.encodeResult(out.request, value);
    out = world.decodeOutcome(sample(() => k.drive(s,{control:"reply",value:reply})));
  }
  assert.equal(out.kind,"completed");
  assert.equal(Buffer.from(out.value).readBigUInt64LE(), family === "Q" ? 135n : 128n);
  sample(() => k.close(s)); sample(() => k.releasePrepared(p));
  assert.equal(k.usage().workingLive,0n);
  rows.push({family,depth,distinctReplies:Number(next)-1,peak,pauseLive});
  writeFileSync(output, JSON.stringify({kernelSha256:expectedSha256,rows},null,2)+"\n");
  console.log(JSON.stringify(rows.at(-1)));
}
