import { isUint8Array } from "./errors.mjs";
export const MAX_U64 = (1n << 64n) - 1n;
export const UTF8 = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
const encoder = new TextEncoder();
const bufferGetter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype), "buffer").get;
const lengthGetter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype), "byteLength").get;
const sharedLength = typeof SharedArrayBuffer === "undefined" ? null : Object.getOwnPropertyDescriptor(SharedArrayBuffer.prototype, "byteLength").get;
export function copyBytes(value) {
  if (!isUint8Array(value)) throw new TypeError("expected Uint8Array");
  if (lengthGetter.call(value) > 64 * 1024 * 1024) throw new RangeError("byte input exceeds physical limit");
  if (sharedLength) {
    let shared = false;
    try { sharedLength.call(bufferGetter.call(value)); shared = true; } catch {}
    if (shared) throw new TypeError("shared input is not supported");
  }
  const owned = new Uint8Array(value);
  return owned;
}
export function u64(value) {
  if (typeof value !== "bigint" && (typeof value !== "number" || !Number.isSafeInteger(value))) throw new TypeError("expected exact integer");
  const n = BigInt(value);
  if (n < 0n || n > MAX_U64) throw new RangeError("u64 overflow");
  return n;
}
export function natural(value) {
  let n = u64(value);
  const bytes = [];
  do { const low = Number(n & 127n); n >>= 7n; bytes.push(low | (n ? 128 : 0)); } while (n);
  return Uint8Array.from(bytes);
}
export function concat(...parts) {
  const length = parts.reduce((sum, part) => sum + part.length, 0);
  if (!Number.isSafeInteger(length)) throw new RangeError("byte length overflow");
  const bytes = new Uint8Array(length);
  let at = 0;
  for (const part of parts) { bytes.set(part, at); at += part.length; }
  return bytes;
}
export function field(bytes) { return concat(natural(bytes.length), bytes); }
export function frame(family, payload) {
  if (!/^ABL_(BPI|PST|PKI|PKO|ERQ|ERS)3$/.test(family)) throw new Error("InvalidFamily");
  const header = new Uint8Array(20);
  header.set(encoder.encode(family));
  const view = new DataView(header.buffer);
  view.setUint16(8, 3, true);
  view.setBigUint64(12, BigInt(payload.length), true);
  return concat(header, payload);
}
export function body(family, input) {
  const bytes = copyBytes(input);
  if (bytes.length < 20) throw new Error("Truncated");
  const view = new DataView(bytes.buffer);
  if (UTF8.decode(bytes.subarray(0, 8)) !== family) throw new Error("InvalidFamily");
  if (view.getUint16(8, true) !== 3) throw new Error("UnsupportedVersion");
  if (view.getUint16(10, true) !== 0) throw new Error("InvalidFlags");
  if (view.getBigUint64(12, true) !== BigInt(bytes.length - 20)) throw new Error("InvalidLength");
  return bytes.subarray(20);
}
export class Reader {
  constructor(bytes) { this.bytes = copyBytes(bytes); this.position = 0; }
  take(n) {
    if (!Number.isSafeInteger(n) || n < 0 || n > this.bytes.length - this.position) throw new Error("Truncated");
    const result = this.bytes.slice(this.position, this.position + n);
    this.position += n;
    return result;
  }
  natural() {
    let value = 0n;
    for (let i = 0; i < 10; i++) {
      const byte = this.byte();
      if (i === 9 && byte > 1) throw new Error("InvalidLength");
      value |= BigInt(byte & 127) << BigInt(i * 7);
      if (!(byte & 128)) { if (i && byte === 0) throw new Error("NonCanonical"); return value; }
    }
    throw new Error("InvalidLength");
  }
  byte() { if (this.position >= this.bytes.length) throw new Error("Truncated"); return this.bytes[this.position++]; }
  field() { const n = this.natural(); if (n > BigInt(this.bytes.length - this.position)) throw new Error("Truncated"); return this.take(Number(n)); }
  optional(read) { const tag = this.byte(); if (tag > 1) throw new Error("InvalidTag"); return tag ? read() : null; }
  finish() { if (this.position !== this.bytes.length) throw new Error("NonCanonical"); }
}
export async function digest(bytes) { return new Uint8Array(await crypto.subtle.digest("SHA-256", copyBytes(bytes))); }
export function same(a, b) { return a.length === b.length && a.every((x, i) => x === b[i]); }
export function hex(bytes) { return Array.from(bytes, n => n.toString(16).padStart(2, "0")).join(""); }
