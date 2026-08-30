#!/usr/bin/env bun

import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import {
  copyFile,
  cp,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rename,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { dirname, join, posix, resolve, sep } from "node:path";
import { tmpdir } from "node:os";
import { pathToFileURL } from "node:url";

import {
  BOUNDARY_PROCESS_PROOF,
  ConformanceAcquisitionError,
  conformanceErrorRecord,
  sha256Hex,
} from "./acquire_process_conformance_assets.mjs";
import { REPOSITORY_REPAIR_TRANSCRIPT } from "./acquire_repository_repair_transcript.mjs";

const DEFAULT_BOUNDARY_LOCK = resolve("conformance/boundary-process-proof.lock.json");
const DEFAULT_BOUNDARY_ROOT = resolve("conformance/vectors");
const DEFAULT_TRANSCRIPT_LOCK = resolve("conformance/repository-repair-transcript/lock.json");
const DEFAULT_TRANSCRIPT_ROOT = resolve("conformance/repository-repair-transcript/data");
const DEFAULT_RECEIPT = resolve("dist/world-v4.0.0-process-host-conformance-receipt.json");
const MAX_CHILD_OUTPUT_BYTES = 8 * 1024 * 1024;

function fail(code, message, details = {}) {
  throw new ConformanceAcquisitionError(code, message, details);
}

async function readJson(path, label, expectedSha256) {
  let bytes;
  try {
    bytes = await readFile(path);
  } catch (error) {
    fail("WORLD_CONFORMANCE_PREREQUISITE_MISSING", `${label} is missing`, {
      path,
      cause: error?.code ?? error?.message ?? String(error),
    });
  }
  const observedSha256 = sha256Hex(bytes);
  if (observedSha256 !== expectedSha256) {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", `${label} differs from the exact checked-in projection`, {
      path,
      expected: expectedSha256,
      observed: observedSha256,
    });
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", `${label} is not valid UTF-8 JSON`, { path });
  }
}

function safeRelativePath(value, label) {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.includes("\\") ||
    value.startsWith("/") ||
    posix.normalize(value) !== value ||
    value === ".." ||
    value.startsWith("../")
  ) {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", `${label} is not a safe relative path`, { label, value });
  }
  return value;
}

async function regularFileIdentity(root, record, label) {
  if (!record || typeof record !== "object" || Array.isArray(record)) {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", `${label} must be an artifact record`);
  }
  const relativePath = safeRelativePath(record.path, `${label}.path`);
  if (!Number.isSafeInteger(record.byteLength) || record.byteLength < 0) {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", `${label}.byteLength is invalid`);
  }
  if (typeof record.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(record.sha256)) {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", `${label}.sha256 is invalid`);
  }
  const path = join(root, ...relativePath.split("/"));
  let fileStat;
  try {
    fileStat = await stat(path);
  } catch (error) {
    fail("WORLD_CONFORMANCE_PREREQUISITE_MISSING", `${label} file is missing`, {
      path,
      cause: error?.code ?? error?.message ?? String(error),
    });
  }
  if (!fileStat.isFile() || fileStat.size !== record.byteLength) {
    fail("WORLD_CONFORMANCE_ASSET_INVALID", `${label} is not the locked regular file`, {
      path,
      expectedByteLength: record.byteLength,
      observedByteLength: fileStat.size,
      regular: fileStat.isFile(),
    });
  }
  const bytes = new Uint8Array(await readFile(path));
  const observedDigest = sha256Hex(bytes);
  if (observedDigest !== record.sha256) {
    fail("WORLD_CONFORMANCE_ASSET_INVALID", `${label} digest mismatch`, {
      path,
      expected: record.sha256,
      observed: observedDigest,
    });
  }
  return relativePath;
}

async function recursiveFiles(root, prefix = "") {
  const entries = [];
  for (const entry of await readdir(join(root, prefix), { withFileTypes: true })) {
    const name = prefix === "" ? entry.name : `${prefix}/${entry.name}`;
    if (entry.isDirectory()) entries.push(...(await recursiveFiles(root, name)));
    else if (entry.isFile()) entries.push(name);
    else fail("WORLD_CONFORMANCE_ASSET_INVALID", "proof asset tree contains a non-regular entry", { path: name });
  }
  return entries.sort();
}

