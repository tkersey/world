import { describe, expect, test } from "bun:test";
import { runInNewContext } from "node:vm";

import {
  decodeEffectRequest,
  decodeEffectResult,
  encodeEffectResult,
} from "../src/process_v1/effect.mjs";
import { WorldProcessHostError } from "../src/process_v1/errors.mjs";

// Emitted by Boundary v1.7.0's native Process vector producer and accepted by
// the fixed kernel. Keeping this as bytes prevents the World test from becoming
// the oracle for Boundary's digest domains or field ordering.
const REQUEST = fromHex(
  "41424c5f4552513101000000" +
  "e64d11941d799a728a024fe33dce0950d8d3e7182a4a90d4ee1692d43ce07366" +
  "68f82b4dc159dbabf9e87e0532a4bfe8e05d8868c582b789f47e72f4c3128174" +
  "377e7f60b8a67f3b8d2a8a4d19a28d0662a43214484c7215676d2fd9feeb5229" +
  "696bfeac6c5e64a4c055e5565235dd5520696a39cabfd6a79101c3a5efd1b487" +
  "3aa996547334e2b5c79010988ccbefdddbc6e581170037b784665f76ce978350" +
  "3aa996547334e2b5c79010988ccbefdddbc6e581170037b784665f76ce978350" +
  "9267d1ce105276db8fbbbb306b34e8a73e6db7c536b8aa6dc77f065819469edf" +
  "20" +
  "70726f636573732e6b65726e656c2e666978747572652e6c6f6f6b75702e7631" +
  "04" +
  "11000000",
);

const RESULT = fromHex(
  "41424c5f4552533101000000" +
  "e64d11941d799a728a024fe33dce0950d8d3e7182a4a90d4ee1692d43ce07366" +
  "3aa996547334e2b5c79010988ccbefdddbc6e581170037b784665f76ce978350" +
  "04" +
  "1d000000",
);

const REQUEST_FIXED_LENGTH = 236;
const IDENTITY_OFFSET = REQUEST_FIXED_LENGTH + 1;
const IDENTITY_LENGTH = 32;
const PAYLOAD_LENGTH_OFFSET = IDENTITY_OFFSET + IDENTITY_LENGTH;
const RESULT_FIXED_LENGTH = 76;

