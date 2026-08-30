import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

import { WorldProcessHostError } from "../src/process_v1/errors.mjs";
import { decodeProcessOutcome } from "../src/process_v1/outcome.mjs";

const REQUESTED_FIXTURE = readRequestedFixture("typed-effect-initial.outcome");
const SPLICED_STATE = readRequestedFixture("effect-morphism.outcome").state;
const REQUESTED_STATE = REQUESTED_FIXTURE.state;
const REQUEST = REQUESTED_FIXTURE.request;

describe("ABL_PKO1", () => {
  test("decodes every v1 outcome kind without interpreting opaque payloads", () => {
    const state = Uint8Array.of(0xde, 0xad);
    const cases = [
      [0, "Progressed", "state", state],
      [1, "Requested", "request", REQUEST],
      [2, "ExplicitlyYielded", "state", state],
      [3, "Completed", "result", new Uint8Array()],
      [4, "AuthoredFailure", "failure", Uint8Array.of(0xfa, 0x11)],
    ];

    for (const [tag, kind, field, expected] of cases) {
      const primary = tag === 1 ? REQUESTED_STATE : expected;
      const secondary = tag === 1 ? REQUEST : new Uint8Array();
      const outcome = decodeProcessOutcome(
        encodeOutcome(tag, primary, secondary),
      );
      expect(outcome.kind).toBe(kind);
      expect(hex(outcome[field])).toBe(hex(expected));
      expect(Object.isFrozen(outcome)).toBe(true);
      expect(Object.keys(outcome).sort()).toEqual(
        tag === 1
          ? ["bytes", "kind", "request", "state"]
          : ["bytes", field, "kind"].sort(),
      );
    }
  });

  test("decodes exact u64 NeedsCapacity requirements as BigInt", () => {
    const primary = new Uint8Array(32);
    const values = [
      0xffff_ffff_ffff_ffffn,
      64n,
      123_456n,
      4096n,
    ];
    const view = new DataView(primary.buffer);
    values.forEach((value, index) => {
      view.setBigUint64(index * 8, value, true);
    });

    const outcome = decodeProcessOutcome(encodeOutcome(5, primary));
    expect(outcome.kind).toBe("NeedsCapacity");
    expect(outcome.requirement).toEqual({
      minimumInputBytes: values[0],
      minimumOutputBytes: values[1],
      minimumScratchBytes: values[2],
      minimumMemoryPages: values[3],
    });
    expect(Object.isFrozen(outcome.requirement)).toBe(true);
    expect(Object.keys(outcome).sort()).toEqual([
      "bytes",
      "kind",
      "requirement",
    ]);
  });

  test("owns independent copies of the input and every exposed byte field", () => {
    const input = new Uint8Array(REQUESTED_FIXTURE.bytes);
    const outcome = decodeProcessOutcome(input);
    input.fill(0);

    expect(new TextDecoder().decode(outcome.bytes.subarray(0, 8))).toBe(
      "ABL_PKO1",
    );
    outcome.bytes[32] ^= 0xff;
    expect(hex(outcome.state)).toBe(hex(REQUESTED_STATE));
    outcome.request[0] ^= 0xff;
    const requestOffset = 32 + REQUESTED_STATE.length;
    expect(new TextDecoder().decode(
      outcome.bytes.subarray(requestOffset, requestOffset + 8),
    )).toBe(
      "ABL_ERQ1",
    );
  });

  test("accepts genuine Uint8Array bytes from another realm", () => {
    const outcome = decodeProcessOutcome(foreignBytes(REQUESTED_FIXTURE.bytes));
    expect(outcome.kind).toBe("Requested");
    expect(hex(outcome.state)).toBe(hex(REQUESTED_STATE));
    expect(hex(outcome.request)).toBe(hex(REQUEST));
  });

  test("rejects non-Uint8Array views and spoofed objects", () => {
    const spoofedTypedArray = new Uint16Array(1);
    Object.defineProperty(spoofedTypedArray, Symbol.toStringTag, {
      value: "Uint8Array",
    });
    for (const value of [
      new DataView(new ArrayBuffer(8)),
      new Uint16Array(1),
      spoofedTypedArray,
      {},
      { [Symbol.toStringTag]: "Uint8Array" },
    ]) {
      expectOutcomeError(() => decodeProcessOutcome(value), "input-type");
    }
  });

  test("rejects malformed headers, lengths, reserved bytes, and kinds", () => {
    const valid = encodeOutcome(0, Uint8Array.of(1));
    const unsafe = new Uint8Array(valid);
    writeU64(unsafe, 12, 9_007_199_254_740_992n);
    const unknown = new Uint8Array(valid);
    unknown[10] = 6;
    const reservedKind = new Uint8Array(valid);
    reservedKind[11] = 1;
    const reservedTail = new Uint8Array(valid);
    reservedTail[31] = 1;
    const wrongLength = new Uint8Array(valid);
    writeU64(wrongLength, 12, 0n);

    const cases = [
      [new Uint8Array(31), "record-length"],
      [mutate(valid, 0), "magic"],
      [mutate(valid, 8), "format-version"],
      [reservedKind, "reserved"],
      [reservedTail, "reserved"],
      [unknown, "kind"],
      [unsafe, "unsafe-length"],
      [wrongLength, "record-length"],
      [concat(valid, [0]), "record-length"],
    ];

    for (const [bytes, reason] of cases) {
      expectOutcomeError(() => decodeProcessOutcome(bytes), reason);
    }
    expectOutcomeError(() => decodeProcessOutcome("not bytes"), "input-type");
  });

  test("enforces each kind's primary and secondary shape", () => {
    for (const kind of [0, 2, 3, 4]) {
      expectOutcomeError(
        () => decodeProcessOutcome(
          encodeOutcome(kind, Uint8Array.of(1), Uint8Array.of(2)),
        ),
        "kind-shape",
      );
    }

    expectOutcomeError(
      () => decodeProcessOutcome(encodeOutcome(5, new Uint8Array(31))),
      "kind-shape",
    );
    expectOutcomeError(
      () => decodeProcessOutcome(
        encodeOutcome(5, new Uint8Array(32), Uint8Array.of(1)),
      ),
      "kind-shape",
    );
  });

  test("validates a Requested ERQ1 but returns its opaque bytes", () => {
    const forged = new Uint8Array(REQUEST);
    forged[12] ^= 1;
    expectHostError(
      () => decodeProcessOutcome(
        encodeOutcome(1, REQUESTED_STATE, forged),
      ),
      "WORLD_EFFECT_REQUEST_INVALID",
      "request-identity-digest",
    );

    const valid = decodeProcessOutcome(REQUESTED_FIXTURE.bytes);
    expect(valid.request).toBeInstanceOf(Uint8Array);
    expect(valid.request.effectSemanticIdentity).toBeUndefined();
    expect(hex(valid.request)).toBe(hex(REQUEST));
  });

  test("binds a Requested ERQ1 to the exact opaque pre-request State", () => {
    const mutatedState = new Uint8Array(REQUESTED_STATE);
    mutatedState[mutatedState.length - 1] ^= 0x01;

    for (const state of [mutatedState, SPLICED_STATE]) {
      expectOutcomeError(
        () => decodeProcessOutcome(encodeOutcome(1, state, REQUEST)),
        "request-state-digest",
      );
    }
  });
});