function assertBoundaryLockIdentity(lock) {
  if (lock.format !== "world-boundary-process-proof-lock/v1" || lock.status !== "locked") {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", "Boundary Process proof lock is not locked");
  }
  const boundary = lock.boundary;
  if (
    boundary?.version !== BOUNDARY_PROCESS_PROOF.version ||
    boundary?.commit !== BOUNDARY_PROCESS_PROOF.commit ||
    boundary?.kernelSha256 !== BOUNDARY_PROCESS_PROOF.kernelSha256 ||
    boundary?.kernelByteLength !== BOUNDARY_PROCESS_PROOF.kernelByteLength ||
    boundary?.processKernelAbiVersion !== 1
  ) {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", "Boundary Process proof lock targets a different kernel tuple");
  }
  if (
    lock.producer?.repository !== BOUNDARY_PROCESS_PROOF.repository ||
    lock.producer?.releaseTag !== BOUNDARY_PROCESS_PROOF.releaseTag ||
    lock.producer?.commit !== BOUNDARY_PROCESS_PROOF.commit
  ) {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", "Boundary Process proof lock has the wrong producer tuple");
  }
}

function assertTranscriptLockIdentity(lock) {
  if (lock.format !== "world-repository-repair-process-transcript-lock/v1" || lock.status !== "locked") {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", "repository-repair Process transcript lock is not locked");
  }
  if (
    lock.producer?.repository !== REPOSITORY_REPAIR_TRANSCRIPT.repository ||
    lock.producer?.releaseTag !== REPOSITORY_REPAIR_TRANSCRIPT.releaseTag ||
    lock.producer?.releaseUrl !== REPOSITORY_REPAIR_TRANSCRIPT.releaseUrl ||
    lock.producer?.commit !== REPOSITORY_REPAIR_TRANSCRIPT.commit
  ) {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", "repository-repair transcript producer tuple is invalid");
  }
  if (
    lock.boundary?.version !== BOUNDARY_PROCESS_PROOF.version ||
    lock.boundary?.commit !== BOUNDARY_PROCESS_PROOF.commit ||
    lock.boundary?.kernelSha256 !== BOUNDARY_PROCESS_PROOF.kernelSha256 ||
    lock.boundary?.kernelByteLength !== BOUNDARY_PROCESS_PROOF.kernelByteLength ||
    lock.boundary?.processKernelAbiVersion !== 1
  ) {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", "repository-repair transcript targets a different Boundary kernel tuple");
  }
  if (
    lock.receipt?.reductionCount !== 96 ||
    lock.receipt?.residualBoundaryCount !== 17 ||
    lock.receipt?.freshWasmInstanceCount !== 97
  ) {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", "repository-repair transcript receipt counts are incomplete");
  }
}

async function verifyLockedTree(lock, root, label) {
  if (!Array.isArray(lock.artifacts) || lock.artifacts.length === 0) {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", `${label}.artifacts is empty`);
  }
  const expectedPaths = [];
  const ids = new Set();
  for (let index = 0; index < lock.artifacts.length; index += 1) {
    const artifact = lock.artifacts[index];
    if (typeof artifact?.id !== "string" || ids.has(artifact.id)) {
      fail("WORLD_CONFORMANCE_LOCK_INVALID", `${label}.artifacts contains an invalid or duplicate id`, { index });
    }
    ids.add(artifact.id);
    expectedPaths.push(await regularFileIdentity(root, artifact, `${label}.artifacts[${index}]`));
  }
  const observedPaths = await recursiveFiles(root);
  expectedPaths.sort();
  if (JSON.stringify(expectedPaths) !== JSON.stringify(observedPaths)) {
    fail("WORLD_CONFORMANCE_ASSET_INVALID", `${label} inventory differs from its lock`, {
      expected: expectedPaths,
      observed: observedPaths,
    });
  }
}

