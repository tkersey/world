#!/usr/bin/env bun

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { lstat, readFile, readdir } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)));
const WORLD_VERSION = "4.1.0";
const API_EXPORTS = Object.freeze([
  "WorldProcessHostError",
  "admitProcessKernel",
  "decodeEffectRequest",
  "decodeEffectResult",
  "decodeProcessOutcome",
  "encodeEffectResult",
]);

function parseExpectedIdentity(argv) {
  assert.deepEqual(argv.filter((_, index) => index % 2 === 0), [
    "--expected-boundary-version",
    "--expected-boundary-commit",
    "--expected-kernel-sha256",
  ], "usage: verify-runtime.mjs --expected-boundary-version VERSION --expected-boundary-commit COMMIT --expected-kernel-sha256 SHA256");
  assert.equal(argv.length, 6, "runtime verification requires an external expected identity");
  const expected = Object.freeze({
    boundaryVersion: argv[1],
    boundaryCommit: argv[3],
    kernelSha256: argv[5],
  });
  assert(/^\d+\.\d+\.\d+$/.test(expected.boundaryVersion), "expected Boundary version is invalid");
  assert(/^[0-9a-f]{40}$/.test(expected.boundaryCommit), "expected Boundary commit is invalid");
  assert(/^[0-9a-f]{64}$/.test(expected.kernelSha256), "expected kernel digest is invalid");
  return expected;
}

const expectedIdentity = parseExpectedIdentity(process.argv.slice(2));

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function compareUtf8(left, right) {
  return Buffer.from(left, "utf8").compare(Buffer.from(right, "utf8"));
}

function safeRelative(path) {
  return typeof path === "string"
    && path.length > 0
    && !path.includes("\0")
    && !path.includes("\\")
    && !path.startsWith("/")
    && !path.endsWith("/")
    && !path.includes("//")
    && path.split("/").every((component) => component !== "" && component !== "." && component !== "..");
}

async function walk(relative = "") {
  const directory = relative === "" ? root : join(root, ...relative.split("/"));
  const output = [];
  const entries = await readdir(directory, { withFileTypes: true });
  entries.sort((left, right) => compareUtf8(left.name, right.name));
  for (const entry of entries) {
    const path = relative === "" ? entry.name : `${relative}/${entry.name}`;
    assert(safeRelative(path), `runtime tree path is unsafe: ${path}`);
    const info = await lstat(join(root, ...path.split("/")));
    assert(!info.isSymbolicLink(), `runtime tree symlink is forbidden: ${path}`);
    if (info.isDirectory()) output.push(...await walk(path));
    else {
      assert(info.isFile(), `runtime tree entry is not a regular file: ${path}`);
      const expectedMode = path === "bin/world.mjs" || path === "verify-runtime.mjs" ? 0o755 : 0o644;
      assert.equal(info.mode & 0o777, expectedMode, `runtime tree mode differs: ${path}`);
      output.push(path);
    }
  }
  return output;
}

function admitInventory(files) {
  const fixed = new Set([
    "LICENSE",
    "README.md",
    "bin/world.mjs",
    "boundary-process-kernel-v1.wasm",
    "checksums.sha256",
    "package.json",
    "runtime-manifest.json",
    "src/process_v1/kernel_identity.json",
    "verify-runtime.mjs",
  ]);
  let processModules = 0;
  for (const path of files) {
    if (fixed.has(path)) continue;
    assert(/^src\/process_v1\/[a-z0-9_]+\.mjs$/.test(path), `runtime tree has an unexpected file: ${path}`);
    processModules += 1;
  }
  for (const path of fixed) assert(files.includes(path), `runtime tree is missing: ${path}`);
  assert(processModules > 0 && files.includes("src/process_v1/index.mjs"), "runtime tree has no public Process v1 module");
}

function parseChecksums(bytes) {
  const text = bytes.toString("utf8");
  assert(text.endsWith("\n") && text.length > 1, "runtime checksum file is malformed");
  const result = new Map();
  for (const line of text.slice(0, -1).split("\n")) {
    const match = /^([0-9a-f]{64})  ([A-Za-z0-9_./-]+)$/.exec(line);
    assert(match && safeRelative(match[2]), `runtime checksum row is malformed: ${line}`);
    assert(!result.has(match[2]), `runtime checksum path is duplicated: ${match[2]}`);
    result.set(match[2], match[1]);
  }
  return result;
}

function productionSourceDigest(entries) {
  const paths = [...entries.keys()]
    .filter((path) => path === "bin/world.mjs" || path.startsWith("src/process_v1/"))
    .sort(compareUtf8);
  assert(paths.includes("bin/world.mjs") && paths.includes("src/process_v1/index.mjs"), "runtime production source set is incomplete");
  const digest = createHash("sha256");
  digest.update("world-production-source/v1\0");
  for (const path of paths) {
    digest.update(path, "utf8");
    digest.update("\0");
    digest.update(entries.get(path));
    digest.update("\0");
  }
  return digest.digest("hex");
}

function exactObject(value, expected, label) {
  assert(value !== null && typeof value === "object" && !Array.isArray(value), `${label} must be an object`);
  assert.deepEqual(Object.keys(value).sort(), Object.keys(expected).sort(), `${label} fields are not exact`);
  for (const [key, expectedValue] of Object.entries(expected)) assert.deepEqual(value[key], expectedValue, `${label}.${key} differs`);
}

const files = (await walk()).sort(compareUtf8);
admitInventory(files);
const entries = new Map();
for (const path of files) entries.set(path, await readFile(join(root, ...path.split("/"))));

