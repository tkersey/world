import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { constants as fsConstants, realpathSync } from "node:fs";
import {
  lstat,
  mkdir,
  open,
  readdir,
  realpath,
  rename,
  rm,
} from "node:fs/promises";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseBoundaryProcessKernelIdentityV1 } from
  "../src/process_v1/kernel_identity.mjs";
import {
  inspectProcessKernelWasm,
  PROCESS_KERNEL_EXPORT_NAMES,
} from "../src/process_v1/wasm.mjs";

export const WORLD_VERSION = "4.1.0";
export const RUNTIME_FORMAT = "world-process-host-runtime/v1";
export const RUNTIME_ROOT = `world-v${WORLD_VERSION}-process-host-runtime`;
export const RUNTIME_ARCHIVE_NAME = `${RUNTIME_ROOT}.tar.gz`;
export const RUNTIME_ARCHIVE_MAX_BYTES = 16 * 1024 * 1024;
export const RUNTIME_EXPANDED_MAX_BYTES = 32 * 1024 * 1024;
export const RUNTIME_ENTRY_MAX_BYTES = 16 * 1024 * 1024;
export const RUNTIME_ENTRY_MAX_COUNT = 256;
const TRACKED_FILE_MAX_BYTES = 64 * 1024 * 1024;
const TRACKED_REPOSITORY_MAX_BYTES = 128 * 1024 * 1024;
const KERNEL_ABI_PROBE_TIMEOUT_MS = 5_000;
const SUPPORTED_PROCESS_KERNEL_ABI_VERSION = 1;
const KERNEL_ABI_PROBE_SOURCE = String.raw`
(async () => {
  const { readFileSync } = await import("node:fs");
  const bytes = readFileSync(0);
  const module = await WebAssembly.compile(bytes);
  const instance = await WebAssembly.instantiate(module, {});
  process.stdout.write(String(instance.exports.boundary_process_kernel_abi_version()) + "\n");
})().catch((error) => {
  process.stderr.write((error instanceof Error ? error.message : String(error)) + "\n");
  process.exitCode = 1;
});
`;

const scriptPath = fileURLToPath(import.meta.url);
export const repositoryRoot = resolve(dirname(scriptPath), "..");
export const defaultArchivePath = join(repositoryRoot, "dist", RUNTIME_ARCHIVE_NAME);
export const defaultChecksumPath = `${defaultArchivePath}.sha256`;

const FIXED_SOURCE_PATHS = Object.freeze([
  "LICENSE",
  "README.md",
  "package.json",
  "bin/world.mjs",
  "boundary-process-kernel-v1.wasm",
  "verify-runtime.mjs",
]);

const REQUIRED_PROCESS_MODULES = Object.freeze([
  "effect.mjs",
  "errors.mjs",
  "file_input.mjs",
  "index.mjs",
  "kernel.mjs",
  "kernel_identity.mjs",
  "outcome.mjs",
  "wasm.mjs",
]);

const REQUIRED_PROCESS_ASSETS = Object.freeze([
  "kernel_identity.json",
]);

const GENERATED_PATHS = Object.freeze([
  "checksums.sha256",
  "runtime-manifest.json",
]);

export function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

export function runtimeMode(path) {
  return path === "bin/world.mjs" || path === "verify-runtime.mjs" ? 0o755 : 0o644;
}

export function isSafeRelativePath(path) {
  if (typeof path !== "string" || path.length === 0 || path.includes("\0") || path.includes("\\")) return false;
  if (path.startsWith("/") || path.endsWith("/") || path.includes("//")) return false;
  const components = path.split("/");
  return components.every((component) => component !== "" && component !== "." && component !== "..");
}

const FILE_GENERATION_FIELDS = Object.freeze(["dev", "ino", "size", "mtimeNs", "ctimeNs"]);

function assertSameFileGeneration(actual, expected, message) {
  for (const field of FILE_GENERATION_FIELDS) assert.equal(actual[field], expected[field], message);
}