export async function requireLockedProofs({
  boundaryLockPath = DEFAULT_BOUNDARY_LOCK,
  boundaryRoot = DEFAULT_BOUNDARY_ROOT,
  transcriptLockPath = DEFAULT_TRANSCRIPT_LOCK,
  transcriptRoot = DEFAULT_TRANSCRIPT_ROOT,
} = {}) {
  const [boundaryLock, transcriptLock] = await Promise.all([
    readJson(boundaryLockPath, "Boundary Process proof lock", BOUNDARY_PROCESS_PROOF.lockSha256),
    readJson(transcriptLockPath, "repository-repair Process transcript lock", REPOSITORY_REPAIR_TRANSCRIPT.lockSha256),
  ]);
  const missing = [];
  if (boundaryLock.status === "missing") {
    missing.push({
      code: "WORLD_BOUNDARY_PROCESS_CORPUS_MISSING",
      producer: boundaryLock.producer,
      requiredAssets: boundaryLock.requiredAssets,
      reason: boundaryLock.missingReason,
      remedy: boundaryLock.remedy,
      acquisitionCommand: "bun scripts/acquire_process_conformance_assets.mjs",
    });
  }
  if (transcriptLock.status === "missing") {
    missing.push({
      code: "WORLD_REPOSITORY_REPAIR_TRANSCRIPT_MISSING",
      producer: transcriptLock.producer,
      requiredAssets: transcriptLock.requiredAssets,
      reason: transcriptLock.missingReason,
      remedy: transcriptLock.remedy,
      acquisitionCommand: "bun scripts/acquire_repository_repair_transcript.mjs",
    });
  }
  if (missing.length !== 0) {
    fail(
      "WORLD_CONFORMANCE_PREREQUISITES_MISSING",
      "full World Process conformance requires two immutable upstream proof assets that are not published",
      { missing, runtimeOnlyCommand: "bun scripts/run_clean_room_conformance.mjs --smoke" },
    );
  }
  assertBoundaryLockIdentity(boundaryLock);
  assertTranscriptLockIdentity(transcriptLock);
  await Promise.all([
    verifyLockedTree(boundaryLock, boundaryRoot, "boundaryProof"),
    verifyLockedTree(transcriptLock, transcriptRoot, "repositoryRepairTranscript"),
  ]);
  return Object.freeze({
    boundaryLock,
    boundaryLockPath,
    boundaryRoot,
    transcriptLock,
    transcriptLockPath,
    transcriptRoot,
  });
}

async function runChild(command, args, { cwd, env } = {}) {
  const environmentKeys = Object.keys(env ?? {});
  if (environmentKeys.length !== 1 || environmentKeys[0] !== "PATH") {
    throw new Error("clean-room child environment must contain only PATH");
  }
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(command, args, { cwd, env, stdio: ["ignore", "pipe", "pipe"] });
    const stdout = [];
    const stderr = [];
    let outputBytes = 0;
    const append = (target, chunk) => {
      outputBytes += chunk.byteLength;
      if (outputBytes > MAX_CHILD_OUTPUT_BYTES) {
        child.kill("SIGKILL");
        rejectPromise(new Error("child output exceeded the clean-room bound"));
      } else target.push(chunk);
    };
    child.stdout.on("data", (chunk) => append(stdout, chunk));
    child.stderr.on("data", (chunk) => append(stderr, chunk));
    child.once("error", rejectPromise);
    child.once("close", (code, signal) => {
      const result = {
        code,
        signal,
        stdout: Buffer.concat(stdout),
        stderr: Buffer.concat(stderr),
      };
      if (code === 0) resolvePromise(result);
      else rejectPromise(Object.assign(new Error(`child failed with exit ${code ?? signal}`), { result }));
    });
  });
}

async function loadArchiveModules() {
  let buildModule;
  let checkModule;
  try {
    [buildModule, checkModule] = await Promise.all([
      import("./build_runtime_archive.mjs"),
      import("./check_runtime_archive.mjs"),
    ]);
  } catch (error) {
    fail("WORLD_RUNTIME_SMOKE_UNAVAILABLE", "runtime archive construction modules are unavailable", {
      cause: error?.message ?? String(error),
    });
  }
  if (typeof buildModule.buildRuntimeArchive !== "function" || typeof checkModule.checkRuntimeArchive !== "function") {
    fail("WORLD_RUNTIME_SMOKE_UNAVAILABLE", "runtime archive modules do not expose the required programmatic API");
  }
  return { buildRuntimeArchive: buildModule.buildRuntimeArchive, checkRuntimeArchive: checkModule.checkRuntimeArchive };
}

