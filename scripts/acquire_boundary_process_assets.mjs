import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { constants as fsConstants } from "node:fs";
import { lstat, mkdir, open, readFile, rename, rm } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const MAXIMUM_DOWNLOAD_BYTES = 64 * 1024 * 1024;

export const EXPECTED_BOUNDARY_LOCK = Object.freeze({
  format: "world-boundary-process-lock/v1",
  boundaryVersion: "1.7.0",
  boundaryCommit: "4fd4cd959ea283a6b5af12a228f0d80a102683e3",
  sourceArchiveUrl: "https://github.com/tkersey/boundary/archive/refs/tags/v1.7.0.tar.gz",
  sourceArchiveSha256: "a787f9838458d43e93aa7b955a36f69eb377b18036a05e3461ae3e7084f2e7d7",
  kernelReleaseUrl: "https://github.com/tkersey/boundary/releases/download/v1.7.0/boundary-process-kernel-v1.wasm",
  kernelSha256: "178f9c2fb79402a85ab5a7905586879347ad5c99f988127eec001c9ecfd813f0",
  kernelByteLength: 647473,
  processKernelAbiVersion: 1,
  kernelImportCount: 0,
  kernelExportCount: 13,
  memoryInitialPages: 2457,
  memoryMaximumPages: 4096,
});

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function exactLock(value) {
  assert(value !== null && typeof value === "object" && !Array.isArray(value), "Boundary lock must be an object");
  assert.deepEqual(Object.keys(value).sort(), Object.keys(EXPECTED_BOUNDARY_LOCK).sort(), "Boundary lock fields are not exact");
  for (const [key, expected] of Object.entries(EXPECTED_BOUNDARY_LOCK)) assert.deepEqual(value[key], expected, `Boundary lock ${key} differs`);
  return Object.freeze(value);
}

export async function readExactBoundaryLock(path = join(repositoryRoot, "conformance", "boundary.lock.json")) {
  const info = await lstat(path);
  assert(info.isFile() && !info.isSymbolicLink(), "Boundary lock is not a regular file");
  return exactLock(JSON.parse(await readFile(path, "utf8")));
}

async function readRegular(path, maximum, label) {
  assert(isAbsolute(path), `${label} path must be absolute`);
  const pathInfo = await lstat(path, { bigint: true });
  assert(pathInfo.isFile() && !pathInfo.isSymbolicLink(), `${label} is not a regular file`);
  assert(pathInfo.size <= BigInt(maximum), `${label} exceeds its size limit`);
  const handle = await open(path, fsConstants.O_RDONLY | fsConstants.O_NONBLOCK);
  try {
    const before = await handle.stat({ bigint: true });
    assert(before.isFile(), `${label} descriptor is not a regular file`);
    const bytes = await handle.readFile();
    assert.equal(BigInt(bytes.length), before.size, `${label} changed during read`);
    const after = await handle.stat({ bigint: true });
    for (const field of ["dev", "ino", "size", "mtimeNs", "ctimeNs"]) assert.equal(after[field], before[field], `${label} changed during read`);
    return Buffer.from(bytes);
  } finally {
    await handle.close();
  }
}

async function fetchBounded(url, maximum, label) {
  const response = await fetch(url, { redirect: "follow", headers: { accept: "application/octet-stream" } });
  assert(response.ok, `${label} download failed with HTTP ${response.status}`);
  const declared = response.headers.get("content-length");
  if (declared !== null) {
    assert(/^\d+$/.test(declared), `${label} Content-Length is invalid`);
    assert(BigInt(declared) <= BigInt(maximum), `${label} download exceeds its size limit`);
  }
  assert(response.body !== null, `${label} response has no body`);
  const chunks = [];
  let total = 0;
  for await (const chunk of response.body) {
    total += chunk.byteLength;
    assert(total <= maximum, `${label} download exceeds its size limit`);
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks, total);
}

function admitKernel(bytes, lock) {
  assert.equal(bytes.length, lock.kernelByteLength, "Boundary Process kernel byte length differs from the lock");
  assert.equal(sha256(bytes), lock.kernelSha256, "Boundary Process kernel digest differs from the lock");
  assert.equal(WebAssembly.validate(bytes), true, "Boundary Process kernel is not valid WebAssembly");
  return bytes;
}

