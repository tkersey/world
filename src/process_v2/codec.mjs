// Copyright (c) 2026 World contributors. MIT license.
import { createHash } from "node:crypto";
import { isUint8Array } from "./errors.mjs";
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
const MAX_U64 = (1n << 64n) - 1n;

function snapshotBytes(value) {
  if (!isUint8Array(value)) throw new TypeError("expected bytes");
  // The typed-array constructor copies intrinsic view bytes without invoking
  // caller-defined iterators, properties, subarray methods or species.
  return new Uint8Array(value);
}

export function natural(value) {
  if (typeof value === "number" && !Number.isSafeInteger(value)) throw new RangeError("inexact integer");
  let remaining = BigInt(value);
  if (remaining < 0n || remaining > MAX_U64) throw new RangeError("u64 overflow");
  const bytes = [];
  do {
    const low = Number(remaining & 127n);
    remaining >>= 7n;
    bytes.push(low | (remaining ? 128 : 0));
  } while (remaining);
  return Uint8Array.from(bytes);
}

export function concat(...parts) {
  const length = parts.reduce((sum, part) => sum + part.length, 0);
  if (!Number.isSafeInteger(length)) throw new RangeError("byte length overflow");
  const output = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) { output.set(part, offset); offset += part.length; }
  return output;
}

export function field(bytes) { return concat(natural(bytes.length), bytes); }
export function frame(magic, body) {
  if (!/^ABL_(BPI|PST|PKI|PKO|ERQ|ERS)2$/.test(magic)) throw new Error("InvalidFamily");
  const header = new Uint8Array(20);
  header.set(encoder.encode(magic));
  const view = new DataView(header.buffer);
  view.setUint16(8, 2, true);
  view.setBigUint64(12, BigInt(body.length), true);
  return concat(header, body);
}

export function body(magic, bytes) {
  if (!isUint8Array(bytes)) throw new Error("Truncated");
  bytes = snapshotBytes(bytes);
  if (bytes.length < 20) throw new Error("Truncated");
  const actual = decoder.decode(bytes.subarray(0, 8));
  if (/^ABL_(BPI|PST|PKI|PKO|ERQ|ERS)1$/.test(actual)) throw new Error("UnsupportedFamily");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (actual !== magic) throw new Error("InvalidFamily");
  if (view.getUint16(8, true) !== 2) throw new Error("UnsupportedVersion");
  if (view.getUint16(10, true) !== 0) throw new Error("InvalidFlags");
  if (view.getBigUint64(12, true) !== BigInt(bytes.length - 20)) throw new Error("InvalidLength");
  return bytes.subarray(20);
}

export class Reader {
  constructor(bytes) { this.bytes = snapshotBytes(bytes); this.position = 0; }
  take(length) {
    if (!Number.isSafeInteger(length) || length < 0 || this.position < 0 || this.position > this.bytes.length || length > this.bytes.length - this.position) throw new Error("Truncated");
    const start = this.position;
    this.position += length;
    return new Uint8Array(this.bytes.subarray(start, this.position));
  }
  natural() {
    let value = 0n;
    for (let index = 0; index < 10; index++) {
      if (this.position >= this.bytes.length) throw new Error("Truncated");
      const byte = this.bytes[this.position++];
      if (index === 9 && byte > 1) throw new Error("InvalidLength");
      value |= BigInt(byte & 127) << BigInt(7 * index);
      if (!(byte & 128)) {
        if (index && byte === 0) throw new Error("NonCanonical");
        return value;
      }
    }
    throw new Error("InvalidLength");
  }
  field() {
    const length = this.natural();
    if (length > BigInt(this.bytes.length - this.position)) throw new Error("Truncated");
    return this.take(Number(length));
  }
  finish() { if (this.position !== this.bytes.length) throw new Error("NonCanonical"); }
}

export function encodeInput({ mode = "advance", image, initialArgs, state, result, cancel }) {
  if (mode !== "advance" && mode !== "run") throw new Error("InvalidMode");
  if ((initialArgs !== undefined) === (state !== undefined)) throw new Error("InvalidInstance");
  if (result !== undefined && cancel !== undefined) throw new Error("InvalidControl");
  if (initialArgs !== undefined && (cancel !== undefined || result !== undefined)) throw new Error("InvalidControl");
  const instance = initialArgs === undefined ? concat(natural(1), field(snapshotBytes(state))) : concat(natural(0), field(snapshotBytes(initialArgs)));
  let control;
  if (cancel !== undefined) {
    if (typeof cancel === "string" && !cancel.isWellFormed()) throw new Error("InvalidUtf8");
    const reason = typeof cancel === "string" ? concat(natural(0), field(encoder.encode(cancel))) : concat(natural(1), field(snapshotBytes(cancel)));
    control = concat(natural(1), reason);
  } else {
    control = concat(natural(0), natural(result === undefined ? 0 : 1), result === undefined ? new Uint8Array() : field(snapshotBytes(result)));
  }
  return frame("ABL_PKI2", concat(natural(mode === "advance" ? 0 : 1), field(snapshotBytes(image)), instance, control));
}