export async function runRuntimeCleanRoomSmoke({ archivePath, checksumPath, extractTo, keepExtractedRoot = false } = {}) {
  const { buildRuntimeArchive, checkRuntimeArchive } = await loadArchiveModules();
  let construction;
  if (archivePath || checksumPath) {
    if (!archivePath || !checksumPath) {
      fail("WORLD_CONFORMANCE_USAGE", "--archive and --checksum must be supplied together");
    }
    construction = { archivePath: resolve(archivePath), checksumPath: resolve(checksumPath) };
  } else {
    construction = await buildRuntimeArchive();
  }
  const ownsTemporaryRoot = !extractTo;
  const temporaryRoot = ownsTemporaryRoot ? await mkdtemp(join(tmpdir(), "world-runtime-smoke-")) : null;
  const extractionRoot = extractTo ? resolve(extractTo) : join(temporaryRoot, "runtime");
  try {
    const checked = await checkRuntimeArchive({
      archivePath: construction.archivePath,
      checksumPath: construction.checksumPath,
      extractTo: extractionRoot,
      keepExtractedRoot: keepExtractedRoot || !ownsTemporaryRoot,
      verifyRebuild: true,
    });
    return Object.freeze({
      archivePath: construction.archivePath,
      checksumPath: construction.checksumPath,
      archiveSha256: checked.archiveSha256,
      archiveByteLength: checked.archiveByteLength,
      runtimeInventory: Object.freeze([...checked.runtimeInventory]),
      extractedRoot: keepExtractedRoot || !ownsTemporaryRoot ? checked.extractedRoot : null,
      reproducible: checked.reproducible,
      innerVerified: checked.innerVerified,
    });
  } finally {
    if (ownsTemporaryRoot && !keepExtractedRoot) await rm(temporaryRoot, { recursive: true, force: true });
  }
}

