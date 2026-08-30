import { createHash } from "node:crypto";

import { worldError } from "./errors.mjs";
import { decodeEffectRequest } from "./effect.mjs";

const OUTCOME_MAGIC = ascii("ABL_PKO1");
const FORMAT_VERSION = 1;
const HEADER_LENGTH = 32;
const MAX_SAFE_LENGTH = BigInt(Number.MAX_SAFE_INTEGER);

const KINDS = Object.freeze({
  0: "Progressed",
  1: "Requested",
  2: "ExplicitlyYielded",
  3: "Completed",
  4: "AuthoredFailure",
  5: "NeedsCapacity",
});

/** Strictly decode one canonical Boundary Process ABI v1 outcome. */
export function decodeProcessOutcome(input) {
  const bytes = snapshotBytes(input);
  if (bytes.length < HEADER_LENGTH) invalidOutcome("record-length");
  requireMagic(bytes);
  if (readU16(bytes, 8) !== FORMAT_VERSION) {
    invalidOutcome("format-version");
  }
  if (bytes[11] !== 0 || !allZero(bytes, 28, 32)) {
    invalidOutcome("reserved");
  }

  const kindTag = bytes[10];
  const kind = KINDS[kindTag];
  if (kind === undefined) invalidOutcome("kind");

  const primaryLength = readU64(bytes, 12);
  const secondaryLength = readU64(bytes, 20);
  const totalLength = BigInt(HEADER_LENGTH) + primaryLength + secondaryLength;
  if (
    primaryLength > MAX_SAFE_LENGTH ||
    secondaryLength > MAX_SAFE_LENGTH ||
    totalLength > MAX_SAFE_LENGTH
  ) {
    invalidOutcome("unsafe-length");
  }
  if (totalLength !== BigInt(bytes.length)) {
    invalidOutcome("record-length");
  }

  const primaryEnd = HEADER_LENGTH + Number(primaryLength);
  const primary = bytes.subarray(HEADER_LENGTH, primaryEnd);
  const secondary = bytes.subarray(primaryEnd);

  switch (kindTag) {
    case 0:
      requireEmptySecondary(secondary);
      return Object.freeze({
        bytes,
        kind,
        state: copy(primary),
      });
    case 1:
      {
        const request = decodeEffectRequest(secondary);
        const stateDigest = new Uint8Array(
          createHash("sha256").update(primary).digest(),
        );
        if (!equalBytes(stateDigest, request.preRequestStateDigest)) {
          invalidOutcome("request-state-digest");
        }
      }
      return Object.freeze({
        bytes,
        kind,
        state: copy(primary),
        request: copy(secondary),
      });
    case 2:
      requireEmptySecondary(secondary);
      return Object.freeze({
        bytes,
        kind,
        state: copy(primary),
      });
    case 3:
      requireEmptySecondary(secondary);
      return Object.freeze({
        bytes,
        kind,
        result: copy(primary),
      });
    case 4:
      requireEmptySecondary(secondary);
      return Object.freeze({
        bytes,
        kind,
        failure: copy(primary),
      });
    case 5:
      if (primary.length !== 32 || secondary.length !== 0) {
        invalidOutcome("kind-shape");
      }
      return Object.freeze({
        bytes,
        kind,
        requirement: Object.freeze({
          minimumInputBytes: readU64(primary, 0),
          minimumOutputBytes: readU64(primary, 8),
          minimumScratchBytes: readU64(primary, 16),
          minimumMemoryPages: readU64(primary, 24),
        }),
      });
    default:
      invalidOutcome("kind");
  }
}

function snapshotBytes(value) {
  if (!(value instanceof Uint8Array)) invalidOutcome("input-type");
  try {
    return new Uint8Array(value);
  } catch {
    invalidOutcome("input-detached");
  }
}

function requireMagic(bytes) {
  for (let index = 0; index < OUTCOME_MAGIC.length; index += 1) {
    if (bytes[index] !== OUTCOME_MAGIC[index]) invalidOutcome("magic");
  }
}

function requireEmptySecondary(secondary) {
  if (secondary.length !== 0) invalidOutcome("kind-shape");
}

function allZero(bytes, start, end) {
  for (let index = start; index < end; index += 1) {
    if (bytes[index] !== 0) return false;
  }
  return true;
}

function readU16(bytes, offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function readU64(bytes, offset) {
  let value = 0n;
  for (let index = 7; index >= 0; index -= 1) {
    value = (value << 8n) | BigInt(bytes[offset + index]);
  }
  return value;
}

function copy(bytes) {
  return new Uint8Array(bytes);
}

function equalBytes(left, right) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

function ascii(value) {
  return new TextEncoder().encode(value);
}

function invalidOutcome(reason) {
  throw worldError(
    "WORLD_PROCESS_OUTCOME_INVALID",
    "invalid Boundary Process outcome",
    { reason },
  );
}
