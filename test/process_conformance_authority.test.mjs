import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { lstat, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  BOUNDARY_PROCESS_PROOF,
  canonicalJsonBytes,
  fetchGitHubAssetBytes,
  sha256Hex,
} from "../scripts/acquire_process_conformance_assets.mjs";
import { REPOSITORY_REPAIR_TRANSCRIPT } from "../scripts/acquire_repository_repair_transcript.mjs";
import {
  assertConformanceReceiptCustody,
  cleanRoomEnvironment,
  copyLockedProofSnapshot,
  requireLockedProofs,
} from "../scripts/run_clean_room_conformance.mjs";

const repositoryRoot = new URL("../", import.meta.url).pathname.replace(/\/$/, "");
const boundaryLockPath = join(repositoryRoot, "conformance", "boundary-process-proof.lock.json");
const boundaryRoot = join(repositoryRoot, "conformance", "vectors");
const transcriptLockPath = join(repositoryRoot, "conformance", "repository-repair-transcript", "lock.json");
const transcriptRoot = join(repositoryRoot, "conformance", "repository-repair-transcript", "data");

let temporaryRoot;
let boundaryLock;
let transcriptLock;

beforeAll(async () => {
  temporaryRoot = await mkdtemp(join(tmpdir(), "world-conformance-authority-test-"));
  boundaryLock = JSON.parse(await readFile(boundaryLockPath, "utf8"));
  transcriptLock = JSON.parse(await readFile(transcriptLockPath, "utf8"));
});

afterAll(async () => {
  if (temporaryRoot) await rm(temporaryRoot, { recursive: true, force: true });
});

