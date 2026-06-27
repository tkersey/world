import { encodeCanonicalValueImage, u64WordBytes } from './world_loaded_value_codec.mjs';

export const operationBoot = 0;
export const operationRestore = 1;
export const operationContinue = 2;
export const operationReplay = 3;
export const operationVerify = 4;
export const operationInspect = 5;
export const operationCancel = 6;
export const operationReset = 7;

export const resolutionResponded = 0;
export const resolutionRejected = 1;
export const resolutionFailed = 2;
export const resolutionPending = 3;
export const resolutionDeferred = 4;
export const resolutionCancelled = 5;

export function encodeBootTurnInput({ manifestFingerprint, metadata = '' }) {
  return encodeTurnInput({
    operation: operationBoot,
    manifestFingerprint,
    turnSequenceNumber: 0n,
    hostMetadata: metadata,
  });
}

export function encodeContinueTurnInput({ manifestFingerprint, previousTurnReceiptFingerprint, turnSequenceNumber, resolutions, metadata = '' }) {
  return encodeTurnInput({
    operation: operationContinue,
    manifestFingerprint,
    previousTurnReceiptFingerprint,
    turnSequenceNumber,
    resolutions,
    hostMetadata: metadata,
  });
}

export function encodeResolutionInput({ request, responseFingerprint = 0x600d0001n, status = resolutionResponded, metadata = 'fixture-response' }) {
  const responseValueImageBytes = status === resolutionResponded
    ? encodeCanonicalValueImage({
        boundaryValueFingerprint: request.expectedResponseValueRefFingerprint,
        codecSchemaDescriptorFingerprint: request.expectedResponseSchemaRefFingerprint,
        bytes: u64WordBytes(responseFingerprint),
        dynamicSize: false,
      })
    : new Uint8Array();
  return {
    targetHostRequestFingerprint: request.requestFingerprint,
    status,
    responseValueImageBytes,
    hostClaimBytes: utf8('host-claim:fixture'),
    attemptNumber: 1,
    metadata: utf8(metadata),
  };
}

export function encodeTurnInput({
  operation,
  manifestFingerprint,
  expectedParentClosureFingerprint = null,
  expectedParentStateFingerprint = null,
  previousTurnReceiptFingerprint = null,
  turnSequenceNumber,
  rootArgumentImages = [],
  parentTurnClosureBytes = new Uint8Array(),
  resolutions = [],
  receiverEvidenceFingerprints = [],
  retention = null,
  deterministicTurnBudget = 0n,
  requestedEvidenceProfile = 1,
  hostMetadata = '',
  allowDuplicateResolutionTargets = false,
}) {
  const sortedResolutions = [...resolutions].sort((left, right) =>
    compareU64(left.targetHostRequestFingerprint, right.targetHostRequestFingerprint));
  for (let i = 1; i < sortedResolutions.length; i += 1) {
    if (!allowDuplicateResolutionTargets && toU64(sortedResolutions[i - 1].targetHostRequestFingerprint) === toU64(sortedResolutions[i].targetHostRequestFingerprint)) {
      throw new Error('duplicate resolution target');
    }
  }
  return concat([
    u32(2),
    u8(operation),
    u64(manifestFingerprint),
    optionalU64(expectedParentClosureFingerprint),
    optionalU64(expectedParentStateFingerprint),
    optionalU64(previousTurnReceiptFingerprint),
    u64(turnSequenceNumber),
    byteSlices(rootArgumentImages),
    bytes(parentTurnClosureBytes),
    resolutionInputs(sortedResolutions),
    u64Slice(receiverEvidenceFingerprints),
    optionalRetentionInput(retention),
    u64(deterministicTurnBudget),
    u8(requestedEvidenceProfile),
    bytes(hostMetadata),
  ]);
}

export function decodeRuntimeManifest(text) {
  return parseManifestText(text);
}

export function decodeApplianceManifest(bytes) {
  const reader = new BinaryReader(bytes);
  const manifest = {
    formatVersion: reader.u32(),
    fingerprintVersion: reader.u32(),
    manifestFingerprint: reader.u64(),
    abiVersion: reader.u32(),
    rootTargetRefFingerprint: reader.u64(),
    rootWorldSurfaceFingerprint: reader.u64(),
    rootTargetCertificateFingerprint: reader.u64(),
  };
  return { ...manifest, trailingBytes: reader.remaining() };
}

