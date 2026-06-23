const textDecoder = new TextDecoder();

export function inspectTurnOutput(bytes) {
  const reader = new BinaryReader(bytes);
  reader.u32();
  reader.u32();
  reader.u64();
  reader.u64();
  reader.u64();
  reader.u64();
  reader.u64();
  reader.skipQuiescence();
  const status = reader.u8();
  const hostRequestCount = Number(reader.u64());
  for (let i = 0; i < hostRequestCount; i += 1) reader.skipHostRequest();
  reader.skipU64Slice();
  const rootResultFingerprint = reader.optionalU64();
  const rootResultBytesLen = reader.bytesLen();
  reader.optionalU64();
  reader.optionalU64();
  reader.bytesLen();
  const archiveAppendFingerprint = reader.optionalU64();
  reader.optionalU64();
  reader.bytesLen();
  const archiveAppendBytesLen = reader.bytesLen();
  return {
    status,
    hostRequestCount,
    rootResultFingerprint,
    rootResultBytesLen,
    archiveAppendFingerprint,
    archiveAppendBytesLen,
  };
}

export function decodeUtf8(bytes) {
  return textDecoder.decode(bytes);
}

export class BinaryReader {
  constructor(bytes) {
    this.bytes = bytes;
    this.offset = 0;
    this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
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

  bytesLen() {
    const len = this.u32();
    this.require(len);
    this.offset += len;
    return len;
  }

  skipU64Slice() {
    const count = Number(this.u64());
    this.require(count * 8);
    this.offset += count * 8;
  }

  skipQuiescence() {
    this.u64();
    this.u8();
    for (let i = 0; i < 9; i += 1) this.u64();
  }

  skipHostRequest() {
    this.u32();
    this.u32();
    this.u64();
    this.u64();
    this.u32();
    this.u64();
    this.u64();
    this.u32();
    this.u64();
    this.u64();
    this.u64();
    this.u8();
    this.u8();
    this.u64();
    this.u64();
    this.u64();
    this.u64();
    this.u64();
    this.optionalU64();
    this.bytesLen();
    this.bytesLen();
    this.bytesLen();
    this.optionalU64();
    this.optionalU64();
    this.optionalU64();
    this.optionalU64();
    this.bytesLen();
    this.bytesLen();
  }

  require(len) {
    if (len < 0 || this.offset + len > this.bytes.length) throw new Error('truncated turn output');
  }
}