describe("World conformance proof authority", () => {
  test("binds the checked-in locks to exact authenticated producer projections", async () => {
    expect(sha256Hex(await readFile(boundaryLockPath))).toBe(BOUNDARY_PROCESS_PROOF.lockSha256);
    expect(sha256Hex(await readFile(transcriptLockPath))).toBe(REPOSITORY_REPAIR_TRANSCRIPT.lockSha256);
    expect(boundaryLock.producer).toEqual({
      repository: BOUNDARY_PROCESS_PROOF.repository,
      releaseTag: BOUNDARY_PROCESS_PROOF.releaseTag,
      releaseUrl: BOUNDARY_PROCESS_PROOF.releaseUrl,
      commit: BOUNDARY_PROCESS_PROOF.commit,
    });
    expect(transcriptLock.producer).toEqual({
      repository: REPOSITORY_REPAIR_TRANSCRIPT.repository,
      releaseTag: REPOSITORY_REPAIR_TRANSCRIPT.releaseTag,
      releaseUrl: REPOSITORY_REPAIR_TRANSCRIPT.releaseUrl,
      commit: REPOSITORY_REPAIR_TRANSCRIPT.commit,
    });
  });

  test("rejects a truncated Boundary vector projection before execution", async () => {
    const mutated = structuredClone(boundaryLock);
    mutated.vectors.pop();
    await expect(expectWithBoundaryLock(mutated)).rejects.toMatchObject({ code: "WORLD_CONFORMANCE_LOCK_INVALID" });
  });

  test("rejects a duplicate Boundary vector projection before execution", async () => {
    const mutated = structuredClone(boundaryLock);
    mutated.vectors[1] = structuredClone(mutated.vectors[0]);
    await expect(expectWithBoundaryLock(mutated)).rejects.toMatchObject({ code: "WORLD_CONFORMANCE_LOCK_INVALID" });
  });

  test("rejects a forged Agent producer tuple before execution", async () => {
    const mutated = structuredClone(transcriptLock);
    mutated.producer = {
      ...mutated.producer,
      releaseTag: "v999.0.0",
      releaseUrl: "https://github.com/tkersey/agent/releases/tag/v999.0.0",
      commit: "0".repeat(40),
    };
    const path = join(temporaryRoot, "forged-agent-lock.json");
    await writeFile(path, canonicalJsonBytes(mutated));
    await expect(requireLockedProofs({ boundaryLockPath, boundaryRoot, transcriptLockPath: path, transcriptRoot }))
      .rejects.toMatchObject({ code: "WORLD_CONFORMANCE_LOCK_INVALID" });
  });

  test("rejects symlinked proof roots before reading proof locks", async () => {
    const symlinkedBoundaryRoot = join(temporaryRoot, `boundary-root-${crypto.randomUUID()}`);
    const symlinkedTranscriptRoot = join(temporaryRoot, `transcript-root-${crypto.randomUUID()}`);
    await symlink(boundaryRoot, symlinkedBoundaryRoot, "dir");
    await symlink(transcriptRoot, symlinkedTranscriptRoot, "dir");
    const missingLockPath = join(temporaryRoot, `missing-lock-${crypto.randomUUID()}.json`);

    await expect(requireLockedProofs({
      boundaryLockPath: missingLockPath,
      boundaryRoot: symlinkedBoundaryRoot,
      transcriptLockPath: missingLockPath,
      transcriptRoot,
    })).rejects.toMatchObject({ code: "WORLD_CONFORMANCE_ASSET_INVALID" });
    await expect(requireLockedProofs({
      boundaryLockPath: missingLockPath,
      boundaryRoot,
      transcriptLockPath: missingLockPath,
      transcriptRoot: symlinkedTranscriptRoot,
    })).rejects.toMatchObject({ code: "WORLD_CONFORMANCE_ASSET_INVALID" });
  });

  test("rejects symlinked proof roots before creating a copy destination", async () => {
    const symlinkedBoundaryRoot = join(temporaryRoot, `copy-boundary-root-${crypto.randomUUID()}`);
    const symlinkedTranscriptRoot = join(temporaryRoot, `copy-transcript-root-${crypto.randomUUID()}`);
    await symlink(boundaryRoot, symlinkedBoundaryRoot, "dir");
    await symlink(transcriptRoot, symlinkedTranscriptRoot, "dir");

    for (const [candidateBoundaryRoot, candidateTranscriptRoot] of [
      [symlinkedBoundaryRoot, transcriptRoot],
      [boundaryRoot, symlinkedTranscriptRoot],
    ]) {
      const destinationRoot = join(temporaryRoot, `rejected-proof-copy-${crypto.randomUUID()}`);
      await expect(copyLockedProofSnapshot({
        boundaryLockPath,
        boundaryRoot: candidateBoundaryRoot,
        transcriptLockPath,
        transcriptRoot: candidateTranscriptRoot,
        destinationRoot,
      })).rejects.toMatchObject({ code: "WORLD_CONFORMANCE_ASSET_INVALID" });
      await expect(lstat(destinationRoot)).rejects.toMatchObject({ code: "ENOENT" });
    }
  });

  test("copies admitted proof roots as real directories", async () => {
    const copied = await copyLockedProofSnapshot({
      boundaryLockPath,
      boundaryRoot,
      transcriptLockPath,
      transcriptRoot,
      destinationRoot: join(temporaryRoot, `valid-proof-copy-${crypto.randomUUID()}`),
    });
    const [copiedBoundaryStat, copiedTranscriptStat] = await Promise.all([
      lstat(copied.boundaryRoot),
      lstat(copied.transcriptRoot),
    ]);
    expect(copiedBoundaryStat.isDirectory()).toBe(true);
    expect(copiedBoundaryStat.isSymbolicLink()).toBe(false);
    expect(copiedTranscriptStat.isDirectory()).toBe(true);
    expect(copiedTranscriptStat.isSymbolicLink()).toBe(false);
  });

  test("revalidates the private proof snapshot after copying", async () => {
    const destinationRoot = join(temporaryRoot, `proof-${crypto.randomUUID()}`);
    await expect(
      copyLockedProofSnapshot({
        boundaryLockPath,
        boundaryRoot,
        transcriptLockPath,
        transcriptRoot,
        destinationRoot,
        afterCopy: async ({ boundaryRoot: copiedBoundaryRoot }) => {
          const artifact = boundaryLock.artifacts.find(({ byteLength }) => byteLength > 0);
          const path = join(copiedBoundaryRoot, ...artifact.path.split("/"));
          const bytes = new Uint8Array(await readFile(path));
          bytes[0] ^= 0xff;
          await writeFile(path, bytes);
        },
      }),
    ).rejects.toMatchObject({ code: "WORLD_CONFORMANCE_ASSET_INVALID" });
  });

  test("rejects conformance receipt aliases of proof inputs before execution", async () => {
    const base = join(temporaryRoot, `receipt-custody-${crypto.randomUUID()}`);
    const archivePath = join(base, "runtime.tar.gz");
    const checksumPath = join(base, "runtime.tar.gz.sha256");
    const boundaryArtifact = boundaryLock.artifacts[0];
    const transcriptArtifact = transcriptLock.artifacts[0];
    const protectedAliases = [
      archivePath,
      checksumPath,
      boundaryLockPath,
      transcriptLockPath,
      join(boundaryRoot, ...boundaryArtifact.path.split("/")),
      join(transcriptRoot, ...transcriptArtifact.path.split("/")),
      join(boundaryRoot, "new-receipt.json"),
      join(transcriptRoot, "new-receipt.json"),
    ];

    for (const receiptPath of protectedAliases) {
      await expect(assertConformanceReceiptCustody({
        boundaryLockPath,
        boundaryRoot,
        transcriptLockPath,
        transcriptRoot,
        receiptPath,
        archivePath,
        checksumPath,
      })).rejects.toThrow(/physically distinct/);
    }
  });

  test("admits a distinct conformance receipt output", async () => {
    const base = join(temporaryRoot, `valid-receipt-custody-${crypto.randomUUID()}`);
    await expect(assertConformanceReceiptCustody({
      boundaryLockPath,
      boundaryRoot,
      transcriptLockPath,
      transcriptRoot,
      receiptPath: join(base, "conformance-receipt.json"),
      archivePath: join(base, "runtime.tar.gz"),
      checksumPath: join(base, "runtime.tar.gz.sha256"),
    })).resolves.toBeUndefined();
  });

  test("passes only PATH to the clean-room runner", () => {
    const environment = cleanRoomEnvironment("/private/empty-path");
    expect(environment).toEqual({ PATH: "/private/empty-path" });
    expect(Object.keys(environment)).toEqual(["PATH"]);
    expect(Object.isFrozen(environment)).toBe(true);
    for (const poisoned of [
      "BUN_OPTIONS",
      "NODE_OPTIONS",
      "DYLD_INSERT_LIBRARIES",
      "DYLD_LIBRARY_PATH",
      "LD_PRELOAD",
      "LD_LIBRARY_PATH",
    ]) {
      expect(poisoned in environment).toBe(false);
    }
  });

  test("enforces the release asset byte bound while streaming", async () => {
    const admittedBytes = new Uint8Array([1, 2, 3, 4]);
    const admitted = await fetchGitHubAssetBytes(
      async () => ({
        ok: true,
        status: 200,
        body: (async function* () {
          yield admittedBytes.subarray(0, 2);
          yield admittedBytes.subarray(2);
        })(),
      }),
      {
        name: "exact.bin",
        browser_download_url: "https://example.invalid/exact.bin",
        size: admittedBytes.byteLength,
        digest: `sha256:${sha256Hex(admittedBytes)}`,
      },
      admittedBytes.byteLength,
    );
    expect(admitted).toEqual(admittedBytes);

    let chunksRead = 0;
    const response = {
      ok: true,
      status: 200,
      body: (async function* () {
        chunksRead += 1;
        yield new Uint8Array([1, 2, 3, 4]);
        chunksRead += 1;
        yield new Uint8Array([5, 6, 7, 8]);
      })(),
    };
    await expect(fetchGitHubAssetBytes(
      async () => response,
      {
        name: "bounded.bin",
        browser_download_url: "https://example.invalid/bounded.bin",
        size: 4,
        digest: `sha256:${"0".repeat(64)}`,
      },
      4,
    )).rejects.toMatchObject({ code: "WORLD_CONFORMANCE_RELEASE_INVALID" });
    expect(chunksRead).toBe(2);
  });
});

async function expectWithBoundaryLock(lock) {
  const path = join(temporaryRoot, `boundary-${crypto.randomUUID()}.json`);
  await writeFile(path, canonicalJsonBytes(lock));
  return requireLockedProofs({ boundaryLockPath: path, boundaryRoot, transcriptLockPath, transcriptRoot });
}