export function decodeHostRequest(reader) {
  const request = {
    requestFormatVersion: reader.u32(),
    requestFingerprintVersion: reader.u32(),
    requestFingerprint: reader.u64(),
    turnSequenceNumber: reader.u64(),
    requestOrdinal: reader.u32(),
    runHandleFingerprint: reader.u64(),
    pendingPortFingerprint: reader.u64(),
    worldPortId: reader.u32(),
    targetRefFingerprint: reader.u64(),
    worldSurfaceFingerprint: reader.u64(),
    actuatorRefFingerprint: reader.u64(),
    actuationClass: reader.u8(),
    allowedResponseStatuses: reader.u8(),
    intentFingerprint: reader.u64(),
    envelopeFingerprint: reader.u64(),
    decisionFingerprint: reader.u64(),
    expectedResponseDescriptorFingerprint: reader.u64(),
    idempotencyKeyFingerprint: reader.u64(),
    supervisionRefFingerprint: reader.optionalU64(),
    metadata: reader.bytes(),
    frameRequestBytes: reader.bytes(),
    payloadValueImageBytes: reader.bytes(),
    payloadValueRefFingerprint: reader.optionalU64(),
    payloadSchemaRefFingerprint: reader.optionalU64(),
    expectedResponseValueRefFingerprint: reader.optionalU64(),
    expectedResponseSchemaRefFingerprint: reader.optionalU64(),
    preparedActuationEvidenceBytes: reader.bytes(),
    idempotencyKeyBytes: reader.bytes(),
  };
  return request;
}

export class BinaryReader {
  constructor(bytes) {
    this.bytesValue = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    this.offset = 0;
    this.view = new DataView(this.bytesValue.buffer, this.bytesValue.byteOffset, this.bytesValue.byteLength);
  }

  u8() {
    this.require(1);
    const value = this.view.getUint8(this.offset);
    this.offset += 1;
    return value;
  }

  u32() {
    this.require(4);
    const value = this.view.getUint32(this.offset, true);
    this.offset += 4;
    return value;
  }

  u64() {
    this.require(8);
    const lo = BigInt(this.view.getUint32(this.offset, true));
    const hi = BigInt(this.view.getUint32(this.offset + 4, true));
    this.offset += 8;
    return (hi << 32n) | lo;
  }

  optionalU64() {
    const tag = this.u8();
    if (tag === 0) return null;
    if (tag !== 1) throw new Error('invalid optional u64 tag');
    return this.u64();
  }

  bytes() {
    const len = this.u32();
    this.require(len);
    const out = this.bytesValue.slice(this.offset, this.offset + len);
    this.offset += len;
    return out;
  }

  bytesLen() {
    return this.bytes().length;
  }

  u64Slice() {
    const count = Number(this.u64());
    const values = [];
    for (let i = 0; i < count; i += 1) values.push(this.u64());
    return values;
  }

  skipU64Slice() {
    this.u64Slice();
  }

  skipByteSlices() {
    const count = Number(this.u64());
    for (let i = 0; i < count; i += 1) this.bytesLen();
  }

  skipQuiescence() {
    this.u64();
    this.u8();
    for (let i = 0; i < 9; i += 1) this.u64();
  }

  skipCheckpoint() {
    this.u32();
    this.u32();
    this.u64();
    this.u64();
    this.u64();
    this.u64();
    this.optionalU64();
    this.bytesLen();
    this.optionalU64();
    this.optionalU64();
    this.optionalU64();
    this.optionalU64();
    this.skipOptionalCursor();
    this.skipOptionalCursor();
    this.u8();
    this.optionalU64();
    const outstanding = Number(this.u64());
    for (let i = 0; i < outstanding; i += 1) decodeHostRequest(this);
    this.u8();
    this.bytesLen();
  }

  skipOptionalCursor() {
    const tag = this.u8();
    if (tag === 0) return;
    if (tag !== 1) throw new Error('invalid optional cursor tag');
    this.u32();
    this.u64();
    this.u64();
    this.optionalU64();
    this.u64();
    this.u64();
    this.u64();
    this.bytesLen();
  }

