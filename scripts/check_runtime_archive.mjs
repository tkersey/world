import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { constants as fsConstants } from "node:fs";
import {
  chmod,
  lstat,
  mkdir,
  mkdtemp,
  open,
  readdir,
  rm,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import {
  RUNTIME_ARCHIVE_MAX_BYTES,
  RUNTIME_ARCHIVE_NAME,
  RUNTIME_ENTRY_MAX_BYTES,
  RUNTIME_ENTRY_MAX_COUNT,
  RUNTIME_EXPANDED_MAX_BYTES,
  RUNTIME_FORMAT,
  RUNTIME_ROOT,
  WORLD_VERSION,
  assertTrackedRepositoryMatchesCommit,
  canonicalGzip,
  canonicalTarHeader,
  checksumsBytes,
  crc32,
  defaultArchivePath,
  defaultChecksumPath,
  isSafeRelativePath,
  productionSourceSha256,
  readBoundedRegularFileSnapshot,
  readBoundaryLock,
  repositoryRoot,
  runtimeMode,
  runtimeSourcePaths,
  sha256,
} from "./build_runtime_archive.mjs";

const MAXIMUM_SIDECAR_BYTES = 256;
const admittedArchiveEntrySnapshots = new WeakMap();
const EXPECTED_API_EXPORTS = Object.freeze([
  "WorldProcessHostError",
  "admitProcessKernel",
  "decodeEffectRequest",
  "decodeEffectResult",
  "decodeProcessOutcome",
  "encodeEffectResult",
]);

function compareUtf8(left, right) {
  return Buffer.from(left, "utf8").compare(Buffer.from(right, "utf8"));
}

async function readBoundedRegularFile(path, maximumBytes, label) {
  return (await readBoundedRegularFileSnapshot(path, maximumBytes, label)).bytes;
}

function runCommittedRuntimeBuilder(root, outputPath, checksumPath) {
  const result = spawnSync(process.execPath, [
    join(root, "scripts", "build_runtime_archive.mjs"),
    "--out",
    outputPath,
    "--checksum",
    checksumPath,
  ], {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 8 * 1024 * 1024,
    env: {
      PATH: process.env.PATH ?? "",
      LANG: "C",
      LC_ALL: "C",
    },
  });
  assert.equal(
    result.status,
    0,
    `committed runtime builder failed:\n${result.stdout ?? ""}\n${result.stderr ?? ""}`,
  );
  assert.match(result.stdout, /^world_runtime_archive_build=pass$/m, "committed runtime builder did not report success");
}

export function parseChecksumSidecar(bytes, expectedName = RUNTIME_ARCHIVE_NAME) {
  const text = Buffer.isBuffer(bytes) ? bytes.toString("utf8") : String(bytes);
  const match = /^([0-9a-f]{64})  ([A-Za-z0-9._-]+)\n$/.exec(text);
  assert(match, "runtime archive checksum sidecar is malformed");
  assert.equal(match[2], expectedName, "runtime archive checksum sidecar names another asset");
  return match[1];
}

export function parseCanonicalGzip(archive) {
  assert(Buffer.isBuffer(archive), "runtime archive must be bytes");
  assert(archive.length <= RUNTIME_ARCHIVE_MAX_BYTES, "runtime archive exceeds its compressed size limit");
  assert(archive.length >= 23, "runtime archive is truncated");
  assert.deepEqual(
    archive.subarray(0, 10),
    Buffer.from([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff]),
    "runtime archive gzip header is not canonical",
  );
  const chunks = [];
  let expandedBytes = 0;
  let offset = 10;
  let terminated = false;
  while (!terminated) {
    assert(offset + 5 <= archive.length - 8, "runtime archive DEFLATE block is truncated");
    const blockHeader = archive[offset];
    offset += 1;
    assert((blockHeader & 0xfe) === 0, "runtime archive DEFLATE block is not canonical stored data");
    terminated = (blockHeader & 1) === 1;
    const length = archive.readUInt16LE(offset);
    const complement = archive.readUInt16LE(offset + 2);
    offset += 4;
    assert.equal((length ^ complement) & 0xffff, 0xffff, "runtime archive DEFLATE stored length is invalid");
    assert(offset + length <= archive.length - 8, "runtime archive DEFLATE payload is truncated");
    expandedBytes += length;
    assert(expandedBytes <= RUNTIME_EXPANDED_MAX_BYTES, "runtime archive expansion exceeds its limit");
    chunks.push(archive.subarray(offset, offset + length));
    offset += length;
  }
  assert.equal(offset + 8, archive.length, "runtime archive must contain exactly one canonical gzip member");
  const tar = Buffer.concat(chunks, expandedBytes);
  assert.equal(archive.readUInt32LE(offset), crc32(tar), "runtime archive gzip CRC32 differs");
  assert.equal(archive.readUInt32LE(offset + 4), tar.length >>> 0, "runtime archive gzip ISIZE differs");
  assert(archive.equals(canonicalGzip(tar)), "runtime archive gzip encoding is not byte-canonical");
  return tar;
}

function textField(field) {
  const zero = field.indexOf(0);
  const end = zero === -1 ? field.length : zero;
  assert(field.subarray(end).every((byte) => byte === 0), "USTAR text field has nonzero padding");
  const text = field.subarray(0, end).toString("utf8");
  assert(Buffer.from(text, "utf8").equals(field.subarray(0, end)), "USTAR text field is not valid UTF-8");
  return text;
}

function octalField(field, label) {
  assert((field[0] & 0x80) === 0, `${label} uses forbidden base-256 encoding`);
  const text = field.toString("ascii");
  assert(/^[0-7]+\0$/.test(text), `${label} is not canonical octal`);
  const value = Number.parseInt(text.slice(0, -1), 8);
  assert(Number.isSafeInteger(value) && value >= 0, `${label} is outside the safe range`);
  return value;
}

function checksumField(field) {
  const text = field.toString("ascii");
  assert(/^[0-7]{6}\0 $/.test(text), "USTAR checksum field is not canonical");
  return Number.parseInt(text.slice(0, 6), 8);
}

function forbiddenRuntimePath(path) {
  return /(^|\/)(?:\.git|node_modules|conformance|test|tests|fixtures?|examples?|templates?|sdk|build_support|runtime-stores?|credentials?|secrets?)(?:\/|$)/i.test(path)
    || /(^|\/)\.env(?:\.|$)/i.test(path)
    || /\.(?:bpi1|pst1|ers1|pko1)$/i.test(path);
}

export function parseCanonicalTar(tar, { root = RUNTIME_ROOT } = {}) {
  assert(Buffer.isBuffer(tar), "runtime USTAR payload must be bytes");
  assert(tar.length >= 1024 && tar.length % 512 === 0, "runtime USTAR payload is not block aligned");
  assert(tar.length <= RUNTIME_EXPANDED_MAX_BYTES, "runtime USTAR payload exceeds its expansion limit");
  const entries = [];
  const seen = new Set();
  const portableSeen = new Set();
  let priorPath = null;
  let payloadBytes = 0;
  let offset = 0;
  while (offset + 512 <= tar.length) {
    const header = tar.subarray(offset, offset + 512);
    offset += 512;
    if (header.every((byte) => byte === 0)) {
      assert(offset + 512 === tar.length, "runtime USTAR must end with exactly two zero blocks");
      assert(tar.subarray(offset, offset + 512).every((byte) => byte === 0), "runtime USTAR terminator is incomplete");
      offset += 512;
      break;
    }
    assert(entries.length < RUNTIME_ENTRY_MAX_COUNT, "runtime USTAR has too many entries");
    const storedChecksum = checksumField(header.subarray(148, 156));
    const checksumHeader = Buffer.from(header);
    checksumHeader.fill(0x20, 148, 156);
    assert.equal(checksumHeader.reduce((sum, byte) => sum + byte, 0), storedChecksum, "runtime USTAR header checksum differs");
    const name = textField(header.subarray(0, 100));
    const prefix = textField(header.subarray(345, 500));
    const archivePath = prefix === "" ? name : `${prefix}/${name}`;
    assert(archivePath.startsWith(`${root}/`), "runtime USTAR has an unexpected root");
    const path = archivePath.slice(root.length + 1);
    assert(isSafeRelativePath(path), `runtime USTAR path is unsafe: ${path}`);
    assert(!forbiddenRuntimePath(path), `runtime USTAR contains forbidden application or source data: ${path}`);
    assert(!seen.has(path), `runtime USTAR contains a duplicate entry: ${path}`);
    seen.add(path);
    const portable = path.normalize("NFC").toLowerCase();
    assert(!portableSeen.has(portable), `runtime USTAR has a portable path collision: ${path}`);
    portableSeen.add(portable);
    if (priorPath !== null) assert(compareUtf8(priorPath, path) < 0, "runtime USTAR entries are not in canonical UTF-8 order");
    priorPath = path;
    assert.equal(header[156], 0x30, `runtime USTAR entry is not a regular file: ${path}`);
    const mode = octalField(header.subarray(100, 108), "USTAR mode");
    assert.equal(mode, runtimeMode(path), `runtime USTAR mode differs: ${path}`);
    const size = octalField(header.subarray(124, 136), "USTAR size");
    assert(size <= RUNTIME_ENTRY_MAX_BYTES, `runtime USTAR entry exceeds its size limit: ${path}`);
    assert(header.equals(canonicalTarHeader(archivePath, size, mode)), `runtime USTAR header is not canonical: ${path}`);
    const padding = (512 - (size % 512)) % 512;
    assert(offset + size + padding <= tar.length - 1024, `runtime USTAR entry is truncated: ${path}`);
    const bytes = Buffer.from(tar.subarray(offset, offset + size));
    offset += size;
    assert(tar.subarray(offset, offset + padding).every((byte) => byte === 0), `runtime USTAR padding is nonzero: ${path}`);
    offset += padding;
    payloadBytes += size;
    assert(payloadBytes <= RUNTIME_EXPANDED_MAX_BYTES, "runtime USTAR payload exceeds its expansion limit");
    entries.push(Object.freeze({ path, bytes, mode }));
  }
  assert.equal(offset, tar.length, "runtime USTAR has no exact terminator");
  assert(entries.length > 0, "runtime USTAR is empty");
  return Object.freeze(entries);
}

function parseChecksums(bytes) {
  const text = bytes.toString("utf8");
  assert(text.endsWith("\n") && text.length > 1, "runtime checksums file is malformed");
  const checksums = new Map();
  for (const line of text.slice(0, -1).split("\n")) {
    const match = /^([0-9a-f]{64})  ([A-Za-z0-9_./-]+)$/.exec(line);
    assert(match, `runtime checksum row is malformed: ${line}`);
    assert(isSafeRelativePath(match[2]), `runtime checksum path is unsafe: ${match[2]}`);
    assert(!checksums.has(match[2]), `runtime checksum path is duplicated: ${match[2]}`);
    checksums.set(match[2], match[1]);
  }
  return checksums;
}

function exactObject(value, expected, label) {
  assert(value !== null && typeof value === "object" && !Array.isArray(value), `${label} must be an object`);
  assert.deepEqual(Object.keys(value).sort(), Object.keys(expected).sort(), `${label} fields are not exact`);
  for (const [key, expectedValue] of Object.entries(expected)) assert.deepEqual(value[key], expectedValue, `${label}.${key} differs`);
}

function validatePackage(bytes) {
  const value = JSON.parse(bytes.toString("utf8"));
  exactObject(value, {
    name: "@tkersey/world",
    version: WORLD_VERSION,
    type: "module",
    private: false,
    license: "MIT",
    exports: { "./process-v1": "./src/process_v1/index.mjs" },
    bin: { world: "./bin/world.mjs" },
    engines: { bun: ">=1.4.0" },
  }, "runtime package");
  return value;
}

function allowedInventory(paths) {
  const fixed = new Set([
    "LICENSE",
    "README.md",
    "bin/world.mjs",
    "boundary-process-kernel-v1.wasm",
    "checksums.sha256",
    "package.json",
    "runtime-manifest.json",
    "verify-runtime.mjs",
  ]);
  let moduleCount = 0;
  for (const path of paths) {
    if (fixed.has(path)) continue;
    assert(/^src\/process_v1\/[a-z0-9_]+\.mjs$/.test(path), `runtime archive has an unexpected entry: ${path}`);
    moduleCount += 1;
  }
  for (const path of fixed) assert(paths.includes(path), `runtime archive is missing: ${path}`);
  assert(moduleCount > 0 && paths.includes("src/process_v1/index.mjs"), "runtime archive has no public Process v1 module");
}

export async function admitRuntimeArchiveBytes(archive, {
  expectedDigest,
  expectedInventory = null,
  lock,
} = {}) {
  assert(Buffer.isBuffer(archive), "runtime archive must be bytes");
  const actualDigest = sha256(archive);
  if (expectedDigest !== undefined) assert.equal(actualDigest, expectedDigest, "runtime archive SHA-256 differs from its sidecar");
  const tar = parseCanonicalGzip(archive);
  const parsed = parseCanonicalTar(tar);
  const paths = parsed.map(({ path }) => path);
  allowedInventory(paths);
  if (expectedInventory !== null) assert.deepEqual(paths, [...expectedInventory].sort(compareUtf8), "runtime archive inventory differs from the source tree");
  const entries = new Map(parsed.map(({ path, bytes }) => [path, bytes]));
  const checksums = parseChecksums(entries.get("checksums.sha256"));
  const covered = paths.filter((path) => path !== "checksums.sha256").sort(compareUtf8);
  assert.deepEqual([...checksums.keys()].sort(compareUtf8), covered, "runtime checksum coverage is not exact");
  for (const path of covered) assert.equal(sha256(entries.get(path)), checksums.get(path), `runtime checksum differs: ${path}`);
  assert(entries.get("checksums.sha256").equals(checksumsBytes(entries)), "runtime checksums file is not canonical");
  const boundaryLock = lock ?? await readBoundaryLock(repositoryRoot);
  const manifest = JSON.parse(entries.get("runtime-manifest.json").toString("utf8"));
  exactObject(manifest, {
    format: RUNTIME_FORMAT,
    worldVersion: WORLD_VERSION,
    processKernelAbiVersion: boundaryLock.processKernelAbiVersion,
    boundaryVersion: boundaryLock.boundaryVersion,
    boundaryCommit: boundaryLock.boundaryCommit,
    kernelSha256: boundaryLock.kernelSha256,
    kernelByteLength: boundaryLock.kernelByteLength,
    kernelImportCount: boundaryLock.kernelImportCount,
    sourceCommit: manifest.sourceCommit,
    productionSourceSha256: manifest.productionSourceSha256,
  }, "runtime manifest");
  assert(/^[0-9a-f]{40}$/.test(manifest.sourceCommit), "runtime manifest sourceCommit is invalid");
  assert(/^[0-9a-f]{64}$/.test(manifest.productionSourceSha256), "runtime manifest productionSourceSha256 is invalid");
  assert.equal(productionSourceSha256(entries), manifest.productionSourceSha256, "runtime production source digest differs");
  const kernel = entries.get("boundary-process-kernel-v1.wasm");
  assert.equal(kernel.length, boundaryLock.kernelByteLength, "runtime kernel byte length differs");
  assert.equal(sha256(kernel), boundaryLock.kernelSha256, "runtime kernel digest differs");
  assert.equal(WebAssembly.validate(kernel), true, "runtime kernel is not valid WebAssembly");
  const module = await WebAssembly.compile(kernel);
  assert.equal(WebAssembly.Module.imports(module).length, boundaryLock.kernelImportCount, "runtime kernel import count differs");
  validatePackage(entries.get("package.json"));
  const admitted = Object.freeze({
    archiveSha256: actualDigest,
    archiveByteLength: archive.length,
    archiveEntryCount: entries.size,
    expandedByteLength: tar.length,
    entries,
    parsed,
    manifest: Object.freeze(manifest),
    runtimeInventory: Object.freeze(paths),
  });
  admittedArchiveEntrySnapshots.set(admitted, Object.freeze(parsed.map(({ path, bytes, mode }) => Object.freeze({
    path,
    bytes: Buffer.from(bytes),
    mode,
  }))));
  return admitted;
}

async function requireFreshDirectory(path) {
  try {
    await mkdir(path, { mode: 0o700 });
  } catch (error) {
    if (error?.code !== "EEXIST") throw error;
    const info = await lstat(path);
    assert(info.isDirectory() && !info.isSymbolicLink(), "runtime extraction target is not a directory");
    assert.deepEqual(await readdir(path), [], "runtime extraction target must be empty");
    await chmod(path, 0o700);
  }
  assert.deepEqual(await readdir(path), [], "runtime extraction target must be empty");
}

export async function extractAdmittedRuntime(admitted, destination) {
  const entries = admittedArchiveEntrySnapshots.get(admitted);
  assert(entries !== undefined, "runtime extraction requires an admitted archive");
  await requireFreshDirectory(destination);
  for (const entry of entries) {
    assert(isSafeRelativePath(entry.path), `unsafe admitted runtime path: ${entry.path}`);
    const target = join(destination, ...entry.path.split("/"));
    await mkdir(dirname(target), { recursive: true, mode: 0o700 });
    const handle = await open(target, fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY, entry.mode);
    try {
      await handle.writeFile(entry.bytes);
      await handle.sync();
    } finally {
      await handle.close();
    }
    await chmod(target, entry.mode);
  }
  return destination;
}

function runInnerVerifier(extractedRoot, sanitizedPath) {
  const result = spawnSync(process.execPath, ["./verify-runtime.mjs"], {
    cwd: extractedRoot,
    encoding: "utf8",
    maxBuffer: 8 * 1024 * 1024,
    env: {
      PATH: sanitizedPath,
      LANG: "C",
      LC_ALL: "C",
      WORLD_CLEAN_ROOM: "1",
    },
  });
  assert.equal(result.status, 0, `embedded runtime verifier failed:\n${result.stdout ?? ""}\n${result.stderr ?? ""}`);
  assert.match(result.stdout, /^world_runtime_verify=pass$/m, "embedded runtime verifier did not report success");
  return Object.freeze({ stdout: result.stdout, stderr: result.stderr ?? "" });
}

export async function checkRuntimeArchive({
  root = repositoryRoot,
  archivePath = join(root, "dist", RUNTIME_ARCHIVE_NAME),
  checksumPath = `${archivePath}.sha256`,
  extractTo = null,
  keepExtractedRoot = false,
  verifyRebuild = true,
  runInner = true,
} = {}) {
  const archive = await readBoundedRegularFile(archivePath, RUNTIME_ARCHIVE_MAX_BYTES, "runtime archive");
  const sidecar = await readBoundedRegularFile(checksumPath, MAXIMUM_SIDECAR_BYTES, "runtime archive checksum sidecar");
  const expectedDigest = parseChecksumSidecar(sidecar, basename(archivePath));
  const expectedInventory = [...await runtimeSourcePaths(root), "checksums.sha256", "runtime-manifest.json"].sort(compareUtf8);
  const lock = await readBoundaryLock(root);
  const admitted = await admitRuntimeArchiveBytes(archive, { expectedDigest, expectedInventory, lock });

  let reproducible = false;
  if (verifyRebuild) {
    await assertTrackedRepositoryMatchesCommit(root, admitted.manifest.sourceCommit);
    const temporary = await mkdtemp(join(tmpdir(), "world-runtime-rebuild-"));
    try {
      const firstPath = join(temporary, "first", RUNTIME_ARCHIVE_NAME);
      const secondPath = join(temporary, "second", RUNTIME_ARCHIVE_NAME);
      runCommittedRuntimeBuilder(root, firstPath, `${firstPath}.sha256`);
      runCommittedRuntimeBuilder(root, secondPath, `${secondPath}.sha256`);
      const first = await readBoundedRegularFile(firstPath, RUNTIME_ARCHIVE_MAX_BYTES, "first rebuilt runtime archive");
      const second = await readBoundedRegularFile(secondPath, RUNTIME_ARCHIVE_MAX_BYTES, "second rebuilt runtime archive");
      const [firstAdmission, secondAdmission] = await Promise.all([
        admitRuntimeArchiveBytes(first, { expectedInventory, lock }),
        admitRuntimeArchiveBytes(second, { expectedInventory, lock }),
      ]);
      assert.equal(firstAdmission.manifest.sourceCommit, secondAdmission.manifest.sourceCommit, "two exact runtime rebuilds bind different source commits");
      assert.equal(admitted.manifest.sourceCommit, firstAdmission.manifest.sourceCommit, "runtime manifest sourceCommit differs from exact source rebuild");
      assert(first.equals(second), "two runtime archive rebuilds are not byte-identical");
      assert(first.equals(archive), "runtime archive differs from an exact source rebuild");
      await assertTrackedRepositoryMatchesCommit(root, admitted.manifest.sourceCommit);
      reproducible = true;
    } finally {
      await rm(temporary, { recursive: true, force: true });
    }
  }

  let temporaryRoot = null;
  let extractedRoot = extractTo;
  let inner = null;
  if (runInner || extractTo !== null) {
    if (extractedRoot === null) {
      temporaryRoot = await mkdtemp(join(tmpdir(), "world-runtime-admitted-"));
      extractedRoot = join(temporaryRoot, RUNTIME_ROOT);
    }
    await extractAdmittedRuntime(admitted, extractedRoot);
    if (runInner) {
      const pathRoot = await mkdtemp(join(tmpdir(), "world-runtime-empty-path-"));
      try {
        inner = runInnerVerifier(extractedRoot, pathRoot);
      } finally {
        await rm(pathRoot, { recursive: true, force: true });
      }
    }
  }

  const result = Object.freeze({
    format: RUNTIME_FORMAT,
    archivePath,
    checksumPath,
    archiveSha256: admitted.archiveSha256,
    archiveByteLength: admitted.archiveByteLength,
    archiveEntryCount: admitted.archiveEntryCount,
    expandedByteLength: admitted.expandedByteLength,
    runtimeInventory: admitted.runtimeInventory,
    manifest: admitted.manifest,
    reproducible,
    innerVerified: inner !== null,
    innerStdout: inner?.stdout ?? "",
    extractedRoot: keepExtractedRoot || extractTo !== null ? extractedRoot : null,
  });
  if (temporaryRoot !== null && !keepExtractedRoot) await rm(temporaryRoot, { recursive: true, force: true });
  return result;
}

function parseArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--archive") options.archivePath = resolve(argv[++index] ?? "");
    else if (argument === "--checksum") options.checksumPath = resolve(argv[++index] ?? "");
    else if (argument === "--extract-to") {
      options.extractTo = resolve(argv[++index] ?? "");
      options.keepExtractedRoot = true;
    } else throw new Error(`unknown check-runtime argument: ${argument}`);
  }
  if (options.archivePath && !options.checksumPath) options.checksumPath = `${options.archivePath}.sha256`;
  return options;
}

function isMain() {
  return process.argv[1] !== undefined && pathToFileURL(resolve(process.argv[1])).href === import.meta.url;
}

if (isMain()) {
  const result = await checkRuntimeArchive(parseArguments(process.argv.slice(2)));
  console.log(`world_runtime_archive_sha256=${result.archiveSha256}`);
  console.log(`world_runtime_archive_bytes=${result.archiveByteLength}`);
  console.log(`world_runtime_archive_entries=${result.archiveEntryCount}`);
  console.log(`world_runtime_inventory=${JSON.stringify(result.runtimeInventory)}`);
  console.log(`world_runtime_reproducible=${result.reproducible}`);
  console.log(`world_runtime_inner_verified=${result.innerVerified}`);
  if (result.extractedRoot !== null) console.log(`world_runtime_extracted_root=${result.extractedRoot}`);
  console.log("world_runtime_archive_check=pass");
}

export const runtimeArchiveContract = Object.freeze({
  apiExports: EXPECTED_API_EXPORTS,
  archiveName: RUNTIME_ARCHIVE_NAME,
  defaultArchivePath,
  defaultChecksumPath,
});
