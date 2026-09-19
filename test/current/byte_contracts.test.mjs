import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { runInNewContext } from "node:vm";
import { concat, frame, field, natural, body, Reader } from "../../src/embedding/wire.mjs";
import { decodeOutcome, decodeRequest, encodeInput, encodeResult, validateValue } from "../../src/embedding/codec.mjs";

function requestFixture(schema = Uint8Array.of(0, 1, 6), payload = Uint8Array.of(42)) {
  const digest = bytes => new Uint8Array(createHash("sha256").update(bytes).digest());
  const identity = new TextEncoder().encode("test/byte-ownership");
  const binding = concat(new Uint8Array(32), new Uint8Array(32), natural(0),
    field(identity), field(schema), field(schema), field(payload));
  const requestIdentity = digest(concat(new TextEncoder().encode("boundary.effect-request/v3\0"), binding));
  return frame("ABL_ERQ3", concat(binding, requestIdentity));
}

test("decoded Buffer fields have detached ownership in both directions", async () => {
  const outcome = Buffer.from(frame("ABL_PKO3", concat(natural(3), field(Uint8Array.of(42)))));
  const value = decodeOutcome(outcome).value;
  outcome[outcome.length - 1] = 99;
  assert.deepEqual([...value], [42]);
  value[0] = 17;
  assert.equal(outcome[outcome.length - 1], 99);
  const request = Buffer.from(requestFixture()), original = Buffer.from(request);
  const decoded = await decodeRequest(request);
  const fields = Object.values(decoded).filter(value => value instanceof Uint8Array);
  assert.equal(fields.length, 7);
  const copies = fields.map(value => Uint8Array.from(value));
  request.fill(0xff);
  fields.forEach((value, index) => assert.deepEqual(value, copies[index]));
  const again = await decodeRequest(original), unchanged = Buffer.from(original);
  for (const value of Object.values(again)) if (value instanceof Uint8Array) value.fill(0);
  assert.deepEqual(original, unchanged);
  await encodeResult(original, Uint8Array.of(7));
});

test("byte codecs accept intrinsic Uint8Arrays across realms and reject lookalikes", async () => {
  const foreign = bytes => runInNewContext("Uint8Array.from(values)", { values: [...bytes] });
  const outcome = frame("ABL_PKO3", concat(natural(3), field(Uint8Array.of(42))));
  assert.deepEqual(decodeOutcome(foreign(outcome)), decodeOutcome(outcome));
  const request = requestFixture();
  assert.deepEqual(await decodeRequest(foreign(request)), await decodeRequest(request));
  assert.deepEqual(await encodeResult(foreign(request), foreign([7])), await encodeResult(request, Uint8Array.of(7)));
  assert.deepEqual(encodeInput({ image: foreign(frame("ABL_BPI3", new Uint8Array())), initialArgs: foreign([]) }),
    encodeInput({ image: frame("ABL_BPI3", new Uint8Array()), initialArgs: new Uint8Array() }));
  validateValue(foreign([0, 1, 6]), foreign([42]));
  for (const fake of [new Uint16Array(2), new DataView(new ArrayBuffer(4)), Object.create(Uint8Array.prototype)]) {
    assert.throws(() => encodeInput({ image: fake, initialArgs: new Uint8Array() }), /expected Uint8Array/);
    assert.throws(() => decodeOutcome(fake), /expected Uint8Array/);
  }
});

test("invocation fields preserve view bytes without invoking custom iterators", async () => {
  const customized = bytes => {
    const value = Uint8Array.from(bytes);
    value[Symbol.iterator] = function* () { yield 9; };
    return value;
  };
  const image = frame("ABL_BPI3", new Uint8Array()), state = frame("ABL_PST3", new Uint8Array());
  for (const input of [
    { image, initialArgs: Uint8Array.of(3, 4) },
    { image, state, control: "reply", value: Uint8Array.of(5, 6) },
    { image, state, control: "cancel_bytes", value: Uint8Array.of(5, 6) },
  ]) {
    const hostile = Object.fromEntries(Object.entries(input).map(([key, value]) => [key, typeof value === "string" ? value : customized(value)]));
    assert.deepEqual(encodeInput(hostile), encodeInput(input));
  }
});

