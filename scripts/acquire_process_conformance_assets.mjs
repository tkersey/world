#!/usr/bin/env bun

import { createHash, randomUUID } from "node:crypto";
import {
  access,
  lstat,
  mkdir,
  readFile,
  readdir,
  rename,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { basename, dirname, join, relative, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";

import { canonicalFuturePathIdentity } from "./build_runtime_archive.mjs";

export const BOUNDARY_PROCESS_PROOF = Object.freeze({
  repository: "tkersey/boundary",
  releaseTag: "v1.7.0",
  releaseUrl: "https://github.com/tkersey/boundary/releases/tag/v1.7.0",
  commit: "4fd4cd959ea283a6b5af12a228f0d80a102683e3",
  version: "1.7.0",
  kernelSha256: "178f9c2fb79402a85ab5a7905586879347ad5c99f988127eec001c9ecfd813f0",
  kernelByteLength: 647_473,
  processKernelAbiVersion: 1,
  manifestAssetName: "boundary-process-v1-conformance-corpus.json",
  manifestSha256: "5ef2fb9fc3667ce97eae74d5bf9b635da46596fd7f0b3e68a04a43b24b7bb331",
  payloadAssetName: "boundary-process-v1-conformance-corpus.bin",
  payloadSha256: "17a74f8adfdd7fe9aced05d01fe0432f7ad6720b69cf353bc57a695378bb527f",
  payloadByteLength: 33_578_193,
  lockSha256: "74c1a2c1bb998499db4e85da04f2f8ea3d13a9422d81b7023ba0f6b9f44b5fcb",
});

export const BOUNDARY_REQUIRED_SCENARIOS = Object.freeze([
  "initial-progress",
  "ordinary-progress",
  "typed-residual-effect",
  "effect-morphism",
  "recursive-call-return",
  "explicit-yield",
  "completion",
  "authored-failure-v1",
  "authored-failure-v2",
  "pending-request-reconstruction",
  "typed-resume",
  "needs-capacity",
  "non-agent",
]);

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
const MAX_ARTIFACTS = 4096;
const MAX_VECTORS = 1024;
const IDENTIFIER_PATTERN = /^[a-z0-9][a-z0-9._-]{0,127}$/;
const DIGEST_PATTERN = /^[0-9a-f]{64}$/;

export class ConformanceAcquisitionError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = "ConformanceAcquisitionError";
    this.code = code;
    this.details = Object.freeze({ ...details });
  }
}

export function sha256Hex(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

export function canonicalJsonBytes(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function fail(code, message, details = {}) {
  throw new ConformanceAcquisitionError(code, message, details);
}

function identityContains(root, candidate) {
  const prefix = root.endsWith("/") ? root : `${root}/`;
  return candidate === root || candidate.startsWith(prefix);
}

async function canonicalOutputPathIdentity(path) {
  const resolved = resolve(path);
  const parentIdentity = await canonicalFuturePathIdentity(dirname(resolved));
  const prefix = parentIdentity.endsWith("/") ? parentIdentity : `${parentIdentity}/`;
  return `${prefix}${basename(resolved).normalize("NFC").toLowerCase()}`;
}

export async function assertConformanceAcquisitionCustody({
  destination,
  lockPath,
  label = "conformance acquisition",
  outputLabel = "lock output",
}) {
  const destinationIdentity = await canonicalFuturePathIdentity(destination);
  const lockIdentities = new Set([
    await canonicalFuturePathIdentity(lockPath),
    await canonicalOutputPathIdentity(lockPath),
  ]);
  if ([...lockIdentities].some((identity) => identityContains(destinationIdentity, identity))) {
    fail(
      "WORLD_CONFORMANCE_DESTINATION_CONFLICT",
      `${label} ${outputLabel} must be physically distinct from the destination artifact namespace`,
      { destination, lockPath },
    );
  }
}

export function validateBoundaryProcessReleaseIdentity(release) {
  if (
    release?.draft !== false ||
    release?.tag_name !== BOUNDARY_PROCESS_PROOF.releaseTag ||
    release?.html_url !== BOUNDARY_PROCESS_PROOF.releaseUrl
  ) {
    fail("WORLD_CONFORMANCE_RELEASE_INVALID", "Boundary Process corpus is not contained in the exact published v1.7.0 release", {
      expected: {
        draft: false,
        tag: BOUNDARY_PROCESS_PROOF.releaseTag,
        url: BOUNDARY_PROCESS_PROOF.releaseUrl,
      },
      observed: {
        draft: release?.draft ?? null,
        tag: release?.tag_name ?? null,
        url: release?.html_url ?? null,
      },
    });
  }
  return release;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, required, optional, label) {
  if (!isPlainObject(value)) fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} must be an object`, { label });
  const allowed = new Set([...required, ...optional]);
  for (const key of required) {
    if (!Object.hasOwn(value, key)) {
      fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} is missing ${key}`, { label, key });
    }
  }
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} has unexpected field ${key}`, { label, key });
    }
  }
}

function exactString(value, expected, label) {
  if (value !== expected) {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} does not match the locked value`, {
      label,
      expected,
      observed: value,
    });
  }
}