function foreignBytes(bytes) {
  return runInNewContext("(input) => new Uint8Array(input)")(bytes);
}

function readRequestedFixture(name) {
  const bytes = new Uint8Array(readFileSync(new URL(
    `../conformance/vectors/artifacts/${name}`,
    import.meta.url,
  )));
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const primaryLength = Number(view.getBigUint64(12, true));
  const secondaryLength = Number(view.getBigUint64(20, true));
  const stateEnd = 32 + primaryLength;
  return {
    bytes,
    state: bytes.slice(32, stateEnd),
    request: bytes.slice(stateEnd, stateEnd + secondaryLength),
  };
}

function encodeOutcome(kind, primary, secondary = new Uint8Array()) {
  const result = new Uint8Array(32 + primary.length + secondary.length);
  result.set(new TextEncoder().encode("ABL_PKO1"), 0);
  result[8] = 1;
  result[10] = kind;
  writeU64(result, 12, BigInt(primary.length));
  writeU64(result, 20, BigInt(secondary.length));
  result.set(primary, 32);
  result.set(secondary, 32 + primary.length);
  return result;
}

function writeU64(bytes, offset, value) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  view.setBigUint64(offset, value, true);
}

function expectOutcomeError(run, reason) {
  expectHostError(run, "WORLD_PROCESS_OUTCOME_INVALID", reason);
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

function hex(value) {
  return Buffer.from(value).toString("hex");
}
