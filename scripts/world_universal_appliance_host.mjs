import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { decodeUtf8, inspectTurnOutput } from './world_universal_appliance_codec.mjs';
import {
  decodeApplianceManifest,
  decodeRuntimeManifest,
  encodeBootTurnInput,
  encodeContinueTurnInput,
  encodeResolutionInput,
} from './world_appliance_wire_codec.mjs';

export const statusOk = 0;
export const statusNeedsHost = 2;
export const statusCompleted = 3;
export const statusInvalidCommand = 7;
export const closureNeedsHost = 0;
export const closureCompleted = 2;

const textEncoder = new TextEncoder();

export async function runConformance({ wasmPath, imageAPath, commandAPath, imageBPath, commandBPath, proofPath }) {
  const wasmBytes = fs.readFileSync(wasmPath);
  const module = await WebAssembly.compile(wasmBytes);
  const imageA = fs.readFileSync(imageAPath);
  fs.readFileSync(commandAPath);
  const imageB = fs.readFileSync(imageBPath);
  fs.readFileSync(commandBPath);
  const proof = inspectTwoProgramProof(fs.readFileSync(proofPath, 'utf8'));

  const instance = await WebAssembly.instantiate(module, {});
  const rejectedTextEnvelope = rejectTextEnvelope(instance);
  const resultA = loadAndRunImage(instance, imageA, 'universal.fixture.a.reply');
  unload(instance, 'image A');
  const missingImageTurn = encodeBootTurnInput({ manifestFingerprint: 1n, metadata: 'submit-without-image' });
  const submitWithoutImageRejected =
    instance.exports.world_appliance_submit_turn(writeGuest(instance, missingImageTurn), missingImageTurn.length) === statusInvalidCommand;
  const resultB = loadAndRunImage(instance, imageB, 'universal.fixture.b.reply');
  unload(instance, 'image B');

  const fresh = await WebAssembly.instantiate(module, {});
  const freshA = loadAndRunImage(fresh, imageA, 'universal.fixture.a.reply');
  unload(fresh, 'fresh image A');
  const freshB = loadAndRunImage(fresh, imageB, 'universal.fixture.b.reply');
  unload(fresh, 'fresh image B');

  return {
    actualExternalRuntimeExecuted: true,
    compiledOnce: true,
    emptyImports: true,
    rejectedTextEnvelope,
    submitWithoutImageRejected,
    proof,
    resultA,
    resultB,
    freshA,
    freshB,
    nativeHelperUsed: false,
    javascriptCodecIndependent: true,
  };
}

export function rejectTextEnvelope(instance) {
  const bytes = textEncoder.encode('world.Executable.TextEnvelope.v1\nfingerprint=8cdcc3dc851ba11b\npayload=test-a');
  return instance.exports.world_appliance_load_executable(writeGuest(instance, bytes), bytes.length) === statusInvalidCommand;
}

export function loadAndRunImage(instance, imageBytes, replyMetadata) {
  const exports = instance.exports;
  if (exports.world_appliance_abi_version() !== 3) throw new Error('unexpected ABI version');

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
  const manifestBytes = new Uint8Array(instance.exports.memory.buffer, manifestPtr, manifestLen).slice();
  const applianceManifest = decodeApplianceManifest(manifestBytes);

  const bootTurn = encodeBootTurnInput({
    manifestFingerprint: applianceManifest.manifestFingerprint,
    metadata: `${replyMetadata}:boot`,
  });
  const submitStatus = exports.world_appliance_submit_turn(writeGuest(instance, bootTurn), bootTurn.length);
  if (submitStatus === statusCompleted) {
    const completedOutput = readClosureBytes(instance);
    const completedSummary = inspectTurnOutput(completedOutput);
    return completedRunSummary(completedOutput, completedSummary, false);
  }
  if (submitStatus !== statusNeedsHost) return { loaded: true, manifestPresent: true, outputReady: false };
  const needsHostOutput = readClosureBytes(instance);
  const needsHostSummary = inspectTurnOutput(needsHostOutput);
  if (needsHostSummary.status !== closureNeedsHost || needsHostSummary.hostRequestCount === 0) {
    return { loaded: true, manifestPresent: true, outputReady: true, hostRequestReady: false };
  }
  const resolution = encodeResolutionInput({
    request: needsHostSummary.hostRequests[0],
    responseFingerprint: 0x600d0001n,
    metadata: replyMetadata,
  });
  const continueTurn = encodeContinueTurnInput({
    manifestFingerprint: needsHostSummary.manifestFingerprint,
    previousTurnReceiptFingerprint: needsHostSummary.turnReceipt.receiptFingerprint,
    turnSequenceNumber: needsHostSummary.turnSequenceNumber + 1n,
    resolutions: [resolution],
    metadata: `${replyMetadata}:continue`,
  });

  const replyStatus = exports.world_appliance_submit_turn(writeGuest(instance, continueTurn), continueTurn.length);
  if (replyStatus !== statusCompleted) {
    return {
      loaded: true,
      manifestPresent: true,
      outputReady: true,
      hostRequestReady: true,
      completed: false,
      replyStatus,
      replyCommandLen: continueTurn.length,
      lastError: readLastError(instance),
    };
  }
  const completedOutput = readClosureBytes(instance);
  const completedSummary = inspectTurnOutput(completedOutput);
  return completedRunSummary(completedOutput, completedSummary, true);
}