const CLEAN_ROOM_RUNNER = String.raw`import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { readFile, readdir, stat } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [runtimeRoot, boundaryLockPath, boundaryRoot, transcriptLockPath, transcriptRoot] = process.argv.slice(2).map((value) => resolve(value));
if (Object.keys(process.env).length !== 1 || !("PATH" in process.env)) throw new Error("clean_room_environment");
const childEnvironment = Object.freeze({ PATH: process.env.PATH ?? "" });
const runtimeModule = await import(pathToFileURL(join(runtimeRoot, "src/process_v1/index.mjs")).href);
const { admitProcessKernel, decodeProcessOutcome } = runtimeModule;
if (typeof admitProcessKernel !== "function" || typeof decodeProcessOutcome !== "function") throw new Error("clean_room_runtime_api");

const readJson = async (path) => JSON.parse(await readFile(path, "utf8"));
const boundaryLock = await readJson(boundaryLockPath);
const transcriptLock = await readJson(transcriptLockPath);
const kernelBytes = new Uint8Array(await readFile(join(runtimeRoot, "boundary-process-kernel-v1.wasm")));
let host = await admitProcessKernel(kernelBytes, { expectedSha256: boundaryLock.boundary.kernelSha256 });

const equal = (left, right) => Buffer.from(left).equals(Buffer.from(right));
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const bytesAt = async (root, relativePath) => new Uint8Array(await readFile(join(root, ...relativePath.split("/"))));
const outcomeRequestBytes = (outcome) => outcome.request?.bytes ?? outcome.request;
const invocation = async (vector) => {
  const image = await bytesAt(boundaryRoot, vector.imagePath);
  const instanceBytes = await bytesAt(boundaryRoot, vector.instance.path);
  const effectResult = vector.effectResultPath === null ? undefined : await bytesAt(boundaryRoot, vector.effectResultPath);
  const instance = vector.instance.kind === "initialArgs" ? { initialArgs: instanceBytes } : { state: instanceBytes };
  const outcome = await host.advance({ image, instance, ...(effectResult === undefined ? {} : { effectResult }) });
  const expected = await bytesAt(boundaryRoot, vector.expectedOutcomePath);
  if (!equal(outcome.bytes, expected) || outcome.kind !== vector.expectedKind) throw new Error("boundary_vector_mismatch:" + vector.id);
  return { vector, image, instance, effectResult, expected };
};

const vectorResults = [];
for (const vector of boundaryLock.vectors) vectorResults.push(await invocation(vector));
const concurrentSource = vectorResults.find((entry) => entry.vector.expectedKind !== "NeedsCapacity") ?? vectorResults[0];
const concurrentOptions = {
  image: concurrentSource.image,
  instance: concurrentSource.instance,
  ...(concurrentSource.effectResult === undefined ? {} : { effectResult: concurrentSource.effectResult }),
};
const concurrent = await Promise.all([host.advance(concurrentOptions), host.advance(concurrentOptions)]);
if (!equal(concurrent[0].bytes, concurrentSource.expected) || !equal(concurrent[1].bytes, concurrentSource.expected)) {
  throw new Error("boundary_concurrency_mismatch");
}

const cliVector = vectorResults.find((entry) => entry.vector.expectedKind !== "NeedsCapacity") ?? vectorResults[0];
const cliArgs = [
  join(runtimeRoot, "bin/world.mjs"), "process", "step",
  "--kernel", join(runtimeRoot, "boundary-process-kernel-v1.wasm"),
  "--image", join(boundaryRoot, ...cliVector.vector.imagePath.split("/")),
  cliVector.vector.instance.kind === "initialArgs" ? "--initial-args" : "--state",
  join(boundaryRoot, ...cliVector.vector.instance.path.split("/")),
];
if (cliVector.vector.effectResultPath !== null) cliArgs.push("--result", join(boundaryRoot, ...cliVector.vector.effectResultPath.split("/")));
const cli = await new Promise((accept, reject) => {
  const child = spawn(process.execPath, cliArgs, { cwd: runtimeRoot, env: childEnvironment, stdio: ["ignore", "pipe", "pipe"] });
  const stdout = [];
  const stderr = [];
  child.stdout.on("data", (chunk) => stdout.push(chunk));
  child.stderr.on("data", (chunk) => stderr.push(chunk));
  child.once("error", reject);
  child.once("close", (code) => code === 0 ? accept({ stdout: Buffer.concat(stdout), stderr: Buffer.concat(stderr) }) : reject(new Error("clean_room_cli:" + code + ":" + Buffer.concat(stderr).toString("utf8"))));
});
if (!equal(cli.stdout, cliVector.expected)) throw new Error("clean_room_cli_output_mismatch");

const image = await bytesAt(transcriptRoot, transcriptLock.transcript.programImagePath);
const initialArgs = await bytesAt(transcriptRoot, transcriptLock.transcript.initialArgsPath);
let instance = { initialArgs };
let effectResult;
let requestBoundary = 0;
let transferRecovered = false;
let finalOutcome;
for (const expectedEntry of transcriptLock.transcript.expectedOutcomes) {
  const actual = await host.advance({ image, instance, ...(effectResult === undefined ? {} : { effectResult }) });
  const expected = await bytesAt(transcriptRoot, expectedEntry.path);
  if (!equal(actual.bytes, expected) || actual.kind !== expectedEntry.kind) {
    throw new Error("repository_repair_outcome_mismatch:" + expectedEntry.reductionIndex);
  }
  finalOutcome = actual;
  effectResult = undefined;
  if (actual.state !== undefined) instance = { state: actual.state };
  if (actual.kind === "Requested") {
    const requestEntry = transcriptLock.transcript.requests[requestBoundary];
    const resultEntry = transcriptLock.transcript.effectResults[requestBoundary];
    if (!requestEntry || requestEntry.reductionIndex !== expectedEntry.reductionIndex || !resultEntry) {
      throw new Error("repository_repair_boundary_index:" + requestBoundary);
    }
    const expectedRequest = await bytesAt(transcriptRoot, requestEntry.path);
    if (!equal(outcomeRequestBytes(actual), expectedRequest)) throw new Error("repository_repair_request_mismatch:" + requestBoundary);
    let reconstructionHost = host;
    if (requestBoundary === transcriptLock.transcript.transferAfterBoundary) {
      reconstructionHost = await admitProcessKernel(kernelBytes, { expectedSha256: boundaryLock.boundary.kernelSha256 });
    }
    const reconstructed = await reconstructionHost.advance({ image, instance });
    if (!equal(reconstructed.bytes, actual.bytes) || !equal(outcomeRequestBytes(reconstructed), expectedRequest)) {
      throw new Error("repository_repair_reconstruction_mismatch:" + requestBoundary);
    }
    if (requestBoundary === transcriptLock.transcript.transferAfterBoundary) {
      host = reconstructionHost;
      transferRecovered = true;
    }
    effectResult = await bytesAt(transcriptRoot, resultEntry.path);
    requestBoundary += 1;
  }
}
if (requestBoundary !== 17 || finalOutcome?.kind !== "Completed") throw new Error("repository_repair_terminal_shape");
if (digest(finalOutcome.result) !== transcriptLock.transcript.terminal.resultSha256) throw new Error("repository_repair_terminal_result");

const commandUnavailable = async (name) => new Promise((accept) => {
  const child = spawn(name, ["--version"], { cwd: runtimeRoot, env: childEnvironment, stdio: "ignore" });
  child.once("error", (error) => accept(error.code === "ENOENT"));
  child.once("close", () => accept(false));
});
const gitAvailable = !(await commandUnavailable("git"));
const zigAvailable = !(await commandUnavailable("zig"));
if (gitAvailable || zigAvailable) throw new Error("clean_room_tool_visible");

const inventory = async (root, prefix = "") => {
  const result = [];
  for (const entry of await readdir(join(root, prefix), { withFileTypes: true })) {
    const name = prefix === "" ? entry.name : prefix + "/" + entry.name;
    if (entry.isDirectory()) result.push(...await inventory(root, name));
    else if (entry.isFile()) result.push(name);
    else throw new Error("runtime_non_regular:" + name);
  }
  return result.sort();
};
process.stdout.write(JSON.stringify({
  format: "world-process-host-clean-room-result/v1",
  boundaryVectorCount: boundaryLock.vectors.length,
  boundaryByteIdenticalCount: boundaryLock.vectors.length,
  concurrencyByteIdentical: true,
  cliByteIdentical: true,
  repositoryRepairReductionCount: transcriptLock.transcript.reductionCount,
  repositoryRepairResidualBoundaryCount: requestBoundary,
  requestReconstructionCount: requestBoundary,
  transferAfterBoundary: transcriptLock.transcript.transferAfterBoundary,
  transferRecovered,
  terminalResultSha256: transcriptLock.transcript.terminal.resultSha256,
  runtimeInventory: await inventory(runtimeRoot),
  gitAvailable,
  zigAvailable,
}) + "\n");
`;

