import assert from "node:assert/strict";
import test from "node:test";
import { validateValue } from "../../src/process_v2/codec.mjs";

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