function nonemptyString(value, label, maximum = 1024) {
  if (typeof value !== "string" || value.length === 0 || value.length > maximum || value.includes("\0")) {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} must be a bounded nonempty string`, { label });
  }
  return value;
}

function digest(value, label) {
  if (typeof value !== "string" || !DIGEST_PATTERN.test(value)) {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} must be a lowercase SHA-256 digest`, { label });
  }
  return value;
}

function safeInteger(value, minimum, maximum, label) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} is outside its admitted range`, {
      label,
      minimum,
      maximum,
      observed: value,
    });
  }
  return value;
}

function identifier(value, label) {
  if (typeof value !== "string" || !IDENTIFIER_PATTERN.test(value)) {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} is not a canonical identifier`, { label });
  }
  return value;
}

export function parseManifestBytes(bytes, label = "manifest") {
  if (!(bytes instanceof Uint8Array) || bytes.byteLength === 0 || bytes.byteLength > MAX_MANIFEST_BYTES) {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} has an invalid byte length`, {
      label,
      byteLength: bytes?.byteLength,
      maximum: MAX_MANIFEST_BYTES,
    });
  }
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} is not valid UTF-8`, { label });
  }
  try {
    return JSON.parse(text);
  } catch {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} is not valid JSON`, { label });
  }
}

function validateBoundaryIdentity(value) {
  exactKeys(
    value,
    ["version", "commit", "processKernelAbiVersion", "kernelSha256", "kernelByteLength"],
    [],
    "manifest.boundary",
  );
  exactString(value.version, BOUNDARY_PROCESS_PROOF.version, "manifest.boundary.version");
  exactString(value.commit, BOUNDARY_PROCESS_PROOF.commit, "manifest.boundary.commit");
  exactString(value.kernelSha256, BOUNDARY_PROCESS_PROOF.kernelSha256, "manifest.boundary.kernelSha256");
  if (value.processKernelAbiVersion !== BOUNDARY_PROCESS_PROOF.processKernelAbiVersion) {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", "manifest.boundary.processKernelAbiVersion must be 1");
  }
  if (value.kernelByteLength !== BOUNDARY_PROCESS_PROOF.kernelByteLength) {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", "manifest.boundary.kernelByteLength does not match Boundary v1.7.0");
  }
}

function validateProducer(value) {
  exactKeys(value, ["repository", "releaseTag", "releaseUrl", "commit"], [], "manifest.producer");
  exactString(value.repository, BOUNDARY_PROCESS_PROOF.repository, "manifest.producer.repository");
  exactString(value.releaseTag, BOUNDARY_PROCESS_PROOF.releaseTag, "manifest.producer.releaseTag");
  exactString(value.releaseUrl, BOUNDARY_PROCESS_PROOF.releaseUrl, "manifest.producer.releaseUrl");
  exactString(value.commit, BOUNDARY_PROCESS_PROOF.commit, "manifest.producer.commit");
}

export function validateArtifactTable(artifacts, payloadByteLength, label = "manifest.artifacts") {
  if (!Array.isArray(artifacts) || artifacts.length === 0 || artifacts.length > MAX_ARTIFACTS) {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} must contain 1..${MAX_ARTIFACTS} artifacts`, { label });
  }
  const byId = new Map();
  const ordered = [];
  for (let index = 0; index < artifacts.length; index += 1) {
    const artifact = artifacts[index];
    const artifactLabel = `${label}[${index}]`;
    exactKeys(artifact, ["id", "offset", "byteLength", "sha256"], [], artifactLabel);
    const id = identifier(artifact.id, `${artifactLabel}.id`);
    if (byId.has(id)) fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} contains duplicate artifact id ${id}`, { id });
    const offset = safeInteger(artifact.offset, 0, payloadByteLength, `${artifactLabel}.offset`);
    const byteLength = safeInteger(artifact.byteLength, 0, payloadByteLength, `${artifactLabel}.byteLength`);
    if (offset + byteLength > payloadByteLength) {
      fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${artifactLabel} exceeds the payload`, { id, offset, byteLength });
    }
    const normalized = Object.freeze({ id, offset, byteLength, sha256: digest(artifact.sha256, `${artifactLabel}.sha256`) });
    byId.set(id, normalized);
    ordered.push(normalized);
  }
  ordered.sort((left, right) => left.offset - right.offset || left.id.localeCompare(right.id));
  let cursor = 0;
  for (const artifact of ordered) {
    if (artifact.offset !== cursor) {
      fail("WORLD_CONFORMANCE_MANIFEST_INVALID", "artifact slices must partition the payload without gaps or overlap", {
        artifact: artifact.id,
        expectedOffset: cursor,
        observedOffset: artifact.offset,
      });
    }
    cursor += artifact.byteLength;
  }
  if (cursor !== payloadByteLength) {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", "artifact slices do not cover the complete payload", {
      coveredBytes: cursor,
      payloadByteLength,
    });
  }
  return Object.freeze({ byId, ordered: Object.freeze(ordered) });
}

