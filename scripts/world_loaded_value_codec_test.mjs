#!/usr/bin/env node
import {
  encodeByteStringList,
  encodeI32,
  encodeProduct,
  encodeString,
  encodeSum,
} from './world_loaded_value_codec.mjs';

function expectHex(label, actual, expected) {
  const hex = [...actual].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  if (hex !== expected) {
    throw new Error(`${label}: expected ${expected}, got ${hex}`);
  }
}

expectHex('i32', encodeI32(-2), 'feffffff');
expectHex('string', encodeString('hi'), '020000006869');
expectHex('string-list', encodeByteStringList(['a', 'bc']), '020000000100000061020000006263');

const product = encodeProduct([encodeString('alpha'), encodeI32(7)]);
expectHex('product', product, '0200000005000000616c70686107000000');
expectHex('sum-with-payload', encodeSum(1, product), '01000000010200000005000000616c70686107000000');
expectHex('sum-without-payload', encodeSum(0), '0000000000');

console.log('loaded_value_codec=true');
