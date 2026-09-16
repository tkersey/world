import test from "node:test";
import assert from "node:assert/strict";
import { runInNewContext } from "node:vm";
import { createHash } from "node:crypto";
import { copyBytes, natural, concat, field, frame, body, Reader } from "../../src/embedding/wire.mjs";
import { decodeRequest, encodeResult, decodeOutcome, validateValue } from "../../src/embedding/codec.mjs";

test("byte ownership uses intrinsic brands and rejects shared mutable backing", () => {
  const foreign = runInNewContext("new Uint8Array([1, 2, 3])");
  foreign[Symbol.iterator] = () => { throw new Error("unexpected iterator"); };
  const owned = copyBytes(foreign);
  foreign[0] = 9;
  assert.deepEqual(owned, Uint8Array.of(1, 2, 3));
  assert.throws(() => copyBytes({ [Symbol.toStringTag]: "Uint8Array", length: 3 }));
  assert.throws(() => copyBytes(new Proxy(new Uint8Array(3), {})));
  assert.throws(() => copyBytes(new Uint8Array(new SharedArrayBuffer(8))));
});

function request() {
  const binding = concat(new Uint8Array(32).fill(1), new Uint8Array(32).fill(2), natural(3),
    field(new TextEncoder().encode("operation")), field(Uint8Array.of(0, 1, 9)),
    field(Uint8Array.of(0, 1, 1)), field(Uint8Array.of(42, 0, 0, 0, 0, 0, 0, 0)));
  const digest = createHash("sha256").update("boundary.effect-request/v3\0").update(binding).digest();
  return frame("ABL_ERQ3", concat(binding, digest));
}
test("request hashes and typed replies survive caller mutation across async hashing", async () => {
  const bytes = request(), pending = decodeRequest(bytes);
  bytes.fill(255);
  const decoded = await pending;
  assert.equal(decoded.semanticIdentity, "operation");
  const response = await encodeResult(request(), Uint8Array.of(1));
  const reader = new Reader(body("ABL_ERS3", response));
  assert.deepEqual(reader.take(32), decoded.requestIdentity);
  assert.deepEqual(reader.field(), Uint8Array.of(1)); reader.finish();
  await assert.rejects(encodeResult(request(), Uint8Array.of(2)), /InvalidValue/);
  const corrupt = request(); corrupt[corrupt.length - 1] ^= 1;
  await assert.rejects(decodeRequest(corrupt), /InvalidRequest/);
});
test("ordinary value contracts preserve zero-size cardinality and reject internal schemas", () => {
  const huge = concat(Uint8Array.of(0, 2, 17, 1), natural((1n << 64n) - 1n), Uint8Array.of(0));
  validateValue(huge, new Uint8Array());
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 16), new Uint8Array()), /InvalidSchema/);
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 11), Uint8Array.of(1, 255)));
  assert.throws(() => new Reader(Uint8Array.of(128, 0)).natural(), /NonCanonical/);
});
test("resident outcome explicitly omits checkpoint bytes", () => {
  assert.deepEqual(decodeOutcome(frame("ABL_PKO3", Uint8Array.of(0, 0))), { kind: "progressed", state: null });
  const source = frame("ABL_PKO3", Uint8Array.of(3, 1, 42));
  const decoded = decodeOutcome(source); source.fill(255);
  assert.deepEqual(decoded, { kind: "completed", value: Uint8Array.of(42) });
});