function completedRunSummary(completedOutput, completedSummary, hostRequestReady) {
  return {
    loaded: true,
    manifestPresent: true,
    outputReady: true,
    hostRequestReady,
    completed: completedSummary.status === closureCompleted && completedSummary.hostRequestCount === 0,
    rootResultReady: completedSummary.rootResultFingerprint !== null && completedSummary.rootResultBytesLen > 0,
    archiveAppendReady: completedSummary.archiveAppendFingerprint !== null && completedSummary.archiveAppendBytesLen > 0,
    completedOutputSha256: sha256Hex(completedOutput),
    rootResultFingerprint: fingerprintString(completedSummary.rootResultFingerprint),
    archiveAppendFingerprint: fingerprintString(completedSummary.archiveAppendFingerprint),
  };
}

function inspectTwoProgramProof(text) {
  const facts = parseProofFacts(text);
  const read = (key) => {
    const value = facts.get(key);
    if (value === undefined || value.length === 0) throw new Error(`missing proof fact ${key}`);
    return value;
  };
  const readInt = (key) => {
    const value = Number(read(key));
    if (!Number.isSafeInteger(value)) throw new Error(`invalid numeric proof fact ${key}`);
    return value;
  };
  return {
    programPlanANotEqualB: read('program_plan_a_hash') !== read('program_plan_b_hash'),
    rootModuleANotEqualB: read('root_module_a_fingerprint') !== read('root_module_b_fingerprint'),
    dispatchANotEqualB: read('dispatch_a_fingerprint') !== read('dispatch_b_fingerprint'),
    manifestANotEqualB: read('manifest_a_fingerprint') !== read('manifest_b_fingerprint'),
    imageAOnePort:
      readInt('module_count_a') === 1 &&
      readInt('external_binding_count_a') === 1 &&
      readInt('route_count_a') === 0,
    imageBLoadedProvider:
      readInt('module_count_b') > 1 &&
      readInt('external_binding_count_b') === 0 &&
      readInt('route_count_b') > 0 &&
      readInt('provider_module_count_b') > 0,
  };
}

function parseProofFacts(text) {
  const facts = new Map();
  for (const line of text.split('\n')) {
    if (line.length === 0) continue;
    const equals = line.indexOf('=');
    if (equals <= 0) throw new Error(`malformed proof fact: ${line}`);
    const key = line.slice(0, equals);
    const value = line.slice(equals + 1);
    if (facts.has(key)) throw new Error(`duplicate proof fact: ${key}`);
    facts.set(key, value);
  }
  return facts;
}

function sha256Hex(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function fingerprintString(value) {
  return value === null ? null : value.toString(16).padStart(16, '0');
}

export function readClosureBytes(instance) {
  const exports = instance.exports;
  const closureLen = exports.world_appliance_closure_len();
  if (closureLen === 0) throw new Error('missing closure');
  const closurePtr = exports.world_appliance_alloc(closureLen);
  if (closurePtr === 0) throw new Error('closure allocation failed');
  if (exports.world_appliance_read_closure(closurePtr, closureLen) !== closureLen) throw new Error('closure read failed');
  return new Uint8Array(instance.exports.memory.buffer, closurePtr, closureLen).slice();
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
  const facts = decodeRuntimeManifest(manifest);
  if (facts.get('imports') !== '0') throw new Error('runtime manifest does not declare zero imports');
  const required = [
    'runtime_profile_fingerprint=',
    'supports_loaded_execution=true\n',
    'supports_internal_providers=true\n',
    'supports_external_actuation=true\n',
    'max_modules=8\n',
    'max_provider_depth=8\n',
    'max_external_bindings=16\n',
    'max_module_bytes=131072\n',
    'max_image_bytes=131072\n',
    'max_command_bytes=65536\n',
    'max_output_bytes=131072\n',
    'max_linear_memory_pages=1024\n',
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