export async function readBoundedRegularFileSnapshot(path, maximumBytes, label, testHooks = undefined) {
  assert(isAbsolute(path), `${label} path must be absolute`);
  const pathBefore = await lstat(path, { bigint: true });
  assert(pathBefore.isFile() && !pathBefore.isSymbolicLink(), `${label} is not a regular file`);
  assert(pathBefore.size <= BigInt(maximumBytes), `${label} exceeds its size limit`);
  await testHooks?.afterPathStat?.();
  const handle = await open(path, fsConstants.O_RDONLY | fsConstants.O_NONBLOCK);
  try {
    const before = await handle.stat({ bigint: true });
    assert(before.isFile(), `${label} descriptor is not a regular file`);
    assertSameFileGeneration(before, pathBefore, `${label} path generation does not match opened descriptor`);
    assert(before.size <= BigInt(maximumBytes), `${label} exceeds its size limit`);
    await testHooks?.afterDescriptorStat?.();
    const byteLength = Number(before.size);
    const bytes = Buffer.allocUnsafe(byteLength);
    let offset = 0;
    while (offset < byteLength) {
      const { bytesRead } = await handle.read(bytes, offset, byteLength - offset, offset);
      assert(bytesRead !== 0, `${label} changed during read`);
      offset += bytesRead;
    }
    const growthProbe = Buffer.allocUnsafe(1);
    const { bytesRead: growthBytes } = await handle.read(growthProbe, 0, 1, byteLength);
    assert.equal(growthBytes, 0, `${label} changed during read`);
    const after = await handle.stat({ bigint: true });
    assertSameFileGeneration(after, before, `${label} descriptor changed during read`);
    await testHooks?.afterDescriptorRead?.();
    const pathAfter = await lstat(path, { bigint: true });
    assert(pathAfter.isFile() && !pathAfter.isSymbolicLink(), `${label} path is no longer a regular file`);
    assertSameFileGeneration(pathAfter, before, `${label} path changed during read`);
    return Object.freeze({
      bytes: Buffer.from(bytes),
      generation: Object.freeze(Object.fromEntries(FILE_GENERATION_FIELDS.map((field) => [field, after[field]]))),
      executable: (after.mode & 0o111n) !== 0n,
    });
  } finally {
    await handle.close();
  }
}

export async function canonicalFuturePathIdentity(path) {
  assert(typeof path === "string" && path.length > 0, "custody path must be nonempty");
  let ancestor = resolve(path);
  const suffix = [];
  for (;;) {
    try {
      await lstat(ancestor);
      break;
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
      const parent = dirname(ancestor);
      assert.notEqual(parent, ancestor, `custody path has no existing ancestor: ${path}`);
      suffix.unshift(basename(ancestor));
      ancestor = parent;
    }
  }
  const physical = join(await realpath(ancestor), ...suffix);
  return physical.replaceAll("\\", "/").normalize("NFC").toLowerCase();
}

function identityContains(rootIdentity, candidateIdentity) {
  const prefix = rootIdentity.endsWith("/") ? rootIdentity : `${rootIdentity}/`;
  return candidateIdentity === rootIdentity || candidateIdentity.startsWith(prefix);
}

async function canonicalRenameTargetIdentity(path) {
  const parentIdentity = await canonicalFuturePathIdentity(dirname(resolve(path)));
  return join(parentIdentity, basename(path))
    .replaceAll("\\", "/")
    .normalize("NFC")
    .toLowerCase();
}

