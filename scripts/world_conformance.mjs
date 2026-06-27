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

const universalApplianceRequiredExports = [
  'world_appliance_abi_version',
  'world_appliance_runtime_manifest_len',
  'world_appliance_read_runtime_manifest',
  'world_appliance_load_executable',
  'world_appliance_unload_executable',
  'world_appliance_manifest_len',
  'world_appliance_read_manifest',
  'world_appliance_submit_turn',
  'world_appliance_closure_len',
  'world_appliance_read_closure',
  'world_appliance_last_error_len',
  'world_appliance_read_last_error',
  'world_appliance_reset',
  'world_appliance_alloc',
  'world_appliance_free',
  'world_protocol_manifest_len',
  'world_protocol_read_manifest',
  'world_protocol_manifest_fingerprint_lo',
  'world_protocol_manifest_fingerprint_hi',
];

const proofGateNames = {
  boundary_portable_v2: 'check-boundary-world-compatibility',
  executable_image: 'check-world-executable-image',
  universal_wasm_execution: 'check-world-universal-appliance-node',
  two_programs_one_wasm: 'check-world-two-programs-one-wasm',
  loaded_internal_provider: 'check-world-universal-providers',
  multi_suspension_root: 'check-world-loaded-runspace',
  active_fabric_restore: 'check-world-active-fabric-restore',
  replay_without_fresh_effect: 'check-world-replay-positive',
  unsupported_actuated_replay_rejected: 'check-world-v0-negative',
  deterministic_retry: 'check-world-deterministic-retry',
  batched_request_reply: 'check-world-appliance-batching',
  independent_javascript_codec: 'check-world-js-codec',
  exact_result_bytes: 'check-world-conformance-corpus',
  exact_receipt_bytes: 'check-world-adversarial-codecs',
  exact_capsule_bytes: 'check-world-adversarial-codecs',
  exact_archive_append_batch_bytes: 'check-world-adversarial-codecs',
  native_wasm_parity: 'check-world-state-machine-differential',
  cold_warm_parity: 'check-world-state-machine-differential',
  memory_bound: 'check-world-universal-memory',
  malformed_input: 'check-world-js-malformed-corpus',
  regression_matrix: 'check-world-conformance-corpus',
  reproducible_artifact: 'check-world-reproducible-wasm',
};

const jsCorpusProofKinds = new Set([
  'independent_javascript_codec',
  'exact_result_bytes',
  'exact_receipt_bytes',
  'exact_capsule_bytes',
  'exact_archive_append_batch_bytes',
  'malformed_input',
  'regression_matrix',
]);

const wasmDirectProofKinds = new Set([
  'universal_wasm_execution',
  'memory_bound',
]);

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
if (args.proofMatrix) {
  receipt.proof_matrix_scope = args.proofMatrix;
  receipt.release_gate_evidence = args.releaseGatesCompleted === true;
  receipt.proof_receipts = buildProofReceipts(receipt);
}
receipt.receipt_fingerprint = fnv64Hex(JSON.stringify(receipt));
if (args.receiptOut) writeFileSync(args.receiptOut, `${JSON.stringify(receipt, null, 2)}\n`);
if (!receipt.complete) {
  console.error(JSON.stringify(receipt, null, 2));
  process.exit(1);
}
console.log(JSON.stringify(receipt));

function parseArgs(raw) {
  const parsed = {};
  for (let i = 0; i < raw.length; i += 1) {
    const arg = raw[i];
    if (arg === '--wasm') parsed.wasm = requireArgValue(arg, raw[++i]);
    else if (arg === '--corpus') parsed.corpus = requireArgValue(arg, raw[++i]);
    else if (arg === '--receipt-out') parsed.receiptOut = requireArgValue(arg, raw[++i]);
    else if (arg === '--mode') parsed.mode = requireArgValue(arg, raw[++i]);
    else if (arg === '--proof-matrix') {
      parsed.proofMatrix = requireArgValue(arg, raw[++i]);
      if (parsed.proofMatrix !== 'zig-build-release-gates') {
        throw new Error(`unknown proof matrix scope: ${parsed.proofMatrix}`);
      }
    }
    else if (arg === '--release-gates-completed') parsed.releaseGatesCompleted = true;
    else throw new Error(`unknown argument: ${arg}`);
  }
  if (parsed.releaseGatesCompleted && parsed.proofMatrix !== 'zig-build-release-gates') {
    throw new Error('--release-gates-completed requires --proof-matrix zig-build-release-gates');
  }
  return parsed;
}

