import assert from "node:assert/strict";
import { constants as fsConstants } from "node:fs";
import { lstat, mkdir, open, readFile, rename, rm } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

import {
  RUNTIME_ARCHIVE_NAME,
  WORLD_VERSION,
  repositoryRoot,
} from "./build_runtime_archive.mjs";
import {
  checkRuntimeArchive,
  runtimeArchiveContract,
} from "./check_runtime_archive.mjs";

export const RELEASE_RECEIPT_FORMAT = "world-process-host-release-receipt/v1";
export const DEFAULT_RELEASE_RECEIPT = `world-v${WORLD_VERSION}-process-host-release-receipt.json`;
export const DEFAULT_CONFORMANCE_RECEIPT = `world-v${WORLD_VERSION}-process-host-conformance-receipt.json`;

async function readConformanceReceipt(path, proof) {
  const info = await lstat(path);
  assert(info.isFile() && !info.isSymbolicLink(), "conformance receipt must be a regular file");
  assert(info.size > 0 && info.size <= 1024 * 1024, "conformance receipt has an invalid size");
  const receipt = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(await readFile(path)));
  assert.equal(receipt.format, "world-process-host-conformance-receipt/v1", "conformance receipt format differs");
  assert.equal(receipt.result, "passed", "conformance receipt does not report success");
  assert.equal(receipt.worldVersion, WORLD_VERSION, "conformance receipt World version differs");
  assert.equal(receipt.boundary?.version, proof.manifest.boundaryVersion, "conformance receipt Boundary version differs");
  assert.equal(receipt.boundary?.commit, proof.manifest.boundaryCommit, "conformance receipt Boundary commit differs");
  assert.equal(receipt.boundary?.kernelSha256, proof.manifest.kernelSha256, "conformance receipt kernel differs");
  assert.equal(receipt.cleanRoom?.runtimeArchiveSha256, proof.archiveSha256, "conformance receipt runtime archive differs");
  assert.equal(receipt.boundaryCorpus?.vectorCount, 20, "conformance receipt vector count differs");
  assert.equal(receipt.boundaryCorpus?.byteIdenticalCount, 20, "conformance receipt parity count differs");
  assert.equal(receipt.repositoryRepair?.reductionCount, 96, "conformance receipt reduction count differs");
  assert.equal(receipt.repositoryRepair?.residualBoundaryCount, 17, "conformance receipt boundary count differs");
  assert.equal(receipt.repositoryRepair?.requestReconstructionCount, 17, "conformance receipt reconstruction count differs");
  assert.equal(receipt.repositoryRepair?.transferRecovered, true, "conformance receipt transfer proof failed");
  return receipt;
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

export async function writeReleaseReceipt({
  root = repositoryRoot,
  archivePath = join(root, "dist", RUNTIME_ARCHIVE_NAME),
  checksumPath = `${archivePath}.sha256`,
  conformanceReceiptPath = join(root, "dist", DEFAULT_CONFORMANCE_RECEIPT),
  outputPath = join(root, "dist", DEFAULT_RELEASE_RECEIPT),
} = {}) {
  const proof = await checkRuntimeArchive({
    root,
    archivePath,
    checksumPath,
    verifyRebuild: true,
    runInner: true,
  });
  assert(proof.reproducible && proof.innerVerified, "release receipt requires a reproducible, internally verified runtime archive");
  const conformance = await readConformanceReceipt(conformanceReceiptPath, proof);
  const receipt = Object.freeze({
    format: RELEASE_RECEIPT_FORMAT,
    worldVersion: WORLD_VERSION,
    sourceCommit: proof.manifest.sourceCommit,
    productionSourceSha256: proof.manifest.productionSourceSha256,
    boundaryVersion: proof.manifest.boundaryVersion,
    boundaryCommit: proof.manifest.boundaryCommit,
    processKernelAbiVersion: proof.manifest.processKernelAbiVersion,
    kernelSha256: proof.manifest.kernelSha256,
    kernelByteLength: proof.manifest.kernelByteLength,
    kernelImportCount: proof.manifest.kernelImportCount,
    archiveName: basename(archivePath),
    archiveSha256: proof.archiveSha256,
    archiveByteLength: proof.archiveByteLength,
    archiveEntryCount: proof.archiveEntryCount,
    runtimeInventory: proof.runtimeInventory,
    productionSourceFileCount: proof.runtimeInventory.filter((path) => path === "bin/world.mjs" || path.startsWith("src/process_v1/")).length,
    runtimeDependencyCount: 0,
    publicApiExports: [...runtimeArchiveContract.apiExports],
    cliCommands: ["world process step"],
    archiveStructureVerified: true,
    archiveChecksumsVerified: true,
    byteReproducible: true,
    cleanRoomRuntimeVerified: true,
    semanticConformanceClaimed: true,
    semanticConformance: Object.freeze({
      boundaryVectorCount: conformance.boundaryCorpus.vectorCount,
      boundaryByteIdenticalCount: conformance.boundaryCorpus.byteIdenticalCount,
      repositoryRepairReductionCount: conformance.repositoryRepair.reductionCount,
      repositoryRepairResidualBoundaryCount: conformance.repositoryRepair.residualBoundaryCount,
      requestReconstructionCount: conformance.repositoryRepair.requestReconstructionCount,
      transferAfterBoundary: conformance.repositoryRepair.transferAfterBoundary,
      transferRecovered: conformance.repositoryRepair.transferRecovered,
      terminalResultSha256: conformance.repositoryRepair.terminalResultSha256,
    }),
    publicReleaseClaimed: false,
    completionClaimed: false,
  });
  await atomicWrite(outputPath, Buffer.from(`${JSON.stringify(receipt, null, 2)}\n`, "utf8"));
  return Object.freeze({ outputPath, receipt });
}

function parseArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--archive") options.archivePath = resolve(argv[++index] ?? "");
    else if (argument === "--checksum") options.checksumPath = resolve(argv[++index] ?? "");
    else if (argument === "--conformance-receipt") options.conformanceReceiptPath = resolve(argv[++index] ?? "");
    else if (argument === "--out") options.outputPath = resolve(argv[++index] ?? "");
    else throw new Error(`unknown release-receipt argument: ${argument}`);
  }
  if (options.archivePath && !options.checksumPath) options.checksumPath = `${options.archivePath}.sha256`;
  return options;
}

function isMain() {
  return process.argv[1] !== undefined && pathToFileURL(resolve(process.argv[1])).href === import.meta.url;
}

if (isMain()) {
  const result = await writeReleaseReceipt(parseArguments(process.argv.slice(2)));
  console.log(`world_release_receipt=${result.outputPath}`);
  console.log(`world_release_receipt_archive_sha256=${result.receipt.archiveSha256}`);
  console.log("world_release_receipt=pass");
}