export function cleanRoomEnvironment(emptyPath) {
  return Object.freeze({ PATH: emptyPath });
}

export async function copyLockedProofSnapshot({
  boundaryLockPath,
  boundaryRoot,
  transcriptLockPath,
  transcriptRoot,
  destinationRoot,
  afterCopy,
}) {
  if (afterCopy !== undefined && typeof afterCopy !== "function") {
    fail("WORLD_CONFORMANCE_USAGE", "afterCopy must be a function");
  }
  const copiedBoundaryRoot = join(destinationRoot, "boundary");
  const copiedTranscriptRoot = join(destinationRoot, "repository-repair");
  await mkdir(destinationRoot, { mode: 0o700 });
  await cp(boundaryRoot, copiedBoundaryRoot, { recursive: true, errorOnExist: true, force: false });
  await cp(transcriptRoot, copiedTranscriptRoot, { recursive: true, errorOnExist: true, force: false });
  const copiedBoundaryLock = join(destinationRoot, "boundary.lock.json");
  const copiedTranscriptLock = join(destinationRoot, "repository-repair.lock.json");
  await copyFile(boundaryLockPath, copiedBoundaryLock);
  await copyFile(transcriptLockPath, copiedTranscriptLock);
  const copiedProofPaths = Object.freeze({
    boundaryLockPath: copiedBoundaryLock,
    boundaryRoot: copiedBoundaryRoot,
    transcriptLockPath: copiedTranscriptLock,
    transcriptRoot: copiedTranscriptRoot,
  });
  if (afterCopy) await afterCopy(copiedProofPaths);
  return requireLockedProofs(copiedProofPaths);
}

