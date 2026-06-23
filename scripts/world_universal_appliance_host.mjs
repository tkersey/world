import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import childProcess from 'node:child_process';
import { createHash } from 'node:crypto';
import { decodeUtf8, inspectTurnOutput } from './world_universal_appliance_codec.mjs';

export const statusOk = 0;
export const statusNeedsHost = 2;
export const statusCompleted = 3;
export const statusInvalidCommand = 7;

const textEncoder = new TextEncoder();

export async function runConformance({ replyHelperPath, wasmPath, imageAPath, commandAPath, imageBPath, commandBPath }) {
  const wasmBytes = fs.readFileSync(wasmPath);
  const module = await WebAssembly.compile(wasmBytes);
  const imageA = fs.readFileSync(imageAPath);
  const commandA = fs.readFileSync(commandAPath);
  const imageB = fs.readFileSync(imageBPath);
  const commandB = fs.readFileSync(commandBPath);

  const instance = await WebAssembly.instantiate(module, {});
  const rejectedTextEnvelope = rejectTextEnvelope(instance);
  const resultA = loadAndRunImage(replyHelperPath, instance, imageA, commandA, 'universal.fixture.a.reply');
  unload(instance, 'image A');
  const submitWithoutImageRejected =
    instance.exports.world_appliance_submit_command(writeGuest(instance, commandA), commandA.length) === statusInvalidCommand;
  const resultB = loadAndRunImage(replyHelperPath, instance, imageB, commandB, 'universal.fixture.b.reply');
  unload(instance, 'image B');

  const fresh = await WebAssembly.instantiate(module, {});
  const freshA = loadAndRunImage(replyHelperPath, fresh, imageA, commandA, 'universal.fixture.a.reply');
  unload(fresh, 'fresh image A');
  const freshB = loadAndRunImage(replyHelperPath, fresh, imageB, commandB, 'universal.fixture.b.reply');
  unload(fresh, 'fresh image B');

  return {
    actualExternalRuntimeExecuted: true,
    compiledOnce: true,
    emptyImports: true,
    rejectedTextEnvelope,
    submitWithoutImageRejected,
    resultA,
    resultB,
    freshA,
    freshB,
  };
}

export function rejectTextEnvelope(instance) {
  const bytes = textEncoder.encode('world.Executable.TextEnvelope.v1\nfingerprint=8cdcc3dc851ba11b\npayload=test-a');
  return instance.exports.world_appliance_load_executable(writeGuest(instance, bytes), bytes.length) === statusInvalidCommand;
}

export function loadAndRunImage(replyHelperPath, instance, imageBytes, commandBytes, replyMetadata) {
  const exports = instance.exports;
  if (exports.world_appliance_abi_version() !== 2) throw new Error('unexpected ABI version');

  const manifest = readRuntimeManifest(instance);
  if (!manifest.includes('imports=0\n')) throw new Error('runtime manifest does not declare zero imports');
  assertRuntimeProfileManifest(manifest);

  const loadStatus = exports.world_appliance_load_executable(writeGuest(instance, imageBytes), imageBytes.length);
  if (loadStatus !== statusOk) return { loaded: false, loadStatus, lastError: readLastError(instance) };
  const manifestLen = exports.world_appliance_manifest_len();
  if (manifestLen === 0 || manifestLen === imageBytes.length) return { loaded: true, manifestPresent: false };
  const manifestPtr = exports.world_appliance_alloc(manifestLen);
  if (manifestPtr === 0) throw new Error('manifest allocation failed');
  if (exports.world_appliance_read_manifest(manifestPtr, manifestLen) !== manifestLen) return { loaded: true, manifestPresent: false };

  const submitStatus = exports.world_appliance_submit_command(writeGuest(instance, commandBytes), commandBytes.length);
  if (submitStatus !== statusNeedsHost) return { loaded: true, manifestPresent: true, outputReady: false };
  const needsHostOutput = readOutputBytes(instance);
  const needsHostSummary = inspectTurnOutput(needsHostOutput);
  if (needsHostSummary.status !== 0 || needsHostSummary.hostRequestCount === 0) {
    return { loaded: true, manifestPresent: true, outputReady: true, hostRequestReady: false };
  }
  const replyCommandBytes = replyCommandForOutput(replyHelperPath, needsHostOutput, replyMetadata);

  const replyStatus = exports.world_appliance_submit_command(writeGuest(instance, replyCommandBytes), replyCommandBytes.length);
  if (replyStatus !== statusCompleted) {
    return {
      loaded: true,
      manifestPresent: true,
      outputReady: true,
      hostRequestReady: true,
      completed: false,
      replyStatus,
      replyCommandLen: replyCommandBytes.length,
      lastError: readLastError(instance),
    };
  }
  const completedOutput = readOutputBytes(instance);
  const completedSummary = inspectTurnOutput(completedOutput);
  return {
    loaded: true,
    manifestPresent: true,
    outputReady: true,
    hostRequestReady: true,
    completed: completedSummary.status === 1 && completedSummary.hostRequestCount === 0,
    rootResultReady: completedSummary.rootResultFingerprint !== null && completedSummary.rootResultBytesLen > 0,
    archiveAppendReady: completedSummary.archiveAppendFingerprint !== null && completedSummary.archiveAppendBytesLen > 0,
    completedOutputSha256: sha256Hex(completedOutput),
    rootResultFingerprint: fingerprintString(completedSummary.rootResultFingerprint),
    archiveAppendFingerprint: fingerprintString(completedSummary.archiveAppendFingerprint),
  };
}

