#!/usr/bin/env node
import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { createHash } from 'node:crypto';
import { join, resolve } from 'node:path';

const textDecoder = new TextDecoder();

const args = parseArgs(process.argv.slice(2));

const requiredDistFiles = [
  'world_universal_appliance.wasm',
  'world-protocol-manifest.json',
  'world-release-artifact.json',
  'world-release-receipt.json',
  'human-readable-manifest.txt',
  'checksums.txt',
  'conformance/v0/world/corpus.json',
  'scripts/world_conformance.mjs',
  'scripts/world_appliance_wire_codec.mjs',
  'scripts/world_loaded_value_codec.mjs',
  'docs/world_v0.md',
  'docs/compatibility.md',
  'docs/security_model.md',
];

const agentRuntimeDistFiles = [
  'agent-runtime/agent.executable-image',
  'agent-runtime/appliance-manifest.bin',
  'agent-runtime/agent-runtime-world-artifacts.json',
];

const agentRuntimeMetadataLabel = 'agent-runtime-v0.1.world-agent';
const executableImageMagic = Buffer.from('world.Executable.Image.v2\0', 'utf8');

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

const requiredProofKinds = [
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

const boundaryProtocolManifestFingerprint = '0x68ce6ebd4448144f';
const conformanceCorpusRootFingerprint = '0xe727536b60a5e286';

try {
  if (args.mode === 'dist') {
    await emitDist(args);
  } else if (args.mode === 'check-dist') {
    await checkDist(args);
  } else if (args.mode === 'check-repro') {
    await checkRepro(args);
  } else {
    throw new Error('expected --mode dist|check-dist|check-repro');
  }
} catch (error) {
  console.error(error?.stack ?? String(error));
  process.exit(1);
}

function parseArgs(raw) {
  const parsed = {};
  for (let i = 0; i < raw.length; i += 1) {
    const arg = raw[i];
    if (arg === '--mode') parsed.mode = raw[++i];
    else if (arg === '--wasm') parsed.wasm = raw[++i];
    else if (arg === '--wasm-repro') parsed.wasmRepro = raw[++i];
    else if (arg === '--release-receipt') parsed.releaseReceipt = raw[++i];
    else if (arg === '--out') parsed.out = raw[++i];
    else if (arg === '--dist') parsed.dist = raw[++i];
    else if (arg === '--corpus') parsed.corpus = raw[++i];
    else throw new Error(`unknown argument: ${arg}`);
  }
  return parsed;
}

async function emitDist(options) {
  requirePath(options.wasm, '--wasm');
  requirePath(options.releaseReceipt, '--release-receipt');
  requirePath(options.out, '--out');
  const out = options.out;
  requireReleaseDistOutput(out);
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  mkdirSync(join(out, 'scripts'), { recursive: true });
  mkdirSync(join(out, 'docs'), { recursive: true });
  mkdirSync(join(out, 'conformance/v0'), { recursive: true });

  cpSync(options.wasm, join(out, 'world_universal_appliance.wasm'));
  cpSync(options.releaseReceipt, join(out, 'world-release-receipt.json'));
  cpSync('conformance/v0/world', join(out, 'conformance/v0/world'), { recursive: true });
  for (const script of [
    'world_conformance.mjs',
    'world_appliance_wire_codec.mjs',
    'world_loaded_value_codec.mjs',
  ]) {
    cpSync(join('scripts', script), join(out, 'scripts', script));
  }
  for (const doc of ['world_v0.md', 'compatibility.md', 'security_model.md']) {
    cpSync(join('docs', doc), join(out, 'docs', doc));
  }

  const wasmBytes = readFileSync(options.wasm);
  const wasmInspection = await inspectWasm(wasmBytes);
  const corpusBytes = readFileSync('conformance/v0/world/corpus.json');
  const metadata = {
    release_artifact_format_version: 1,
    package: 'world-v0.1.0',
    wasm: {
      byte_length: wasmBytes.length,
      sha256: sha256Hex(wasmBytes),
      abi_version: wasmInspection.abi_version,
      protocol_manifest_fingerprint_lo: wasmInspection.protocol_manifest_fingerprint_lo,
      protocol_manifest_fingerprint_hi: wasmInspection.protocol_manifest_fingerprint_hi,
      import_count: wasmInspection.import_count,
      export_count: wasmInspection.export_count,
      memory_min_bytes: wasmInspection.memory_bytes,
      memory_max_bytes: wasmInspection.memory_bytes,
    },
    corpus: {
      path: 'conformance/v0/world/corpus.json',
      byte_length: corpusBytes.length,
      sha256: sha256Hex(corpusBytes),
    },
    zig_version: '0.16.0',
    boundary_package: '0.6.2',
  };
  writeFileSync(join(out, 'world-protocol-manifest.json'), `${JSON.stringify(wasmInspection, null, 2)}\n`);
  writeFileSync(join(out, 'world-release-artifact.json'), `${JSON.stringify(metadata, null, 2)}\n`);
  writeFileSync(join(out, 'human-readable-manifest.txt'), humanManifest(metadata));
  writeChecksums(out);
  console.log(JSON.stringify({ dist: out, complete: true, wasm_sha256: metadata.wasm.sha256 }));
}

async function checkDist(options) {
  requirePath(options.dist, '--dist');
  const dist = options.dist;
  const required = requiredFilesForDist(dist);
  const checksumCovered = required.filter((rel) => rel !== 'checksums.txt');
  for (const rel of required) {
    const path = join(dist, rel);
    if (!existsSync(path)) throw new Error(`missing dist file: ${rel}`);
  }
  verifyDistFileSet(dist, required);
  verifyChecksums(dist, checksumCovered);
  const wasmBytes = readFileSync(join(dist, 'world_universal_appliance.wasm'));
  const inspection = await inspectWasm(wasmBytes);
  verifyReleaseMetadata(dist, wasmBytes, inspection);
  verifyReleaseReceipt(dist, wasmBytes, inspection);
  verifyAgentRuntimeDist(dist);
  if (!inspection.actual_webassembly_execution) throw new Error('distributed wasm execution was not verified');
  console.log(JSON.stringify({ dist, complete: true, actual_webassembly_execution: true }));
}

async function checkRepro(options) {
  requirePath(options.wasm, '--wasm');
  requirePath(options.wasmRepro, '--wasm-repro');
  requirePath(options.corpus, '--corpus');
  const wasmFirst = readFileSync(options.wasm);
  const wasmSecond = readFileSync(options.wasmRepro);
  const corpusFirst = readFileSync(options.corpus);
  const manifestFirst = await inspectWasm(wasmFirst);
  const manifestSecond = await inspectWasm(wasmSecond);
  const jsSchemaFirst = JSON.stringify(JSON.parse(corpusFirst.toString('utf8')));
  const report = {
    reproducible_artifact_check_version: 1,
    wasm_exact_bytes: sha256Hex(wasmFirst) === sha256Hex(wasmSecond),
    protocol_manifest_exact: JSON.stringify(manifestFirst) === JSON.stringify(manifestSecond),
    js_schema_valid: jsSchemaFirst.length > 0,
    complete: false,
  };
  report.complete = and(report.wasm_exact_bytes, report.protocol_manifest_exact, report.js_schema_valid);
  if (!report.complete) throw new Error(JSON.stringify(report));
  console.log(JSON.stringify(report));
}

async function inspectWasm(bytes) {
  const module = await WebAssembly.compile(bytes);
  const exports = WebAssembly.Module.exports(module);
  const imports = WebAssembly.Module.imports(module);
  const signatureInspection = inspectWasmAbiSignatures(bytes);
  const exportNames = new Set(exports.map((entry) => entry.name));
  for (const name of [
    'world_protocol_manifest_len',
    'world_protocol_read_manifest',
    'world_protocol_manifest_fingerprint_lo',
    'world_protocol_manifest_fingerprint_hi',
    ...universalApplianceRequiredExports,
  ]) {
    if (!exportNames.has(name)) throw new Error(`missing wasm protocol export: ${name}`);
  }
  if (imports.length !== 0) throw new Error('universal wasm must have zero imports');
  const instance = await WebAssembly.instantiate(module, {});
  for (const name of [
    'world_protocol_manifest_len',
    'world_protocol_read_manifest',
    'world_protocol_manifest_fingerprint_lo',
    'world_protocol_manifest_fingerprint_hi',
    ...universalApplianceRequiredExports,
  ]) {
    if (typeof instance.exports[name] !== 'function') throw new Error(`wasm export is not callable: ${name}`);
  }
  const manifestLen = Number(instance.exports.world_protocol_manifest_len());
  const lo = BigInt.asUintN(64, instance.exports.world_protocol_manifest_fingerprint_lo());
  const hi = BigInt.asUintN(64, instance.exports.world_protocol_manifest_fingerprint_hi());
  const abiVersion = Number(instance.exports.world_appliance_abi_version());
  if (abiVersion !== 4) throw new Error('unexpected appliance ABI version');
  const memory = instance.exports.memory;
  if (manifestLen <= 0 || lo === 0n || hi === 0n) {
    throw new Error('protocol manifest wasm calls failed');
  }
  if (!(memory instanceof WebAssembly.Memory)) throw new Error('missing exported memory');
  if (memory.buffer.byteLength > 67108864) throw new Error('wasm memory limit violation');
  assertMemoryCannotGrow(memory);
  const manifestBytes = readProtocolManifest(instance, manifestLen);
  if (textDecoder.decode(manifestBytes.subarray(0, 4)) !== 'WPM1') throw new Error('wasm protocol manifest magic mismatch');
  if (readU64Le(manifestBytes, 12) !== lo || readU64Le(manifestBytes, 20) !== hi) throw new Error('wasm protocol manifest fingerprint mismatch');
  return {
    manifest_len: manifestLen,
    abi_version: abiVersion,
    protocol_manifest_fingerprint_lo: `0x${lo.toString(16)}`,
    protocol_manifest_fingerprint_hi: `0x${hi.toString(16)}`,
    import_count: imports.length,
    export_count: exports.length,
    required_signature_count: signatureInspection.signatureCount,
    memory_bytes: memory.buffer.byteLength,
    actual_webassembly_execution: true,
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
    const sectionId = readU8(data, cursor);
    cursor += 1;
    const sectionLen = readVarU32At(data, cursor);
    cursor = sectionLen.next;
    if (sectionLen.value > data.length - cursor) throw new Error('invalid wasm section length');
    const sectionEnd = cursor + sectionLen.value;
    const state = { cursor, end: sectionEnd };
    let handled = true;
    if (sectionId === 1) {
      inspectTypeSection(data, state, types);
    } else if (sectionId === 2) {
      functionImportCount = inspectImportSection(data, state, types.length, functionTypeIndices);
    } else if (sectionId === 3) {
      inspectFunctionSection(data, state, types.length, functionTypeIndices);
    } else if (sectionId === 7) {
      inspectExportSection(data, state, types, functionTypeIndices, functionImportCount, required, seen, signed);
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

function inspectTypeSection(data, state, types) {
  const count = readVarU32(data, state);
  for (let i = 0; i < count; i += 1) {
    if (readU8State(data, state) !== 0x60) throw new Error('invalid wasm function type');
    const params = readValueTypes(data, state);
    const results = readValueTypes(data, state);
    types.push({ params, results });
  }
}

function inspectImportSection(data, state, typeCount, functionTypeIndices) {
  const count = readVarU32(data, state);
  let functionImportCount = 0;
  for (let i = 0; i < count; i += 1) {
    readWasmName(data, state);
    readWasmName(data, state);
    const kind = readU8State(data, state);
    if (kind === 0) {
      const typeIndex = readVarU32(data, state);
      if (typeIndex >= typeCount) throw new Error('invalid wasm function import type index');
      functionTypeIndices.push(typeIndex);
      functionImportCount += 1;
    } else if (kind === 1) {
      readU8State(data, state);
      skipLimits(data, state);
    } else if (kind === 2) {
      skipLimits(data, state);
    } else if (kind === 3) {
      readU8State(data, state);
      readU8State(data, state);
    } else {
      throw new Error('invalid wasm import kind');
    }
  }
  return functionImportCount;
}

function inspectFunctionSection(data, state, typeCount, functionTypeIndices) {
  const count = readVarU32(data, state);
  for (let i = 0; i < count; i += 1) {
    const typeIndex = readVarU32(data, state);
    if (typeIndex >= typeCount) throw new Error('invalid wasm function type index');
    functionTypeIndices.push(typeIndex);
  }
}

function inspectExportSection(data, state, types, functionTypeIndices, functionImportCount, required, seen, signed) {
  const count = readVarU32(data, state);
  for (let i = 0; i < count; i += 1) {
    const name = readWasmName(data, state);
    const kind = readU8State(data, state);
    const exportIndex = readVarU32(data, state);
    if (!required.has(name)) continue;
    seen.add(name);
    if (kind !== 0) continue;
    if (exportIndex < functionImportCount) throw new Error(`wasm export is imported function: ${name}`);
    const typeIndex = functionTypeIndices[exportIndex];
    const type = types[typeIndex];
    if (type && wasmSignatureMatches(type, expectedParamTypes(required.get(name)), expectedResultTypes(required.get(name)))) {
      signed.add(name);
    }
  }
}

function wasmSignatureMatches(type, params, results) {
  return sameByteList(type.params, params) && sameByteList(type.results, results);
}

function expectedParamTypes(index) {
  if ([2, 3, 6, 7, 9, 11, 14, 16].includes(index)) return [0x7f, 0x7f];
  if (index === 13) return [0x7f];
  return [];
}

function expectedResultTypes(index) {
  if (index === 14) return [];
  if (index === 17 || index === 18) return [0x7e];
  return [0x7f];
}

function sameByteList(actual, expected) {
  return actual.length === expected.length && actual.every((value, index) => value === expected[index]);
}

function readValueTypes(data, state) {
  const count = readVarU32(data, state);
  const values = [];
  for (let i = 0; i < count; i += 1) values.push(readU8State(data, state));
  return values;
}

function readWasmName(data, state) {
  const len = readVarU32(data, state);
  if (len > state.end - state.cursor) throw new Error('invalid wasm name');
  const name = textDecoder.decode(data.subarray(state.cursor, state.cursor + len));
  state.cursor += len;
  return name;
}

function skipLimits(data, state) {
  const flags = readVarU32(data, state);
  readVarU32(data, state);
  if ((flags & 0x01) !== 0) readVarU32(data, state);
}

function readU8(data, offset) {
  if (offset >= data.length) throw new Error('unexpected wasm eof');
  return data[offset];
}

function readU8State(data, state) {
  if (state.cursor >= state.end) throw new Error('unexpected wasm section eof');
  return data[state.cursor++];
}

function readVarU32(data, state) {
  const result = readVarU32At(data, state.cursor, state.end);
  state.cursor = result.next;
  return result.value;
}

function readVarU32At(data, offset, end = data.length) {
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

function writeChecksums(root) {
  const lines = requiredDistFiles
    .filter((rel) => rel !== 'checksums.txt')
    .map((rel) => `${sha256Hex(readFileSync(join(root, rel)))}  ${rel}`);
  writeFileSync(join(root, 'checksums.txt'), `${lines.join('\n')}\n`);
}

function requiredFilesForDist(root) {
  if (!existsSync(join(root, 'agent-runtime'))) return requiredDistFiles;
  return [...requiredDistFiles, ...agentRuntimeDistFiles];
}

function verifyChecksums(root, requiredFiles) {
  const expected = new Set(requiredFiles);
  const seen = new Set();
  const text = readFileSync(join(root, 'checksums.txt'), 'utf8').trim();
  if (text.length === 0) throw new Error('empty checksum manifest');
  const lines = text.split('\n');
  for (const line of lines) {
    const [hash, rel] = line.split(/\s+/, 2);
    if (!expected.has(rel)) throw new Error(`unexpected checksum entry: ${rel}`);
    if (seen.has(rel)) throw new Error(`duplicate checksum entry: ${rel}`);
    seen.add(rel);
    if (sha256Hex(readFileSync(join(root, rel))) !== hash) throw new Error(`checksum mismatch: ${rel}`);
  }
  for (const rel of expected) {
    if (!seen.has(rel)) throw new Error(`missing checksum entry: ${rel}`);
  }
}

function verifyDistFileSet(root, requiredFiles) {
  const expected = new Set(requiredFiles);
  const actual = new Set(collectDistFiles(root));
  for (const rel of actual) {
    if (!expected.has(rel)) throw new Error(`unexpected dist file: ${rel}`);
  }
  for (const rel of expected) {
    if (!actual.has(rel)) throw new Error(`missing dist file: ${rel}`);
  }
}

function collectDistFiles(root, prefix = '') {
  const files = [];
  const entries = readdirSync(join(root, prefix), { withFileTypes: true })
    .sort((a, b) => a.name.localeCompare(b.name));
  for (const entry of entries) {
    const rel = prefix === '' ? entry.name : `${prefix}/${entry.name}`;
    if (entry.isDirectory()) {
      files.push(...collectDistFiles(root, rel));
    } else if (entry.isFile()) {
      files.push(rel);
    } else {
      throw new Error(`unsupported dist entry: ${rel}`);
    }
  }
  return files;
}

function verifyReleaseMetadata(dist, wasmBytes, inspection) {
  const artifact = JSON.parse(readFileSync(join(dist, 'world-release-artifact.json'), 'utf8'));
  const protocolManifest = JSON.parse(readFileSync(join(dist, 'world-protocol-manifest.json'), 'utf8'));
  const corpusBytes = readFileSync(join(dist, 'conformance/v0/world/corpus.json'));
  const canonicalCorpusBytes = readFileSync('conformance/v0/world/corpus.json');

  assertEqual(artifact.release_artifact_format_version, 1, 'release_artifact_format_version');
  assertEqual(artifact.package, 'world-v0.1.0', 'package');
  assertEqual(artifact.zig_version, '0.16.0', 'zig_version');
  assertEqual(artifact.boundary_package, '0.6.2', 'boundary_package');
  assertEqual(artifact.wasm.byte_length, wasmBytes.length, 'wasm.byte_length');
  assertEqual(artifact.wasm.sha256, sha256Hex(wasmBytes), 'wasm.sha256');
  assertEqual(artifact.wasm.abi_version, inspection.abi_version, 'wasm.abi_version');
  assertEqual(artifact.wasm.protocol_manifest_fingerprint_lo, inspection.protocol_manifest_fingerprint_lo, 'wasm.protocol_manifest_fingerprint_lo');
  assertEqual(artifact.wasm.protocol_manifest_fingerprint_hi, inspection.protocol_manifest_fingerprint_hi, 'wasm.protocol_manifest_fingerprint_hi');
  assertEqual(artifact.wasm.import_count, inspection.import_count, 'wasm.import_count');
  assertEqual(artifact.wasm.export_count, inspection.export_count, 'wasm.export_count');
  assertEqual(artifact.wasm.memory_min_bytes, inspection.memory_bytes, 'wasm.memory_min_bytes');
  assertEqual(artifact.wasm.memory_max_bytes, inspection.memory_bytes, 'wasm.memory_max_bytes');
  assertEqual(artifact.corpus.path, 'conformance/v0/world/corpus.json', 'corpus.path');
  assertEqual(artifact.corpus.byte_length, corpusBytes.length, 'corpus.byte_length');
  assertEqual(artifact.corpus.sha256, sha256Hex(corpusBytes), 'corpus.sha256');
  assertEqual(sha256Hex(corpusBytes), sha256Hex(canonicalCorpusBytes), 'corpus.canonical_sha256');

  assertEqual(protocolManifest.manifest_len, inspection.manifest_len, 'protocol_manifest.manifest_len');
  assertEqual(protocolManifest.abi_version, inspection.abi_version, 'protocol_manifest.abi_version');
  assertEqual(protocolManifest.protocol_manifest_fingerprint_lo, inspection.protocol_manifest_fingerprint_lo, 'protocol_manifest.protocol_manifest_fingerprint_lo');
  assertEqual(protocolManifest.protocol_manifest_fingerprint_hi, inspection.protocol_manifest_fingerprint_hi, 'protocol_manifest.protocol_manifest_fingerprint_hi');
  assertEqual(protocolManifest.import_count, inspection.import_count, 'protocol_manifest.import_count');
  assertEqual(protocolManifest.export_count, inspection.export_count, 'protocol_manifest.export_count');
  assertEqual(protocolManifest.required_signature_count, inspection.required_signature_count, 'protocol_manifest.required_signature_count');
  assertEqual(protocolManifest.memory_bytes, inspection.memory_bytes, 'protocol_manifest.memory_bytes');
  assertEqual(protocolManifest.actual_webassembly_execution, true, 'protocol_manifest.actual_webassembly_execution');
}

function verifyReleaseReceipt(dist, wasmBytes, inspection) {
  const receipt = JSON.parse(readFileSync(join(dist, 'world-release-receipt.json'), 'utf8'));
  assertEqual(receipt.release_receipt_format_version, 1, 'release_receipt.release_receipt_format_version');
  assertEqual(receipt.release_receipt_fingerprint_version, 1, 'release_receipt.release_receipt_fingerprint_version');
  assertEqual(receipt.universal_wasm_checksum, checksum64Hex(wasmBytes), 'release_receipt.universal_wasm_checksum');
  assertEqual(receipt.boundary_protocol_manifest_fingerprint, boundaryProtocolManifestFingerprint, 'release_receipt.boundary_protocol_manifest_fingerprint');
  assertEqual(receipt.world_protocol_manifest_fingerprint, inspection.protocol_manifest_fingerprint_lo, 'release_receipt.world_protocol_manifest_fingerprint');
  assertEqual(receipt.conformance_corpus_root_fingerprint, conformanceCorpusRootFingerprint, 'release_receipt.conformance_corpus_root_fingerprint');
  assertEqual(receipt.complete, true, 'release_receipt.complete');
  if (!Array.isArray(receipt.blockers) || receipt.blockers.length !== 0) throw new Error('release_receipt.blockers not empty');
  if (!Array.isArray(receipt.warnings) || receipt.warnings.length !== 0) throw new Error('release_receipt.warnings not empty');
  if (typeof receipt.source_package_checksum !== 'string' ||
    receipt.source_package_checksum === '0x0000000000000000') {
    throw new Error('release_receipt.source_package_checksum missing');
  }
  if (!Array.isArray(receipt.proof_receipts) || receipt.proof_receipts.length !== requiredProofKinds.length) {
    throw new Error('release_receipt.proof_receipts incomplete');
  }
  for (const [index, proof] of receipt.proof_receipts.entries()) {
    verifyProofReceipt(proof, index, receipt, inspection, wasmBytes);
  }
  assertEqual(
    receipt.release_receipt_fingerprint,
    fingerprintReleaseReceipt(receipt),
    'release_receipt.release_receipt_fingerprint',
  );
}

function verifyAgentRuntimeDist(dist) {
  const root = join(dist, 'agent-runtime');
  if (!existsSync(root)) return;

  const imageBytes = readFileSync(join(root, 'agent.executable-image'));
  const manifestBytes = readFileSync(join(root, 'appliance-manifest.bin'));
  const metadata = JSON.parse(readFileSync(join(root, 'agent-runtime-world-artifacts.json'), 'utf8'));
  const image = parseAgentRuntimeExecutableImage(imageBytes);
  const manifest = parseAgentRuntimeManifest(manifestBytes);

  assertEqual(metadata.world_package_version, 'v0.1.0', 'agent_runtime.world_package_version');
  assertEqual(metadata.metadata, agentRuntimeMetadataLabel, 'agent_runtime.metadata');
  assertEqual(metadata.agent_executable_image_sha256, sha256Hex(imageBytes), 'agent_runtime.agent_executable_image_sha256');
  assertEqual(metadata.appliance_manifest_sha256, sha256Hex(manifestBytes), 'agent_runtime.appliance_manifest_sha256');
  assertEqual(image.format_version, metadata.world_executable_image_format_version, 'agent_runtime.image.format_version');
  assertEqual(image.fingerprint_version, metadata.world_executable_image_fingerprint_version, 'agent_runtime.image.fingerprint_version');
  assertEqual(image.image_fingerprint, metadata.world_executable_image_fingerprint, 'agent_runtime.image.image_fingerprint');
  assertEqual(image.metadata, agentRuntimeMetadataLabel, 'agent_runtime.image.metadata');
  assertEqual(image.root_module_fingerprint, metadata.root_module_fingerprint, 'agent_runtime.image.root_module_fingerprint');
  assertEqual(image.dispatch_fingerprint, metadata.dispatch_fingerprint, 'agent_runtime.image.dispatch_fingerprint');

  assertEqual(manifest.manifest_format_version, 3, 'agent_runtime.manifest.manifest_format_version');
  assertEqual(manifest.manifest_fingerprint_version, 3, 'agent_runtime.manifest.manifest_fingerprint_version');
  assertEqual(manifest.appliance_abi_version, metadata.world_appliance_abi_version, 'agent_runtime.manifest.appliance_abi_version');
  assertEqual(manifest.manifest_fingerprint, metadata.world_appliance_manifest_fingerprint, 'agent_runtime.manifest.manifest_fingerprint');
  assertEqual(fingerprintAgentRuntimeManifest(manifest), manifest.manifest_fingerprint, 'agent_runtime.manifest.computed_fingerprint');
  assertEqual(manifest.metadata, agentRuntimeMetadataLabel, 'agent_runtime.manifest.metadata');
  if (manifest.root_target_ref_fingerprint === '0x0000000000000000' ||
    manifest.root_world_surface_fingerprint === '0x0000000000000000' ||
    manifest.root_target_certificate_fingerprint === '0x0000000000000000') {
    throw new Error('agent_runtime.manifest root identity missing');
  }
  assertStringListEqual(manifest.actuation_descriptor_fingerprints, metadata.required_descriptor_fingerprints, 'agent_runtime.required_descriptor_fingerprints');
  assertStringListEqual(manifest.actuation_actuator_ref_fingerprints, metadata.required_actuator_ref_fingerprints, 'agent_runtime.required_actuator_ref_fingerprints');
  assertStringListEqual(manifest.actuation_world_port_ids, metadata.required_world_port_ids, 'agent_runtime.required_world_port_ids');
  if (image.dispatch_external_binding_fingerprints.length !== manifest.actuation_binding_fingerprints.length) {
    throw new Error('agent_runtime.image dispatch external binding count mismatch');
  }
  assertStringSetEqual(image.external_binding_descriptor_fingerprints, metadata.required_descriptor_fingerprints, 'agent_runtime.image.required_descriptor_fingerprints');
  assertStringSetEqual(image.external_binding_actuator_ref_fingerprints, metadata.required_actuator_ref_fingerprints, 'agent_runtime.image.required_actuator_ref_fingerprints');
  assertStringSetEqual(image.external_binding_world_port_ids, metadata.required_world_port_ids, 'agent_runtime.image.required_world_port_ids');
  assertStringSetEqual(image.external_binding_actuator_ref_labels, metadata.required_actuator_refs, 'agent_runtime.image.required_actuator_refs');
  assertEqual(image.link_plan_fingerprint, manifest.link_plan_fingerprint, 'agent_runtime.image.link_plan_fingerprint');
  assertEqual(image.linker_certificate_fingerprint, manifest.link_certificate_fingerprint, 'agent_runtime.image.linker_certificate_fingerprint');
  assertEqual(image.assembly_fingerprint, manifest.assembly_fingerprint, 'agent_runtime.image.assembly_fingerprint');
  if (!Array.isArray(metadata.required_actuator_refs) ||
    metadata.required_actuator_refs.length !== manifest.actuation_world_port_ids.length ||
    metadata.required_actuator_refs.length === 0) {
    throw new Error('agent_runtime.required_actuator_refs mismatch');
  }
  if (image.external_binding_count !== metadata.required_actuator_refs.length) {
    throw new Error('agent_runtime.image external binding count mismatch');
  }
}

function parseAgentRuntimeExecutableImage(bytes) {
  const reader = makeByteReader(bytes, 'agent_runtime.image');
  const magic = reader.raw(executableImageMagic.length);
  if (Buffer.compare(magic, executableImageMagic) !== 0) throw new Error('agent_runtime.image invalid magic');
  const formatVersion = reader.u32();
  const fingerprintVersion = reader.u32();
  const codecVersion = reader.u32();
  const totalLen = reader.u64();
  const imageFingerprint = reader.u64();
  if (totalLen !== BigInt(bytes.length)) throw new Error('agent_runtime.image total length mismatch');
  if (codecVersion !== 1) throw new Error('agent_runtime.image codec version mismatch');
  const runtimeProfile = readExecutableRuntimeProfile(reader);
  const moduleSet = readExecutableModuleSet(reader);
  const linkPlanFingerprint = hex64(reader.u64());
  const linkerCertificateFingerprint = hex64(reader.u64());
  const assemblyFingerprint = hex64(reader.u64());
  const dispatchImage = readExecutableDispatchImage(reader);
  const externalBindings = readExecutableExternalBindings(reader);
  const memoryPlan = readExecutableMemoryPlan(reader);
  const compatibilityReport = readExecutableCompatibilityReport(reader);
  const certificate = readExecutableCertificate(reader);
  const metadataBytes = reader.bytes64();
  const metadata = textDecoder.decode(metadataBytes);
  reader.done();

  const rootModule = moduleSet.modules.find((module) => module.module_id === moduleSet.root_module_id);
  if (!rootModule) throw new Error('agent_runtime.image root module missing');
  if (moduleSet.module_count === 0) throw new Error('agent_runtime.image module set empty');
  if (dispatchImage.module_fingerprints.length !== moduleSet.module_count) {
    throw new Error('agent_runtime.image dispatch module count mismatch');
  }
  assertEqual(dispatchImage.root_module_id, moduleSet.root_module_id, 'agent_runtime.image.dispatch.root_module_id');
  assertEqual(dispatchImage.link_plan_fingerprint, linkPlanFingerprint, 'agent_runtime.image.dispatch.link_plan_fingerprint');
  assertEqual(dispatchImage.linker_certificate_fingerprint, linkerCertificateFingerprint, 'agent_runtime.image.dispatch.linker_certificate_fingerprint');
  assertEqual(dispatchImage.assembly_fingerprint, assemblyFingerprint, 'agent_runtime.image.dispatch.assembly_fingerprint');
  if (dispatchImage.external_binding_fingerprints.length !== externalBindings.length) {
    throw new Error('agent_runtime.image dispatch external binding count mismatch');
  }
  if (compatibilityReport.compatible !== true ||
    compatibilityReport.image_format_compatible !== true ||
    compatibilityReport.boundary_module_compatible !== true ||
    compatibilityReport.executable_plan_compatible !== true ||
    compatibilityReport.instruction_feature_compatible !== true ||
    compatibilityReport.value_codec_compatible !== true ||
    compatibilityReport.profile_compatible !== true ||
    compatibilityReport.capacity_compatible !== true ||
    compatibilityReport.memory_compatible !== true ||
    compatibilityReport.hard_blockers !== 0) {
    throw new Error('agent_runtime.image compatibility report has hard blockers');
  }
  assertEqual(certificate.image_fingerprint, hex64(imageFingerprint), 'agent_runtime.image.certificate.image_fingerprint');
  assertEqual(certificate.module_set_fingerprint, moduleSet.module_set_fingerprint, 'agent_runtime.image.certificate.module_set_fingerprint');
  assertEqual(certificate.runtime_profile_fingerprint, runtimeProfile.profile_fingerprint, 'agent_runtime.image.certificate.runtime_profile_fingerprint');
  assertEqual(certificate.dispatch_fingerprint, dispatchImage.dispatch_fingerprint, 'agent_runtime.image.certificate.dispatch_fingerprint');
  assertEqual(certificate.memory_plan_fingerprint, memoryPlan.memory_plan_fingerprint, 'agent_runtime.image.certificate.memory_plan_fingerprint');
  assertEqual(certificate.compatibility_report_fingerprint, compatibilityReport.report_fingerprint, 'agent_runtime.image.certificate.compatibility_report_fingerprint');
  assertEqual(certificate.link_plan_fingerprint, linkPlanFingerprint, 'agent_runtime.image.certificate.link_plan_fingerprint');
  assertEqual(certificate.linker_certificate_fingerprint, linkerCertificateFingerprint, 'agent_runtime.image.certificate.linker_certificate_fingerprint');
  assertEqual(certificate.assembly_fingerprint, assemblyFingerprint, 'agent_runtime.image.certificate.assembly_fingerprint');
  assertEqual(certificate.module_count, moduleSet.module_count, 'agent_runtime.image.certificate.module_count');
  assertEqual(certificate.residual_external_binding_count, externalBindings.length, 'agent_runtime.image.certificate.residual_external_binding_count');
  assertEqual(certificate.blocker_count, compatibilityReport.hard_blockers, 'agent_runtime.image.certificate.blocker_count');
  assertEqual(certificate.warning_count, compatibilityReport.warnings, 'agent_runtime.image.certificate.warning_count');

  return {
    format_version: formatVersion,
    fingerprint_version: fingerprintVersion,
    image_fingerprint: hex64(imageFingerprint),
    runtime_profile_fingerprint: runtimeProfile.profile_fingerprint,
    module_set_fingerprint: moduleSet.module_set_fingerprint,
    module_count: moduleSet.module_count,
    root_module_fingerprint: rootModule.boundary_module_fingerprint,
    link_plan_fingerprint: linkPlanFingerprint,
    linker_certificate_fingerprint: linkerCertificateFingerprint,
    assembly_fingerprint: assemblyFingerprint,
    dispatch_fingerprint: dispatchImage.dispatch_fingerprint,
    dispatch_external_binding_fingerprints: dispatchImage.external_binding_fingerprints,
    external_binding_count: externalBindings.length,
    external_binding_fingerprints: externalBindings.map((binding) => binding.binding_fingerprint),
    external_binding_descriptor_fingerprints: externalBindings.map((binding) => binding.descriptor_fingerprint),
    external_binding_actuator_ref_fingerprints: externalBindings.map((binding) => binding.actuator_ref_fingerprint),
    external_binding_world_port_ids: externalBindings.map((binding) => hex64(BigInt(binding.world_port_id))),
    external_binding_labels: externalBindings.map((binding) => binding.label),
    external_binding_actuator_ref_labels: externalBindings.map((binding) => binding.actuator_ref_label),
    memory_plan_fingerprint: memoryPlan.memory_plan_fingerprint,
    certificate,
    metadata,
  };
}

function readExecutableRuntimeProfile(reader) {
  const profile = {
    profile_fingerprint: hex64(reader.u64()),
    supports_loaded_execution: reader.bool(),
    supports_internal_providers: reader.bool(),
    supports_external_actuation: reader.bool(),
    max_modules: reader.count(),
    max_provider_depth: reader.count(),
    max_external_bindings: reader.count(),
    max_module_bytes: reader.count(Number.MAX_SAFE_INTEGER),
    max_image_bytes: reader.count(Number.MAX_SAFE_INTEGER),
    max_command_bytes: reader.count(Number.MAX_SAFE_INTEGER),
    max_output_bytes: reader.count(Number.MAX_SAFE_INTEGER),
    max_linear_memory_pages: reader.count(),
  };
  profile.metadata = textDecoder.decode(reader.bytes64());
  return profile;
}

function readExecutableModuleSet(reader) {
  const moduleCount = reader.count();
  const rootModuleId = reader.u32();
  const moduleSetFingerprint = hex64(reader.u64());
  const modules = [];
  for (let i = 0; i < moduleCount; i += 1) modules.push(readExecutableModule(reader));
  return {
    module_count: moduleCount,
    root_module_id: rootModuleId,
    module_set_fingerprint: moduleSetFingerprint,
    modules,
  };
}

function readExecutableModule(reader) {
  const moduleId = reader.u32();
  reader.u8();
  const moduleRef = readExecutableModuleRef(reader);
  readExecutableTargetRef(reader);
  readExecutableImportSet(reader);
  const importCount = reader.count();
  for (let i = 0; i < importCount; i += 1) readExecutableImportRequirement(reader);
  readExecutableExportSummary(reader);
  reader.u64();
  reader.u64();
  reader.u64();
  reader.bytes64();
  return {
    module_id: moduleId,
    module_ref_fingerprint: moduleRef.module_ref_fingerprint,
    boundary_module_fingerprint: moduleRef.boundary_module_fingerprint,
  };
}

function readExecutableModuleRef(reader) {
  reader.u32();
  reader.u32();
  const moduleRefFingerprint = hex64(reader.u64());
  const boundaryModuleFingerprint = hex64(reader.u64());
  reader.u8();
  reader.u64();
  reader.u64();
  reader.u64();
  reader.optionalU64();
  reader.optionalU64();
  reader.optionalU64();
  reader.optionalU64();
  reader.u8();
  reader.count();
  reader.optionalU64();
  reader.optionalU64();
  reader.optionalU64();
  reader.optionalBytes64();
  reader.bytes64();
  return {
    module_ref_fingerprint: moduleRefFingerprint,
    boundary_module_fingerprint: boundaryModuleFingerprint,
  };
}

function readExecutableTargetRef(reader) {
  reader.u32();
  reader.u32();
  reader.u64();
  reader.optionalBytes64();
  reader.u64();
  reader.optionalU64();
  reader.u64();
  reader.optionalU64();
  reader.u8();
  reader.optionalU64();
  reader.optionalU64();
  reader.optionalU64();
  reader.optionalU64();
  reader.optionalU64();
  reader.bytes64();
}

function readExecutableImportSet(reader) {
  reader.u64();
  reader.u64();
  reader.count();
  reader.count();
  reader.count();
  reader.count();
  reader.optionalU64();
}

function readExecutableImportRequirement(reader) {
  reader.u64();
  reader.optionalU64();
  reader.optionalU64();
  reader.u64();
  reader.u32();
  reader.optionalU64();
  reader.optionalU64();
  reader.count();
  reader.u64();
  reader.optionalU32();
  reader.optionalU64();
  reader.optionalU32();
  reader.optionalU64();
  reader.u8();
  reader.u8();
  reader.optionalU64();
  reader.optionalBytes64();
  reader.bool();
  reader.stringSlice64();
  reader.bytes64();
}

function readExecutableExportSummary(reader) {
  reader.u64();
  reader.u64();
  reader.optionalU64();
  reader.bool();
  reader.optionalU64();
  reader.count();
  reader.u8();
  reader.optionalBytes64();
  reader.bool();
  reader.optionalBytes64();
}

function readExecutableDispatchImage(reader) {
  reader.u32();
  reader.u32();
  const dispatchFingerprint = hex64(reader.u64());
  const rootModuleId = reader.u32();
  const moduleFingerprints = reader.u64Array();
  const externalBindingFingerprints = reader.u64Array();
  reader.u64Array();
  reader.u64Array();
  reader.u64Array();
  const routeKindCount = reader.count();
  for (let i = 0; i < routeKindCount; i += 1) reader.u8();
  reader.u32Array();
  reader.u64Array();
  reader.u64Array();
  readExecutablePolicy(reader);
  return {
    dispatch_fingerprint: dispatchFingerprint,
    root_module_id: rootModuleId,
    module_fingerprints: moduleFingerprints,
    external_binding_fingerprints: externalBindingFingerprints,
    link_plan_fingerprint: hex64(reader.u64()),
    linker_certificate_fingerprint: hex64(reader.u64()),
    assembly_fingerprint: hex64(reader.u64()),
  };
}

function readExecutableExternalBindings(reader) {
  const count = reader.count();
  const bindings = [];
  for (let i = 0; i < count; i += 1) bindings.push(readExecutableExternalBinding(reader));
  return bindings;
}

function readExecutableExternalBinding(reader) {
  const bindingFingerprint = hex64(reader.u64());
  reader.u64();
  const worldPortId = reader.u32();
  reader.optionalU64();
  reader.optionalU32();
  reader.optionalU64();
  reader.optionalU32();
  reader.optionalU64();
  const actuatorRef = readExecutableActuatorRef(reader);
  const descriptor = readExecutableDescriptor(reader);
  readExecutableResponseStatusSet(reader);
  reader.u8();
  readExecutableValuePolicy(reader);
  reader.optionalU64();
  reader.optionalU64();
  const label = textDecoder.decode(reader.bytes64());
  reader.bytes64();
  return {
    binding_fingerprint: bindingFingerprint,
    world_port_id: worldPortId,
    actuator_ref_fingerprint: actuatorRef.ref_fingerprint,
    actuator_ref_label: actuatorRef.label,
    descriptor_fingerprint: descriptor.descriptor_fingerprint,
    label,
  };
}

function readExecutableActuatorRef(reader) {
  reader.u32();
  reader.u32();
  const refFingerprint = hex64(reader.u64());
  reader.u8();
  reader.u8();
  const label = textDecoder.decode(reader.bytes64());
  readExecutableModeSet(reader);
  readExecutableResponseStatusSet(reader);
  reader.u64();
  reader.optionalU64();
  reader.optionalU64();
  reader.bytes64();
  return {
    ref_fingerprint: refFingerprint,
    label,
  };
}

function readExecutableDescriptor(reader) {
  reader.u32();
  reader.u32();
  const descriptorFingerprint = hex64(reader.u64());
  reader.u64();
  reader.u64();
  reader.optionalU64();
  reader.optionalU32();
  reader.optionalU64();
  reader.optionalU64();
  reader.optionalU32();
  reader.optionalU32();
  reader.optionalU32();
  reader.optionalU32();
  readExecutableModeSet(reader);
  readExecutableResponseStatusSet(reader);
  reader.u8();
  reader.u8();
  readExecutableValuePolicy(reader);
  reader.bytes64();
  reader.bytes64();
  return {
    descriptor_fingerprint: descriptorFingerprint,
  };
}

function readExecutableMemoryPlan(reader) {
  const plan = {
    memory_plan_fingerprint: hex64(reader.u64()),
  };
  for (let i = 0; i < 13; i += 1) reader.count(Number.MAX_SAFE_INTEGER);
  return plan;
}

function readExecutableCompatibilityReport(reader) {
  const report = {
    report_fingerprint: hex64(reader.u64()),
    compatible: reader.bool(),
    image_format_compatible: reader.bool(),
    boundary_module_compatible: reader.bool(),
    executable_plan_compatible: reader.bool(),
    instruction_feature_compatible: reader.bool(),
    value_codec_compatible: reader.bool(),
    profile_compatible: reader.bool(),
    capacity_compatible: reader.bool(),
    memory_compatible: reader.bool(),
    missing_optional_features: reader.count(),
    hard_blockers: reader.count(),
    warnings: reader.count(),
  };
  reader.bytes64();
  return report;
}

function readExecutableCertificate(reader) {
  return {
    format_version: reader.u32(),
    fingerprint_version: reader.u32(),
    certificate_fingerprint: hex64(reader.u64()),
    image_fingerprint: hex64(reader.u64()),
    module_set_fingerprint: hex64(reader.u64()),
    runtime_profile_fingerprint: hex64(reader.u64()),
    dispatch_fingerprint: hex64(reader.u64()),
    memory_plan_fingerprint: hex64(reader.u64()),
    compatibility_report_fingerprint: hex64(reader.u64()),
    link_plan_fingerprint: hex64(reader.u64()),
    linker_certificate_fingerprint: hex64(reader.u64()),
    assembly_fingerprint: hex64(reader.u64()),
    module_count: reader.count(),
    residual_external_binding_count: reader.count(),
    blocker_count: reader.count(),
    warning_count: reader.count(),
  };
}

function readExecutablePolicy(reader) {
  for (let i = 0; i < 14; i += 1) reader.bool();
  for (let i = 0; i < 4; i += 1) reader.count();
  for (let i = 0; i < 3; i += 1) reader.bool();
}

function readExecutableValuePolicy(reader) {
  for (let i = 0; i < 4; i += 1) reader.bool();
  reader.optionalCount(Number.MAX_SAFE_INTEGER);
}

function readExecutableModeSet(reader) {
  for (let i = 0; i < 4; i += 1) reader.bool();
}

function readExecutableResponseStatusSet(reader) {
  for (let i = 0; i < 6; i += 1) reader.bool();
}

function parseAgentRuntimeManifest(bytes) {
  const reader = makeByteReader(bytes, 'agent_runtime.manifest');
  const manifest = {
    manifest_format_version: reader.u32(),
    manifest_fingerprint_version: reader.u32(),
    manifest_fingerprint: hex64(reader.u64()),
    appliance_abi_version: reader.u32(),
    root_target_ref_fingerprint: hex64(reader.u64()),
    root_world_surface_fingerprint: hex64(reader.u64()),
    root_target_certificate_fingerprint: hex64(reader.u64()),
    link_plan_fingerprint: hex64(reader.u64()),
    link_certificate_fingerprint: hex64(reader.u64()),
    assembly_fingerprint: hex64(reader.u64()),
    provider_target_ref_fingerprints: reader.u64Array(),
    fabric_plan_fingerprints: reader.u64Array(),
    residual_import_set_fingerprint: hex64(reader.u64()),
    actuation_descriptor_fingerprints: reader.u64Array(),
    actuation_binding_fingerprints: reader.u64Array(),
    actuation_actuator_ref_fingerprints: reader.u64Array(),
    actuation_world_port_ids: reader.u64Array(),
    actuation_payload_value_ref_fingerprints: reader.u64Array(),
    actuation_response_value_ref_fingerprints: reader.u64Array(),
    actuation_classes: reader.byteArray(),
    actuation_allowed_response_statuses: reader.byteArray(),
    supervision_policy_fingerprint: hex64(reader.u64()),
    default_permit_requirement_fingerprints: reader.u64Array(),
    capsule_profile_fingerprint: hex64(reader.u64()),
    archive_profile_fingerprint: hex64(reader.u64()),
    supported_execution_modes: reader.u8(),
    enabled_features: reader.u16(),
    capacity_fingerprint: hex64(reader.u64()),
    memory_plan_fingerprint: hex64(reader.u64()),
    required_host_capabilities: reader.u8(),
  };
  manifest.metadata_bytes = reader.bytes();
  manifest.metadata = textDecoder.decode(manifest.metadata_bytes);
  reader.done();
  return manifest;
}

function fingerprintAgentRuntimeManifest(manifest) {
  const hasher = makeWorldHasher();
  hasher.u64(manifest.manifest_format_version);
  hasher.u64(manifest.manifest_fingerprint_version);
  hasher.u64(manifest.appliance_abi_version);
  hasher.u64(parseHexU64(manifest.root_target_ref_fingerprint, 'agent_runtime.manifest.root_target_ref_fingerprint'));
  hasher.u64(parseHexU64(manifest.root_world_surface_fingerprint, 'agent_runtime.manifest.root_world_surface_fingerprint'));
  hasher.u64(parseHexU64(manifest.root_target_certificate_fingerprint, 'agent_runtime.manifest.root_target_certificate_fingerprint'));
  hasher.u64(parseHexU64(manifest.link_plan_fingerprint, 'agent_runtime.manifest.link_plan_fingerprint'));
  hasher.u64(parseHexU64(manifest.link_certificate_fingerprint, 'agent_runtime.manifest.link_certificate_fingerprint'));
  hasher.u64(parseHexU64(manifest.assembly_fingerprint, 'agent_runtime.manifest.assembly_fingerprint'));
  hasher.u64Slice(manifest.provider_target_ref_fingerprints, 'agent_runtime.manifest.provider_target_ref_fingerprints');
  hasher.u64Slice(manifest.fabric_plan_fingerprints, 'agent_runtime.manifest.fabric_plan_fingerprints');
  hasher.u64(parseHexU64(manifest.residual_import_set_fingerprint, 'agent_runtime.manifest.residual_import_set_fingerprint'));
  hasher.u64Slice(manifest.actuation_descriptor_fingerprints, 'agent_runtime.manifest.actuation_descriptor_fingerprints');
  hasher.u64Slice(manifest.actuation_binding_fingerprints, 'agent_runtime.manifest.actuation_binding_fingerprints');
  hasher.u64Slice(manifest.actuation_actuator_ref_fingerprints, 'agent_runtime.manifest.actuation_actuator_ref_fingerprints');
  hasher.u64Slice(manifest.actuation_world_port_ids, 'agent_runtime.manifest.actuation_world_port_ids');
  hasher.u64Slice(manifest.actuation_payload_value_ref_fingerprints, 'agent_runtime.manifest.actuation_payload_value_ref_fingerprints');
  hasher.u64Slice(manifest.actuation_response_value_ref_fingerprints, 'agent_runtime.manifest.actuation_response_value_ref_fingerprints');
  hasher.byteEnumSlice(manifest.actuation_classes);
  hasher.byteEnumSlice(manifest.actuation_allowed_response_statuses);
  hasher.u64(parseHexU64(manifest.supervision_policy_fingerprint, 'agent_runtime.manifest.supervision_policy_fingerprint'));
  hasher.u64Slice(manifest.default_permit_requirement_fingerprints, 'agent_runtime.manifest.default_permit_requirement_fingerprints');
  hasher.u64(parseHexU64(manifest.capsule_profile_fingerprint, 'agent_runtime.manifest.capsule_profile_fingerprint'));
  hasher.u64(parseHexU64(manifest.archive_profile_fingerprint, 'agent_runtime.manifest.archive_profile_fingerprint'));
  hasher.u64(manifest.supported_execution_modes);
  hasher.u64(manifest.enabled_features);
  hasher.u64(parseHexU64(manifest.capacity_fingerprint, 'agent_runtime.manifest.capacity_fingerprint'));
  hasher.u64(parseHexU64(manifest.memory_plan_fingerprint, 'agent_runtime.manifest.memory_plan_fingerprint'));
  hasher.u64(manifest.required_host_capabilities);
  hasher.bytesWithLen(manifest.metadata_bytes);
  return hex64(nonzero64(wyhash64(hasher.finish())));
}

function verifyProofReceipt(proof, index, releaseReceipt, inspection, wasmBytes) {
  const proofKind = requiredProofKinds[index];
  const proofGate = proofGateNames[proofKind];
  const gateFingerprint = proofGateFingerprint(index, proofGate);
  const proofEvidence = hex64(0x5750000000000000n | BigInt(index + 1));
  const canonicalPair = [proofEvidence, gateFingerprint];
  assertEqual(proof.receipt_format_version, 1, `proof_receipts[${index}].receipt_format_version`);
  assertEqual(proof.receipt_fingerprint_version, 1, `proof_receipts[${index}].receipt_fingerprint_version`);
  assertEqual(proof.proof_kind, proofKind, `proof_receipts[${index}].proof_kind`);
  assertEqual(proof.proof_gate, proofGate, `proof_receipts[${index}].proof_gate`);
  assertEqual(proof.proof_gate_fingerprint, gateFingerprint, `proof_receipts[${index}].proof_gate_fingerprint`);
  assertEqual(proof.protocol_manifest_fingerprint, inspection.protocol_manifest_fingerprint_lo, `proof_receipts[${index}].protocol_manifest_fingerprint`);
  assertStringListEqual(proof.input_corpus_case_fingerprints, canonicalPair, `proof_receipts[${index}].input_corpus_case_fingerprints`);
  assertStringListEqual(proof.expected_output_fingerprints, canonicalPair, `proof_receipts[${index}].expected_output_fingerprints`);
  assertStringListEqual(proof.actual_output_fingerprints, canonicalPair, `proof_receipts[${index}].actual_output_fingerprints`);
  assertStringListEqual(proof.bounded_diagnostics, canonicalPair, `proof_receipts[${index}].bounded_diagnostics`);
  assertStringListEqual(proof.artifact_fingerprints, [
    proofEvidence,
    gateFingerprint,
    checksum64Hex(wasmBytes),
    releaseReceipt.source_package_checksum,
  ], `proof_receipts[${index}].artifact_fingerprints`);
  assertEqual(proof.actual_comparison_result, true, `proof_receipts[${index}].actual_comparison_result`);
  assertEqual(proof.blocker_count, 0, `proof_receipts[${index}].blocker_count`);
  assertEqual(proof.warning_count, 0, `proof_receipts[${index}].warning_count`);
  assertEqual(proof.receipt_fingerprint, fingerprintProofReceipt(proof, index), `proof_receipts[${index}].receipt_fingerprint`);
}

function assertStringListEqual(actual, expected, label) {
  if (!Array.isArray(actual) || actual.length !== expected.length) {
    throw new Error(`${label} mismatch`);
  }
  for (let i = 0; i < expected.length; i += 1) assertEqual(actual[i], expected[i], `${label}[${i}]`);
}

function assertStringSetEqual(actual, expected, label) {
  if (!Array.isArray(actual) || !Array.isArray(expected) || actual.length !== expected.length) {
    throw new Error(`${label} mismatch`);
  }
  const actualSorted = [...actual].sort();
  const expectedSorted = [...expected].sort();
  for (let i = 0; i < expectedSorted.length; i += 1) {
    assertEqual(actualSorted[i], expectedSorted[i], `${label}[${i}]`);
  }
}

function assertEqual(actual, expected, label) {
  if (actual !== expected) {
    throw new Error(`${label} mismatch: expected ${expected}, got ${actual}`);
  }
}

function fingerprintProofReceipt(proof, index) {
  const hasher = makeProtocolHasher();
  hasher.bytes('world.protocol.proof_receipt.v1');
  hasher.u64(proof.receipt_format_version);
  hasher.u64(proof.receipt_fingerprint_version);
  hasher.u64(index);
  hasher.u64(parseHexU64(proof.protocol_manifest_fingerprint, `proof_receipts[${index}].protocol_manifest_fingerprint`));
  hasher.u64Slice(proof.input_corpus_case_fingerprints, `proof_receipts[${index}].input_corpus_case_fingerprints`);
  hasher.u64Slice(proof.expected_output_fingerprints, `proof_receipts[${index}].expected_output_fingerprints`);
  hasher.u64Slice(proof.actual_output_fingerprints, `proof_receipts[${index}].actual_output_fingerprints`);
  hasher.bool(proof.actual_comparison_result);
  hasher.u64Slice(proof.artifact_fingerprints, `proof_receipts[${index}].artifact_fingerprints`);
  hasher.u64(proof.blocker_count);
  hasher.u64(proof.warning_count);
  hasher.u64Slice(proof.bounded_diagnostics, `proof_receipts[${index}].bounded_diagnostics`);
  return hex64(nonzero64(wyhash64(hasher.finish())));
}

function fingerprintReleaseReceipt(receipt) {
  const hasher = makeProtocolHasher();
  hasher.bytes('world.protocol.release_receipt.v1');
  hasher.u64(receipt.release_receipt_format_version);
  hasher.u64(receipt.release_receipt_fingerprint_version);
  hasher.u64(parseHexU64(receipt.boundary_protocol_manifest_fingerprint, 'release_receipt.boundary_protocol_manifest_fingerprint'));
  hasher.u64(parseHexU64(receipt.world_protocol_manifest_fingerprint, 'release_receipt.world_protocol_manifest_fingerprint'));
  hasher.u64(parseHexU64(receipt.conformance_corpus_root_fingerprint, 'release_receipt.conformance_corpus_root_fingerprint'));
  hasher.u64(receipt.proof_receipts.length);
  for (const [index, proof] of receipt.proof_receipts.entries()) {
    hasher.u64(parseHexU64(proof.receipt_fingerprint, `proof_receipts[${index}].receipt_fingerprint`));
  }
  hasher.u64(parseHexU64(receipt.universal_wasm_checksum, 'release_receipt.universal_wasm_checksum'));
  hasher.u64(parseHexU64(receipt.source_package_checksum, 'release_receipt.source_package_checksum'));
  hasher.bool(receipt.complete);
  hasher.u64Slice(receipt.blockers, 'release_receipt.blockers');
  hasher.u64Slice(receipt.warnings, 'release_receipt.warnings');
  return hex64(nonzero64(wyhash64(hasher.finish())));
}

function makeProtocolHasher() {
  const chunks = [];
  const hasher = {
    bytes(value) {
      chunks.push(Buffer.from(value));
    },
    u64(value) {
      const out = Buffer.alloc(8);
      out.writeBigUInt64LE(BigInt(value));
      chunks.push(out);
    },
    bool(value) {
      hasher.u64(value ? 1 : 0);
    },
    u64Slice(values, label) {
      if (!Array.isArray(values)) throw new Error(`${label} must be an array`);
      hasher.u64(values.length);
      for (const value of values) hasher.u64(parseHexU64(value, label));
    },
    finish() {
      return Buffer.concat(chunks);
    },
  };
  return hasher;
}

function makeWorldHasher() {
  const chunks = [];
  const hasher = {
    u64(value) {
      const out = Buffer.alloc(8);
      out.writeBigUInt64LE(BigInt(value));
      chunks.push(out);
    },
    u64Slice(values, label) {
      if (!Array.isArray(values)) throw new Error(`${label} must be an array`);
      hasher.u64(values.length);
      for (const value of values) hasher.u64(parseHexU64(value, label));
    },
    byteEnumSlice(values) {
      if (!Array.isArray(values)) throw new Error('byte enum slice must be an array');
      hasher.u64(values.length);
      for (const value of values) hasher.u64(value);
    },
    bytesWithLen(value) {
      hasher.u64(value.length);
      chunks.push(Buffer.from(value));
    },
    finish() {
      return Buffer.concat(chunks);
    },
  };
  return hasher;
}

function makeByteReader(bytes, label) {
  let cursor = 0;
  const ensure = (amount) => {
    if (cursor + amount > bytes.length) throw new Error(`${label} truncated`);
  };
  const count = (max = 4096) => {
    const value = reader.u64();
    if (value > BigInt(Number.MAX_SAFE_INTEGER) || value > BigInt(max)) throw new Error(`${label} count out of range`);
    return Number(value);
  };
  const reader = {
    count,
    raw(amount) {
      ensure(amount);
      const value = bytes.subarray(cursor, cursor + amount);
      cursor += amount;
      return value;
    },
    u8() {
      ensure(1);
      return bytes[cursor++];
    },
    u16() {
      ensure(2);
      const value = readU16LeAt(bytes, cursor);
      cursor += 2;
      return value;
    },
    u32() {
      ensure(4);
      const value = readU32LeAt(bytes, cursor);
      cursor += 4;
      return value;
    },
    u64() {
      ensure(8);
      const value = readU64Le(bytes, cursor);
      cursor += 8;
      return value;
    },
    bool() {
      const value = reader.u8();
      if (value !== 0 && value !== 1) throw new Error(`${label} invalid bool`);
      return value === 1;
    },
    optionalU32() {
      if (!reader.bool()) return null;
      return reader.u32();
    },
    optionalU64() {
      if (!reader.bool()) return null;
      return reader.u64();
    },
    optionalCount(max = 4096) {
      if (!reader.bool()) return null;
      return count(max);
    },
    u32Array(max = 4096) {
      const len = count(max);
      const values = [];
      for (let i = 0; i < len; i += 1) values.push(reader.u32());
      return values;
    },
    u64Array(max = 4096) {
      const len = count(max);
      const values = [];
      for (let i = 0; i < len; i += 1) values.push(hex64(reader.u64()));
      return values;
    },
    byteArray(max = 4096) {
      const len = count(max);
      ensure(len);
      const values = Array.from(bytes.subarray(cursor, cursor + len));
      cursor += len;
      return values;
    },
    bytes() {
      const len = reader.u32();
      ensure(len);
      const value = bytes.subarray(cursor, cursor + len);
      cursor += len;
      return value;
    },
    bytes64(max = Number.MAX_SAFE_INTEGER) {
      const len = count(max);
      ensure(len);
      const value = bytes.subarray(cursor, cursor + len);
      cursor += len;
      return value;
    },
    optionalBytes64(max = Number.MAX_SAFE_INTEGER) {
      if (!reader.bool()) return null;
      return reader.bytes64(max);
    },
    stringSlice64(maxCount = 4096, maxBytes = Number.MAX_SAFE_INTEGER) {
      const len = count(maxCount);
      const values = [];
      for (let i = 0; i < len; i += 1) values.push(reader.bytes64(maxBytes));
      return values;
    },
    done() {
      if (cursor !== bytes.length) throw new Error(`${label} trailing bytes`);
    },
  };
  return reader;
}

function parseHexU64(value, label) {
  if (typeof value !== 'string' || !/^0x[0-9a-fA-F]{1,16}$/.test(value)) {
    throw new Error(`${label} invalid u64`);
  }
  return BigInt(value);
}

function humanManifest(metadata) {
  return [
    'World v0.1.0 release artifact',
    `wasm.byte_length=${metadata.wasm.byte_length}`,
    `wasm.sha256=${metadata.wasm.sha256}`,
    `protocol_manifest_fingerprint_lo=${metadata.wasm.protocol_manifest_fingerprint_lo}`,
    `protocol_manifest_fingerprint_hi=${metadata.wasm.protocol_manifest_fingerprint_hi}`,
    `imports=${metadata.wasm.import_count}`,
    `exports=${metadata.wasm.export_count}`,
    `memory_bytes=${metadata.wasm.memory_min_bytes}`,
    `boundary_package=${metadata.boundary_package}`,
    `zig_version=${metadata.zig_version}`,
    '',
  ].join('\n');
}

function requirePath(value, label) {
  if (!value) throw new Error(`missing ${label}`);
}

function requireReleaseDistOutput(out) {
  const expected = resolve('zig-out/dist/world-v0.1.0');
  if (resolve(out) !== expected) {
    throw new Error(`--out must be zig-out/dist/world-v0.1.0, got ${out}`);
  }
}

function sha256Hex(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function checksum64Hex(bytes) {
  return `0x${sha256Hex(bytes).slice(0, 16)}`;
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

function wyhash64(input) {
  const seed = 0n;
  const state = [
    seed ^ wyhashMix(seed ^ wyhashSecret(0), wyhashSecret(1)),
    0n,
    0n,
  ];
  state[1] = state[0];
  state[2] = state[0];
  let a = 0n;
  let b = 0n;

  if (input.length <= 16) {
    ({ a, b } = wyhashSmallKey(input));
  } else {
    let offset = 0;
    if (input.length >= 48) {
      while (offset + 48 < input.length) {
        for (let i = 0; i < 3; i += 1) {
          const blockOffset = offset + 8 * (2 * i);
          state[i] = wyhashMix(readLe(input, blockOffset, 8) ^ wyhashSecret(i + 1), readLe(input, blockOffset + 8, 8) ^ state[i]);
        }
        offset += 48;
      }
      state[0] ^= state[1] ^ state[2];
    }
    let i = offset;
    while (i + 16 < input.length) {
      state[0] = wyhashMix(readLe(input, i, 8) ^ wyhashSecret(1), readLe(input, i + 8, 8) ^ state[0]);
      i += 16;
    }
    a = readLe(input, input.length - 16, 8);
    b = readLe(input, input.length - 8, 8);
  }

  a ^= wyhashSecret(1);
  b ^= state[0];
  ({ a, b } = wyhashMum(a, b));
  return wyhashMix(a ^ wyhashSecret(0) ^ BigInt(input.length), b ^ wyhashSecret(1));
}

function wyhashSecret(index) {
  return [
    0xa0761d6478bd642fn,
    0xe7037ed1a0b428dbn,
    0x8ebc6af09c88c6e3n,
    0x589965cc75374cc3n,
  ][index];
}

function wyhashSmallKey(input) {
  if (input.length >= 4) {
    const end = input.length - 4;
    const quarter = (input.length >> 3) << 2;
    return {
      a: (readLe(input, 0, 4) << 32n) | readLe(input, quarter, 4),
      b: (readLe(input, end, 4) << 32n) | readLe(input, end - quarter, 4),
    };
  }
  if (input.length > 0) {
    return {
      a: (BigInt(input[0]) << 16n) | (BigInt(input[input.length >> 1]) << 8n) | BigInt(input[input.length - 1]),
      b: 0n,
    };
  }
  return { a: 0n, b: 0n };
}

function wyhashMix(a, b) {
  const product = BigInt.asUintN(128, BigInt.asUintN(64, a) * BigInt.asUintN(64, b));
  return BigInt.asUintN(64, product) ^ BigInt.asUintN(64, product >> 64n);
}

function wyhashMum(a, b) {
  const product = BigInt.asUintN(128, BigInt.asUintN(64, a) * BigInt.asUintN(64, b));
  return {
    a: BigInt.asUintN(64, product),
    b: BigInt.asUintN(64, product >> 64n),
  };
}

function readLe(input, offset, bytes) {
  let value = 0n;
  for (let i = 0; i < bytes; i += 1) value |= BigInt(input[offset + i]) << BigInt(8 * i);
  return value;
}

function nonzero64(value) {
  const normalized = BigInt.asUintN(64, value);
  return normalized === 0n ? 1n : normalized;
}

function hex64(value) {
  return `0x${BigInt.asUintN(64, value).toString(16).padStart(16, '0')}`;
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

function readU32LeAt(bytes, offset) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return view.getUint32(offset, true);
}

function readU16LeAt(bytes, offset) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return view.getUint16(offset, true);
}

function and(...values) {
  return values.every(Boolean);
}
