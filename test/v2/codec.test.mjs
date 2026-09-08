import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { runInNewContext } from "node:vm";
import { concat, frame, field, natural, decodeOutcome, decodeRequest, encodeInput, encodeResult, validateValue } from "../../src/process_v2/codec.mjs";

function requestFixture() {
  const digest = bytes => new Uint8Array(createHash("sha256").update(bytes).digest());
  const domain = (name, ...parts) => digest(concat(new TextEncoder().encode(name), ...parts.map(field)));
  const identity = new TextEncoder().encode("test/byte-ownership");
  const schema = Uint8Array.of(0, 1, 6), payload = Uint8Array.of(42), zero = new Uint8Array(32);
  const contract = domain("boundary.residual-contract/v2", identity, schema, schema);
  const bindings = [zero, zero, contract, zero];
  const values = [identity, schema, schema, payload];
  const requestIdentity = domain("boundary.effect-request/v2", ...bindings, ...values);
  return frame("ABL_ERQ2", concat(...bindings, ...values.map(field), requestIdentity));
}

test("decoded Buffer fields have detached ownership in both directions", () => {
  const outcome = Buffer.from(frame("ABL_PKO2", concat(natural(3), field(Uint8Array.of(42)))));
  const value = decodeOutcome(outcome).value;
  outcome[outcome.length - 1] = 99;
  assert.deepEqual([...value], [42]);
  value[0] = 17;
  assert.equal(outcome[outcome.length - 1], 99);
  const request = Buffer.from(requestFixture()), original = Buffer.from(request);
  const decoded = decodeRequest(request);
  const fields = Object.values(decoded).filter(value => value instanceof Uint8Array);
  assert.equal(fields.length, 9);
  const copies = fields.map(value => Uint8Array.from(value));
  request.fill(0xff);
  fields.forEach((value, index) => assert.deepEqual(value, copies[index]));
  const again = decodeRequest(original), unchanged = Buffer.from(original);
  for (const value of Object.values(again)) if (value instanceof Uint8Array) value.fill(0);
  assert.deepEqual(original, unchanged);
  assert.doesNotThrow(() => encodeResult(original, Uint8Array.of(7)));
});

test("byte codecs accept intrinsic Uint8Arrays across realms and reject lookalikes", () => {
  const foreign = bytes => runInNewContext("Uint8Array.from(values)", { values: [...bytes] });
  const outcome = frame("ABL_PKO2", concat(natural(3), field(Uint8Array.of(42))));
  assert.deepEqual(decodeOutcome(foreign(outcome)), decodeOutcome(outcome));
  const request = requestFixture();
  assert.deepEqual(decodeRequest(foreign(request)), decodeRequest(request));
  assert.deepEqual(encodeResult(foreign(request), foreign([7])), encodeResult(request, Uint8Array.of(7)));
  assert.deepEqual(encodeInput({ image: foreign([1]), initialArgs: foreign([]) }),
    encodeInput({ image: Uint8Array.of(1), initialArgs: new Uint8Array() }));
  validateValue(foreign([0, 1, 6]), foreign([42]));
  for (const fake of [new Uint16Array(2), new DataView(new ArrayBuffer(4)), Object.create(Uint8Array.prototype)]) {
    assert.throws(() => encodeInput({ image: fake, initialArgs: new Uint8Array() }), /expected bytes/);
    assert.throws(() => decodeOutcome(fake), /Truncated/);
  }
});

test("fixed arrays have an exact length and no value count prefix", () => {
  const schema = Uint8Array.of(0, 2, 17, 1, 2, 6);
  validateValue(schema, Uint8Array.of(4, 5));
  assert.throws(() => validateValue(schema, Uint8Array.of(4)), /InvalidValue/);
  assert.throws(() => validateValue(schema, Uint8Array.of(4, 5, 6)), /NonCanonical/);
});

test("bounded text counts UTF-8 bytes and bounded bytes retain arbitrary bytes", () => {
  validateValue(Uint8Array.of(0, 1, 19, 2), Uint8Array.of(2, 0xc3, 0xa9));
  validateValue(Uint8Array.of(0, 1, 18, 2), Uint8Array.of(2, 0xff, 0));
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 19, 1), Uint8Array.of(2, 0xc3, 0xa9)), /InvalidValue/);
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 18, 1), Uint8Array.of(2, 0xff, 0)), /InvalidValue/);
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 19, 1), Uint8Array.of(1, 0xff)));
});

test("bounds distinguish canonical types and zero-width arrays need no element traversal", () => {
  const distinct = Uint8Array.of(0, 3, 12, 2, 1, 2, 18, 1, 18, 2);
  validateValue(distinct, Uint8Array.of(0, 0));
  const duplicate = Uint8Array.of(0, 3, 12, 2, 1, 2, 18, 1, 18, 1);
  assert.throws(() => validateValue(duplicate, Uint8Array.of(0, 0)), /NonCanonical/);
  const zeroWidth = Uint8Array.of(0, 2, 17, 1, 255, 255, 255, 255, 255, 255, 255, 255, 255, 1, 0);
  validateValue(zeroWidth, new Uint8Array());
});

test("enumerations preserve sparse tags, empty domains, and canonical tag order", () => {
  validateValue(Uint8Array.of(0, 1, 20, 2, 2, 7), Uint8Array.of(7, 0, 0, 0));
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 20, 2, 2, 7), Uint8Array.of(5, 0, 0, 0)), /InvalidValue/);
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 20, 0), Uint8Array.of(0, 0, 0, 0)), /InvalidValue/);
  assert.throws(() => validateValue(Uint8Array.of(0, 1, 20, 2, 7, 2), Uint8Array.of(7, 0, 0, 0)), /InvalidSchema/);
});