test("result validation and serialization use the same detached bytes", async () => {
  const schema = Uint8Array.of(0, 1, 1), request = requestFixture(schema, Uint8Array.of(1));
  const value = new Uint8Array(1);
  value[0] = 1;
  let calls = 0;
  value.subarray = () => { calls++; value[0] = 2; return Uint8Array.of(1); };
  const pending = encodeResult(request, value);
  value[0] = 2;
  const encoded = await pending;
  assert.equal(calls, 0);
  assert.deepEqual(encoded, await encodeResult(request, Uint8Array.of(1)));
  value[0] = 2;
  const reader = new Reader(body("ABL_ERS3", encoded));
  reader.take(32);
  const emitted = reader.field();
  reader.finish();
  validateValue(schema, emitted);
  assert.deepEqual(emitted, Uint8Array.of(1));
  const invalid = Uint8Array.of(2), rejected = encodeResult(request, invalid);
  invalid[0] = 1;
  await assert.rejects(rejected, /InvalidValue/);
});

test("codec ingress ignores byte-view property, method and species overrides", async () => {
  class CustomBytes extends Uint8Array {
    static get [Symbol.species]() { throw new Error("custom species"); }
  }
  const factories = [
    bytes => Uint8Array.from(bytes),
    bytes => Buffer.from(bytes),
    bytes => runInNewContext("Uint8Array.from(values)", { values: [...bytes] }),
    bytes => new CustomBytes(bytes),
  ];
  for (const make of factories) {
    const hostile = bytes => {
      const value = make(bytes);
      const forbidden = () => { throw new Error("custom byte-view operation"); };
      for (const key of ["length", "byteLength", "byteOffset", "buffer", "constructor"]) {
        Object.defineProperty(value, key, { get: forbidden });
      }
      value[Symbol.iterator] = value.subarray = value.slice = forbidden;
      return value;
    };
    const request = requestFixture(), outcome = frame("ABL_PKO3", concat(natural(3), field(Uint8Array.of(42))));
    assert.deepEqual(await decodeRequest(hostile(request)), await decodeRequest(request));
    assert.deepEqual(decodeOutcome(hostile(outcome)), decodeOutcome(outcome));
    assert.deepEqual(await encodeResult(hostile(request), hostile([7])), await encodeResult(request, Uint8Array.of(7)));
    assert.deepEqual(encodeInput({ image: hostile(frame("ABL_BPI3", new Uint8Array())), initialArgs: hostile([]) }),
      encodeInput({ image: frame("ABL_BPI3", new Uint8Array()), initialArgs: new Uint8Array() }));
    validateValue(hostile([0, 1, 6]), hostile([42]));
  }
});

test("fixed arrays have an exact length and no value count prefix", async () => {
  const schema = Uint8Array.of(0, 2, 17, 1, 2, 6);
  validateValue(schema, Uint8Array.of(4, 5));
  assert.throws(() => validateValue(schema, Uint8Array.of(4)), /InvalidValue/);
  assert.throws(() => validateValue(schema, Uint8Array.of(4, 5, 6)), /NonCanonical/);
});

test("bounded text counts UTF-8 bytes and bounded bytes retain arbitrary bytes", async () => {
  validateValue(Uint8Array.of(0, 1, 19, 2), Uint8Array.of(2, 0xc3, 0xa9));
  validateValue(Uint8Array.of(0, 1, 18, 2), Uint8Array.of(2, 0xff, 0));
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 19, 1), Uint8Array.of(2, 0xc3, 0xa9)), /InvalidValue/);
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 18, 1), Uint8Array.of(2, 0xff, 0)), /InvalidValue/);
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 19, 1), Uint8Array.of(1, 0xff)));
});

test("bounds distinguish canonical types and zero-width arrays need no element traversal", async () => {
  const distinct = Uint8Array.of(0, 3, 12, 2, 1, 2, 18, 1, 18, 2);
  validateValue(distinct, Uint8Array.of(0, 0));
  const duplicate = Uint8Array.of(0, 3, 12, 2, 1, 2, 18, 1, 18, 1);
  assert.throws(() => validateValue(duplicate, Uint8Array.of(0, 0)), /NonCanonical/);
  const zeroWidth = Uint8Array.of(0, 2, 17, 1, 255, 255, 255, 255, 255, 255, 255, 255, 255, 1, 0);
  validateValue(zeroWidth, new Uint8Array());
});

test("enumerations preserve sparse tags, empty domains, and canonical tag order", async () => {
  validateValue(Uint8Array.of(0, 1, 20, 2, 2, 7), Uint8Array.of(7, 0, 0, 0));
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 20, 2, 2, 7), Uint8Array.of(5, 0, 0, 0)), /InvalidValue/);
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 20, 0), Uint8Array.of(0, 0, 0, 0)), /InvalidValue/);
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 20, 2, 7, 2), Uint8Array.of(7, 0, 0, 0)), /InvalidSchema/);
});
