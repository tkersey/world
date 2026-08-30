import { describe, expect, test } from "bun:test";

import { WorldProcessHostError } from "../src/process_v1/errors.mjs";
import { decodeProcessOutcome } from "../src/process_v1/outcome.mjs";

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
      const primary = tag === 1 ? state : expected;
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
    const input = encodeOutcome(1, Uint8Array.of(1, 2, 3), REQUEST);
    const outcome = decodeProcessOutcome(input);
    input.fill(0);

    expect(new TextDecoder().decode(outcome.bytes.subarray(0, 8))).toBe(
      "ABL_PKO1",
    );
    outcome.bytes[32] ^= 0xff;
    expect([...outcome.state]).toEqual([1, 2, 3]);
    outcome.request[0] ^= 0xff;
    expect(new TextDecoder().decode(outcome.bytes.subarray(35, 43))).toBe(
      "ABL_ERQ1",
    );
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
        encodeOutcome(1, Uint8Array.of(1), forged),
      ),
      "WORLD_EFFECT_REQUEST_INVALID",
      "request-identity-digest",
    );

    const valid = decodeProcessOutcome(
      encodeOutcome(1, Uint8Array.of(1), REQUEST),
    );
    expect(valid.request).toBeInstanceOf(Uint8Array);
    expect(valid.request.effectSemanticIdentity).toBeUndefined();
    expect(hex(valid.request)).toBe(hex(REQUEST));
  });
});

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

function fromHex(value) {
  return new Uint8Array(Buffer.from(value, "hex"));
}

function hex(value) {
  return Buffer.from(value).toString("hex");
}