async function writeJsonAtomic(path, value) {
  const temporary = `${path}.tmp-${randomUUID()}`;
  await mkdir(dirname(path), { recursive: true });
  await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { flag: "wx", mode: 0o644 });
  await rename(temporary, path);
}

export async function runFullCleanRoomConformance({
  boundaryLockPath = DEFAULT_BOUNDARY_LOCK,
  boundaryRoot = DEFAULT_BOUNDARY_ROOT,
  transcriptLockPath = DEFAULT_TRANSCRIPT_LOCK,
  transcriptRoot = DEFAULT_TRANSCRIPT_ROOT,
  receiptPath = DEFAULT_RECEIPT,
  archivePath,
  checksumPath,
} = {}) {
  await requireLockedProofs({ boundaryLockPath, boundaryRoot, transcriptLockPath, transcriptRoot });
  const cleanRoot = await mkdtemp(join(tmpdir(), "world-process-clean-room-"));
  try {
    const proofRoot = join(cleanRoot, "proof");
    const copiedProofs = await copyLockedProofSnapshot({
      boundaryLockPath,
      boundaryRoot,
      transcriptLockPath,
      transcriptRoot,
      destinationRoot: proofRoot,
    });
    const runtimeRoot = join(cleanRoot, "runtime");
    const smoke = await runRuntimeCleanRoomSmoke({
      archivePath,
      checksumPath,
      extractTo: runtimeRoot,
      keepExtractedRoot: true,
    });
    const runnerPath = join(cleanRoot, "runner.mjs");
    const emptyPath = join(cleanRoot, "empty-path");
    await mkdir(emptyPath, { mode: 0o700 });
    await writeFile(runnerPath, CLEAN_ROOM_RUNNER, { flag: "wx", mode: 0o600 });
    let execution;
    try {
      execution = await runChild(
        process.execPath,
        [
          runnerPath,
          runtimeRoot,
          copiedProofs.boundaryLockPath,
          copiedProofs.boundaryRoot,
          copiedProofs.transcriptLockPath,
          copiedProofs.transcriptRoot,
        ],
        { cwd: cleanRoot, env: cleanRoomEnvironment(emptyPath) },
      );
    } catch (error) {
      fail("WORLD_CLEAN_ROOM_CONFORMANCE_FAILED", "clean-room Process conformance execution failed", {
        exitCode: error?.result?.code ?? null,
        signal: error?.result?.signal ?? null,
        stderr: error?.result?.stderr?.toString("utf8").slice(0, 16_384) ?? error?.message ?? String(error),
      });
    }
    let result;
    try {
      result = JSON.parse(execution.stdout.toString("utf8"));
    } catch {
      fail("WORLD_CLEAN_ROOM_CONFORMANCE_FAILED", "clean-room runner did not return its canonical JSON result", {
        stdout: execution.stdout.toString("utf8").slice(0, 16_384),
      });
    }
    if (
      result.format !== "world-process-host-clean-room-result/v1" ||
      result.boundaryVectorCount !== copiedProofs.boundaryLock.vectors.length ||
      result.boundaryByteIdenticalCount !== copiedProofs.boundaryLock.vectors.length ||
      result.repositoryRepairReductionCount !== 96 ||
      result.repositoryRepairResidualBoundaryCount !== 17 ||
      result.requestReconstructionCount !== 17 ||
      result.transferRecovered !== true ||
      result.gitAvailable !== false ||
      result.zigAvailable !== false ||
      JSON.stringify(result.runtimeInventory) !== JSON.stringify(smoke.runtimeInventory)
    ) {
      fail("WORLD_CLEAN_ROOM_CONFORMANCE_FAILED", "clean-room result does not close every required proof", { result });
    }
    const receipt = {
      format: "world-process-host-conformance-receipt/v1",
      result: "passed",
      worldVersion: "4.0.0",
      boundary: {
        version: BOUNDARY_PROCESS_PROOF.version,
        commit: BOUNDARY_PROCESS_PROOF.commit,
        kernelSha256: BOUNDARY_PROCESS_PROOF.kernelSha256,
      },
      boundaryCorpus: {
        producerTag: copiedProofs.boundaryLock.producer.releaseTag,
        producerCommit: copiedProofs.boundaryLock.producer.commit,
        manifestSha256: copiedProofs.boundaryLock.manifest.sha256,
        payloadSha256: copiedProofs.boundaryLock.payload.sha256,
        vectorCount: result.boundaryVectorCount,
        byteIdenticalCount: result.boundaryByteIdenticalCount,
        needsCapacityVectorId: copiedProofs.boundaryLock.receipt.needsCapacityVectorId,
        nonAgentVectorId: copiedProofs.boundaryLock.receipt.nonAgentVectorId,
      },
      repositoryRepair: {
        producerTag: copiedProofs.transcriptLock.producer.releaseTag,
        producerCommit: copiedProofs.transcriptLock.producer.commit,
        manifestSha256: copiedProofs.transcriptLock.manifest.sha256,
        payloadSha256: copiedProofs.transcriptLock.payload.sha256,
        programImageSha256: REPOSITORY_REPAIR_TRANSCRIPT.programImageSha256,
        reductionCount: result.repositoryRepairReductionCount,
        residualBoundaryCount: result.repositoryRepairResidualBoundaryCount,
        requestReconstructionCount: result.requestReconstructionCount,
        transferAfterBoundary: result.transferAfterBoundary,
        transferRecovered: result.transferRecovered,
        terminalResultSha256: result.terminalResultSha256,
      },
      cleanRoom: {
        runtimeArchiveSha256: smoke.archiveSha256,
        runtimeInventory: result.runtimeInventory,
        gitAvailable: false,
        zigAvailable: false,
      },
    };
    await writeJsonAtomic(receiptPath, receipt);
    return Object.freeze({ ...receipt, receiptPath });
  } finally {
    await rm(cleanRoot, { recursive: true, force: true });
  }
}