async function atomicWrite(path, bytes) {
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.tmp-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  let handle;
  try {
    handle = await open(temporary, fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY, 0o644);
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

function exactBoundarySource(sourceRoot, lock) {
  assert(isAbsolute(sourceRoot), "WORLD_BOUNDARY_SOURCE must be an absolute path");
  const commit = execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: sourceRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
  assert.equal(commit, lock.boundaryCommit, "local Boundary source is not the exact landed v1.7.0 commit");
}

function resolveLocalKernel(sourceRoot, explicitKernel) {
  if (explicitKernel !== null) {
    assert(isAbsolute(explicitKernel), "WORLD_BOUNDARY_PROCESS_KERNEL must be an absolute path");
    if (sourceRoot !== null) {
      const inside = relative(sourceRoot, explicitKernel);
      assert(inside !== "" && !inside.startsWith("..") && !isAbsolute(inside), "local Boundary kernel must be located inside WORLD_BOUNDARY_SOURCE");
    }
    return explicitKernel;
  }
  assert(sourceRoot !== null, "local acquisition requires WORLD_BOUNDARY_PROCESS_KERNEL or WORLD_BOUNDARY_SOURCE");
  return join(sourceRoot, "zig-out", "boundary-process-kernel-v1.wasm");
}

export function classifyLocalBoundaryAssetProvenance(sourceRoot) {
  return sourceRoot === null ? "local-kernel-override" : "local-checkout-asset";
}

export async function acquireBoundaryProcessAssets({
  root = repositoryRoot,
  lockPath = join(root, "conformance", "boundary.lock.json"),
  outputPath = join(root, "boundary-process-kernel-v1.wasm"),
  mode = "local",
  kernelPath = process.env.WORLD_BOUNDARY_PROCESS_KERNEL ?? null,
  sourceRoot = process.env.WORLD_BOUNDARY_SOURCE ?? null,
  checkOnly = false,
} = {}) {
  assert(mode === "local" || mode === "release", "Boundary acquisition mode must be local or release");
  assert(isAbsolute(outputPath), "Boundary kernel output path must be absolute");
  const lock = await readExactBoundaryLock(lockPath);
  let bytes;
  let provenance;
  if (mode === "release") {
    assert(kernelPath === null && sourceRoot === null, "release acquisition forbids local Boundary overrides");
    const [kernel, sourceArchive] = await Promise.all([
      fetchBounded(lock.kernelReleaseUrl, MAXIMUM_DOWNLOAD_BYTES, "Boundary Process kernel"),
      fetchBounded(lock.sourceArchiveUrl, MAXIMUM_DOWNLOAD_BYTES, "Boundary source archive"),
    ]);
    assert.equal(sha256(sourceArchive), lock.sourceArchiveSha256, "Boundary source archive digest differs from the lock");
    bytes = admitKernel(kernel, lock);
    provenance = "public-release";
  } else if (kernelPath !== null || sourceRoot !== null) {
    if (sourceRoot !== null) exactBoundarySource(resolve(sourceRoot), lock);
    const resolvedKernel = resolveLocalKernel(sourceRoot === null ? null : resolve(sourceRoot), kernelPath === null ? null : resolve(kernelPath));
    bytes = admitKernel(await readRegular(resolvedKernel, MAXIMUM_DOWNLOAD_BYTES, "local Boundary Process kernel"), lock);
    provenance = classifyLocalBoundaryAssetProvenance(sourceRoot);
  } else {
    bytes = admitKernel(await readRegular(outputPath, MAXIMUM_DOWNLOAD_BYTES, "bundled Boundary Process kernel"), lock);
    provenance = "bundled-check";
  }
  if (!checkOnly) await atomicWrite(outputPath, bytes);
  return Object.freeze({
    format: "world-boundary-process-acquisition/v1",
    provenance,
    boundaryVersion: lock.boundaryVersion,
    boundaryCommit: lock.boundaryCommit,
    kernelSha256: lock.kernelSha256,
    kernelByteLength: lock.kernelByteLength,
    processKernelAbiVersion: lock.processKernelAbiVersion,
    outputPath,
    wrote: !checkOnly,
  });
}

function parseArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--release") options.mode = "release";
    else if (argument === "--check") options.checkOnly = true;
    else if (argument === "--kernel") options.kernelPath = resolve(argv[++index] ?? "");
    else if (argument === "--source") options.sourceRoot = resolve(argv[++index] ?? "");
    else if (argument === "--out") options.outputPath = resolve(argv[++index] ?? "");
    else if (argument === "--lock") options.lockPath = resolve(argv[++index] ?? "");
    else throw new Error(`unknown Boundary acquisition argument: ${argument}`);
  }
  return options;
}

function isMain() {
  return process.argv[1] !== undefined && pathToFileURL(resolve(process.argv[1])).href === import.meta.url;
}

if (isMain()) {
  const result = await acquireBoundaryProcessAssets(parseArguments(process.argv.slice(2)));
  console.log(`world_boundary_acquisition=${result.provenance}`);
  console.log(`world_boundary_version=${result.boundaryVersion}`);
  console.log(`world_boundary_commit=${result.boundaryCommit}`);
  console.log(`world_boundary_kernel_sha256=${result.kernelSha256}`);
  console.log(`world_boundary_kernel_bytes=${result.kernelByteLength}`);
  console.log(`world_boundary_kernel_abi=${result.processKernelAbiVersion}`);
  console.log(`world_boundary_kernel_output=${result.outputPath}`);
  console.log("world_boundary_process_assets=pass");
}
