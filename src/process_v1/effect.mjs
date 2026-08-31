import { createHash } from "node:crypto";

import { isUint8Array, worldError } from "./errors.mjs";

const REQUEST_MAGIC = ascii("ABL_ERQ1");
const RESULT_MAGIC = ascii("ABL_ERS1");
const FORMAT_VERSION = 1;
const DIGEST_LENGTH = 32;
const REQUEST_FIXED_LENGTH = 8 + 2 + 2 + 7 * DIGEST_LENGTH;
const RESULT_FIXED_LENGTH = 8 + 2 + 2 + 2 * DIGEST_LENGTH;
const MAX_SAFE_LENGTH = BigInt(Number.MAX_SAFE_INTEGER);
const UTF8_DECODER = new TextDecoder("utf-8", {
  fatal: true,
  ignoreBOM: true,
});

const EFFECT_SEMANTIC_DOMAIN = ascii(
  "boundary-effect-site-semantic-contract-v1",
);
const SINGLE_RESUME = ascii("single-resume");
const REQUEST_IDENTITY_DOMAIN = ascii(
  "boundary-process-request-identity-v1\0",
);

/** Strictly decode one canonical Boundary Process ABI v1 EffectRequest. */
export function decodeEffectRequest(input) {
  const bytes = snapshotBytes(input, invalidRequest);
  if (bytes.length < REQUEST_FIXED_LENGTH + 2) {
    invalidRequest("record-length");
  }
  requireMagic(bytes, REQUEST_MAGIC, invalidRequest);
  if (readU16(bytes, 8) !== FORMAT_VERSION) {
    invalidRequest("format-version");
  }
  if (readU16(bytes, 10) !== 0) {
    invalidRequest("flags");
  }

  let cursor = 12;
  const requestIdentityDigest = takeDigest(bytes, cursor);
  cursor += DIGEST_LENGTH;
  const programTransitionDigest = takeDigest(bytes, cursor);
  cursor += DIGEST_LENGTH;
  const preRequestStateDigest = takeDigest(bytes, cursor);
  cursor += DIGEST_LENGTH;
  const effectSiteSemanticDigest = takeDigest(bytes, cursor);
  cursor += DIGEST_LENGTH;
  const payloadSchemaDigest = takeDigest(bytes, cursor);
  cursor += DIGEST_LENGTH;
  const resumeSchemaDigest = takeDigest(bytes, cursor);
  cursor += DIGEST_LENGTH;
  const continuationDigest = takeDigest(bytes, cursor);
  cursor += DIGEST_LENGTH;

  const identityNatural = readNatural(bytes, cursor, invalidRequest);
  cursor += identityNatural.byteLength;
  const identityLength = safeLength(identityNatural.value, invalidRequest);
  if (identityLength === 0 || identityLength > bytes.length - cursor) {
    invalidRequest("semantic-identity-length");
  }
  const identityBytes = bytes.subarray(cursor, cursor + identityLength);
  cursor += identityLength;

  let effectSemanticIdentity;
  try {
    effectSemanticIdentity = UTF8_DECODER.decode(identityBytes);
  } catch {
    invalidRequest("semantic-identity-utf8");
  }

  const payloadNatural = readNatural(bytes, cursor, invalidRequest);
  cursor += payloadNatural.byteLength;
  const payloadLength = safeLength(payloadNatural.value, invalidRequest);
  if (payloadLength !== bytes.length - cursor) {
    invalidRequest("record-length");
  }
  const payload = bytes.subarray(cursor);

  const expectedEffectSemanticDigest = effectSemanticDigest(
    identityBytes,
    payloadSchemaDigest,
    resumeSchemaDigest,
  );
  if (!equalBytes(effectSiteSemanticDigest, expectedEffectSemanticDigest)) {
    invalidRequest("effect-semantic-digest");
  }

  const expectedRequestIdentity = requestIdentityDigestFor({
    programTransitionDigest,
    preRequestStateDigest,
    effectSiteSemanticDigest,
    payloadSchemaDigest,
    resumeSchemaDigest,
    continuationDigest,
    identityBytes,
    payload,
  });
  if (!equalBytes(requestIdentityDigest, expectedRequestIdentity)) {
    invalidRequest("request-identity-digest");
  }

  return Object.freeze({
    bytes,
    requestIdentityDigest: copy(requestIdentityDigest),
    programTransitionDigest: copy(programTransitionDigest),
    preRequestStateDigest: copy(preRequestStateDigest),
    effectSiteSemanticDigest: copy(effectSiteSemanticDigest),
    payloadSchemaDigest: copy(payloadSchemaDigest),
    resumeSchemaDigest: copy(resumeSchemaDigest),
    continuationDigest: copy(continuationDigest),
    effectSemanticIdentity,
    payload: copy(payload),
  });
}