function artifactReference(value, artifacts, label) {
  const id = identifier(value, label);
  if (!artifacts.has(id)) fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} names an unknown artifact`, { label, id });
  return id;
}

export function validateBoundaryProcessCorpusManifest(manifest) {
  exactKeys(
    manifest,
    ["format", "producer", "boundary", "payload", "artifacts", "vectors", "receipt"],
    [],
    "manifest",
  );
  exactString(manifest.format, "boundary-process-v1-conformance-corpus/v1", "manifest.format");
  validateProducer(manifest.producer);
  validateBoundaryIdentity(manifest.boundary);

  exactKeys(manifest.payload, ["assetName", "sha256", "byteLength"], [], "manifest.payload");
  exactString(manifest.payload.assetName, BOUNDARY_PROCESS_PROOF.payloadAssetName, "manifest.payload.assetName");
  const payloadByteLength = safeInteger(manifest.payload.byteLength, 1, MAX_PAYLOAD_BYTES, "manifest.payload.byteLength");
  const payloadSha256 = digest(manifest.payload.sha256, "manifest.payload.sha256");
  if (
    payloadByteLength !== BOUNDARY_PROCESS_PROOF.payloadByteLength ||
    payloadSha256 !== BOUNDARY_PROCESS_PROOF.payloadSha256
  ) {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", "manifest.payload does not identify the exact Boundary v1.7.0 corpus", {
      expectedByteLength: BOUNDARY_PROCESS_PROOF.payloadByteLength,
      observedByteLength: payloadByteLength,
      expectedSha256: BOUNDARY_PROCESS_PROOF.payloadSha256,
      observedSha256: payloadSha256,
    });
  }
  const artifactTable = validateArtifactTable(manifest.artifacts, payloadByteLength);

  if (!Array.isArray(manifest.vectors) || manifest.vectors.length === 0 || manifest.vectors.length > MAX_VECTORS) {
    fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `manifest.vectors must contain 1..${MAX_VECTORS} vectors`);
  }
  const scenarioSet = new Set();
  const vectorIds = new Set();
  const vectors = manifest.vectors.map((vector, index) => {
    const label = `manifest.vectors[${index}]`;
    exactKeys(
      vector,
      [
        "id",
        "scenarios",
        "image",
        "instance",
        "effectResult",
        "expectedOutcome",
        "expectedKind",
        "nativeOutcomeSha256",
        "kernelOutcomeSha256",
      ],
      [],
      label,
    );
    const id = identifier(vector.id, `${label}.id`);
    if (vectorIds.has(id)) fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `duplicate vector id ${id}`, { id });
    vectorIds.add(id);
    if (!Array.isArray(vector.scenarios) || vector.scenarios.length === 0 || new Set(vector.scenarios).size !== vector.scenarios.length) {
      fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label}.scenarios must be a nonempty unique array`, { id });
    }
    for (const scenario of vector.scenarios) {
      if (!BOUNDARY_REQUIRED_SCENARIOS.includes(scenario)) {
        fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label}.scenarios contains unknown scenario ${scenario}`, { id, scenario });
      }
      scenarioSet.add(scenario);
    }
    exactKeys(vector.instance, ["kind", "artifact"], [], `${label}.instance`);
    if (vector.instance.kind !== "initialArgs" && vector.instance.kind !== "state") {
      fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label}.instance.kind is invalid`, { id });
    }
    if (vector.effectResult !== null && typeof vector.effectResult !== "string") {
      fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label}.effectResult must be null or an artifact id`, { id });
    }
    if (!OUTCOME_KINDS.has(vector.expectedKind)) {
      fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label}.expectedKind is invalid`, { id, expectedKind: vector.expectedKind });
    }
    const expectedOutcome = artifactReference(vector.expectedOutcome, artifactTable.byId, `${label}.expectedOutcome`);
    const expectedDigest = artifactTable.byId.get(expectedOutcome).sha256;
    const nativeOutcomeSha256 = digest(vector.nativeOutcomeSha256, `${label}.nativeOutcomeSha256`);
    const kernelOutcomeSha256 = digest(vector.kernelOutcomeSha256, `${label}.kernelOutcomeSha256`);
    if (nativeOutcomeSha256 !== expectedDigest || kernelOutcomeSha256 !== expectedDigest) {
      fail("WORLD_CONFORMANCE_MANIFEST_INVALID", `${label} does not prove byte-identical native/kernel output`, {
        id,
        expectedDigest,
        nativeOutcomeSha256,
        kernelOutcomeSha256,
      });
    }
    return Object.freeze({
      id,
      scenarios: Object.freeze([...vector.scenarios]),
      image: artifactReference(vector.image, artifactTable.byId, `${label}.image`),
      instance: Object.freeze({
        kind: vector.instance.kind,
        artifact: artifactReference(vector.instance.artifact, artifactTable.byId, `${label}.instance.artifact`),
      }),
      effectResult:
        vector.effectResult === null
          ? null
          : artifactReference(vector.effectResult, artifactTable.byId, `${label}.effectResult`),
      expectedOutcome,
      expectedKind: vector.expectedKind,
      nativeOutcomeSha256,
      kernelOutcomeSha256,
    });
  });
  const missingScenarios = BOUNDARY_REQUIRED_SCENARIOS.filter((scenario) => !scenarioSet.has(scenario));
  if (missingScenarios.length !== 0) {
    fail("WORLD_CONFORMANCE_MANIFEST_INCOMPLETE", "Boundary corpus omits required Process scenarios", {
      missingScenarios,
    });
  }

  exactKeys(
    manifest.receipt,
    ["format", "vectorCount", "nativeKernelParityCount", "needsCapacityVectorId", "nonAgentVectorId"],
    [],
    "manifest.receipt",
  );
  exactString(manifest.receipt.format, "boundary-process-v1-parity-receipt/v1", "manifest.receipt.format");
  if (manifest.receipt.vectorCount !== vectors.length || manifest.receipt.nativeKernelParityCount !== vectors.length) {
    fail("WORLD_CONFORMANCE_MANIFEST_INCOMPLETE", "Boundary receipt counts do not cover every vector", {
      vectorCount: vectors.length,
      receiptVectorCount: manifest.receipt.vectorCount,
      nativeKernelParityCount: manifest.receipt.nativeKernelParityCount,
    });
  }
  const needsCapacityVectorId = identifier(manifest.receipt.needsCapacityVectorId, "manifest.receipt.needsCapacityVectorId");
  const nonAgentVectorId = identifier(manifest.receipt.nonAgentVectorId, "manifest.receipt.nonAgentVectorId");
  const byVectorId = new Map(vectors.map((vector) => [vector.id, vector]));
  if (!byVectorId.get(needsCapacityVectorId)?.scenarios.includes("needs-capacity")) {
    fail("WORLD_CONFORMANCE_MANIFEST_INCOMPLETE", "Boundary receipt does not identify the NeedsCapacity vector");
  }
  if (!byVectorId.get(nonAgentVectorId)?.scenarios.includes("non-agent")) {
    fail("WORLD_CONFORMANCE_MANIFEST_INCOMPLETE", "Boundary receipt does not identify the non-Agent vector");
  }

  return Object.freeze({
    manifest,
    payload: Object.freeze({
      assetName: BOUNDARY_PROCESS_PROOF.payloadAssetName,
      sha256: payloadSha256,
      byteLength: payloadByteLength,
    }),
    artifacts: artifactTable,
    vectors: Object.freeze(vectors),
    receipt: Object.freeze({
      vectorCount: vectors.length,
      nativeKernelParityCount: vectors.length,
      needsCapacityVectorId,
      nonAgentVectorId,
    }),
  });
}