const checksums = parseChecksums(entries.get("checksums.sha256"));
const covered = files.filter((path) => path !== "checksums.sha256").sort(compareUtf8);
assert.deepEqual([...checksums.keys()].sort(compareUtf8), covered, "runtime checksum coverage is not exact");
for (const path of covered) assert.equal(sha256(entries.get(path)), checksums.get(path), `runtime checksum differs: ${path}`);

const packageJson = JSON.parse(entries.get("package.json").toString("utf8"));
exactObject(packageJson, {
  name: "@tkersey/world",
  version: WORLD_VERSION,
  type: "module",
  private: false,
  license: "MIT",
  exports: { "./process-v1": "./src/process_v1/index.mjs" },
  bin: { world: "./bin/world.mjs" },
  engines: { bun: ">=1.4.0" },
}, "runtime package");

const identity = JSON.parse(entries.get("src/process_v1/kernel_identity.json").toString("utf8"));
exactObject(identity, {
  boundaryVersion: identity.boundaryVersion,
  boundaryCommit: identity.boundaryCommit,
  abiVersion: identity.abiVersion,
  byteLength: identity.byteLength,
  sha256: identity.sha256,
  importCount: identity.importCount,
  exportCount: identity.exportCount,
  memoryInitialPages: identity.memoryInitialPages,
  memoryMaximumPages: identity.memoryMaximumPages,
}, "runtime kernel identity");
assert(/^\d+\.\d+\.\d+$/.test(identity.boundaryVersion), "runtime Boundary version is invalid");
assert(/^[0-9a-f]{40}$/.test(identity.boundaryCommit), "runtime Boundary commit is invalid");
assert(/^[0-9a-f]{64}$/.test(identity.sha256), "runtime kernel digest is invalid");
for (const field of ["abiVersion", "byteLength", "importCount", "exportCount", "memoryInitialPages", "memoryMaximumPages"]) {
  assert(Number.isSafeInteger(identity[field]) && identity[field] >= 0, `runtime kernel ${field} is invalid`);
}
assert.equal(identity.abiVersion, 1, "runtime kernel ABI version is not supported");
assert.equal(identity.boundaryVersion, expectedIdentity.boundaryVersion, "runtime Boundary version differs from the external expectation");
assert.equal(identity.boundaryCommit, expectedIdentity.boundaryCommit, "runtime Boundary commit differs from the external expectation");
assert.equal(identity.sha256, expectedIdentity.kernelSha256, "runtime kernel digest differs from the external expectation");

const manifest = JSON.parse(entries.get("runtime-manifest.json").toString("utf8"));
exactObject(manifest, {
  format: "world-process-host-runtime/v1",
  worldVersion: WORLD_VERSION,
  processKernelAbiVersion: identity.abiVersion,
  boundaryVersion: identity.boundaryVersion,
  boundaryCommit: identity.boundaryCommit,
  kernelSha256: identity.sha256,
  kernelByteLength: identity.byteLength,
  kernelImportCount: identity.importCount,
  sourceCommit: manifest.sourceCommit,
  productionSourceSha256: manifest.productionSourceSha256,
}, "runtime manifest");
assert(/^[0-9a-f]{40}$/.test(manifest.sourceCommit), "runtime manifest source commit is invalid");
assert.equal(productionSourceDigest(entries), manifest.productionSourceSha256, "runtime production source digest differs");

const kernel = entries.get("boundary-process-kernel-v1.wasm");
assert.equal(kernel.length, identity.byteLength, "runtime kernel byte length differs");
assert.equal(sha256(kernel), identity.sha256, "runtime kernel digest differs");
assert.equal(WebAssembly.validate(kernel), true, "runtime kernel is not valid WebAssembly");
const kernelModule = await WebAssembly.compile(kernel);
assert.equal(WebAssembly.Module.imports(kernelModule).length, identity.importCount, "runtime kernel import count differs");
assert.equal(WebAssembly.Module.exports(kernelModule).length, identity.exportCount, "runtime kernel export count differs");

const api = await import("./src/process_v1/index.mjs");
assert.deepEqual(Object.keys(api).sort(compareUtf8), [...API_EXPORTS].sort(compareUtf8), "runtime public API exports differ");
const host = await api.admitProcessKernel(new Uint8Array(kernel), { expectedSha256: identity.sha256 });
assert.equal(host.abiVersion, identity.abiVersion, "runtime admitted host ABI differs");
assert.equal(host.byteLength, identity.byteLength, "runtime admitted host kernel length differs");
assert.equal(host.sha256, identity.sha256, "runtime admitted host kernel digest differs");

console.log("world_runtime_internal_consistency=pass");
console.log(`world_runtime_inventory=${JSON.stringify(files)}`);
console.log(`world_runtime_file_count=${files.length}`);
console.log(`world_runtime_production_source_file_count=${covered.filter((path) => path === "bin/world.mjs" || path.startsWith("src/process_v1/")).length}`);
console.log("world_runtime_dependency_count=0");
console.log(`world_runtime_public_api_exports=${JSON.stringify([...API_EXPORTS].sort(compareUtf8))}`);
console.log("world_runtime_cli_commands=[\"world process step\"]");
console.log(`world_runtime_boundary_commit=${identity.boundaryCommit}`);
console.log(`world_runtime_kernel_sha256=${identity.sha256}`);
console.log(`world_runtime_kernel_bytes=${identity.byteLength}`);
console.log(`world_runtime_kernel_imports=${identity.importCount}`);
console.log(`world_runtime_kernel_abi=${identity.abiVersion}`);