/**
 * Encode the exact ABL_ERS1 result framing for one validated request.
 * Resume bytes remain opaque; the Boundary kernel owns typed validation.
 */
export function encodeEffectResult(input) {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    invalidResult("input-type");
  }

  const requestBytes = snapshotRequestBytes(input.request);
  const resume = snapshotBytes(input.resume, invalidResult);
  const request = decodeEffectRequest(requestBytes);
  const natural = encodeNatural(BigInt(resume.length));

  if (resume.length > Number.MAX_SAFE_INTEGER - RESULT_FIXED_LENGTH - natural.length) {
    invalidResult("unsafe-length");
  }
  const bytes = new Uint8Array(
    RESULT_FIXED_LENGTH + natural.length + resume.length,
  );
  let cursor = 0;
  cursor = append(bytes, cursor, RESULT_MAGIC);
  writeU16(bytes, cursor, FORMAT_VERSION);
  cursor += 2;
  writeU16(bytes, cursor, 0);
  cursor += 2;
  cursor = append(bytes, cursor, request.requestIdentityDigest);
  cursor = append(bytes, cursor, request.resumeSchemaDigest);
  cursor = append(bytes, cursor, natural);
  append(bytes, cursor, resume);

  return bytes;
}

/** Strictly decode one canonical Boundary Process ABI v1 EffectResult. */
export function decodeEffectResult(input) {
  const bytes = snapshotBytes(input, invalidResult);
  if (bytes.length < RESULT_FIXED_LENGTH + 1) {
    invalidResult("record-length");
  }
  requireMagic(bytes, RESULT_MAGIC, invalidResult);
  if (readU16(bytes, 8) !== FORMAT_VERSION) {
    invalidResult("format-version");
  }
  if (readU16(bytes, 10) !== 0) {
    invalidResult("flags");
  }

  let cursor = 12;
  const requestIdentityDigest = takeDigest(bytes, cursor);
  cursor += DIGEST_LENGTH;
  const resumeSchemaDigest = takeDigest(bytes, cursor);
  cursor += DIGEST_LENGTH;
  const resumeNatural = readNatural(bytes, cursor, invalidResult);
  cursor += resumeNatural.byteLength;
  const resumeLength = safeLength(resumeNatural.value, invalidResult);
  if (resumeLength !== bytes.length - cursor) {
    invalidResult("record-length");
  }

  return Object.freeze({
    bytes,
    requestIdentityDigest: copy(requestIdentityDigest),
    resumeSchemaDigest: copy(resumeSchemaDigest),
    resume: copy(bytes.subarray(cursor)),
  });
}

function effectSemanticDigest(identityBytes, payloadSchema, resumeSchema) {
  const hash = createHash("sha256");
  updateSemanticBytes(hash, EFFECT_SEMANTIC_DOMAIN);
  updateSemanticBytes(hash, identityBytes);
  hash.update(payloadSchema);
  hash.update(resumeSchema);
  updateSemanticBytes(hash, SINGLE_RESUME);
  return new Uint8Array(hash.digest());
}