export function validateBundlePayload(validated, payloadBytes) {
  if (!(payloadBytes instanceof Uint8Array)) {
    fail("WORLD_CONFORMANCE_PAYLOAD_INVALID", "conformance payload must be bytes");
  }
  if (payloadBytes.byteLength !== validated.payload.byteLength) {
    fail("WORLD_CONFORMANCE_PAYLOAD_INVALID", "conformance payload byte length does not match its manifest", {
      expected: validated.payload.byteLength,
      observed: payloadBytes.byteLength,
    });
  }
  const actualPayloadDigest = sha256Hex(payloadBytes);
  if (actualPayloadDigest !== validated.payload.sha256) {
    fail("WORLD_CONFORMANCE_PAYLOAD_INVALID", "conformance payload digest does not match its manifest", {
      expected: validated.payload.sha256,
      observed: actualPayloadDigest,
    });
  }
  const files = new Map();
  for (const artifact of validated.artifacts.ordered) {
    const bytes = payloadBytes.slice(artifact.offset, artifact.offset + artifact.byteLength);
    const actualDigest = sha256Hex(bytes);
    if (actualDigest !== artifact.sha256) {
      fail("WORLD_CONFORMANCE_PAYLOAD_INVALID", `artifact ${artifact.id} digest mismatch`, {
        artifact: artifact.id,
        expected: artifact.sha256,
        observed: actualDigest,
      });
    }
    files.set(artifact.id, bytes);
  }
  return files;
}

