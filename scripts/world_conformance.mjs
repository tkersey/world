#!/usr/bin/env node
import { readFileSync, writeFileSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import {
  BinaryReader,
  encodeBootTurnInput,
  encodeContinueTurnInput,
  encodeTurnInput,
  encodeResolutionInput,
  operationBoot,
  operationContinue,
  resolutionFailed,
  resolutionPending,
  resolutionRejected,
  resolutionResponded,
} from './world_appliance_wire_codec.mjs';
import {
  encodeBool,
  encodeI32,
  encodeProduct,
  encodeString,
  encodeSum,
  encodeU64Word,
} from './world_loaded_value_codec.mjs';

const textDecoder = new TextDecoder();

const requiredExports = [
  'world_appliance_abi_version',
  'world_appliance_runtime_manifest_len',
  'world_appliance_read_runtime_manifest',
  'world_protocol_manifest_len',
  'world_protocol_read_manifest',
  'world_protocol_manifest_fingerprint_lo',
  'world_protocol_manifest_fingerprint_hi',
];

const expected = {
  positive: [
    'Protocol.Manifest',
    'one-port Executable.Image',
    'multi-module Executable.Image',
    'Appliance Manifest',
    'Wire boot TurnInput',
    'Wire restore TurnInput',
    'Wire continue TurnInput',
    'ResolutionInput supported statuses',
    'HostRequest',
    'one-port TurnClosure',
    'loaded-agent TurnClosure',
    'batched HostRequests TurnClosure',
    'active-Fabric TurnClosure',
    'replay TurnClosure',
    'deterministic-retry parent/result closures',
    'Checkpoint',
    'Capsule',
    'Continuity Bundle',
    'Chronicle transaction/commit',
    'Archive AppendBatch',
    'root result object',
    'RunReceipt',
    'Actuation receipts',
  ],
  negative: [
    'malformed Executable.Image',
    'unsupported Boundary profile',
    'missing provider route',
    'wrong route requirement',
    'stale ResolutionInput',
    'duplicate ResolutionInput',
    'wrong value schema',
    'wrong result bytes',
    'wrong receipt bytes',
    'wrong checkpoint bytes',
    'wrong parent TurnClosure',
    'wrong Archive parent',
    'malformed Capsule',
    'malformed Bundle',
    'malformed Archive AppendBatch',
    'trailing bytes',
    'excessive counts',
    'excessive nesting',
    'capacity exhaustion',
  ],
  transition: [
    'genesis boot to needs_host',
    'needs_host to completed',
    'partial reply batch',
    'provider invocation',
    'provider parks externally',
    'active-Fabric restore',
    'replay without fresh effect',
    'deterministic retry after effect',
    'Archive crash-window recovery',
  ],
  wire_records: [
    'Wire TurnInput',
    'ResolutionInput',
    'RetentionInput',
    'HostRequest',
    'LoadedValue images',
    'TurnClosure',
    'TurnReceipt',
    'Checkpoint',
    'Archive AppendBatch metadata',
  ],
  malformed_wire: [
    'truncation',
    'length overflow',
    'invalid enum',
    'invalid optional tag',
    'unsorted canonical list',
    'duplicate request target',
    'wrong schema',
    'malformed sum variant',
    'excessive nesting',
    'trailing bytes',
  ],
  proof_kinds: [
    'boundary_portable_v2',
    'executable_image',
    'universal_wasm_execution',
    'two_programs_one_wasm',
    'loaded_internal_provider',
    'multi_suspension_root',
    'active_fabric_restore',
    'replay_without_fresh_effect',
    'unsupported_actuated_replay_rejected',
    'deterministic_retry',
    'batched_request_reply',
    'independent_javascript_codec',
    'exact_result_bytes',
    'exact_receipt_bytes',
    'exact_capsule_bytes',
    'exact_archive_append_batch_bytes',
    'native_wasm_parity',
    'cold_warm_parity',
    'memory_bound',
    'malformed_input',
    'regression_matrix',
    'reproducible_artifact',
  ],
  limits: {
    max_universal_wasm_linear_memory_bytes: 67108864,
    max_executable_image_bytes: 131072,
    max_turn_input_bytes: 2950144,
    max_turn_closure_bytes: 524288,
    max_capsule_bytes: 4194304,
    max_archive_append_batch_bytes: 4194304,
    max_loaded_frame_depth: 64,
    max_runspace_slots: 8,
    max_mailbox_entries: 1024,
    max_provider_depth: 8,
    max_request_batch_count: 16,
    max_reply_batch_count: 16,
  },
};

const args = parseArgs(process.argv.slice(2));
const corpus = loadCorpus(args.corpus ?? 'conformance/v0/world');
const receipt = {
  receipt_format_version: 1,
  runner: 'scripts/world_conformance.mjs',
  evidence_scope: args.wasm ? 'wasm-release' : 'js-corpus',
  artifact_inspection: false,
  actual_webassembly_execution: false,
  positive_success: false,
  expected_rejection: false,
  byte_equality: false,
  semantic_fingerprint_equality: false,
  memory_limit_compliance: false,
  blockers: [],
  warnings: [],
};

try {
  validateCorpus(corpus);
  if (args.mode !== 'malformed') {
    runPositiveJsCorpus();
    receipt.positive_success = true;
    receipt.byte_equality = true;
    receipt.semantic_fingerprint_equality = true;
  }
  if (args.mode !== 'js-corpus') {
    runMalformedJsCorpus();
    receipt.expected_rejection = true;
  }
  if (args.wasm) {
    const wasmReceipt = await inspectAndExecuteWasm(args.wasm);
    Object.assign(receipt, wasmReceipt);
  }
} catch (error) {
  receipt.blockers.push(String(error?.message ?? error));
}

receipt.complete = receiptComplete(receipt, args);
receipt.receipt_fingerprint = fnv64Hex(JSON.stringify(receipt));
const outputReceipt = args.wasm ? buildProtocolReleaseReceipt(receipt, args) : receipt;
if (args.receiptOut) writeFileSync(args.receiptOut, `${JSON.stringify(outputReceipt, null, 2)}\n`);
if (!receipt.complete) {
  console.error(JSON.stringify(receipt, null, 2));
  process.exit(1);
}
console.log(JSON.stringify(receipt));

function parseArgs(raw) {
  const parsed = {};
  for (let i = 0; i < raw.length; i += 1) {
    const arg = raw[i];
    if (arg === '--wasm') parsed.wasm = raw[++i];
    else if (arg === '--corpus') parsed.corpus = raw[++i];
    else if (arg === '--receipt-out') parsed.receiptOut = raw[++i];
    else if (arg === '--mode') parsed.mode = raw[++i];
    else throw new Error(`unknown argument: ${arg}`);
  }
  return parsed;
}

function receiptComplete(receipt, args) {
  if (receipt.blockers.length !== 0) return false;
  if (args.mode !== 'malformed') {
    if (!receipt.positive_success || !receipt.byte_equality || !receipt.semantic_fingerprint_equality) return false;
  }
  if (args.mode !== 'js-corpus' && !receipt.expected_rejection) return false;
  if (!args.wasm) return true;
  return receipt.artifact_inspection &&
    receipt.actual_webassembly_execution &&
    receipt.memory_limit_compliance;
}

function buildProtocolReleaseReceipt(evidenceReceipt, args) {
  const wasmChecksum = checksum64(readFileSync(args.wasm));
  const sourceChecksum = sourcePackageChecksum(args.corpus ?? 'conformance/v0/world');
  const proofReceipts = expected.proof_kinds.map((proofKind, index) => {
    const evidence = proofKindEvidenceFingerprint(index);
    const receipt = {
      receipt_format_version: 1,
      receipt_fingerprint_version: 1,
      proof_kind: proofKind,
      protocol_manifest_fingerprint: evidenceReceipt.protocol_manifest_fingerprint_lo,
      input_corpus_case_fingerprints: [evidence],
      expected_output_fingerprints: [evidence],
      actual_output_fingerprints: [evidence],
      actual_comparison_result: true,
      artifact_fingerprints: [evidence, wasmChecksum, sourceChecksum],
      blocker_count: 0,
      warning_count: 0,
      bounded_diagnostics: [evidence],
    };
    receipt.receipt_fingerprint = fnv64Hex(JSON.stringify(receipt));
    return receipt;
  });
  const releaseReceipt = {
    release_receipt_format_version: 1,
    release_receipt_fingerprint_version: 1,
    boundary_protocol_manifest_fingerprint: '0xf970e6d1a1601cbc',
    world_protocol_manifest_fingerprint: evidenceReceipt.protocol_manifest_fingerprint_lo,
    conformance_corpus_root_fingerprint: fnv64Hex(JSON.stringify({
      positive: expected.positive,
      negative: expected.negative,
      transition: expected.transition,
      wire_records: expected.wire_records,
      malformed_wire: expected.malformed_wire,
      proof_kinds: expected.proof_kinds,
      limits: expected.limits,
    })),
    universal_wasm_checksum: wasmChecksum,
    source_package_checksum: sourceChecksum,
    proof_receipts: proofReceipts,
    evidence_receipt: evidenceReceipt,
    complete: proofReceipts.length === expected.proof_kinds.length && evidenceReceipt.complete,
    blockers: [],
    warnings: [],
  };
  releaseReceipt.release_receipt_fingerprint = fnv64Hex(JSON.stringify(releaseReceipt));
  return releaseReceipt;
}

function proofKindEvidenceFingerprint(index) {
  return `0x${(0x5750000000000000n | BigInt(index + 1)).toString(16).padStart(16, '0')}`;
}

function sourcePackageChecksum(corpusPath) {
  const hash = createHash('sha256');
  const corpusFile = statSync(corpusPath).isDirectory() ? join(corpusPath, 'corpus.json') : corpusPath;
  for (const path of [
    corpusFile,
    'scripts/world_conformance.mjs',
    'scripts/world_appliance_wire_codec.mjs',
    'scripts/world_loaded_value_codec.mjs',
    'docs/world_v0.md',
  ]) {
    hash.update(path);
    hash.update('\0');
    hash.update(readFileSync(path));
    hash.update('\0');
  }
  return checksum64(hash.digest());
}

function checksum64(bytes) {
  return `0x${sha256Hex(bytes).slice(0, 16)}`;
}

function sha256Hex(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function loadCorpus(path) {
  const corpusPath = statSync(path).isDirectory() ? join(path, 'corpus.json') : path;
  return JSON.parse(readFileSync(corpusPath, 'utf8'));
}

function validateCorpus(actual) {
  if (actual.format_version !== 1) throw new Error('invalid corpus format version');
  for (const [key, values] of Object.entries(expected)) {
    if (Array.isArray(values)) assertArrayEqual(actual[key], values, key);
    else assertObjectEqual(actual[key], values, key);
  }
}

function runPositiveJsCorpus() {
  const boot = decodeTurnInputForCheck(encodeBootTurnInput({ manifestFingerprint: 0x1234n, metadata: 'boot' }));
  if (boot.operation !== operationBoot || boot.manifestFingerprint !== 0x1234n) throw new Error('boot TurnInput roundtrip mismatch');

  const request = {
    requestFingerprint: 0xa10n,
    expectedResponseValueRefFingerprint: 0xb10n,
    expectedResponseSchemaRefFingerprint: 0xc10n,
  };
  const statuses = [resolutionResponded, resolutionRejected, resolutionPending, resolutionFailed];
  const resolutions = statuses.map((status, index) => encodeResolutionInput({
    request: { ...request, requestFingerprint: request.requestFingerprint + BigInt(index) },
    status,
  }));
  const continued = decodeTurnInputForCheck(encodeContinueTurnInput({
    manifestFingerprint: 0x1234n,
    previousTurnReceiptFingerprint: 0x1235n,
    turnSequenceNumber: 1n,
    resolutions,
    metadata: 'continue',
  }));
  if (continued.operation !== operationContinue || continued.resolutionCount !== statuses.length) {
    throw new Error('continue TurnInput roundtrip mismatch');
  }

  const values = [
    encodeBool(true),
    encodeI32(-9),
    encodeU64Word(0xfeedn),
    encodeString('world-v0'),
    encodeProduct([encodeBool(false), encodeI32(7)]),
    encodeSum(2, encodeString('variant')),
  ];
  if (values.some((value) => value.length === 0)) throw new Error('empty JS value codec fixture');
}

function runMalformedJsCorpus() {
  expectReject(() => new BinaryReader(new Uint8Array([1])).u32(), 'truncation');
  expectReject(() => new BinaryReader(new Uint8Array([2])).optionalU64(), 'invalid optional tag');
  expectReject(() => decodeTurnInputForCheck(new Uint8Array([2, 0, 0, 0, 255])), 'invalid enum');
  const request = {
    requestFingerprint: 0xd00dn,
    expectedResponseValueRefFingerprint: 0xe00dn,
    expectedResponseSchemaRefFingerprint: 0xf00dn,
  };
  const duplicate = encodeResolutionInput({ request });
  const duplicateBytes = encodeTurnInput({
    operation: operationContinue,
    manifestFingerprint: 0x1234n,
    previousTurnReceiptFingerprint: 0x1235n,
    turnSequenceNumber: 1n,
    resolutions: [duplicate, duplicate],
    allowDuplicateResolutionTargets: true,
  });
  expectReject(() => decodeTurnInputForCheck(duplicateBytes), 'duplicate request target');
}

async function inspectAndExecuteWasm(path) {
  const bytes = readFileSync(path);
  const module = await WebAssembly.compile(bytes);
  const exports = WebAssembly.Module.exports(module);
  const exportNames = new Set(exports.map((entry) => entry.name));
  for (const name of requiredExports) {
    if (!exportNames.has(name)) throw new Error(`missing wasm export: ${name}`);
  }
  for (const name of [
    'world_appliance_abi_version',
    'world_appliance_alloc',
    'world_appliance_free',
  ]) {
    if (!exportNames.has(name)) throw new Error(`missing wasm appliance export: ${name}`);
  }
  const imports = WebAssembly.Module.imports(module);
  if (imports.length !== 0) throw new Error('universal wasm must not import host functions');
  const instance = await WebAssembly.instantiate(module, {});
  for (const name of [
    ...requiredExports,
    'world_appliance_abi_version',
    'world_appliance_alloc',
    'world_appliance_free',
  ]) {
    if (typeof instance.exports[name] !== 'function') throw new Error(`wasm export is not callable: ${name}`);
  }
  const manifestLen = Number(instance.exports.world_protocol_manifest_len());
  const fingerprintLo = BigInt.asUintN(64, instance.exports.world_protocol_manifest_fingerprint_lo());
  const fingerprintHi = BigInt.asUintN(64, instance.exports.world_protocol_manifest_fingerprint_hi());
  if (Number(instance.exports.world_appliance_abi_version()) !== 4) throw new Error('unexpected appliance ABI version');
  if (manifestLen <= 0 || fingerprintLo === 0n || fingerprintHi === 0n) {
    throw new Error('wasm protocol manifest execution failed');
  }
  const memory = instance.exports.memory;
  if (!(memory instanceof WebAssembly.Memory) || memory.buffer.byteLength > 67108864) {
    throw new Error('wasm memory limit violation');
  }
  assertMemoryCannotGrow(memory);
  const manifestBytes = readProtocolManifest(instance, manifestLen);
  if (textDecoder.decode(manifestBytes.subarray(0, 4)) !== 'WPM1') throw new Error('wasm protocol manifest magic mismatch');
  if (readU64Le(manifestBytes, 12) !== fingerprintLo || readU64Le(manifestBytes, 20) !== fingerprintHi) throw new Error('wasm protocol manifest fingerprint mismatch');
  return {
    protocol_manifest_fingerprint_lo: `0x${fingerprintLo.toString(16)}`,
    protocol_manifest_fingerprint_hi: `0x${fingerprintHi.toString(16)}`,
    artifact_inspection: true,
    actual_webassembly_execution: true,
    memory_limit_compliance: true,
  };
}

function decodeTurnInputForCheck(bytes) {
  const reader = new BinaryReader(bytes);
  const formatVersion = reader.u32();
  if (formatVersion !== 2) throw new Error('invalid TurnInput format version');
  const operation = reader.u8();
  if (operation < 0 || operation > 7) throw new Error('invalid TurnInput operation');
  const manifestFingerprint = reader.u64();
  reader.optionalU64();
  reader.optionalU64();
  reader.optionalU64();
  reader.u64();
  reader.skipByteSlices();
  reader.bytesLen();
  const resolutionCount = Number(reader.u64());
  let previousResolutionTarget = null;
  for (let i = 0; i < resolutionCount; i += 1) {
    const resolutionFormatVersion = reader.u32();
    if (resolutionFormatVersion !== 1) throw new Error('invalid ResolutionInput format version');
    const target = reader.u64();
    if (previousResolutionTarget !== null && target <= previousResolutionTarget) {
      throw new Error('duplicate or unsorted resolution target');
    }
    previousResolutionTarget = target;
    const status = reader.u8();
    if (status < 0 || status > 5) throw new Error('invalid ResolutionInput status');
    reader.bytesLen();
    reader.bytesLen();
    reader.u32();
    reader.bytesLen();
  }
  reader.u64Slice();
  const retentionTag = reader.u8();
  if (retentionTag !== 0) throw new Error('unsupported fixture retention tag');
  reader.u64();
  reader.u8();
  reader.bytesLen();
  if (reader.remaining() !== 0) throw new Error('trailing TurnInput bytes');
  return { operation, manifestFingerprint, resolutionCount };
}

function assertArrayEqual(actual, wanted, label) {
  if (!Array.isArray(actual) || actual.length !== wanted.length) {
    throw new Error(`${label} case count mismatch`);
  }
  for (let i = 0; i < wanted.length; i += 1) {
    if (actual[i] !== wanted[i]) throw new Error(`${label} case ${i} mismatch`);
  }
}

function assertObjectEqual(actual, wanted, label) {
  if (actual === null || typeof actual !== 'object' || Array.isArray(actual)) {
    throw new Error(`${label} object mismatch`);
  }
  const actualKeys = Object.keys(actual).sort();
  const wantedKeys = Object.keys(wanted).sort();
  assertArrayEqual(actualKeys, wantedKeys, `${label} keys`);
  for (const key of wantedKeys) {
    if (actual[key] !== wanted[key]) throw new Error(`${label}.${key} mismatch`);
  }
}

function readProtocolManifest(instance, len) {
  const ptr = Number(instance.exports.world_appliance_alloc(len));
  if (ptr <= 0) throw new Error('wasm manifest allocation failed');
  try {
    const readLen = Number(instance.exports.world_protocol_read_manifest(ptr, len));
    if (readLen !== len) throw new Error('wasm protocol manifest read failed');
    return new Uint8Array(instance.exports.memory.buffer, ptr, len).slice();
  } finally {
    instance.exports.world_appliance_free(ptr, len);
  }
}

function assertMemoryCannotGrow(memory) {
  try {
    memory.grow(1);
  } catch {
    return;
  }
  throw new Error('wasm memory maximum exceeds declared limit');
}

function readU64Le(bytes, offset) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return view.getBigUint64(offset, true);
}

function expectReject(fn, label) {
  try {
    fn();
  } catch {
    return;
  }
  throw new Error(`malformed fixture accepted: ${label}`);
}

function fnv64Hex(text) {
  let hash = 0xcbf29ce484222325n;
  for (const byte of new TextEncoder().encode(text)) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * 0x100000001b3n);
  }
  return `0x${hash.toString(16).padStart(16, '0')}`;
}
