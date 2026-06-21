#!/usr/bin/env node
'use strict';

const fs = require('node:fs');

const statusOk = 0;
const statusCompleted = 3;
const statusInvalidCommand = 7;
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

async function main() {
  const wasmPath = process.argv[2];
  if (!wasmPath) throw new Error('usage: world_universal_appliance_node_conformance.js <world_universal_appliance.wasm>');

  const wasmBytes = fs.readFileSync(wasmPath);
  const module = await WebAssembly.compile(wasmBytes);

  const imageA = executableImage('A');
  const imageB = executableImage('B');
  const command = 'boot';

  const instanceA = await WebAssembly.instantiate(module, {});
  const resultA = loadAndRunImage(instanceA, imageA, command);
  if (instanceA.exports.world_appliance_unload_executable() !== statusOk) {
    throw new Error('unload image A failed');
  }
  if (instanceA.exports.world_appliance_submit_command(writeGuest(instanceA, textEncoder.encode(command)), command.length) !== statusInvalidCommand) {
    throw new Error('submit without image was not rejected');
  }

  const instanceB = await WebAssembly.instantiate(module, {});
  const resultB = loadAndRunImage(instanceB, imageB, command);
  if (!resultA || !resultB) throw new Error('valid executable image was not loaded and run');

  console.log('actual_external_runtime_executed=true');
  console.log('compiled_once=true');
  console.log('empty_imports=true');
  console.log('image_a_loaded=true');
  console.log('image_b_loaded=true');
  console.log('manifests_present=true');
  console.log('commands_completed=true');
  console.log('submit_without_image_rejected=true');
}

function loadAndRunImage(instance, image, command) {
  const exports = instance.exports;
  if (exports.world_appliance_abi_version() !== 2) throw new Error('unexpected ABI version');

  const manifest = readRuntimeManifest(instance);
  if (!manifest.includes('imports=0\n')) throw new Error('runtime manifest does not declare zero imports');

  const imageBytes = textEncoder.encode(image);
  const commandBytes = textEncoder.encode(command);
  const imagePtr = writeGuest(instance, imageBytes);
  const commandPtr = writeGuest(instance, commandBytes);

  if (exports.world_appliance_load_executable(imagePtr, imageBytes.length) !== statusOk) return false;
  if (exports.world_appliance_manifest_len() !== imageBytes.length) return false;
  if (exports.world_appliance_submit_command(commandPtr, commandBytes.length) !== statusCompleted) return false;
  if (exports.world_appliance_output_len() === 0) return false;
  return true;
}

function readRuntimeManifest(instance) {
  const exports = instance.exports;
  const len = exports.world_appliance_runtime_manifest_len();
  if (len === 0) throw new Error('missing runtime manifest');
  const ptr = exports.world_appliance_alloc(len);
  if (ptr === 0) throw new Error('manifest allocation failed');
  const copied = exports.world_appliance_read_runtime_manifest(ptr, len);
  if (copied !== len) throw new Error('runtime manifest read failed');
  return readGuest(instance, ptr, len);
}

function writeGuest(instance, bytes) {
  const ptr = instance.exports.world_appliance_alloc(bytes.length);
  if (ptr === 0) throw new Error('guest allocation failed');
  new Uint8Array(instance.exports.memory.buffer, ptr, bytes.length).set(bytes);
  return ptr;
}

function readGuest(instance, ptr, len) {
  return textDecoder.decode(new Uint8Array(instance.exports.memory.buffer, ptr, len));
}

function executableImage(payload) {
  const payloadBytes = textEncoder.encode(payload);
  return `world.Executable.Image.v1\nfingerprint=${fnv64Hex(payloadBytes)}\npayload=${payload}`;
}

function fnv64Hex(bytes) {
  let hash = 0xcbf29ce484222325n;
  for (const byte of bytes) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * 0x100000001b3n);
  }
  return hash.toString(16).padStart(16, '0');
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
