import assert from "node:assert/strict";
import { constants as fsConstants } from "node:fs";
import { mkdir, open, rename, rm } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

import {
  RUNTIME_ARCHIVE_NAME,
  WORLD_VERSION,
  assertTrackedRepositoryMatchesCommit,
  repositoryRoot,
} from "./build_runtime_archive.mjs";
import {
  checkRuntimeArchive,
  runtimeArchiveContract,
} from "./check_runtime_archive.mjs";
import { runFullCleanRoomConformance } from "./run_clean_room_conformance.mjs";

export const RELEASE_RECEIPT_FORMAT = "world-process-host-release-receipt/v1";
export const DEFAULT_RELEASE_RECEIPT = `world-v${WORLD_VERSION}-process-host-release-receipt.json`;
export const DEFAULT_CONFORMANCE_RECEIPT = `world-v${WORLD_VERSION}-process-host-conformance-receipt.json`;

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
  outputPath = join(root, "dist", DEFAULT_RELEASE_RECEIPT),
} = {}) {
  const conformanceReceiptPath = join(dirname(outputPath), DEFAULT_CONFORMANCE_RECEIPT);
  const custodyPaths = [archivePath, checksumPath, outputPath, conformanceReceiptPath].map((path) => resolve(path));
  assert.equal(
    new Set(custodyPaths).size,
    custodyPaths.length,
    "archive, checksum, release receipt, and conformance receipt paths must be pairwise distinct",
  );
  const admission = await checkRuntimeArchive({
    root,
    archivePath,
    checksumPath,
    verifyRebuild: false,
    runInner: false,
  });
  await assertTrackedRepositoryMatchesCommit(root, admission.manifest.sourceCommit);
  const proof = await checkRuntimeArchive({
    root,
    archivePath,
    checksumPath,
    verifyRebuild: true,
    runInner: true,
  });
  assert(proof.reproducible && proof.innerVerified, "release receipt requires a reproducible, internally verified runtime archive");
  assert.equal(proof.manifest.sourceCommit, admission.manifest.sourceCommit, "runtime proof sourceCommit changed after repository preflight");
  await assertTrackedRepositoryMatchesCommit(root, proof.manifest.sourceCommit);
  const conformance = await runFullCleanRoomConformance({
    boundaryLockPath: join(root, "conformance", "boundary-process-proof.lock.json"),
    boundaryRoot: join(root, "conformance", "vectors"),
    transcriptLockPath: join(root, "conformance", "repository-repair-transcript", "lock.json"),
    transcriptRoot: join(root, "conformance", "repository-repair-transcript", "data"),
    receiptPath: conformanceReceiptPath,
    archivePath,
    checksumPath,
  });
  assert.equal(conformance.cleanRoom.runtimeArchiveSha256, proof.archiveSha256, "direct conformance runtime archive differs");
  await assertTrackedRepositoryMatchesCommit(root, proof.manifest.sourceCommit);
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
    publishedProcessCorpusParityClaimed: true,
    publishedProcessCorpusParity: Object.freeze({
      boundaryVectorCount: conformance.boundaryCorpus.vectorCount,
      boundaryByteIdenticalCount: conformance.boundaryCorpus.byteIdenticalCount,
      repositoryRepairReductionCount: conformance.repositoryRepair.reductionCount,
      repositoryRepairResidualBoundaryCount: conformance.repositoryRepair.residualBoundaryCount,
      requestReconstructionCount: conformance.repositoryRepair.requestReconstructionCount,
      transferAfterBoundary: conformance.repositoryRepair.transferAfterBoundary,
      transferRecovered: conformance.repositoryRepair.transferRecovered,
      terminalResultSha256: conformance.repositoryRepair.terminalResultSha256,
    }),
    negativeGateCoverageClaimed: false,
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
  console.log("world_release_receipt_write=pass");
}