describe("ABL_ERQ1", () => {
  test("decodes the Boundary v1.7 kernel-produced request exactly", () => {
    const request = decodeEffectRequest(REQUEST);

    expect(Object.isFrozen(request)).toBe(true);
    expect(request.effectSemanticIdentity).toBe(
      "process.kernel.fixture.lookup.v1",
    );
    expect(hex(request.requestIdentityDigest)).toBe(
      "e64d11941d799a728a024fe33dce0950d8d3e7182a4a90d4ee1692d43ce07366",
    );
    expect(hex(request.programTransitionDigest)).toBe(
      "68f82b4dc159dbabf9e87e0532a4bfe8e05d8868c582b789f47e72f4c3128174",
    );
    expect(hex(request.preRequestStateDigest)).toBe(
      "377e7f60b8a67f3b8d2a8a4d19a28d0662a43214484c7215676d2fd9feeb5229",
    );
    expect(hex(request.effectSiteSemanticDigest)).toBe(
      "696bfeac6c5e64a4c055e5565235dd5520696a39cabfd6a79101c3a5efd1b487",
    );
    expect(hex(request.payloadSchemaDigest)).toBe(
      "3aa996547334e2b5c79010988ccbefdddbc6e581170037b784665f76ce978350",
    );
    expect(hex(request.resumeSchemaDigest)).toBe(
      "3aa996547334e2b5c79010988ccbefdddbc6e581170037b784665f76ce978350",
    );
    expect(hex(request.continuationDigest)).toBe(
      "9267d1ce105276db8fbbbb306b34e8a73e6db7c536b8aa6dc77f065819469edf",
    );
    expect([...request.payload]).toEqual([17, 0, 0, 0]);
    expect(hex(request.bytes)).toBe(hex(REQUEST));
  });

  test("owns independent copies of the input and every exposed byte field", () => {
    const input = new Uint8Array(REQUEST);
    const request = decodeEffectRequest(input);
    input.fill(0);

    expect(new TextDecoder().decode(request.bytes.subarray(0, 8))).toBe(
      "ABL_ERQ1",
    );
    request.bytes[12] ^= 0xff;
    expect(request.requestIdentityDigest[0]).toBe(0xe6);
    request.payload[0] ^= 0xff;
    expect(request.bytes.at(-4)).toBe(17);
    request.payloadSchemaDigest[0] ^= 0xff;
    expect(request.resumeSchemaDigest[0]).toBe(0x3a);
  });

  test("accepts genuine Uint8Array bytes from another realm", () => {
    const request = decodeEffectRequest(foreignBytes(REQUEST));
    expect(hex(request.bytes)).toBe(hex(REQUEST));
    expect(request.effectSemanticIdentity).toBe(
      "process.kernel.fixture.lookup.v1",
    );
  });

  test("rejects non-Uint8Array views and spoofed objects", () => {
    for (const value of nonUint8ArrayValues()) {
      expectHostError(
        () => decodeEffectRequest(value),
        "WORLD_EFFECT_REQUEST_INVALID",
        "input-type",
      );
    }
  });

  test("rejects malformed framing, UTF-8, naturals, and digests", () => {
    const cases = [
      [mutate(REQUEST, 0), "magic"],
      [mutate(REQUEST, 8), "format-version"],
      [mutate(REQUEST, 10), "flags"],
      [REQUEST.subarray(0, REQUEST.length - 1), "record-length"],
      [concat(REQUEST, [0]), "record-length"],
      [mutate(REQUEST, 12), "request-identity-digest"],
      [mutate(REQUEST, 108), "effect-semantic-digest"],
      [mutate(REQUEST, IDENTITY_OFFSET), "semantic-identity-utf8"],
      [mutate(REQUEST, REQUEST.length - 1), "request-identity-digest"],
      [
        concat(
          REQUEST.subarray(0, REQUEST_FIXED_LENGTH),
          [0x00],
          REQUEST.subarray(IDENTITY_OFFSET),
        ),
        "semantic-identity-length",
      ],
      [
        concat(
          REQUEST.subarray(0, REQUEST_FIXED_LENGTH),
          [0xa0, 0x00],
          REQUEST.subarray(IDENTITY_OFFSET),
        ),
        "natural-noncanonical",
      ],
      [
        concat(
          REQUEST.subarray(0, PAYLOAD_LENGTH_OFFSET),
          [0x84, 0x00],
          REQUEST.subarray(PAYLOAD_LENGTH_OFFSET + 1),
        ),
        "natural-noncanonical",
      ],
      [
        concat(
          REQUEST.subarray(0, REQUEST_FIXED_LENGTH),
          [0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x02],
        ),
        "natural-overflow",
      ],
      [
        concat(
          REQUEST.subarray(0, REQUEST_FIXED_LENGTH),
          encodeNatural(9_007_199_254_740_992n),
        ),
        "unsafe-length",
      ],
    ];

    for (const [bytes, reason] of cases) {
      expectHostError(
        () => decodeEffectRequest(bytes),
        "WORLD_EFFECT_REQUEST_INVALID",
        reason,
      );
    }
    expectHostError(
      () => decodeEffectRequest("not bytes"),
      "WORLD_EFFECT_REQUEST_INVALID",
      "input-type",
    );
  });
});