export async function assertRepositoryOutputNamespaces(root, outputs, label = "repository output") {
  const rootIdentity = await canonicalFuturePathIdentity(root);
  const identities = await Promise.all(outputs.map(async (output) => Object.freeze({
    ...output,
    identity: await canonicalRenameTargetIdentity(output.path),
  })));
  const repositoryOutputs = identities.filter((output) => identityContains(rootIdentity, output.identity));
  if (repositoryOutputs.length === 0) return;

  const distPath = join(root, "dist");
  try {
    const dist = await lstat(distPath);
    assert(dist.isDirectory() && !dist.isSymbolicLink(), `${label} dist namespace must be a real directory`);
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
  const distIdentity = await canonicalFuturePathIdentity(distPath);
  for (const output of repositoryOutputs) {
    assert(
      output.identity !== distIdentity && identityContains(distIdentity, output.identity),
      `${output.label} must be outside the repository or a file beneath dist`,
    );
  }
}

export async function assertPhysicalPathCustody(paths, protectedPaths = [], label = "custody") {
  const seen = new Map();
  for (const entry of paths) {
    const identity = await canonicalFuturePathIdentity(entry.path);
    assert(!seen.has(identity), `${label} paths must be physically distinct: ${entry.label} aliases ${seen.get(identity)}`);
    seen.set(identity, entry.label);
  }
  for (const entry of protectedPaths) {
    const identity = await canonicalFuturePathIdentity(entry.path);
    assert(!seen.has(identity), `${label} path must be physically distinct from protected input: ${seen.get(identity)} aliases ${entry.label}`);
  }
}

function compareUtf8(left, right) {
  return Buffer.from(left, "utf8").compare(Buffer.from(right, "utf8"));
}

export async function runtimeSourcePaths(root = repositoryRoot) {
  const moduleRoot = join(root, "src", "process_v1");
  const entries = await readdir(moduleRoot, { withFileTypes: true });
  const modules = [];
  const assets = [];
  for (const entry of entries) {
    assert(entry.isFile() && !entry.isSymbolicLink(), `runtime source entry is not a regular file: src/process_v1/${entry.name}`);
    if (/^[a-z0-9_]+\.mjs$/.test(entry.name)) modules.push(entry.name);
    else if (REQUIRED_PROCESS_ASSETS.includes(entry.name)) assets.push(entry.name);
    else assert.fail(`unexpected runtime source entry: src/process_v1/${entry.name}`);
  }
  modules.sort(compareUtf8);
  assets.sort(compareUtf8);
  for (const required of REQUIRED_PROCESS_MODULES) {
    assert(modules.includes(required), `required runtime module is missing: src/process_v1/${required}`);
  }
  assert.deepEqual(assets, [...REQUIRED_PROCESS_ASSETS], "required runtime assets are not exact");
  return [...FIXED_SOURCE_PATHS, ...modules, ...assets].map((name) =>
    FIXED_SOURCE_PATHS.includes(name) ? name : `src/process_v1/${name}`
  ).sort(compareUtf8);
}

async function snapshotRegularFileGeneration(root, path, maximumBytes = RUNTIME_ENTRY_MAX_BYTES) {
  assert(isSafeRelativePath(path), `unsafe runtime input path: ${path}`);
  const absolute = join(root, ...path.split("/"));
  return readBoundedRegularFileSnapshot(absolute, maximumBytes, `runtime input ${path}`);
}

async function snapshotRegularFile(root, path, maximumBytes = RUNTIME_ENTRY_MAX_BYTES) {
  return (await snapshotRegularFileGeneration(root, path, maximumBytes)).bytes;
}

export function productionSourceSha256(entries) {
  const sourcePaths = [...entries.keys()]
    .filter((path) => path === "bin/world.mjs" || path.startsWith("src/process_v1/"))
    .sort(compareUtf8);
  assert(sourcePaths.includes("bin/world.mjs"), "production source digest is missing bin/world.mjs");
  assert(sourcePaths.includes("src/process_v1/index.mjs"), "production source digest is missing the public module");
  const digest = createHash("sha256");
  digest.update("world-production-source/v1\0");
  for (const path of sourcePaths) {
    const bytes = entries.get(path);
    assert(Buffer.isBuffer(bytes), `production source bytes are missing: ${path}`);
    digest.update(path, "utf8");
    digest.update("\0");
    digest.update(bytes);
    digest.update("\0");
  }
  return digest.digest("hex");
}

export function runtimePackageJson(sourceBytes) {
  const source = JSON.parse(sourceBytes.toString("utf8"));
  const runtime = {
    name: "@tkersey/world",
    version: WORLD_VERSION,
    type: "module",
    private: false,
    license: "MIT",
    exports: { "./process-v1": "./src/process_v1/index.mjs" },
    bin: { world: "./bin/world.mjs" },
    engines: { bun: ">=1.4.0" },
  };
  for (const [key, value] of Object.entries(runtime)) assert.deepEqual(source[key], value, `source package ${key} differs from the runtime contract`);
  for (const field of ["dependencies", "optionalDependencies", "peerDependencies"]) {
    assert(source[field] === undefined || Object.keys(source[field]).length === 0, `source package ${field} must be empty`);
  }
  return Buffer.from(stableJson(runtime), "utf8");
}

export async function snapshotRuntimeSources(root = repositoryRoot) {
  const paths = await runtimeSourcePaths(root);
  const entries = new Map();
  for (const path of paths) entries.set(path, await snapshotRegularFile(root, path));
  return entries;
}

export function boundaryProcessKernelLockFromIdentityBytes(bytes) {
  const identity = parseBoundaryProcessKernelIdentityV1(bytes);
  return Object.freeze({
    boundaryVersion: identity.boundaryVersion,
    boundaryCommit: identity.boundaryCommit,
    kernelSha256: identity.sha256,
    kernelByteLength: identity.byteLength,
    processKernelAbiVersion: identity.abiVersion,
    kernelImportCount: identity.importCount,
    kernelExportCount: identity.exportCount,
    memoryInitialPages: identity.memoryInitialPages,
    memoryMaximumPages: identity.memoryMaximumPages,
  });
}

export async function readBoundaryLock(root = repositoryRoot, sourceEntries = null) {
  const source = sourceEntries?.get("src/process_v1/kernel_identity.json")
    ?? await snapshotRegularFile(root, "src/process_v1/kernel_identity.json");
  return boundaryProcessKernelLockFromIdentityBytes(source);
}

export async function assertBoundaryProcessKernelMatchesLock(bytes, lock) {
  assert(bytes instanceof Uint8Array, "Boundary Process kernel must be bytes");
  assert.equal(bytes.byteLength, lock.kernelByteLength, "Boundary Process kernel byte length differs from the lock");
  assert.equal(sha256(bytes), lock.kernelSha256, "Boundary Process kernel digest differs from the lock");
  assert.equal(WebAssembly.validate(bytes), true, "Boundary Process kernel is not valid WebAssembly");
  const inspection = inspectProcessKernelWasm(bytes);
  assert.equal(inspection.importCount, lock.kernelImportCount, "Boundary Process kernel import count differs from the lock");
  assert.equal(inspection.exportCount, lock.kernelExportCount, "Boundary Process kernel export count differs from the lock");
  assert.equal(inspection.memory.initialPages, lock.memoryInitialPages, "Boundary Process kernel initial memory differs from the lock");
  assert.equal(inspection.memory.maximumPages, lock.memoryMaximumPages, "Boundary Process kernel maximum memory differs from the lock");

  const module = await WebAssembly.compile(bytes);
  assert.equal(WebAssembly.Module.imports(module).length, lock.kernelImportCount, "Boundary Process kernel compiled imports differ from the lock");
  const exports = WebAssembly.Module.exports(module);
  assert.equal(exports.length, lock.kernelExportCount, "Boundary Process kernel compiled exports differ from the lock");
  const actualExports = new Map(exports.map((entry) => [entry.name, entry.kind]));
  for (const name of PROCESS_KERNEL_EXPORT_NAMES) {
    assert.equal(actualExports.get(name), name === "memory" ? "memory" : "function", `Boundary Process kernel export differs: ${name}`);
  }

  const abiVersion = probeBoundaryProcessKernelAbi(bytes);
  assert.equal(
    abiVersion,
    lock.processKernelAbiVersion,
    "Boundary Process kernel ABI version differs from the lock",
  );
  assert.equal(abiVersion, SUPPORTED_PROCESS_KERNEL_ABI_VERSION, "Boundary Process kernel ABI version is not supported");
  return Object.freeze({ inspection });
}

export function probeBoundaryProcessKernelAbi(bytes, timeoutMs = KERNEL_ABI_PROBE_TIMEOUT_MS) {
  assert(bytes instanceof Uint8Array, "Boundary Process ABI probe input must be bytes");
  assert(Number.isSafeInteger(timeoutMs) && timeoutMs > 0 && timeoutMs <= KERNEL_ABI_PROBE_TIMEOUT_MS, "Boundary Process ABI probe timeout is invalid");
  const result = spawnSync(process.execPath, ["--eval", KERNEL_ABI_PROBE_SOURCE], {
    input: Buffer.from(bytes),
    encoding: "utf8",
    timeout: timeoutMs,
    killSignal: "SIGKILL",
    maxBuffer: 4096,
    env: {},
  });
  if (result.error?.code === "ETIMEDOUT") assert.fail("Boundary Process kernel ABI probe timed out");
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `Boundary Process kernel ABI probe failed: ${result.stderr.trim()}`);
  assert(/^\d+\n$/.test(result.stdout), "Boundary Process kernel ABI probe returned invalid output");
  return Number(result.stdout.trim());
}

