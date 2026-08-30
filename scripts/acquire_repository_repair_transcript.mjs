#!/usr/bin/env bun

import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

import {
  BOUNDARY_PROCESS_PROOF,
  assertConformanceAcquisitionCustody,
  canonicalJsonBytes,
  ConformanceAcquisitionError,
  conformanceErrorRecord,
  fetchGitHubAssetBytes,
  fetchGitHubJson,
  materializeExactFiles,
  parseManifestBytes,
  resolveGitHubTagCommit,
  sha256Hex,
  validateArtifactTable,
  validateBundlePayload,
  writeJsonAtomic,
} from "./acquire_process_conformance_assets.mjs";

export const REPOSITORY_REPAIR_TRANSCRIPT = Object.freeze({
  repository: "tkersey/agent",
  releaseTag: "v2.7.0",
  releaseUrl: "https://github.com/tkersey/agent/releases/tag/v2.7.0",
  commit: "f8609bc68f2a9c798df3511cfc3a2af60a359d41",
  manifestAssetName: "agent-repository-repair-process-v1-transcript.json",
  manifestSha256: "c2e0e63192c19cbb8e5d0d1d3b6951fcd428f9496c015471f69524286cf236c1",
  payloadAssetName: "agent-repository-repair-process-v1-transcript.bin",
  payloadSha256: "f0ddf27f8402168e76360178b532da37323ada5c97a4294ca9d1c98e1c4838dd",
  payloadByteLength: 364_061,
  lockSha256: "42c8d440c907bbccce50b5c98fcc686eeb425f3d21f56f1926292fde33f54fcc",
  programImageSha256: "7440076a8078220d9d4000b871423d981bbbee19aedba499afaa4a86239fe6a6",
  programImageByteLength: 23_431,
  reductionCount: 96,
  residualBoundaryCount: 17,
  freshWasmInstanceCount: 97,
});

const DIGEST_PATTERN = /^[0-9a-f]{64}$/;
const IDENTIFIER_PATTERN = /^[a-z0-9][a-z0-9._-]{0,127}$/;
const OUTCOME_KINDS = new Set([
  "Progressed",
  "Requested",
  "ExplicitlyYielded",
  "Completed",
  "AuthoredFailure",
  "NeedsCapacity",
]);
const MAX_MANIFEST_BYTES = 4 * 1024 * 1024;
const MAX_PAYLOAD_BYTES = 512 * 1024 * 1024;

function fail(code, message, details = {}) {
  throw new ConformanceAcquisitionError(code, message, details);
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, required, label) {
  if (!isPlainObject(value)) fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", `${label} must be an object`, { label });
  const allowed = new Set(required);
  for (const key of required) {
    if (!Object.hasOwn(value, key)) fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", `${label} is missing ${key}`, { label, key });
  }
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", `${label} has unexpected field ${key}`, { label, key });
  }
}

function exactString(value, expected, label) {
  if (value !== expected) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", `${label} does not match the locked value`, {
      label,
      expected,
      observed: value,
    });
  }
}

function digest(value, label) {
  if (typeof value !== "string" || !DIGEST_PATTERN.test(value)) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", `${label} must be a lowercase SHA-256 digest`, { label });
  }
  return value;
}

function identifier(value, label) {
  if (typeof value !== "string" || !IDENTIFIER_PATTERN.test(value)) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", `${label} must be a canonical identifier`, { label });
  }
  return value;
}

function safeInteger(value, minimum, maximum, label) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", `${label} is outside its admitted range`, {
      label,
      minimum,
      maximum,
      observed: value,
    });
  }
  return value;
}

function artifactReference(value, artifacts, label, used) {
  const id = identifier(value, label);
  if (!artifacts.has(id)) fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", `${label} names an unknown artifact`, { label, id });
  used.add(id);
  return id;
}