describe("ABL_ERS1", () => {
  test("encodes the exact Boundary v1.7 result from bytes or a request view", () => {
    const resume = fromHex("1d000000");
    const fromBytes = encodeEffectResult({ request: REQUEST, resume });
    const fromView = encodeEffectResult({
      request: decodeEffectRequest(REQUEST),
      resume,
    });

    expect(hex(fromBytes)).toBe(hex(RESULT));
    expect(hex(fromView)).toBe(hex(RESULT));
  });

  test("relays request, resume, and result bytes from another realm", () => {
    const encoded = encodeEffectResult({
      request: foreignBytes(REQUEST),
      resume: foreignBytes(fromHex("1d000000")),
    });
    expect(hex(encoded)).toBe(hex(RESULT));

    const decoded = decodeEffectResult(foreignBytes(RESULT));
    expect(hex(decoded.bytes)).toBe(hex(RESULT));
    expect([...decoded.resume]).toEqual([29, 0, 0, 0]);
  });

  test("revalidates request bytes and derives digests from those bytes", () => {
    const request = decodeEffectRequest(REQUEST);
    request.requestIdentityDigest.fill(0);
    request.resumeSchemaDigest.fill(0);
    expect(hex(encodeEffectResult({ request, resume: fromHex("1d000000") }))).toBe(
      hex(RESULT),
    );

    request.bytes[12] ^= 1;
    expectHostError(
      () => encodeEffectResult({ request, resume: fromHex("1d000000") }),
      "WORLD_EFFECT_REQUEST_INVALID",
      "request-identity-digest",
    );
  });

  test("decodes exact framing and owns independent copies", () => {
    const input = new Uint8Array(RESULT);
    const result = decodeEffectResult(input);
    input.fill(0);

    expect(Object.isFrozen(result)).toBe(true);
    expect(hex(result.requestIdentityDigest)).toBe(
      "e64d11941d799a728a024fe33dce0950d8d3e7182a4a90d4ee1692d43ce07366",
    );
    expect(hex(result.resumeSchemaDigest)).toBe(
      "3aa996547334e2b5c79010988ccbefdddbc6e581170037b784665f76ce978350",
    );
    expect([...result.resume]).toEqual([29, 0, 0, 0]);
    result.bytes[12] ^= 0xff;
    expect(result.requestIdentityDigest[0]).toBe(0xe6);
    result.resume[0] ^= 0xff;
    expect(result.bytes.at(-4)).toBe(29);
  });

  test("round-trips an empty opaque resume", () => {
    const bytes = encodeEffectResult({
      request: REQUEST,
      resume: new Uint8Array(),
    });
    const result = decodeEffectResult(bytes);
    expect(result.resume.length).toBe(0);
    expect(bytes.length).toBe(RESULT_FIXED_LENGTH + 1);
  });

  test("rejects malformed framing and noncanonical natural lengths", () => {
    const cases = [
      [mutate(RESULT, 0), "magic"],
      [mutate(RESULT, 8), "format-version"],
      [mutate(RESULT, 10), "flags"],
      [RESULT.subarray(0, RESULT.length - 1), "record-length"],
      [concat(RESULT, [0]), "record-length"],
      [
        concat(
          RESULT.subarray(0, RESULT_FIXED_LENGTH),
          [0x84, 0x00],
          RESULT.subarray(RESULT_FIXED_LENGTH + 1),
        ),
        "natural-noncanonical",
      ],
      [
        concat(
          RESULT.subarray(0, RESULT_FIXED_LENGTH),
          encodeNatural(9_007_199_254_740_992n),
        ),
        "unsafe-length",
      ],
    ];

    for (const [bytes, reason] of cases) {
      expectHostError(
        () => decodeEffectResult(bytes),
        "WORLD_EFFECT_RESULT_INVALID",
        reason,
      );
    }
    expectHostError(
      () => encodeEffectResult({ request: REQUEST, resume: "not bytes" }),
      "WORLD_EFFECT_RESULT_INVALID",
      "input-type",
    );
    for (const value of nonUint8ArrayValues()) {
      expectHostError(
        () => decodeEffectResult(value),
        "WORLD_EFFECT_RESULT_INVALID",
        "input-type",
      );
      expectHostError(
        () => encodeEffectResult({ request: REQUEST, resume: value }),
        "WORLD_EFFECT_RESULT_INVALID",
        "input-type",
      );
    }
  });
});

function foreignBytes(bytes) {
  return runInNewContext("(input) => new Uint8Array(input)")(bytes);
}

function nonUint8ArrayValues() {
  const spoofedTypedArray = new Uint16Array(1);
  Object.defineProperty(spoofedTypedArray, Symbol.toStringTag, {
    value: "Uint8Array",
  });
  return [
    new DataView(new ArrayBuffer(8)),
    new Uint16Array(1),
    spoofedTypedArray,
    {},
    { [Symbol.toStringTag]: "Uint8Array" },
  ];
}

function expectHostError(run, code, reason) {
  let caught;
  try {
    run();
  } catch (error) {
    caught = error;
  }
  expect(caught).toBeInstanceOf(WorldProcessHostError);
  expect(caught.code).toBe(code);
  expect(caught.details.reason).toBe(reason);
  expect(Object.isFrozen(caught.details)).toBe(true);
}

function mutate(bytes, offset) {
  const result = new Uint8Array(bytes);
  result[offset] ^= 0xff;
  return result;
}

function concat(...parts) {
  const values = parts.map((part) =>
    part instanceof Uint8Array ? part : Uint8Array.from(part)
  );
  const result = new Uint8Array(
    values.reduce((length, value) => length + value.length, 0),
  );
  let offset = 0;
  for (const value of values) {
    result.set(value, offset);
    offset += value.length;
  }
  return result;
}

function encodeNatural(value) {
  const result = [];
  let remaining = value;
  do {
    let byte = Number(remaining & 0x7fn);
    remaining >>= 7n;
    if (remaining !== 0n) byte |= 0x80;
    result.push(byte);
  } while (remaining !== 0n);
  return Uint8Array.from(result);
}

function fromHex(value) {
  return new Uint8Array(Buffer.from(value, "hex"));
}

function hex(value) {
  return Buffer.from(value).toString("hex");
}