  readTurnReceipt() {
    const receipt = {
      formatVersion: this.u32(),
      fingerprintVersion: this.u32(),
      receiptFingerprint: this.u64(),
      manifestFingerprint: this.u64(),
      turnSequenceNumber: this.u64(),
      commandFingerprint: this.u64(),
      priorCheckpointFingerprint: this.optionalU64(),
      appliedHostReplyFingerprints: this.u64Slice(),
      emittedHostRequestFingerprints: this.u64Slice(),
      sourceCapsuleFingerprint: this.optionalU64(),
      resultingCapsuleFingerprint: this.u64(),
      archiveAppendBatchFingerprint: this.optionalU64(),
      resultingArchiveMomentFingerprint: this.optionalU64(),
      resultingArchiveSealFingerprint: this.optionalU64(),
      resultingChronicleCursorFingerprint: this.optionalU64(),
      rootResultFingerprint: this.optionalU64(),
      status: this.u8(),
      runReceiptFingerprint: this.optionalU64(),
      blockerCount: this.u64(),
      warningCount: this.u64(),
    };
    return receipt;
  }

  remaining() {
    return this.bytesValue.length - this.offset;
  }

  require(len) {
    if (len < 0 || this.offset + len > this.bytesValue.length) throw new Error('truncated wire bytes');
  }
}

function resolutionInputs(values) {
  return concat([u64(values.length), ...values.map((value) => concat([
    u32(1),
    u64(value.targetHostRequestFingerprint),
    u8(value.status),
    bytes(value.responseValueImageBytes ?? new Uint8Array()),
    bytes(value.hostClaimBytes ?? new Uint8Array()),
    u32(value.attemptNumber ?? 0),
    bytes(value.metadata ?? new Uint8Array()),
  ]))]);
}

function optionalRetentionInput(value) {
  if (value == null) return u8(0);
  return concat([
    u8(1),
    u32(1),
    u64(value.priorArchiveAppendBatchFingerprint),
    u64(value.resultingMomentFingerprint),
    u64(value.resultingSealFingerprint),
    u64(value.resultingChronicleCursorFingerprint),
    u8(value.hostRetentionStatus),
    bytes(value.metadata ?? new Uint8Array()),
  ]);
}

function byteSlices(values) {
  return concat([u64(values.length), ...values.map(bytes)]);
}

function u64Slice(values) {
  return concat([u64(values.length), ...values.map(u64)]);
}

function optionalU64(value) {
  return value == null ? u8(0) : concat([u8(1), u64(value)]);
}

function bytes(value) {
  const actual = bytesOf(value);
  return concat([u32(actual.length), actual]);
}

function u8(value) {
  return Uint8Array.of(Number(value) & 0xff);
}

function u32(value) {
  const out = new Uint8Array(4);
  new DataView(out.buffer).setUint32(0, Number(value), true);
  return out;
}

function u64(value) {
  const out = new Uint8Array(8);
  const actual = toU64(value);
  const view = new DataView(out.buffer);
  view.setUint32(0, Number(actual & 0xffff_ffffn), true);
  view.setUint32(4, Number((actual >> 32n) & 0xffff_ffffn), true);
  return out;
}

function utf8(value) {
  return new TextEncoder().encode(value);
}

function bytesOf(value) {
  if (value instanceof Uint8Array) return value;
  if (typeof value === 'string') return utf8(value);
  if (ArrayBuffer.isView(value)) return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  if (Array.isArray(value)) return Uint8Array.from(value);
  throw new Error('expected byte-like value');
}

function concat(chunks) {
  const normalized = chunks.map(bytesOf);
  const total = normalized.reduce((sum, chunk) => sum + chunk.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of normalized) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

function compareU64(left, right) {
  const a = toU64(left);
  const b = toU64(right);
  return a < b ? -1 : a > b ? 1 : 0;
}

function toU64(value) {
  return BigInt.asUintN(64, BigInt(value));
}

function parseManifestText(text) {
  const values = new Map();
  let lineNumber = 0;
  for (const line of text.split('\n')) {
    lineNumber += 1;
    if (line.length === 0) continue;
    const index = line.indexOf('=');
    if (index <= 0) {
      if (lineNumber === 1) {
        values.set('format', line);
        continue;
      }
      throw new Error(`malformed manifest line: ${line}`);
    }
    values.set(line.slice(0, index), line.slice(index + 1));
  }
  return values;
}