function validateBoundary(value) {
  exactKeys(
    value,
    ["version", "commit", "processKernelAbiVersion", "kernelSha256", "kernelByteLength"],
    "manifest.boundary",
  );
  exactString(value.version, BOUNDARY_PROCESS_PROOF.version, "manifest.boundary.version");
  exactString(value.commit, BOUNDARY_PROCESS_PROOF.commit, "manifest.boundary.commit");
  exactString(value.kernelSha256, BOUNDARY_PROCESS_PROOF.kernelSha256, "manifest.boundary.kernelSha256");
  if (value.processKernelAbiVersion !== 1 || value.kernelByteLength !== BOUNDARY_PROCESS_PROOF.kernelByteLength) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", "manifest.boundary does not describe the exact Boundary v1.7.0 Process kernel");
  }
}

function validateProducer(value) {
  exactKeys(value, ["repository", "releaseTag", "releaseUrl", "commit"], "manifest.producer");
  exactString(value.repository, REPOSITORY_REPAIR_TRANSCRIPT.repository, "manifest.producer.repository");
  exactString(value.releaseTag, REPOSITORY_REPAIR_TRANSCRIPT.releaseTag, "manifest.producer.releaseTag");
  exactString(value.releaseUrl, REPOSITORY_REPAIR_TRANSCRIPT.releaseUrl, "manifest.producer.releaseUrl");
  exactString(value.commit, REPOSITORY_REPAIR_TRANSCRIPT.commit, "manifest.producer.commit");
}