function parseCli(argv) {
  const options = { smoke: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--smoke") options.smoke = true;
    else if (
      argument === "--receipt" ||
      argument === "--archive" ||
      argument === "--checksum" ||
      argument === "--boundary-lock" ||
      argument === "--boundary-root" ||
      argument === "--transcript-lock" ||
      argument === "--transcript-root"
    ) {
      const value = argv[index + 1];
      if (!value) fail("WORLD_CONFORMANCE_USAGE", `${argument} requires a path`);
      const property = {
        "--receipt": "receiptPath",
        "--archive": "archivePath",
        "--checksum": "checksumPath",
        "--boundary-lock": "boundaryLockPath",
        "--boundary-root": "boundaryRoot",
        "--transcript-lock": "transcriptLockPath",
        "--transcript-root": "transcriptRoot",
      }[argument];
      options[property] = resolve(value);
      index += 1;
    } else if (argument === "--help") options.help = true;
    else fail("WORLD_CONFORMANCE_USAGE", `unknown argument ${argument}`, { argument });
  }
  if ((options.archivePath && !options.checksumPath) || (!options.archivePath && options.checksumPath)) {
    fail("WORLD_CONFORMANCE_USAGE", "--archive and --checksum must be supplied together");
  }
  return options;
}

export async function main(argv = process.argv.slice(2)) {
  const options = parseCli(argv);
  if (options.help) {
    process.stdout.write(
      "usage: bun scripts/run_clean_room_conformance.mjs [--smoke] [--archive PATH --checksum PATH] [--receipt PATH]\n",
    );
    return;
  }
  if (options.smoke) {
    const result = await runRuntimeCleanRoomSmoke(options);
    process.stdout.write(
      `${JSON.stringify({
        ok: true,
        format: "world-process-host-runtime-smoke-result/v1",
        archiveSha256: result.archiveSha256,
        archiveByteLength: result.archiveByteLength,
        runtimeInventory: result.runtimeInventory,
        reproducible: result.reproducible,
        innerVerified: result.innerVerified,
        semanticConformance: "not-run",
      })}\n`,
    );
    return;
  }
  const result = await runFullCleanRoomConformance(options);
  process.stdout.write(`${JSON.stringify({ ok: true, ...result })}\n`);
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
if (isMain) {
  main().catch((error) => {
    process.stderr.write(`${JSON.stringify(conformanceErrorRecord(error))}\n`);
    process.exitCode = 1;
  });
}