export function gitProvenanceEnvironment(environment = process.env) {
  const sanitized = { ...environment };
  for (const key of Object.keys(sanitized)) {
    if (key.startsWith("GIT_")) delete sanitized[key];
  }
  sanitized.GIT_NO_REPLACE_OBJECTS = "1";
  return sanitized;
}

export function assertSelectedGitCheckoutRoot(root) {
  const selected = gitOutput(root, ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
  assert.equal(realpathSync(selected), realpathSync(root), "selected Git checkout root differs from the requested root");
}

function gitOutput(root, arguments_, options = {}) {
  return execFileSync("git", arguments_, {
    cwd: root,
    encoding: options.encoding,
    env: gitProvenanceEnvironment(),
    maxBuffer: options.maxBuffer ?? 1024 * 1024,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

export function exactGitHeadCommit(root = repositoryRoot) {
  assertSelectedGitCheckoutRoot(root);
  const commit = gitOutput(root, ["rev-parse", "HEAD"], {
    encoding: "utf8",
  }).trim();
  assert(/^[0-9a-f]{40}$/.test(commit), "World source commit is not an exact Git commit");
  return commit;
}

function gitBlobAtPath(root, commit, path, maximumBytes) {
  assert(/^[0-9a-f]{40}$/.test(commit), "Git blob commit is not exact");
  assert(isSafeRelativePath(path), `unsafe Git blob path: ${path}`);
  return Buffer.from(gitOutput(root, ["cat-file", "blob", `${commit}:${path}`], {
    maxBuffer: maximumBytes + 1024,
  }));
}

export function bindRetainedSnapshotsToGitHead(root, snapshots) {
  assert(snapshots instanceof Map && snapshots.size > 0, "retained Git snapshots must be a nonempty Map");
  const commit = exactGitHeadCommit(root);
  const committedRuntimePaths = [
    ...FIXED_SOURCE_PATHS,
    ...[...commitTreeEntries(root, commit).keys()].filter((path) => path.startsWith("src/process_v1/")),
  ].sort(compareUtf8);
  const retainedRuntimePaths = [...snapshots.keys()]
    .filter((path) => FIXED_SOURCE_PATHS.includes(path) || path.startsWith("src/process_v1/"))
    .sort(compareUtf8);
  assert.deepEqual(retainedRuntimePaths, committedRuntimePaths, "retained runtime inventory differs from Git tree at HEAD");
  for (const [path, retainedBytes] of snapshots) {
    assert(Buffer.isBuffer(retainedBytes), `retained runtime bytes are missing: ${path}`);
    const committedBytes = gitBlobAtPath(root, commit, path, Math.max(retainedBytes.length, RUNTIME_ENTRY_MAX_BYTES));
    assert(retainedBytes.equals(committedBytes), `retained runtime bytes differ from Git blob at HEAD: ${path}`);
  }
  assert.equal(exactGitHeadCommit(root), commit, "Git HEAD changed while binding retained runtime bytes");
  return commit;
}

function parseZeroRecords(bytes) {
  assert(Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.at(-1) === 0, "Git record stream is not NUL terminated");
  return bytes.subarray(0, -1).toString("utf8").split("\0");
}

function commitTreeEntries(root, commit) {
  const records = parseZeroRecords(Buffer.from(gitOutput(root, ["ls-tree", "-r", "-z", "--full-tree", commit], {
    maxBuffer: 16 * 1024 * 1024,
  })));
  const entries = new Map();
  for (const record of records) {
    const match = /^(100644|100755) blob ([0-9a-f]+)\t(.+)$/.exec(record);
    assert(match, `tracked Git tree entry is not a regular blob: ${record}`);
    const path = match[3];
    assert(isSafeRelativePath(path), `tracked Git tree path is unsafe: ${path}`);
    assert(!entries.has(path), `tracked Git tree path is duplicated: ${path}`);
    entries.set(path, Object.freeze({ mode: match[1], object: match[2] }));
  }
  assert(entries.size > 0, "tracked Git tree is empty");
  return entries;
}

export function trackedRepositoryPaths(root = repositoryRoot, commit = exactGitHeadCommit(root)) {
  return [...commitTreeEntries(root, commit).keys()].sort(compareUtf8);
}

function indexEntries(root) {
  const records = parseZeroRecords(Buffer.from(gitOutput(root, ["ls-files", "--stage", "-z"], {
    maxBuffer: 16 * 1024 * 1024,
  })));
  const entries = new Map();
  for (const record of records) {
    const match = /^(100644|100755) ([0-9a-f]+) ([0-3])\t(.+)$/.exec(record);
    assert(match, `tracked Git index entry is invalid: ${record}`);
    assert.equal(match[3], "0", `tracked Git index has an unmerged entry: ${match[4]}`);
    assert(!entries.has(match[4]), `tracked Git index path is duplicated: ${match[4]}`);
    entries.set(match[4], Object.freeze({ mode: match[1], object: match[2] }));
  }
  return entries;
}

function assertIndexMatchesTree(root, tree) {
  const index = indexEntries(root);
  assert.deepEqual([...index.keys()].sort(compareUtf8), [...tree.keys()].sort(compareUtf8), "tracked Git index inventory differs from source commit");
  for (const [path, expected] of tree) assert.deepEqual(index.get(path), expected, `tracked Git index differs from source commit: ${path}`);
}

export async function assertTrackedRepositoryMatchesCommit(root, commit) {
  assert(/^[0-9a-f]{40}$/.test(commit), "tracked repository source commit is invalid");
  assert.equal(exactGitHeadCommit(root), commit, "tracked repository HEAD differs from archive sourceCommit");
  const tree = commitTreeEntries(root, commit);
  assertIndexMatchesTree(root, tree);
  const generations = new Map();
  let retainedByteLength = 0;
  for (const [path, expected] of tree) {
    const retained = await snapshotRegularFileGeneration(root, path, TRACKED_FILE_MAX_BYTES);
    retainedByteLength += retained.bytes.length;
    assert(retainedByteLength <= TRACKED_REPOSITORY_MAX_BYTES, "tracked repository exceeds its proof-state size limit");
    assert.equal(retained.executable, expected.mode === "100755", `tracked working mode differs from source commit: ${path}`);
    const committedBytes = gitBlobAtPath(root, commit, path, TRACKED_FILE_MAX_BYTES);
    assert(retained.bytes.equals(committedBytes), `tracked working bytes differ from source commit: ${path}`);
    generations.set(path, retained.generation);
  }
  for (const [path, expected] of generations) {
    const after = await lstat(join(root, ...path.split("/")), { bigint: true });
    assert(after.isFile() && !after.isSymbolicLink(), `tracked working path changed after proof-state snapshot: ${path}`);
    for (const field of ["dev", "ino", "size", "mtimeNs", "ctimeNs"]) {
      assert.equal(after[field], expected[field], `tracked working path changed after proof-state snapshot: ${path}`);
    }
  }
  assertIndexMatchesTree(root, tree);
  assert.equal(exactGitHeadCommit(root), commit, "tracked repository HEAD changed during proof-state verification");
  return Object.freeze({ sourceCommit: commit, trackedFileCount: tree.size, trackedByteLength: retainedByteLength });
}

export function createRuntimeManifest({ lock, commit, entries }) {
  assert(/^[0-9a-f]{40}$/.test(commit), "runtime manifest source commit is invalid");
  const kernel = entries.get("boundary-process-kernel-v1.wasm");
  assert(Buffer.isBuffer(kernel), "runtime kernel bytes are missing");
  assert.equal(kernel.length, lock.kernelByteLength, "runtime kernel byte length differs from Boundary lock");
  assert.equal(sha256(kernel), lock.kernelSha256, "runtime kernel digest differs from Boundary lock");
  return Object.freeze({
    format: RUNTIME_FORMAT,
    worldVersion: WORLD_VERSION,
    processKernelAbiVersion: lock.processKernelAbiVersion,
    boundaryVersion: lock.boundaryVersion,
    boundaryCommit: lock.boundaryCommit,
    kernelSha256: lock.kernelSha256,
    kernelByteLength: lock.kernelByteLength,
    kernelImportCount: lock.kernelImportCount,
    sourceCommit: commit,
    productionSourceSha256: productionSourceSha256(entries),
  });
}

export function stableJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

export function checksumsBytes(entries) {
  const rows = [];
  for (const path of [...entries.keys()].filter((path) => path !== "checksums.sha256").sort(compareUtf8)) {
    rows.push(`${sha256(entries.get(path))}  ${path}`);
  }
  return Buffer.from(`${rows.join("\n")}\n`, "utf8");
}

function splitUstarPath(path) {
  const bytes = Buffer.byteLength(path, "utf8");
  assert(bytes <= 255, `USTAR path exceeds the portable limit: ${path}`);
  if (bytes <= 100) return { name: path, prefix: "" };
  for (let index = path.lastIndexOf("/"); index > 0; index = path.lastIndexOf("/", index - 1)) {
    const prefix = path.slice(0, index);
    const name = path.slice(index + 1);
    if (Buffer.byteLength(prefix, "utf8") <= 155 && Buffer.byteLength(name, "utf8") <= 100) return { name, prefix };
  }
  throw new Error(`USTAR path cannot be represented: ${path}`);
}

function writeOctal(header, offset, width, value) {
  assert(Number.isSafeInteger(value) && value >= 0, "USTAR numeric field is invalid");
  const encoded = value.toString(8);
  assert(encoded.length <= width - 1, "USTAR numeric field exceeds its width");
  header.write(`${encoded.padStart(width - 1, "0")}\0`, offset, width, "ascii");
}

export function canonicalTarHeader(path, size, mode) {
  assert(isSafeRelativePath(path), `unsafe USTAR path: ${path}`);
  assert(/^[\x20-\x7e]+$/.test(path), `USTAR path is not portable ASCII: ${path}`);
  assert(Number.isSafeInteger(size) && size >= 0 && size <= RUNTIME_ENTRY_MAX_BYTES, `USTAR entry size is invalid: ${path}`);
  assert(mode === 0o644 || mode === 0o755, `USTAR mode is invalid: ${path}`);
  const { name, prefix } = splitUstarPath(path);
  const header = Buffer.alloc(512);
  Buffer.from(name, "utf8").copy(header, 0);
  writeOctal(header, 100, 8, mode);
  writeOctal(header, 108, 8, 0);
  writeOctal(header, 116, 8, 0);
  writeOctal(header, 124, 12, size);
  writeOctal(header, 136, 12, 0);
  header.fill(0x20, 148, 156);
  header[156] = 0x30;
  Buffer.from("ustar\0", "ascii").copy(header, 257);
  Buffer.from("00", "ascii").copy(header, 263);
  Buffer.from(prefix, "utf8").copy(header, 345);
  const checksum = header.reduce((sum, byte) => sum + byte, 0);
  const encodedChecksum = checksum.toString(8).padStart(6, "0");
  assert(encodedChecksum.length === 6, "USTAR checksum exceeds its width");
  header.write(`${encodedChecksum}\0 `, 148, 8, "ascii");
  return header;
}

export function createCanonicalTar(entries, root = RUNTIME_ROOT) {
  assert(entries instanceof Map && entries.size > 0, "runtime archive entries must be a nonempty Map");
  assert(entries.size <= RUNTIME_ENTRY_MAX_COUNT, "runtime archive has too many entries");
  assert(isSafeRelativePath(root), "runtime archive root is invalid");
  const paths = [...entries.keys()].sort(compareUtf8);
  const chunks = [];
  let expandedBytes = 1024;
  for (const path of paths) {
    assert(isSafeRelativePath(path), `unsafe runtime archive path: ${path}`);
    const bytes = entries.get(path);
    assert(Buffer.isBuffer(bytes), `runtime archive entry is not bytes: ${path}`);
    assert(bytes.length <= RUNTIME_ENTRY_MAX_BYTES, `runtime archive entry exceeds its limit: ${path}`);
    const archivePath = `${root}/${path}`;
    chunks.push(canonicalTarHeader(archivePath, bytes.length, runtimeMode(path)), bytes);
    const padding = (512 - (bytes.length % 512)) % 512;
    if (padding > 0) chunks.push(Buffer.alloc(padding));
    expandedBytes += 512 + bytes.length + padding;
    assert(expandedBytes <= RUNTIME_EXPANDED_MAX_BYTES, "runtime archive expansion exceeds its limit");
  }
  chunks.push(Buffer.alloc(1024));
  return Buffer.concat(chunks, expandedBytes);
}

export function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}

export function canonicalGzip(bytes) {
  assert(Buffer.isBuffer(bytes), "canonical gzip input must be bytes");
  const blocks = [];
  for (let offset = 0; offset < bytes.length || blocks.length === 0;) {
    const length = Math.min(0xffff, bytes.length - offset);
    const final = offset + length === bytes.length;
    const header = Buffer.alloc(5);
    header[0] = final ? 0x01 : 0x00;
    header.writeUInt16LE(length, 1);
    header.writeUInt16LE(length ^ 0xffff, 3);
    blocks.push(header, bytes.subarray(offset, offset + length));
    offset += length;
  }
  const trailer = Buffer.alloc(8);
  trailer.writeUInt32LE(crc32(bytes), 0);
  trailer.writeUInt32LE(bytes.length >>> 0, 4);
  return Buffer.concat([
    Buffer.from([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff]),
    ...blocks,
    trailer,
  ]);
}

async function atomicWrite(path, bytes, mode) {
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.tmp-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  let handle;
  try {
    handle = await open(temporary, fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY, mode);
    await handle.writeFile(bytes);
    await handle.sync();
    await handle.close();
    handle = undefined;
    await rename(temporary, path);
  } finally {
    if (handle) await handle.close();
    await rm(temporary, { force: true });
  }
}

export async function buildRuntimeArchive({
  root = repositoryRoot,
  outputPath = join(root, "dist", RUNTIME_ARCHIVE_NAME),
  checksumPath = `${outputPath}.sha256`,
} = {}) {
  const archiveBasename = basename(outputPath);
  assert(/^[A-Za-z0-9._-]+$/.test(archiveBasename), "runtime archive basename cannot be represented by the checksum sidecar grammar");
  const sourcePaths = await runtimeSourcePaths(root);
  await assertRepositoryOutputNamespaces(root, [
    { label: "runtime archive", path: outputPath },
    { label: "runtime checksum", path: checksumPath },
  ], "runtime build");
  await assertPhysicalPathCustody(
    [
      { label: "runtime archive", path: outputPath },
      { label: "runtime checksum", path: checksumPath },
    ],
    [
      ...sourcePaths.map((path) => ({ label: path, path: join(root, ...path.split("/")) })),
    ],
    "runtime build custody",
  );
  const sourceEntries = await snapshotRuntimeSources(root);
  const entries = new Map(sourceEntries);
  entries.set("package.json", runtimePackageJson(entries.get("package.json")));
  const retainedSnapshots = new Map(sourceEntries);
  const resolvedCommit = bindRetainedSnapshotsToGitHead(root, retainedSnapshots);
  const lock = await readBoundaryLock(root, sourceEntries);
  await assertBoundaryProcessKernelMatchesLock(entries.get("boundary-process-kernel-v1.wasm"), lock);
  const manifest = createRuntimeManifest({ lock, commit: resolvedCommit, entries });
  entries.set("runtime-manifest.json", Buffer.from(stableJson(manifest), "utf8"));
  entries.set("checksums.sha256", checksumsBytes(entries));
  const expectedPaths = [...await runtimeSourcePaths(root), ...GENERATED_PATHS].sort(compareUtf8);
  assert.deepEqual([...entries.keys()].sort(compareUtf8), expectedPaths, "runtime archive inventory is not exact");
  const archive = canonicalGzip(createCanonicalTar(entries));
  assert(archive.length <= RUNTIME_ARCHIVE_MAX_BYTES, "runtime archive exceeds its compressed size limit");
  const digest = sha256(archive);
  await atomicWrite(outputPath, archive, 0o644);
  await atomicWrite(checksumPath, Buffer.from(`${digest}  ${archiveBasename}\n`, "utf8"), 0o644);
  return Object.freeze({
    format: RUNTIME_FORMAT,
    archivePath: outputPath,
    checksumPath,
    archiveName: RUNTIME_ARCHIVE_NAME,
    archiveSha256: digest,
    archiveByteLength: archive.length,
    archiveEntryCount: entries.size,
    runtimeInventory: [...entries.keys()].sort(compareUtf8),
    productionSourceSha256: manifest.productionSourceSha256,
    sourceCommit: manifest.sourceCommit,
  });
}

function parseArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--out") options.outputPath = resolve(argv[++index] ?? "");
    else if (argument === "--checksum") options.checksumPath = resolve(argv[++index] ?? "");
    else throw new Error(`unknown build-runtime argument: ${argument}`);
  }
  if (options.outputPath && !options.checksumPath) options.checksumPath = `${options.outputPath}.sha256`;
  return options;
}

function isMain() {
  return process.argv[1] !== undefined && pathToFileURL(resolve(process.argv[1])).href === import.meta.url;
}

if (isMain()) {
  const result = await buildRuntimeArchive(parseArguments(process.argv.slice(2)));
  console.log(`world_runtime_archive=${result.archivePath}`);
  console.log(`world_runtime_archive_sha256=${result.archiveSha256}`);
  console.log(`world_runtime_archive_bytes=${result.archiveByteLength}`);
  console.log(`world_runtime_archive_entries=${result.archiveEntryCount}`);
  console.log(`world_runtime_production_source_sha256=${result.productionSourceSha256}`);
  console.log("world_runtime_archive_build=pass");
}