export function validateRepositoryRepairTranscriptManifest(manifest) {
  exactKeys(
    manifest,
    ["format", "producer", "boundary", "payload", "artifacts", "transcript", "receipt"],
    "manifest",
  );
  exactString(manifest.format, "agent-repository-repair-process-transcript/v1", "manifest.format");
  validateProducer(manifest.producer);
  validateBoundary(manifest.boundary);

  exactKeys(manifest.payload, ["assetName", "sha256", "byteLength"], "manifest.payload");
  exactString(manifest.payload.assetName, REPOSITORY_REPAIR_TRANSCRIPT.payloadAssetName, "manifest.payload.assetName");
  const payloadByteLength = safeInteger(manifest.payload.byteLength, 1, MAX_PAYLOAD_BYTES, "manifest.payload.byteLength");
  const payloadSha256 = digest(manifest.payload.sha256, "manifest.payload.sha256");
  if (
    payloadByteLength !== REPOSITORY_REPAIR_TRANSCRIPT.payloadByteLength ||
    payloadSha256 !== REPOSITORY_REPAIR_TRANSCRIPT.payloadSha256
  ) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", "manifest.payload does not identify the exact Agent v2.7.0 transcript", {
      expectedByteLength: REPOSITORY_REPAIR_TRANSCRIPT.payloadByteLength,
      observedByteLength: payloadByteLength,
      expectedSha256: REPOSITORY_REPAIR_TRANSCRIPT.payloadSha256,
      observedSha256: payloadSha256,
    });
  }
  const artifactTable = validateArtifactTable(manifest.artifacts, payloadByteLength, "manifest.artifacts");
  const usedArtifacts = new Set();

  exactKeys(
    manifest.transcript,
    [
      "programImage",
      "initialArgs",
      "reductionCount",
      "residualBoundaryCount",
      "expectedOutcomes",
      "requests",
      "effectResults",
      "transferAfterBoundary",
      "terminal",
    ],
    "manifest.transcript",
  );
  const programImage = artifactReference(
    manifest.transcript.programImage,
    artifactTable.byId,
    "manifest.transcript.programImage",
    usedArtifacts,
  );
  const programArtifact = artifactTable.byId.get(programImage);
  if (
    programArtifact.sha256 !== REPOSITORY_REPAIR_TRANSCRIPT.programImageSha256 ||
    programArtifact.byteLength !== REPOSITORY_REPAIR_TRANSCRIPT.programImageByteLength
  ) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", "transcript does not contain the exact landed repository-repair BPI1", {
      expectedSha256: REPOSITORY_REPAIR_TRANSCRIPT.programImageSha256,
      observedSha256: programArtifact.sha256,
      expectedByteLength: REPOSITORY_REPAIR_TRANSCRIPT.programImageByteLength,
      observedByteLength: programArtifact.byteLength,
    });
  }
  const initialArgs = artifactReference(
    manifest.transcript.initialArgs,
    artifactTable.byId,
    "manifest.transcript.initialArgs",
    usedArtifacts,
  );
  if (manifest.transcript.reductionCount !== REPOSITORY_REPAIR_TRANSCRIPT.reductionCount) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INCOMPLETE", "repository-repair transcript must contain all 96 reductions", {
      observed: manifest.transcript.reductionCount,
    });
  }
  if (manifest.transcript.residualBoundaryCount !== REPOSITORY_REPAIR_TRANSCRIPT.residualBoundaryCount) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INCOMPLETE", "repository-repair transcript must contain all 17 residual boundaries", {
      observed: manifest.transcript.residualBoundaryCount,
    });
  }

  if (
    !Array.isArray(manifest.transcript.expectedOutcomes) ||
    manifest.transcript.expectedOutcomes.length !== REPOSITORY_REPAIR_TRANSCRIPT.reductionCount
  ) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INCOMPLETE", "expectedOutcomes must contain one exact outcome per reduction");
  }
  const expectedOutcomes = manifest.transcript.expectedOutcomes.map((entry, index) => {
    const label = `manifest.transcript.expectedOutcomes[${index}]`;
    exactKeys(entry, ["reductionIndex", "kind", "artifact"], label);
    if (entry.reductionIndex !== index || !OUTCOME_KINDS.has(entry.kind)) {
      fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", `${label} has an invalid index or kind`, {
        expectedIndex: index,
        observedIndex: entry.reductionIndex,
        kind: entry.kind,
      });
    }
    return Object.freeze({
      reductionIndex: index,
      kind: entry.kind,
      artifact: artifactReference(entry.artifact, artifactTable.byId, `${label}.artifact`, usedArtifacts),
    });
  });

  if (!Array.isArray(manifest.transcript.requests) || manifest.transcript.requests.length !== 17) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INCOMPLETE", "requests must contain all 17 residual request records");
  }
  const requests = manifest.transcript.requests.map((entry, index) => {
    const label = `manifest.transcript.requests[${index}]`;
    exactKeys(entry, ["boundaryIndex", "reductionIndex", "artifact"], label);
    if (entry.boundaryIndex !== index) {
      fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", `${label}.boundaryIndex must be contiguous`, { expected: index });
    }
    const reductionIndex = safeInteger(entry.reductionIndex, 0, 95, `${label}.reductionIndex`);
    if (expectedOutcomes[reductionIndex].kind !== "Requested") {
      fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", `${label} does not point to a Requested outcome`, { reductionIndex });
    }
    if (index > 0 && reductionIndex <= manifest.transcript.requests[index - 1].reductionIndex) {
      fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", "request reductions must be strictly increasing", { boundaryIndex: index });
    }
    return Object.freeze({
      boundaryIndex: index,
      reductionIndex,
      artifact: artifactReference(entry.artifact, artifactTable.byId, `${label}.artifact`, usedArtifacts),
    });
  });
  const requestedReductionCount = expectedOutcomes.filter((entry) => entry.kind === "Requested").length;
  if (requestedReductionCount !== 17) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INCOMPLETE", "expected outcomes must contain exactly 17 Requested reductions", {
      observed: requestedReductionCount,
    });
  }

  if (!Array.isArray(manifest.transcript.effectResults) || manifest.transcript.effectResults.length !== 17) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INCOMPLETE", "effectResults must contain all 17 canonical ABL_ERS1 records");
  }
  const effectResults = manifest.transcript.effectResults.map((entry, index) => {
    const label = `manifest.transcript.effectResults[${index}]`;
    exactKeys(entry, ["boundaryIndex", "artifact"], label);
    if (entry.boundaryIndex !== index) {
      fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", `${label}.boundaryIndex must be contiguous`, { expected: index });
    }
    return Object.freeze({
      boundaryIndex: index,
      artifact: artifactReference(entry.artifact, artifactTable.byId, `${label}.artifact`, usedArtifacts),
    });
  });
  const transferAfterBoundary = safeInteger(
    manifest.transcript.transferAfterBoundary,
    1,
    16,
    "manifest.transcript.transferAfterBoundary",
  );

  exactKeys(manifest.transcript.terminal, ["reductionIndex", "kind", "outcomeArtifact", "resultSha256"], "manifest.transcript.terminal");
  if (manifest.transcript.terminal.reductionIndex !== 95 || manifest.transcript.terminal.kind !== "Completed") {
    fail("WORLD_TRANSCRIPT_MANIFEST_INCOMPLETE", "transcript must terminate as Completed at reduction 95");
  }
  const terminalOutcome = artifactReference(
    manifest.transcript.terminal.outcomeArtifact,
    artifactTable.byId,
    "manifest.transcript.terminal.outcomeArtifact",
    usedArtifacts,
  );
  if (terminalOutcome !== expectedOutcomes[95].artifact || expectedOutcomes[95].kind !== "Completed") {
    fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", "terminal outcome does not match expected reduction 95");
  }
  const terminalResultSha256 = digest(manifest.transcript.terminal.resultSha256, "manifest.transcript.terminal.resultSha256");

  exactKeys(
    manifest.receipt,
    [
      "format",
      "programImageSha256",
      "reductionCount",
      "residualBoundaryCount",
      "freshWasmInstanceCount",
      "terminalResultSha256",
    ],
    "manifest.receipt",
  );
  exactString(manifest.receipt.format, "agent-repository-repair-process-transcript-receipt/v1", "manifest.receipt.format");
  exactString(manifest.receipt.programImageSha256, REPOSITORY_REPAIR_TRANSCRIPT.programImageSha256, "manifest.receipt.programImageSha256");
  exactString(manifest.receipt.terminalResultSha256, terminalResultSha256, "manifest.receipt.terminalResultSha256");
  if (
    manifest.receipt.reductionCount !== 96 ||
    manifest.receipt.residualBoundaryCount !== 17 ||
    manifest.receipt.freshWasmInstanceCount !== 97
  ) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INCOMPLETE", "transcript receipt counts do not prove the complete landed replay", {
      receipt: manifest.receipt,
    });
  }

  const unusedArtifacts = artifactTable.ordered.map((artifact) => artifact.id).filter((id) => !usedArtifacts.has(id));
  if (unusedArtifacts.length !== 0) {
    fail("WORLD_TRANSCRIPT_MANIFEST_INVALID", "transcript payload contains unreferenced artifacts", { unusedArtifacts });
  }

  return Object.freeze({
    manifest,
    payload: Object.freeze({
      assetName: REPOSITORY_REPAIR_TRANSCRIPT.payloadAssetName,
      sha256: payloadSha256,
      byteLength: payloadByteLength,
    }),
    artifacts: artifactTable,
    transcript: Object.freeze({
      programImage,
      initialArgs,
      reductionCount: 96,
      residualBoundaryCount: 17,
      expectedOutcomes: Object.freeze(expectedOutcomes),
      requests: Object.freeze(requests),
      effectResults: Object.freeze(effectResults),
      transferAfterBoundary,
      terminal: Object.freeze({
        reductionIndex: 95,
        kind: "Completed",
        outcomeArtifact: terminalOutcome,
        resultSha256: terminalResultSha256,
      }),
    }),
    receipt: Object.freeze({
      reductionCount: 96,
      residualBoundaryCount: 17,
      freshWasmInstanceCount: 97,
      terminalResultSha256,
    }),
  });
}