export function decodeOutcome(bytes) {
  const reader = new Reader(body("ABL_PKO2", bytes));
  const tag = reader.natural();
  let result;
  if (tag === 0n) result = { kind: "Progressed", state: reader.field() };
  else if (tag === 1n) result = { kind: "Requested", state: reader.field(), request: reader.field() };
  else if (tag === 2n) result = { kind: "Yielded", state: reader.field() };
  else if (tag === 3n) result = { kind: "Completed", value: reader.field() };
  else if (tag === 4n) {
    result = { kind: "Failed", value: reader.field(), cleanupFailures: readFailures(reader) };
    const optional = reader.natural();
    if (optional > 1n) throw new Error("InvalidTag");
    if (optional === 1n) result.cancellation = readReason(reader);
  } else if (tag === 5n) result = { kind: "Cancelled", reason: readReason(reader), cleanupFailures: readFailures(reader) };
  else if (tag === 6n) {
    const arenas = ["input", "working", "output", "memory"];
    const arena = reader.natural();
    if (arena >= BigInt(arenas.length)) throw new Error("InvalidTag");
    result = { kind: "NeedsCapacity", arena: arenas[Number(arena)] };
    for (const key of ["input", "working", "output", "memoryPages"]) {
      const minimum = reader.natural();
      const provenance = reader.natural();
      if (provenance > 2n) throw new Error("InvalidTag");
      result[key] = { minimum, provenance: ["not_observed", "exact", "lower_bound"][Number(provenance)] };
    }
  } else throw new Error("InvalidTag");
  reader.finish();
  if (result.state) {
    const snapshot = body("ABL_PST2", result.state);
    if (snapshot.length < 32) throw new Error("Truncated");
    if (result.request) {
      const request = decodeRequest(result.request);
      if (!same(request.pendingStateDigest, digest(result.state)) || !same(request.programIdentity, snapshot.subarray(0, 32))) throw new Error("InvalidRequest");
    }
  }
  return result;
}

function readReason(reader) {
  const tag = reader.natural();
  if (tag > 1n) throw new Error("InvalidTag");
  const bytes = reader.field();
  return tag === 0n ? decoder.decode(bytes) : bytes;
}
function readFailures(reader) {
  const encoded = new Reader(reader.field());
  const count = encoded.natural();
  if (count > BigInt(encoded.bytes.length - encoded.position)) throw new Error("Truncated");
  const failures = [];
  for (let index = 0n; index < count; index++) failures.push(encoded.field());
  encoded.finish();
  return failures;
}

function digest(bytes) { return new Uint8Array(createHash("sha256").update(bytes).digest()); }
function same(a, b) { return a.length === b.length && a.every((byte, index) => byte === b[index]); }
function domainHash(domain, ...fields) { return digest(concat(encoder.encode(domain), ...fields.map(field))); }

export function decodeRequest(bytes) {
  const reader = new Reader(body("ABL_ERQ2", bytes));
  const request = {
    programIdentity: reader.take(32), pendingStateDigest: reader.take(32),
    residualContractDigest: reader.take(32), continuationBindingDigest: reader.take(32),
    semanticIdentityBytes: reader.field(), payloadSchema: reader.field(), resumeSchema: reader.field(), payload: reader.field(),
    requestIdentity: reader.take(32),
  };
  reader.finish();
  request.semanticIdentity = decoder.decode(request.semanticIdentityBytes);
  if (request.semanticIdentityBytes.length === 0) throw new Error("InvalidRequest");
  const contract = domainHash("boundary.residual-contract/v2", request.semanticIdentityBytes, request.payloadSchema, request.resumeSchema);
  const identity = domainHash("boundary.effect-request/v2", request.programIdentity, request.pendingStateDigest,
    request.residualContractDigest, request.continuationBindingDigest, request.semanticIdentityBytes,
    request.payloadSchema, request.resumeSchema, request.payload);
  if (!same(contract, request.residualContractDigest) || !same(identity, request.requestIdentity)) throw new Error("InvalidRequest");
  validateValue(request.payloadSchema, request.payload);
  decodeSchema(request.resumeSchema);
  return request;
}

export function encodeResult(requestBytes, value) {
  const request = decodeRequest(requestBytes);
  if (!isUint8Array(value)) throw new TypeError("result must be canonical value bytes");
  value = snapshotBytes(value);
  validateValue(request.resumeSchema, value);
  return frame("ABL_ERS2", concat(request.requestIdentity, digest(request.resumeSchema), field(value)));
}