function requestIdentityDigestFor(input) {
  const payloadDigest = createHash("sha256").update(input.payload).digest();
  const hash = createHash("sha256");
  hash.update(REQUEST_IDENTITY_DOMAIN);
  hash.update(input.programTransitionDigest);
  hash.update(input.preRequestStateDigest);
  hash.update(input.effectSiteSemanticDigest);
  hash.update(u64Little(BigInt(input.identityBytes.length)));
  hash.update(input.identityBytes);
  hash.update(input.payloadSchemaDigest);
  hash.update(payloadDigest);
  hash.update(input.continuationDigest);
  hash.update(input.resumeSchemaDigest);
  return new Uint8Array(hash.digest());
}

function updateSemanticBytes(hash, bytes) {
  hash.update(u64Little(BigInt(bytes.length)));
  hash.update(bytes);
}

function snapshotRequestBytes(request) {
  if (isUint8Array(request)) return snapshotBytes(request, invalidRequest);
  if (request === null || typeof request !== "object" || Array.isArray(request)) {
    invalidRequest("input-type");
  }
  return snapshotBytes(request.bytes, invalidRequest);
}

function snapshotBytes(value, invalid) {
  if (!isUint8Array(value)) invalid("input-type");
  try {
    return new Uint8Array(value);
  } catch {
    invalid("input-detached");
  }
}

function readNatural(bytes, offset, invalid) {
  let value = 0n;
  for (let index = 0; index < 10; index += 1) {
    if (offset + index >= bytes.length) invalid("natural-truncated");
    const byte = bytes[offset + index];
    const payload = BigInt(byte & 0x7f);
    if (index === 9 && payload > 1n) invalid("natural-overflow");
    value |= payload << BigInt(index * 7);
    if ((byte & 0x80) === 0) {
      const byteLength = index + 1;
      if (naturalEncodedLength(value) !== byteLength) {
        invalid("natural-noncanonical");
      }
      return { value, byteLength };
    }
  }
  invalid("natural-overflow");
}

function encodeNatural(value) {
  const bytes = new Uint8Array(naturalEncodedLength(value));
  let remaining = value;
  for (let index = 0; index < bytes.length; index += 1) {
    let byte = Number(remaining & 0x7fn);
    remaining >>= 7n;
    if (remaining !== 0n) byte |= 0x80;
    bytes[index] = byte;
  }
  return bytes;
}

function naturalEncodedLength(value) {
  let remaining = value;
  let length = 1;
  while (remaining >= 0x80n) {
    remaining >>= 7n;
    length += 1;
  }
  return length;
}

function safeLength(value, invalid) {
  if (value > MAX_SAFE_LENGTH) invalid("unsafe-length");
  return Number(value);
}

function requireMagic(bytes, magic, invalid) {
  for (let index = 0; index < magic.length; index += 1) {
    if (bytes[index] !== magic[index]) invalid("magic");
  }
}

function takeDigest(bytes, offset) {
  return bytes.subarray(offset, offset + DIGEST_LENGTH);
}

function equalBytes(left, right) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

function readU16(bytes, offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function writeU16(bytes, offset, value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = value >>> 8;
}

function u64Little(value) {
  const bytes = new Uint8Array(8);
  let remaining = value;
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number(remaining & 0xffn);
    remaining >>= 8n;
  }
  return bytes;
}

function append(output, offset, bytes) {
  output.set(bytes, offset);
  return offset + bytes.length;
}

function copy(bytes) {
  return new Uint8Array(bytes);
}

function ascii(value) {
  return new TextEncoder().encode(value);
}

function invalidRequest(reason) {
  throw worldError(
    "WORLD_EFFECT_REQUEST_INVALID",
    "invalid Boundary Process effect request",
    { reason },
  );
}

function invalidResult(reason) {
  throw worldError(
    "WORLD_EFFECT_RESULT_INVALID",
    "invalid Boundary Process effect result",
    { reason },
  );
}