function transcriptLock(validated, manifestSha256) {
  const artifactPath = (id) => `artifacts/${id}`;
  return {
    format: "world-repository-repair-process-transcript-lock/v1",
    status: "locked",
    producer: { ...validated.manifest.producer },
    boundary: { ...validated.manifest.boundary },
    manifest: {
      assetName: REPOSITORY_REPAIR_TRANSCRIPT.manifestAssetName,
      sha256: manifestSha256,
    },
    payload: { ...validated.payload },
    receipt: { ...validated.receipt },
    artifacts: validated.artifacts.ordered.map((artifact) => ({
      id: artifact.id,
      path: artifactPath(artifact.id),
      byteLength: artifact.byteLength,
      sha256: artifact.sha256,
    })),
    transcript: {
      programImagePath: artifactPath(validated.transcript.programImage),
      initialArgsPath: artifactPath(validated.transcript.initialArgs),
      reductionCount: validated.transcript.reductionCount,
      residualBoundaryCount: validated.transcript.residualBoundaryCount,
      expectedOutcomes: validated.transcript.expectedOutcomes.map((entry) => ({
        reductionIndex: entry.reductionIndex,
        kind: entry.kind,
        path: artifactPath(entry.artifact),
      })),
      requests: validated.transcript.requests.map((entry) => ({
        boundaryIndex: entry.boundaryIndex,
        reductionIndex: entry.reductionIndex,
        path: artifactPath(entry.artifact),
      })),
      effectResults: validated.transcript.effectResults.map((entry) => ({
        boundaryIndex: entry.boundaryIndex,
        path: artifactPath(entry.artifact),
      })),
      transferAfterBoundary: validated.transcript.transferAfterBoundary,
      terminal: {
        reductionIndex: 95,
        kind: "Completed",
        outcomePath: artifactPath(validated.transcript.terminal.outcomeArtifact),
        resultSha256: validated.transcript.terminal.resultSha256,
      },
    },
  };
}

