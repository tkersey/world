import { readFile } from "node:fs/promises";

const [
  wasmPath,
  manifestPath,
  expectedInitialPagesText,
  expectedMaximumPagesText,
] = process.argv.slice(2);
if (
  !wasmPath ||
  !manifestPath ||
  !expectedInitialPagesText ||
  !expectedMaximumPagesText
) {
  throw new Error(
    "usage: node world_application_v1_artifact_check.mjs <application.world.wasm> <application.manifest.bin> <initial-pages> <maximum-pages>",
  );
}
const expectedInitialPages = parsePages(
  expectedInitialPagesText,
  "initial pages",
);
const expectedMaximumPages = parsePages(
  expectedMaximumPagesText,
  "maximum pages",
);
const wasmBytes = await readFile(wasmPath);
const nativeManifest = await readFile(manifestPath);
const compiled = await WebAssembly.compile(wasmBytes);

const imports = WebAssembly.Module.imports(compiled);
if (imports.length !== 0) {
  throw new Error(
    `World application WASM must import nothing; found ${imports.length} imports`,
  );
}

const requiredExports = new Set([
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
]);
for (const entry of WebAssembly.Module.exports(compiled)) {
  requiredExports.delete(entry.name);
}
if (requiredExports.size !== 0) {
  throw new Error(
    `World application WASM is missing ABI exports: ${[...requiredExports].join(", ")}`,
  );
}

const instance = await WebAssembly.instantiate(compiled, {});
const exports = instance.exports;
if (exports.world_abi_version() !== 1) {
  throw new Error("World application WASM does not implement Application ABI v1");
}

const actualInitialPages = exports.memory.buffer.byteLength / 65_536;
if (actualInitialPages !== expectedInitialPages) {
  throw new Error(
    `World application WASM initial memory is ${actualInitialPages} pages; expected ${expectedInitialPages}`,
  );
}
verifyMaximumMemory(exports.memory, expectedInitialPages, expectedMaximumPages);

const manifestPointer = exports.world_manifest_ptr();
const manifestLength = exports.world_manifest_len();
const wasmManifest = Buffer.from(
  new Uint8Array(exports.memory.buffer, manifestPointer, manifestLength),
);
if (!wasmManifest.equals(nativeManifest)) {
  throw new Error(
    "World application native and WASM manifests have different canonical bytes",
  );
}
if (wasmManifest.subarray(0, 8).toString("ascii") !== "WRLDMNF1") {
  throw new Error("World application manifest has invalid magic");
}
if (wasmManifest.readUInt32LE(8) !== 1) {
  throw new Error("World application manifest has an unsupported format version");
}

console.log(`application_wasm=${wasmPath}`);
console.log(`application_wasm_bytes=${wasmBytes.length}`);
console.log("application_wasm_import_count=0");
console.log(`application_wasm_initial_pages=${expectedInitialPages}`);
console.log(`application_wasm_maximum_pages=${expectedMaximumPages}`);
console.log("native_wasm_manifest_identity=true");

function parsePages(value, label) {
  if (!/^[1-9][0-9]*$/.test(value)) {
    throw new Error(`invalid ${label}: ${value}`);
  }
  const result = Number(value);
  if (!Number.isSafeInteger(result) || result > 65_536) {
    throw new Error(`invalid ${label}: ${value}`);
  }
  return result;
}

function verifyMaximumMemory(memory, initialPages, maximumPages) {
  if (maximumPages < initialPages) {
    throw new Error("maximum memory pages are smaller than initial memory pages");
  }
  const growth = maximumPages - initialPages;
  if (growth !== 0) memory.grow(growth);
  if (memory.buffer.byteLength / 65_536 !== maximumPages) {
    throw new Error("World application WASM did not grow to its declared maximum");
  }
  let rejected = false;
  try {
    memory.grow(1);
  } catch (error) {
    if (error instanceof RangeError) rejected = true;
    else throw error;
  }
  if (!rejected) {
    throw new Error("World application WASM memory has no enforced maximum");
  }
}
