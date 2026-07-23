import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

async function main() {
const wasmPath = process.argv[2];
if (!wasmPath) throw new Error("usage: node scripts/world_application_v1_conformance.mjs <application.wasm>");

const wasmBytes = await readFile(wasmPath);
assertStandaloneStructure(wasmBytes);
const module = await WebAssembly.compile(wasmBytes);
const imports = WebAssembly.Module.imports(module);
if (imports.length !== 0) throw new Error("World application WASM must have zero imports");

const requiredExports = [
  "memory",
  "world_abi_version",
  "world_manifest_ptr",
  "world_manifest_len",
  "world_input_ptr",
  "world_input_capacity",
  "world_step",
  "world_output_ptr",
  "world_output_len",
  "world_error_ptr",
  "world_error_len",
  "world_reset",
];
const exportNames = new Set(WebAssembly.Module.exports(module).map((value) => value.name));
for (const name of requiredExports) {
  if (!exportNames.has(name)) throw new Error(`missing World application ABI export: ${name}`);
}

const first = await instantiate(module);
if (first.world_abi_version() !== 1) throw new Error("unexpected World application ABI version");
if (first.memory.buffer.byteLength !== 8 * 1024 * 1024) throw new Error("unexpected initial linear memory");
let memoryBounded = false;
try {
  first.memory.grow(1);
} catch (error) {
  if (error instanceof RangeError) memoryBounded = true;
  else throw error;
}
if (!memoryBounded) throw new Error("World application memory has no enforced maximum at its initial bound");

const manifest = copyExported(first, "world_manifest_ptr", "world_manifest_len");
expectMagic(manifest, "WRLDMNF1");
if (manifest.readUInt32LE(8) !== 1) throw new Error("unexpected manifest format version");
const applicationId = manifest.subarray(12, 44);

const genesisInput = encodeStepInput({
  applicationId,
  initialArgs: Buffer.alloc(0),
  fuel: 100n,
});
const firstCode = callStep(first, genesisInput);
if (firstCode !== 0) throw abiFailure(first, `genesis step returned ${firstCode}`);
const parentBytes = copyExported(first, "world_output_ptr", "world_output_len");
const parent = decodeFrame(parentBytes);
if (parent.status !== 0 || parent.request === null) throw new Error("genesis did not park on one external effect");
if (parent.sequence !== 0n) throw new Error("genesis Frame sequence is not zero");

const valueBytes = Buffer.alloc(8);
valueBytes.writeBigInt64LE(41n);
const result = encodeOkResult(parent.request, valueBytes);
const continuationInput = encodeStepInput({
  applicationId,
  expectedParentFrameId: parent.frameId,
  priorFrame: parentBytes,
  effectResult: result.bytes,
  fuel: 100n,
});

const second = await instantiate(module);
const secondCode = callStep(second, continuationInput);
if (secondCode !== 0) throw abiFailure(second, `continuation step returned ${secondCode}`);
const childBytes = copyExported(second, "world_output_ptr", "world_output_len");
const child = decodeFrame(childBytes);
if (child.status !== 1 || child.sequence !== 1n) throw new Error("continued Frame did not complete at sequence one");
if (!child.parentFrameId?.equals(parent.frameId)) throw new Error("child Frame does not bind its exact parent");
if (!child.acceptedResultId?.equals(result.resultId)) throw new Error("child Frame does not bind its accepted EffectResult");
if (child.finalResult === null || child.finalResult.readBigInt64LE() !== 41n) throw new Error("unexpected completed result");

const retry = await instantiate(module);
const retryCode = callStep(retry, continuationInput);
if (retryCode !== 0) throw abiFailure(retry, `retry step returned ${retryCode}`);
const retryBytes = copyExported(retry, "world_output_ptr", "world_output_len");
if (!retryBytes.equals(childBytes)) throw new Error("fresh-instance retry did not produce byte-identical Frame bytes");

const malformed = await instantiate(module);
if (malformed.world_step(0) !== 1 || malformed.world_output_len() !== 0) {
  throw new Error("malformed input did not fail without semantic output");
}

console.log(`application_wasm_bytes=${wasmBytes.length}`);
console.log("imports=0");
console.log("dynamic_runtime_markers=0");
console.log(`exports=${requiredExports.length}`);
console.log(`initial_memory_bytes=${first.memory.buffer.byteLength}`);
console.log("bounded_memory=true");
console.log("fresh_instance_continuation=true");
console.log("byte_identical_retry=true");
console.log("final_result=41");
}

async function instantiate(compiled) {
  const instance = await WebAssembly.instantiate(compiled, {});
  return instance.exports;
}

function callStep(exports, bytes) {
  const capacity = exports.world_input_capacity();
  if (bytes.length > capacity) throw new Error("fixture StepInput exceeds application input capacity");
  const pointer = exports.world_input_ptr();
  new Uint8Array(exports.memory.buffer, pointer, bytes.length).set(bytes);
  return exports.world_step(bytes.length);
}

function copyExported(exports, pointerName, lengthName) {
  const pointer = exports[pointerName]();
  const length = exports[lengthName]();
  return Buffer.from(new Uint8Array(exports.memory.buffer, pointer, length));
}

function abiFailure(exports, prefix) {
  const message = copyExported(exports, "world_error_ptr", "world_error_len").toString("utf8");
  return new Error(`${prefix}: ${message}`);
}

