import { BinaryReader, decodeHostRequest } from './world_appliance_wire_codec.mjs';

const textDecoder = new TextDecoder();

export function inspectTurnOutput(bytes) {
  const reader = new BinaryReader(bytes);
  reader.u32();
  reader.u32();
  const closureFingerprint = reader.u64();
  reader.u64();
  const manifestFingerprint = reader.u64();
  reader.optionalU64();
  const turnSequenceNumber = reader.u64();
  reader.u64();
  reader.u64();
  reader.u64();
  reader.u64();
  reader.optionalU64();
  reader.optionalU64();
  reader.optionalU64();
  reader.optionalU64();
  reader.u64();
  reader.bytesLen();
  reader.u64();
  reader.bytesLen();
  reader.u64();
  const turnReceiptBytes = reader.bytes();
  const turnReceipt = new BinaryReader(turnReceiptBytes).readTurnReceipt();
  reader.bytesLen();
  const archiveAppendFingerprint = reader.optionalU64();
  const archiveAppendBytesLen = reader.bytesLen();
  const pendingHostRequestBytes = reader.bytes();
  const hostRequests = decodeHostRequestsImage(pendingHostRequestBytes);
  const rootResultFingerprint = reader.optionalU64();
  const rootResultBytesLen = reader.bytesLen();
  reader.optionalU64();
  reader.optionalU64();
  reader.bytesLen();
  reader.skipU64Slice();
  reader.skipByteSlices();
  reader.skipU64Slice();
  reader.skipByteSlices();
  reader.skipU64Slice();
  reader.skipU64Slice();
  reader.skipU64Slice();
  reader.bytesLen();
  const status = reader.u8();
  return {
    outputFingerprint: closureFingerprint,
    closureFingerprint,
    manifestFingerprint,
    turnSequenceNumber,
    status,
    hostRequestCount: hostRequests.length,
    hostRequests,
    rootResultFingerprint,
    rootResultBytesLen,
    archiveAppendFingerprint,
    archiveAppendBytesLen,
    turnReceipt,
  };
}

function decodeHostRequestsImage(bytes) {
  if (bytes.length === 0) return [];
  const reader = new BinaryReader(bytes);
  const count = Number(reader.u64());
  const requests = [];
  for (let i = 0; i < count; i += 1) requests.push(decodeHostRequest(reader));
  if (reader.remaining() !== 0) throw new Error('trailing HostRequest bytes');
  return requests;
}

export function decodeUtf8(bytes) {
  return textDecoder.decode(bytes);
}
