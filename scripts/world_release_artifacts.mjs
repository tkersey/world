#!/usr/bin/env node
import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';

const textDecoder = new TextDecoder();

const args = parseArgs(process.argv.slice(2));

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
    else if (arg === '--out') parsed.out = raw[++i];
    else if (arg === '--dist') parsed.dist = raw[++i];
    else if (arg === '--corpus') parsed.corpus = raw[++i];
    else throw new Error(`unknown argument: ${arg}`);
  }
  return parsed;
}

async function emitDist(options) {
  requirePath(options.wasm, '--wasm');
  requirePath(options.out, '--out');
  const out = options.out;
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  mkdirSync(join(out, 'scripts'), { recursive: true });
  mkdirSync(join(out, 'docs'), { recursive: true });
  mkdirSync(join(out, 'conformance/v0'), { recursive: true });

  cpSync(options.wasm, join(out, 'world_universal_appliance.wasm'));
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
    boundary_package: '0.5.0',
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
  const required = [
    'world_universal_appliance.wasm',
    'world-protocol-manifest.json',
    'world-release-artifact.json',
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
  for (const rel of required) {
    const path = join(dist, rel);
    if (!existsSync(path)) throw new Error(`missing dist file: ${rel}`);
  }
  verifyChecksums(dist);
  const wasmBytes = readFileSync(join(dist, 'world_universal_appliance.wasm'));
  const inspection = await inspectWasm(wasmBytes);
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
  const corpusSecond = readFileSync(options.corpus);
  const manifestFirst = await inspectWasm(wasmFirst);
  const manifestSecond = await inspectWasm(wasmSecond);
  const jsSchemaFirst = JSON.stringify(JSON.parse(corpusFirst.toString('utf8')));
  const jsSchemaSecond = JSON.stringify(JSON.parse(corpusSecond.toString('utf8')));
  const report = {
    reproducible_artifact_check_version: 1,
    wasm_exact_bytes: sha256Hex(wasmFirst) === sha256Hex(wasmSecond),
    corpus_exact_bytes: sha256Hex(corpusFirst) === sha256Hex(corpusSecond),
    protocol_manifest_exact: JSON.stringify(manifestFirst) === JSON.stringify(manifestSecond),
    js_schema_exact: jsSchemaFirst === jsSchemaSecond,
    complete: false,
  };
  report.complete = and(report.wasm_exact_bytes, report.corpus_exact_bytes, report.protocol_manifest_exact, report.js_schema_exact);
  if (!report.complete) throw new Error(JSON.stringify(report));
  console.log(JSON.stringify(report));
}

async function inspectWasm(bytes) {
  const module = await WebAssembly.compile(bytes);
  const exports = WebAssembly.Module.exports(module);
  const imports = WebAssembly.Module.imports(module);
  const exportNames = new Set(exports.map((entry) => entry.name));
  for (const name of [
    'world_protocol_manifest_len',
    'world_protocol_read_manifest',
    'world_protocol_manifest_fingerprint_lo',
    'world_protocol_manifest_fingerprint_hi',
    'world_appliance_abi_version',
    'world_appliance_alloc',
    'world_appliance_free',
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
    'world_appliance_abi_version',
    'world_appliance_alloc',
    'world_appliance_free',
  ]) {
    if (typeof instance.exports[name] !== 'function') throw new Error(`wasm export is not callable: ${name}`);
  }
  const manifestLen = Number(instance.exports.world_protocol_manifest_len());
  const lo = BigInt.asUintN(64, instance.exports.world_protocol_manifest_fingerprint_lo());
  const hi = BigInt.asUintN(64, instance.exports.world_protocol_manifest_fingerprint_hi());
  if (Number(instance.exports.world_appliance_abi_version()) !== 3) throw new Error('unexpected appliance ABI version');
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
    protocol_manifest_fingerprint_lo: `0x${lo.toString(16)}`,
    protocol_manifest_fingerprint_hi: `0x${hi.toString(16)}`,
    import_count: imports.length,
    export_count: exports.length,
    memory_bytes: memory.buffer.byteLength,
    actual_webassembly_execution: true,
  };
}

function writeChecksums(root) {
  const files = [
    'world_universal_appliance.wasm',
    'world-protocol-manifest.json',
    'world-release-artifact.json',
    'human-readable-manifest.txt',
    'conformance/v0/world/corpus.json',
    'scripts/world_conformance.mjs',
    'scripts/world_appliance_wire_codec.mjs',
    'scripts/world_loaded_value_codec.mjs',
    'docs/world_v0.md',
    'docs/compatibility.md',
    'docs/security_model.md',
  ];
  const lines = files.map((rel) => `${sha256Hex(readFileSync(join(root, rel)))}  ${rel}`);
  writeFileSync(join(root, 'checksums.txt'), `${lines.join('\n')}\n`);
}

function verifyChecksums(root) {
  const lines = readFileSync(join(root, 'checksums.txt'), 'utf8').trim().split('\n');
  for (const line of lines) {
    const [hash, rel] = line.split(/\s+/, 2);
    if (sha256Hex(readFileSync(join(root, rel))) !== hash) throw new Error(`checksum mismatch: ${rel}`);
  }
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

function sha256Hex(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
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

function and(...values) {
  return values.every(Boolean);
}