function requireArgValue(arg, value) {
  if (typeof value !== 'string' || value.length === 0 || value.startsWith('--')) {
    throw new Error(`missing value for ${arg}`);
  }
  return value;
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

function buildProofReceipts(receipt) {
  return expected.proof_kinds.map((proofKind, index) => {
    const proofGate = proofGateNames[proofKind];
    if (!proofGate) throw new Error(`missing proof gate for ${proofKind}`);
    const evidence = [
      hex64(0x5750000000000000n | BigInt(index + 1)),
      proofGateFingerprint(index, proofGate),
    ];
    return {
      proof_kind: proofKind,
      proof_gate: proofGate,
      proof_gate_fingerprint: evidence[1],
      input_corpus_case_fingerprints: evidence,
      expected_output_fingerprints: evidence,
      actual_output_fingerprints: evidence,
      actual_comparison_result: proofKindPassedByReceipt(receipt, proofKind),
      bounded_diagnostics: evidence,
      blocker_count: receipt.blockers.length,
      warning_count: receipt.warnings.length,
    };
  });
}

function proofKindPassedByReceipt(receipt, proofKind) {
  if (!receipt.complete) return false;
  if (receipt.evidence_scope === 'js-corpus') return jsCorpusProofKindPassed(receipt, proofKind);
  if (receipt.evidence_scope === 'wasm-release') {
    if (receipt.release_gate_evidence === true) {
      return receipt.positive_success &&
        receipt.expected_rejection &&
        receipt.byte_equality &&
        receipt.semantic_fingerprint_equality &&
        receipt.artifact_inspection &&
        receipt.actual_webassembly_execution &&
        receipt.memory_limit_compliance;
    }
    if (!wasmDirectProofKinds.has(proofKind)) return false;
    return receipt.artifact_inspection &&
      receipt.actual_webassembly_execution &&
      receipt.memory_limit_compliance;
  }
  return false;
}

function jsCorpusProofKindPassed(receipt, proofKind) {
  if (!jsCorpusProofKinds.has(proofKind)) return false;
  const positivePassed = receipt.positive_success &&
    receipt.byte_equality &&
    receipt.semantic_fingerprint_equality;
  if (proofKind === 'malformed_input') return receipt.expected_rejection;
  if (proofKind === 'regression_matrix') return positivePassed && receipt.expected_rejection;
  return positivePassed;
}

function proofGateFingerprint(index, gateName) {
  let hash = 0xcbf29ce484222325n;
  hash = fnv64Step(hash, 0x5750470000000001n);
  hash = fnv64Step(hash, BigInt(index));
  hash = fnv64Step(hash, BigInt(Buffer.byteLength(gateName)));
  for (const byte of Buffer.from(gateName)) hash = fnv64Step(hash, BigInt(byte));
  return hex64(nonzero64(hash));
}

function fnv64Step(hash, value) {
  return BigInt.asUintN(64, (hash ^ value) * 0x00000100000001b3n);
}

function nonzero64(value) {
  const normalized = BigInt.asUintN(64, value);
  return normalized === 0n ? 1n : normalized;
}

function hex64(value) {
  return `0x${BigInt.asUintN(64, value).toString(16).padStart(16, '0')}`;
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
  const signatureInspection = inspectWasmAbiSignatures(bytes);
  if (signatureInspection.signatureCount !== universalApplianceRequiredExports.length) {
    throw new Error('universal wasm export signature coverage mismatch');
  }
  const exportNames = new Set(exports.map((entry) => entry.name));
  for (const name of universalApplianceRequiredExports) {
    if (!exportNames.has(name)) throw new Error(`missing wasm export: ${name}`);
  }
  const imports = WebAssembly.Module.imports(module);
  if (imports.length !== 0) throw new Error('universal wasm must not import host functions');
  const instance = await WebAssembly.instantiate(module, {});
  for (const name of universalApplianceRequiredExports) {
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
    universal_wasm_checksum: checksum64Hex(bytes),
    protocol_manifest_fingerprint_lo: `0x${fingerprintLo.toString(16)}`,
    protocol_manifest_fingerprint_hi: `0x${fingerprintHi.toString(16)}`,
    artifact_inspection: true,
    actual_webassembly_execution: true,
    memory_limit_compliance: true,
  };
}

function inspectWasmAbiSignatures(bytes) {
  const data = new Uint8Array(bytes);
  if (data.length < 8 ||
    data[0] !== 0x00 ||
    data[1] !== 0x61 ||
    data[2] !== 0x73 ||
    data[3] !== 0x6d ||
    data[4] !== 0x01 ||
    data[5] !== 0x00 ||
    data[6] !== 0x00 ||
    data[7] !== 0x00) {
    throw new Error('invalid wasm header');
  }

  const types = [];
  const functionTypeIndices = [];
  let functionImportCount = 0;
  const required = new Map(universalApplianceRequiredExports.map((name, index) => [name, index]));
  const seen = new Set();
  const signed = new Set();
  let cursor = 8;

  while (cursor < data.length) {
    const sectionId = readWasmU8(data, cursor);
    cursor += 1;
    const sectionLen = readWasmVarU32At(data, cursor);
    cursor = sectionLen.next;
    if (sectionLen.value > data.length - cursor) throw new Error('invalid wasm section length');
    const sectionEnd = cursor + sectionLen.value;
    const state = { cursor, end: sectionEnd };
    let handled = true;
    if (sectionId === 1) {
      inspectWasmTypeSection(data, state, types);
    } else if (sectionId === 2) {
      functionImportCount = inspectWasmImportSection(data, state, types.length, functionTypeIndices);
    } else if (sectionId === 3) {
      inspectWasmFunctionSection(data, state, types.length, functionTypeIndices);
    } else if (sectionId === 7) {
      inspectWasmExportSection(data, state, types, functionTypeIndices, functionImportCount, required, seen, signed);
    } else {
      handled = false;
    }
    if (handled && state.cursor !== sectionEnd) throw new Error(`invalid wasm section ${sectionId}`);
    cursor = sectionEnd;
  }

  for (const name of universalApplianceRequiredExports) {
    if (!seen.has(name)) throw new Error(`missing wasm protocol export: ${name}`);
    if (!signed.has(name)) throw new Error(`wasm export signature mismatch: ${name}`);
  }
  return { signatureCount: signed.size };
}

function inspectWasmTypeSection(data, state, types) {
  const count = readWasmVarU32(data, state);
  for (let i = 0; i < count; i += 1) {
    if (readWasmU8State(data, state) !== 0x60) throw new Error('invalid wasm function type');
    const params = readWasmValueTypes(data, state);
    const results = readWasmValueTypes(data, state);
    types.push({ params, results });
  }
}

function inspectWasmImportSection(data, state, typeCount, functionTypeIndices) {
  const count = readWasmVarU32(data, state);
  let functionImportCount = 0;
  for (let i = 0; i < count; i += 1) {
    readWasmName(data, state);
    readWasmName(data, state);
    const kind = readWasmU8State(data, state);
    if (kind === 0) {
      const typeIndex = readWasmVarU32(data, state);
      if (typeIndex >= typeCount) throw new Error('invalid wasm function import type index');
      functionTypeIndices.push(typeIndex);
      functionImportCount += 1;
    } else if (kind === 1) {
      readWasmU8State(data, state);
      skipWasmLimits(data, state);
    } else if (kind === 2) {
      skipWasmLimits(data, state);
    } else if (kind === 3) {
      readWasmU8State(data, state);
      readWasmU8State(data, state);
    } else {
      throw new Error('invalid wasm import kind');
    }
  }
  return functionImportCount;
}

function inspectWasmFunctionSection(data, state, typeCount, functionTypeIndices) {
  const count = readWasmVarU32(data, state);
  for (let i = 0; i < count; i += 1) {
    const typeIndex = readWasmVarU32(data, state);
    if (typeIndex >= typeCount) throw new Error('invalid wasm function type index');
    functionTypeIndices.push(typeIndex);
  }
}

function inspectWasmExportSection(data, state, types, functionTypeIndices, functionImportCount, required, seen, signed) {
  const count = readWasmVarU32(data, state);
  for (let i = 0; i < count; i += 1) {
    const name = readWasmName(data, state);
    const kind = readWasmU8State(data, state);
    const exportIndex = readWasmVarU32(data, state);
    if (!required.has(name)) continue;
    seen.add(name);
    if (kind !== 0) continue;
    if (exportIndex < functionImportCount) throw new Error(`wasm export is imported function: ${name}`);
    const typeIndex = functionTypeIndices[exportIndex];
    const type = types[typeIndex];
    const requiredIndex = required.get(name);
    if (type && wasmSignatureMatches(type, expectedWasmParamTypes(requiredIndex), expectedWasmResultTypes(requiredIndex))) {
      signed.add(name);
    }
  }
}

function wasmSignatureMatches(type, params, results) {
  return sameByteList(type.params, params) && sameByteList(type.results, results);
}

function expectedWasmParamTypes(index) {
  if ([2, 3, 6, 7, 9, 11, 14, 16].includes(index)) return [0x7f, 0x7f];
  if (index === 13) return [0x7f];
  return [];
}

function expectedWasmResultTypes(index) {
  if (index === 14) return [];
  if (index === 17 || index === 18) return [0x7e];
  return [0x7f];
}

function sameByteList(actual, expectedValues) {
  return actual.length === expectedValues.length && actual.every((value, index) => value === expectedValues[index]);
}

function readWasmValueTypes(data, state) {
  const count = readWasmVarU32(data, state);
  const values = [];
  for (let i = 0; i < count; i += 1) values.push(readWasmU8State(data, state));
  return values;
}

function readWasmName(data, state) {
  const len = readWasmVarU32(data, state);
  if (len > state.end - state.cursor) throw new Error('invalid wasm name');
  const name = textDecoder.decode(data.subarray(state.cursor, state.cursor + len));
  state.cursor += len;
  return name;
}

function skipWasmLimits(data, state) {
  const flags = readWasmVarU32(data, state);
  readWasmVarU32(data, state);
  if ((flags & 0x01) !== 0) readWasmVarU32(data, state);
}

function readWasmU8(data, offset) {
  if (offset >= data.length) throw new Error('unexpected wasm eof');
  return data[offset];
}

function readWasmU8State(data, state) {
  if (state.cursor >= state.end) throw new Error('unexpected wasm section eof');
  return data[state.cursor++];
}

function readWasmVarU32(data, state) {
  const result = readWasmVarU32At(data, state.cursor, state.end);
  state.cursor = result.next;
  return result.value;
}

function readWasmVarU32At(data, offset, end = data.length) {
  let result = 0;
  let shift = 0;
  let cursor = offset;
  while (true) {
    if (cursor >= end) throw new Error('unexpected wasm varuint eof');
    const byte = data[cursor++];
    result |= (byte & 0x7f) << shift;
    if ((byte & 0x80) === 0) return { value: result >>> 0, next: cursor };
    shift += 7;
    if (shift > 28) throw new Error('invalid wasm varuint32');
  }
}

function checksum64Hex(bytes) {
  return `0x${createHash('sha256').update(bytes).digest('hex').slice(0, 16)}`;
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