function apiHeaders() {
  const headers = {
    Accept: "application/vnd.github+json",
    "User-Agent": "world-process-host-v1-conformance-acquisition",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
}

async function fetchChecked(fetchImpl, url, options = {}) {
  let response;
  try {
    response = await fetchImpl(url, {
      ...options,
      headers: { ...apiHeaders(), ...(options.headers ?? {}) },
      signal: AbortSignal.timeout(30_000),
    });
  } catch (error) {
    fail("WORLD_CONFORMANCE_NETWORK_FAILED", `failed to fetch ${url}`, { url, cause: error?.message ?? String(error) });
  }
  if (!response.ok) {
    fail("WORLD_CONFORMANCE_NETWORK_FAILED", `fetch returned HTTP ${response.status}`, { url, status: response.status });
  }
  return response;
}

export async function fetchGitHubJson(fetchImpl, url) {
  const response = await fetchChecked(fetchImpl, url);
  return response.json();
}

export async function fetchGitHubAssetBytes(fetchImpl, asset, maximumByteLength) {
  if (!asset || typeof asset.browser_download_url !== "string") {
    fail("WORLD_CONFORMANCE_RELEASE_INVALID", "release asset metadata is incomplete");
  }
  if (!Number.isSafeInteger(asset.size) || asset.size < 1 || asset.size > maximumByteLength) {
    fail("WORLD_CONFORMANCE_RELEASE_INVALID", `release asset ${asset.name} has an invalid size`, {
      asset: asset.name,
      size: asset.size,
      maximumByteLength,
    });
  }
  const response = await fetchChecked(fetchImpl, asset.browser_download_url, { headers: { Accept: "application/octet-stream" } });
  if (response.body === null || response.body === undefined) {
    fail("WORLD_CONFORMANCE_NETWORK_FAILED", `release asset ${asset.name} response has no body`);
  }
  const chunks = [];
  let observedByteLength = 0;
  for await (const chunk of response.body) {
    if (!(chunk instanceof Uint8Array)) {
      fail("WORLD_CONFORMANCE_NETWORK_FAILED", `release asset ${asset.name} returned a non-byte body chunk`);
    }
    observedByteLength += chunk.byteLength;
    if (observedByteLength > asset.size || observedByteLength > maximumByteLength) {
      fail("WORLD_CONFORMANCE_RELEASE_INVALID", `release asset ${asset.name} exceeded its admitted byte length during download`, {
        asset: asset.name,
        expected: asset.size,
        observed: observedByteLength,
        maximumByteLength,
      });
    }
    chunks.push(Buffer.from(chunk));
  }
  const bytes = new Uint8Array(Buffer.concat(chunks, observedByteLength));
  if (bytes.byteLength !== asset.size) {
    fail("WORLD_CONFORMANCE_RELEASE_INVALID", `release asset ${asset.name} changed byte length during download`, {
      asset: asset.name,
      expected: asset.size,
      observed: bytes.byteLength,
    });
  }
  const actualDigest = sha256Hex(bytes);
  if (typeof asset.digest !== "string" || asset.digest !== `sha256:${actualDigest}`) {
    fail("WORLD_CONFORMANCE_RELEASE_INVALID", `release asset ${asset.name} lacks a matching GitHub digest`, {
      asset: asset.name,
      apiDigest: asset.digest ?? null,
      downloadedDigest: `sha256:${actualDigest}`,
    });
  }
  return bytes;
}

export async function resolveGitHubTagCommit(fetchImpl, repository, tag) {
  let object = (
    await fetchGitHubJson(fetchImpl, `https://api.github.com/repos/${repository}/git/ref/tags/${encodeURIComponent(tag)}`)
  ).object;
  for (let depth = 0; depth < 8; depth += 1) {
    if (!object || typeof object.sha !== "string" || typeof object.type !== "string") {
      fail("WORLD_CONFORMANCE_RELEASE_INVALID", `tag ${tag} has invalid GitHub metadata`, { repository, tag });
    }
    if (object.type === "commit") return object.sha;
    if (object.type !== "tag") {
      fail("WORLD_CONFORMANCE_RELEASE_INVALID", `tag ${tag} does not resolve to a commit`, {
        repository,
        tag,
        objectType: object.type,
      });
    }
    object = (await fetchGitHubJson(fetchImpl, `https://api.github.com/repos/${repository}/git/tags/${object.sha}`)).object;
  }
  fail("WORLD_CONFORMANCE_RELEASE_INVALID", `tag ${tag} indirection is too deep`, { repository, tag });
}

async function pathExists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function recursiveFiles(root, prefix = "") {
  const result = [];
  for (const entry of await readdir(join(root, prefix), { withFileTypes: true })) {
    const name = prefix === "" ? entry.name : `${prefix}/${entry.name}`;
    if (entry.isDirectory()) result.push(...(await recursiveFiles(root, name)));
    else if (entry.isFile()) result.push(name);
    else fail("WORLD_CONFORMANCE_DESTINATION_CONFLICT", "conformance destination contains a non-regular entry", { path: name });
  }
  return result.sort();
}

export async function materializeExactFiles(destination, files) {
  const desiredNames = [...files.keys()].map((id) => `artifacts/${id}`).sort();
  if (await pathExists(destination)) {
    const destinationStat = await lstat(destination);
    if (!destinationStat.isDirectory()) {
      fail("WORLD_CONFORMANCE_DESTINATION_CONFLICT", "existing conformance destination is not a real directory", {
        destination,
      });
    }
    const observedNames = await recursiveFiles(destination);
    if (JSON.stringify(observedNames) !== JSON.stringify(desiredNames)) {
      fail("WORLD_CONFORMANCE_DESTINATION_CONFLICT", "existing conformance destination inventory differs", {
        destination,
        expected: desiredNames,
        observed: observedNames,
      });
    }
    for (const [id, bytes] of files) {
      const observed = new Uint8Array(await readFile(join(destination, "artifacts", id)));
      if (observed.byteLength !== bytes.byteLength || sha256Hex(observed) !== sha256Hex(bytes)) {
        fail("WORLD_CONFORMANCE_DESTINATION_CONFLICT", `existing artifact ${id} differs`, { destination, artifact: id });
      }
    }
    return;
  }
  const staging = `${destination}.tmp-${randomUUID()}`;
  await mkdir(join(staging, "artifacts"), { recursive: true, mode: 0o755 });
  try {
    for (const [id, bytes] of files) {
      await writeFile(join(staging, "artifacts", id), bytes, { flag: "wx", mode: 0o644 });
    }
    await rename(staging, destination);
  } catch (error) {
    fail("WORLD_CONFORMANCE_WRITE_FAILED", "failed to install conformance files atomically", {
      destination,
      staging,
      cause: error?.message ?? String(error),
    });
  } finally {
    await rm(staging, { recursive: true, force: true });
  }
}

export async function writeJsonAtomic(path, value) {
  const temporary = `${path}.tmp-${randomUUID()}`;
  await mkdir(dirname(path), { recursive: true });
  await writeFile(temporary, canonicalJsonBytes(value), { flag: "wx", mode: 0o644 });
  await rename(temporary, path);
}

export function boundaryProofLock(validated, manifestSha256) {
  const artifactPath = (id) => `artifacts/${id}`;
  return {
    format: "world-boundary-process-proof-lock/v1",
    status: "locked",
    producer: { ...validated.manifest.producer },
    boundary: { ...validated.manifest.boundary },
    manifest: {
      assetName: BOUNDARY_PROCESS_PROOF.manifestAssetName,
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
    vectors: validated.vectors.map((vector) => ({
      id: vector.id,
      scenarios: [...vector.scenarios],
      imagePath: artifactPath(vector.image),
      instance: { kind: vector.instance.kind, path: artifactPath(vector.instance.artifact) },
      effectResultPath: vector.effectResult === null ? null : artifactPath(vector.effectResult),
      expectedOutcomePath: artifactPath(vector.expectedOutcome),
      expectedKind: vector.expectedKind,
      expectedOutcomeSha256: vector.kernelOutcomeSha256,
    })),
  };
}

export async function acquireBoundaryProcessConformanceAssets({
  destination = resolve("conformance/vectors"),
  lockPath = resolve("conformance/boundary-process-proof.lock.json"),
  fetchImpl = fetch,
} = {}) {
  await assertConformanceAcquisitionCustody({
    destination,
    lockPath,
    label: "Boundary Process corpus acquisition",
  });
  const releaseApi = `https://api.github.com/repos/${BOUNDARY_PROCESS_PROOF.repository}/releases/tags/${BOUNDARY_PROCESS_PROOF.releaseTag}`;
  const release = validateBoundaryProcessReleaseIdentity(await fetchGitHubJson(fetchImpl, releaseApi));
  const assets = Array.isArray(release.assets) ? release.assets : [];
  const manifestAsset = assets.find((asset) => asset.name === BOUNDARY_PROCESS_PROOF.manifestAssetName);
  if (!manifestAsset) {
    fail(
      "WORLD_BOUNDARY_PROCESS_CORPUS_MISSING",
      "Boundary v1.7.0 does not publish the consumable Process vector/outcome corpus required by World",
      {
        repository: BOUNDARY_PROCESS_PROOF.repository,
        releaseTag: BOUNDARY_PROCESS_PROOF.releaseTag,
        releaseUrl: BOUNDARY_PROCESS_PROOF.releaseUrl,
        requiredAssets: [BOUNDARY_PROCESS_PROOF.manifestAssetName, BOUNDARY_PROCESS_PROOF.payloadAssetName],
        observedAssets: assets.map((asset) => asset.name).sort(),
        remedy:
          "Publish an immutable Boundary Process v1 corpus manifest and partitioned payload containing native/fixed-kernel expected outcomes for every required scenario.",
      },
    );
  }
  const tagCommit = await resolveGitHubTagCommit(fetchImpl, BOUNDARY_PROCESS_PROOF.repository, BOUNDARY_PROCESS_PROOF.releaseTag);
  if (tagCommit !== BOUNDARY_PROCESS_PROOF.commit) {
    fail("WORLD_CONFORMANCE_RELEASE_INVALID", "Boundary v1.7.0 tag target changed", {
      expected: BOUNDARY_PROCESS_PROOF.commit,
      observed: tagCommit,
    });
  }
  const manifestBytes = await fetchGitHubAssetBytes(fetchImpl, manifestAsset, MAX_MANIFEST_BYTES);
  const manifestSha256 = sha256Hex(manifestBytes);
  if (manifestSha256 !== BOUNDARY_PROCESS_PROOF.manifestSha256) {
    fail("WORLD_CONFORMANCE_RELEASE_INVALID", "Boundary Process corpus manifest differs from the authenticated release asset", {
      expected: BOUNDARY_PROCESS_PROOF.manifestSha256,
      observed: manifestSha256,
    });
  }
  const validated = validateBoundaryProcessCorpusManifest(parseManifestBytes(manifestBytes, manifestAsset.name));
  const payloadAsset = assets.find((asset) => asset.name === validated.payload.assetName);
  if (!payloadAsset) {
    fail("WORLD_BOUNDARY_PROCESS_CORPUS_MISSING", "Boundary Process corpus manifest has no matching payload asset", {
      releaseUrl: BOUNDARY_PROCESS_PROOF.releaseUrl,
      requiredAsset: validated.payload.assetName,
      observedAssets: assets.map((asset) => asset.name).sort(),
    });
  }
  if (payloadAsset.size !== validated.payload.byteLength || payloadAsset.digest !== `sha256:${validated.payload.sha256}`) {
    fail("WORLD_CONFORMANCE_RELEASE_INVALID", "Boundary Process payload metadata does not match its manifest", {
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
  const lock = boundaryProofLock(validated, manifestSha256);
  const lockSha256 = sha256Hex(canonicalJsonBytes(lock));
  if (lockSha256 !== BOUNDARY_PROCESS_PROOF.lockSha256) {
    fail("WORLD_CONFORMANCE_LOCK_INVALID", "Boundary Process proof lock projection differs from the checked-in lock", {
      expected: BOUNDARY_PROCESS_PROOF.lockSha256,
      observed: lockSha256,
    });
  }
  await writeJsonAtomic(lockPath, lock);
  return Object.freeze({
    status: "locked",
    lockPath,
    destination,
    manifestSha256,
    payloadSha256: validated.payload.sha256,
    vectorCount: validated.vectors.length,
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

export function conformanceErrorRecord(error) {
  if (error instanceof ConformanceAcquisitionError) {
    return { ok: false, code: error.code, message: error.message, details: error.details };
  }
  return {
    ok: false,
    code: "WORLD_CONFORMANCE_ACQUISITION_FAILED",
    message: "unexpected conformance acquisition failure",
    details: { cause: error?.message ?? String(error) },
  };
}

export async function main(argv = process.argv.slice(2)) {
  const options = parseCli(argv);
  if (options.help) {
    process.stdout.write("usage: bun scripts/acquire_process_conformance_assets.mjs [--destination PATH] [--lock PATH]\n");
    return;
  }
  const result = await acquireBoundaryProcessConformanceAssets(options);
  process.stdout.write(`${JSON.stringify({ ok: true, format: "world-conformance-acquisition-result/v1", ...result })}\n`);
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
if (isMain) {
  main().catch((error) => {
    process.stderr.write(`${JSON.stringify(conformanceErrorRecord(error))}\n`);
    process.exitCode = 1;
  });
}