function decodeSchema(bytes) {
  const reader = new Reader(bytes);
  bytes = reader.bytes;
  if (reader.natural() !== 0n) throw new Error("NonCanonical");
  const count = reader.natural();
  if (count === 0n || count > BigInt(bytes.length - reader.position)) throw new Error("InvalidSchema");
  const index = () => {
    const id = reader.natural();
    if (id >= count) throw new Error("InvalidSchema");
    return Number(id);
  };
  const types = [];
  for (let i = 0; i < Number(count); i++) {
    const tag = Number(reader.natural());
    const type = { tag, children: [], minimum: MAX_U64 };
    if (tag <= 11) type.minimum = BigInt([0, 1, 1, 2, 4, 8, 1, 2, 4, 8, 1, 1][tag]);
    else if (tag === 12 || tag === 13) {
      const length = reader.natural();
      if (length > BigInt(bytes.length - reader.position) || (tag === 13 && length === 0n)) throw new Error("InvalidSchema");
      for (let j = 0; j < Number(length); j++) type.children.push(index());
    } else if (tag === 14 || tag === 15 || tag === 17) {
      type.children.push(index());
      if (tag === 15) type.maximum = reader.natural();
      if (tag === 17) type.length = reader.natural();
      else type.minimum = 1n;
    } else if (tag === 18 || tag === 19) {
      type.maximum = reader.natural();
      type.minimum = 1n;
    } else if (tag === 20) {
      const length = reader.natural();
      if (length > BigInt(bytes.length - reader.position)) throw new Error("InvalidSchema");
      type.members = [];
      for (let j = 0; j < Number(length); j++) {
        const value = reader.natural();
        if (value > 0xffffffffn || (j > 0 && type.members[j - 1] >= value)) throw new Error("InvalidSchema");
        type.members.push(value);
      }
      type.minimum = 4n;
    } else throw new Error("InvalidSchema");
    types.push(type);
  }
  reader.finish();
  let changed = true;
  while (changed) {
    changed = false;
    for (const type of types) {
      const minimum = type.tag === 12 ? type.children.reduce((sum, id) => sum + types[id].minimum, 0n)
        : type.tag === 13 ? 1n + type.children.reduce((min, id) => types[id].minimum < min ? types[id].minimum : min, MAX_U64)
        : type.tag === 17 ? type.length * types[type.children[0]].minimum : type.minimum;
      if (minimum < type.minimum) { type.minimum = minimum; changed = true; }
    }
  }
  if (types.some((type) => type.minimum === MAX_U64)) throw new Error("InvalidSchema");
  let classes = types.map(() => 0);
  while (true) {
    const representatives = new Map();
    const next = types.map((type, i) => {
      const key = [type.tag, String(type.maximum ?? ""), String(type.length ?? ""), String(type.members ?? ""), ...type.children.map((id) => classes[id])].join(":");
      if (!representatives.has(key)) representatives.set(key, i);
      return representatives.get(key);
    });
    if (next.every((value, i) => value === classes[i])) break;
    classes = next;
  }
  if (new Set(classes).size !== types.length) throw new Error("NonCanonical");
  const pending = [0], seen = new Set();
  while (pending.length) {
    const id = pending.pop();
    if (seen.has(id)) continue;
    if (id !== seen.size) throw new Error("NonCanonical");
    seen.add(id);
    for (let i = types[id].children.length - 1; i >= 0; i--) pending.push(types[id].children[i]);
  }
  if (seen.size !== types.length) throw new Error("NonCanonical");
  return types;
}

export function validateValue(schema, bytes) {
  const types = decodeSchema(schema);
  const reader = new Reader(bytes);
  bytes = reader.bytes;
  const pending = [[0, 1n]];
  while (pending.length) {
    const [id, count] = pending.pop();
    const type = types[id];
    if (count === 0n || type.minimum === 0n) continue;
    if (count > BigInt(bytes.length - reader.position) / type.minimum) throw new Error("InvalidValue");
    if (count > 1n) pending.push([id, count - 1n]);
    if (type.tag <= 9) {
      const scalar = reader.take(Number(type.minimum));
      if (type.tag === 1 && scalar[0] > 1) throw new Error("InvalidValue");
    } else if (type.tag === 10 || type.tag === 11 || type.tag === 18 || type.tag === 19) {
      const value = reader.field();
      if (type.maximum !== undefined && BigInt(value.length) > type.maximum) throw new Error("InvalidValue");
      if (type.tag === 11 || type.tag === 19) decoder.decode(value);
    } else if (type.tag === 12) {
      for (let i = type.children.length - 1; i >= 0; i--) pending.push([type.children[i], 1n]);
    } else if (type.tag === 13) {
      const tag = reader.natural();
      if (tag >= BigInt(type.children.length)) throw new Error("InvalidValue");
      pending.push([type.children[Number(tag)], 1n]);
    } else if (type.tag === 17) {
      pending.push([type.children[0], type.length]);
    } else if (type.tag === 20) {
      const value = reader.take(4);
      const tag = BigInt(new DataView(value.buffer, value.byteOffset, 4).getUint32(0, true));
      if (!type.members.includes(tag)) throw new Error("InvalidValue");
    } else {
      const count = reader.natural();
      if (type.maximum !== undefined && count > type.maximum) throw new Error("InvalidValue");
      pending.push([type.children[0], count]);
    }
  }
  reader.finish();
}