function sha256Hex(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function fingerprintString(value) {
  return value === null ? null : value.toString(16).padStart(16, '0');
}

export function replyCommandForOutput(replyHelperPath, outputBytes, metadata) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'world-universal-reply-'));
  try {
    const outputPath = path.join(dir, 'turn-output.bin');
    const commandPath = path.join(dir, 'reply-command.bin');
    fs.writeFileSync(outputPath, outputBytes);
    childProcess.execFileSync(replyHelperPath, ['--reply', outputPath, commandPath, metadata], { stdio: 'pipe' });
    return fs.readFileSync(commandPath);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

export function readOutputBytes(instance) {
  const exports = instance.exports;
  const outputLen = exports.world_appliance_output_len();
  if (outputLen === 0) throw new Error('missing output');
  const outputPtr = exports.world_appliance_alloc(outputLen);
  if (outputPtr === 0) throw new Error('output allocation failed');
  if (exports.world_appliance_read_output(outputPtr, outputLen) !== outputLen) throw new Error('output read failed');
  return new Uint8Array(instance.exports.memory.buffer, outputPtr, outputLen).slice();
}

export function readRuntimeManifest(instance) {
  const exports = instance.exports;
  const len = exports.world_appliance_runtime_manifest_len();
  if (len === 0) throw new Error('missing runtime manifest');
  const ptr = exports.world_appliance_alloc(len);
  if (ptr === 0) throw new Error('manifest allocation failed');
  const copied = exports.world_appliance_read_runtime_manifest(ptr, len);
  if (copied !== len) throw new Error('runtime manifest read failed');
  return readGuest(instance, ptr, len);
}

function assertRuntimeProfileManifest(manifest) {
  const required = [
    'runtime_profile_fingerprint=',
    'supports_loaded_execution=true\n',
    'supports_internal_providers=false\n',
    'supports_external_actuation=true\n',
    'max_modules=8\n',
    'max_provider_depth=8\n',
    'max_external_bindings=16\n',
    'max_module_bytes=131072\n',
    'max_image_bytes=131072\n',
    'max_command_bytes=65536\n',
    'max_output_bytes=131072\n',
    'max_linear_memory_pages=2048\n',
    'runtime_profile_metadata=\n',
  ];
  for (const line of required) {
    if (!manifest.includes(line)) throw new Error(`runtime manifest missing ${line.trim()}`);
  }
}

export function readLastError(instance) {
  const exports = instance.exports;
  const len = exports.world_appliance_last_error_len();
  if (len === 0) return '';
  const ptr = exports.world_appliance_alloc(len);
  if (ptr === 0) return '<allocation failed>';
  const copied = exports.world_appliance_read_last_error(ptr, len);
  return readGuest(instance, ptr, copied);
}

export function writeGuest(instance, bytes) {
  const ptr = instance.exports.world_appliance_alloc(bytes.length);
  if (ptr === 0) throw new Error('guest allocation failed');
  new Uint8Array(instance.exports.memory.buffer, ptr, bytes.length).set(bytes);
  return ptr;
}

export function readGuest(instance, ptr, len) {
  return decodeUtf8(new Uint8Array(instance.exports.memory.buffer, ptr, len));
}

function unload(instance, label) {
  if (instance.exports.world_appliance_unload_executable() !== statusOk) {
    throw new Error(`unload ${label} failed`);
  }
}