export async function acquireRepositoryRepairTranscript({
  destination = resolve("conformance/repository-repair-transcript/data"),
  lockPath = resolve("conformance/repository-repair-transcript/lock.json"),
  fetchImpl = fetch,
} = {}) {
  await assertConformanceAcquisitionCustody({
    destination,
    lockPath,
    label: "repository-repair transcript acquisition",
  });
  const release = await fetchGitHubJson(
    fetchImpl,
    `https://api.github.com/repos/${REPOSITORY_REPAIR_TRANSCRIPT.repository}/releases/tags/${REPOSITORY_REPAIR_TRANSCRIPT.releaseTag}`,
  );
  const releaseAssets = Array.isArray(release?.assets) ? release.assets : [];
  const releaseIdentityMatches =
    release?.draft === false &&
    release?.tag_name === REPOSITORY_REPAIR_TRANSCRIPT.releaseTag &&
    release?.html_url === REPOSITORY_REPAIR_TRANSCRIPT.releaseUrl;
  const hasManifestAsset = releaseAssets.some((asset) => asset.name === REPOSITORY_REPAIR_TRANSCRIPT.manifestAssetName);
  if (!releaseIdentityMatches || !hasManifestAsset) {
    fail(
      "WORLD_REPOSITORY_REPAIR_TRANSCRIPT_MISSING",
      "Agent does not publish the immutable Boundary-1.7-bound repository-repair Process transcript required by World",
      {
        repository: REPOSITORY_REPAIR_TRANSCRIPT.repository,
        requiredAssets: [
          REPOSITORY_REPAIR_TRANSCRIPT.manifestAssetName,
          REPOSITORY_REPAIR_TRANSCRIPT.payloadAssetName,
        ],
        observedRelease: {
          tag: release?.tag_name ?? null,
          url: release?.html_url ?? null,
          assets: releaseAssets.map((asset) => asset.name).sort(),
        },
        requiredProgramImageSha256: REPOSITORY_REPAIR_TRANSCRIPT.programImageSha256,
        requiredBoundaryKernelSha256: BOUNDARY_PROCESS_PROOF.kernelSha256,
        remedy:
          "Land and publish an Agent release asset containing the exact BPI1, InitialArgs, 96 PKO1 outcomes, 17 ERQ1 requests, and 17 ERS1 results bound to Boundary v1.7.0.",
      },
    );
  }
  const assets = releaseAssets;
  const manifestAsset = assets.find((asset) => asset.name === REPOSITORY_REPAIR_TRANSCRIPT.manifestAssetName);
  const manifestBytes = await fetchGitHubAssetBytes(fetchImpl, manifestAsset, MAX_MANIFEST_BYTES);
  const manifestSha256 = sha256Hex(manifestBytes);
  if (manifestSha256 !== REPOSITORY_REPAIR_TRANSCRIPT.manifestSha256) {
    fail("WORLD_CONFORMANCE_RELEASE_INVALID", "Agent transcript manifest differs from the authenticated release asset", {
      expected: REPOSITORY_REPAIR_TRANSCRIPT.manifestSha256,
      observed: manifestSha256,
    });
  }
  const validated = validateRepositoryRepairTranscriptManifest(parseManifestBytes(manifestBytes, manifestAsset.name));
  if (release.tag_name !== validated.manifest.producer.releaseTag || release.html_url !== validated.manifest.producer.releaseUrl) {
    fail("WORLD_CONFORMANCE_RELEASE_INVALID", "Agent transcript manifest is not bound to its containing release", {
      releaseTag: release.tag_name,
      manifestTag: validated.manifest.producer.releaseTag,
      releaseUrl: release.html_url,
      manifestUrl: validated.manifest.producer.releaseUrl,
    });
  }
  const tagCommit = await resolveGitHubTagCommit(
    fetchImpl,
    REPOSITORY_REPAIR_TRANSCRIPT.repository,
    REPOSITORY_REPAIR_TRANSCRIPT.releaseTag,
  );
  if (tagCommit !== REPOSITORY_REPAIR_TRANSCRIPT.commit) {
    fail("WORLD_CONFORMANCE_RELEASE_INVALID", "Agent transcript release tag does not resolve to its declared commit", {
      expected: REPOSITORY_REPAIR_TRANSCRIPT.commit,
      observed: tagCommit,
    });
  }
  const payloadAsset = assets.find((asset) => asset.name === validated.payload.assetName);
  if (!payloadAsset) {
    fail("WORLD_REPOSITORY_REPAIR_TRANSCRIPT_MISSING", "Agent transcript manifest has no matching payload asset", {
      releaseUrl: release.html_url,
      requiredAsset: validated.payload.assetName,
      observedAssets: assets.map((asset) => asset.name).sort(),
    });
  }
  if (payloadAsset.size !== validated.payload.byteLength || payloadAsset.digest !== `sha256:${validated.payload.sha256}`) {
    fail("WORLD_CONFORMANCE_RELEASE_INVALID", "Agent transcript payload metadata does not match its manifest", {
      asset: payloadAsset.name,
      manifestByteLength: validated.payload.byteLength,
      releaseByteLength: payloadAsset.size,
      manifestDigest: `sha256:${validated.payload.sha256}`,
      releaseDigest: payloadAsset.digest ?? null,
    });
  }
  const payloadBytes = await fetchGitHubAssetBytes(fetchImpl, payloadAsset, MAX_PAYLOAD_BYTES);
  const files = validateBundlePayload(validated, payloadBytes);
  await materializeExactFiles(destination, files);
  const lock = transcriptLock(validated, manifestSha256);
  const lockSha256 = sha256Hex(canonicalJsonBytes(lock));
  if (lockSha256 !== REPOSITORY_REPAIR_TRANSCRIPT.lockSha256) {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", "repository-repair transcript lock projection differs from the checked-in lock", {
      expected: REPOSITORY_REPAIR_TRANSCRIPT.lockSha256,
      observed: lockSha256,
    });
  }
  await writeJsonAtomic(lockPath, lock);
  return Object.freeze({
    status: "locked",
    lockPath,
    destination,
    producerTag: validated.manifest.producer.releaseTag,
    producerCommit: validated.manifest.producer.commit,
    manifestSha256,
    payloadSha256: validated.payload.sha256,
    reductionCount: 96,
    residualBoundaryCount: 17,
  });
}

function parseCli(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--destination" || argument === "--lock") {
      const value = argv[index + 1];
      if (!value) fail("WORLD_CONFORMANCE_USAGE", `${argument} requires a path`);
      options[argument === "--destination" ? "destination" : "lockPath"] = resolve(value);
      index += 1;
    } else if (argument === "--help") {
      return { help: true };
    } else {
      fail("WORLD_CONFORMANCE_USAGE", `unknown argument ${argument}`, { argument });
    }
  }
  return options;
}

export async function main(argv = process.argv.slice(2)) {
  const options = parseCli(argv);
  if (options.help) {
    process.stdout.write(
      "usage: bun scripts/acquire_repository_repair_transcript.mjs [--destination PATH] [--lock PATH]\n",
    );
    return;
  }
  const result = await acquireRepositoryRepairTranscript(options);
  process.stdout.write(`${JSON.stringify({ ok: true, format: "world-conformance-acquisition-result/v1", ...result })}\n`);
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
if (isMain) {
  main().catch((error) => {
    process.stderr.write(`${JSON.stringify(conformanceErrorRecord(error))}\n`);
    process.exitCode = 1;
  });
}