function encodeStepInput({ applicationId, expectedParentFrameId = null, priorFrame = null, initialArgs = null, effectResult = null, fuel }) {
  return Buffer.concat([
    Buffer.from("WRLDSTP1"),
    u32(1),
    applicationId,
    optionalDigest(expectedParentFrameId),
    optionalBytes(priorFrame),
    optionalBytes(initialArgs),
    effectResult === null ? Buffer.from([0]) : Buffer.concat([Buffer.from([1]), lenBytes(effectResult)]),
    u64(fuel),
    lenBytes(Buffer.alloc(0)),
  ]);
}

function encodeOkResult(request, resultBytes) {
  const zero = Buffer.alloc(32);
  const canonical = Buffer.concat([
    Buffer.from("WRLDERS1"),
    u32(1),
    zero,
    request.requestId,
    Buffer.from([0]),
    request.resultSchemaId,
    optionalBytes(resultBytes),
    lenBytes(Buffer.alloc(0)),
    u32(1),
  ]);
  const resultId = createHash("sha256")
    .update(Buffer.from("world.effect-result.v1"))
    .update(Buffer.from([0]))
    .update(canonical)
    .digest();
  resultId.copy(canonical, 12);
  return { resultId, bytes: canonical };
}

function decodeFrame(bytes) {
  const reader = new Reader(bytes);
  reader.magic("WRLDFRM1");
  if (reader.u32() !== 1) throw new Error("unexpected Frame format version");
  const frameId = reader.bytes(32);
  reader.bytes(32);
  const parentFrameId = reader.optionalDigest();
  const sequence = reader.u64();
  reader.lenBytes();
  const request = reader.bool() ? decodeRequest(reader.lenBytes()) : null;
  const acceptedResultId = reader.optionalDigest();
  const status = reader.u8();
  reader.optionalDigest();
  const finalResult = reader.optionalBytes();
  reader.optionalBytes();
  const resourceCounters = {
    instructions: reader.u64(),
    continuationOperations: reader.u64(),
    internalHandlerCalls: reader.u64(),
    externalEffects: reader.u64(),
    valueBytes: reader.u64(),
  };
  reader.u64();
  reader.finish();
  return { frameId, parentFrameId, sequence, request, acceptedResultId, status, finalResult, resourceCounters };
}

function decodeRequest(bytes) {
  const reader = new Reader(bytes);
  reader.magic("WRLDERQ1");
  if (reader.u32() !== 1) throw new Error("unexpected EffectRequest format version");
  const requestId = reader.bytes(32);
  reader.bytes(32);
  reader.bytes(32);
  reader.u64();
  reader.u32();
  const siteId = reader.u64();
  const interfaceId = reader.bytes(32);
  reader.bytes(32);
  const resultSchemaId = reader.bytes(32);
  reader.u8();
  const payload = reader.lenBytes();
  reader.bytes(32);
  reader.u64();
  reader.u32();
  reader.u32();
  reader.finish();
  return { requestId, siteId, interfaceId, resultSchemaId, payload };
}

function optionalDigest(value) {
  return value === null ? Buffer.from([0]) : Buffer.concat([Buffer.from([1]), value]);
}

function optionalBytes(value) {
  return value === null ? Buffer.from([0]) : Buffer.concat([Buffer.from([1]), lenBytes(value)]);
}

function lenBytes(value) {
  return Buffer.concat([u32(value.length), value]);
}

function u32(value) {
  const bytes = Buffer.alloc(4);
  bytes.writeUInt32LE(value);
  return bytes;
}

function u64(value) {
  const bytes = Buffer.alloc(8);
  bytes.writeBigUInt64LE(value);
  return bytes;
}

function expectMagic(bytes, expected) {
  if (bytes.subarray(0, expected.length).toString("ascii") !== expected) throw new Error(`missing ${expected} magic`);
}

function assertStandaloneStructure(bytes) {
  for (const marker of [
    "world_appliance_load_executable",
    "Executable.Image",
    "FabricPlan",
    "provider_catalog",
    "world_universal_appliance",
  ]) {
    if (bytes.includes(Buffer.from(marker))) throw new Error(`application WASM retains forbidden runtime marker: ${marker}`);
  }
}

class Reader {
  constructor(bytes) {
    this.value = bytes;
    this.offset = 0;
  }

  bytes(length) {
    const end = this.offset + length;
    if (end > this.value.length) throw new Error("truncated canonical record");
    const result = this.value.subarray(this.offset, end);
    this.offset = end;
    return result;
  }

  magic(expected) {
    if (this.bytes(expected.length).toString("ascii") !== expected) throw new Error(`missing ${expected} magic`);
  }

  u8() {
    return this.bytes(1)[0];
  }

  bool() {
    const value = this.u8();
    if (value > 1) throw new Error("invalid canonical boolean");
    return value === 1;
  }

  u32() {
    return this.bytes(4).readUInt32LE();
  }

  u64() {
    return this.bytes(8).readBigUInt64LE();
  }

  lenBytes() {
    return this.bytes(this.u32());
  }

  optionalBytes() {
    return this.bool() ? this.lenBytes() : null;
  }

  optionalDigest() {
    return this.bool() ? this.bytes(32) : null;
  }

  finish() {
    if (this.offset !== this.value.length) throw new Error("trailing canonical bytes");
  }
}

export {
  assertStandaloneStructure,
  abiFailure,
  callStep,
  copyExported,
  decodeFrame,
  encodeOkResult,
  encodeStepInput,
  instantiate,
};

if (import.meta.url === pathToFileURL(resolve(process.argv[1])).href) await main();
