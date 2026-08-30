import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  BOUNDARY_PROCESS_PROOF,
  canonicalJsonBytes,
  sha256Hex,
} from "../scripts/acquire_process_conformance_assets.mjs";
import { REPOSITORY_REPAIR_TRANSCRIPT } from "../scripts/acquire_repository_repair_transcript.mjs";
import { requireLockedProofs } from "../scripts/run_clean_room_conformance.mjs";

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
});

async function expectWithBoundaryLock(lock) {
  const path = join(temporaryRoot, `boundary-${crypto.randomUUID()}.json`);
  await writeFile(path, canonicalJsonBytes(lock));
  return requireLockedProofs({ boundaryLockPath: path, boundaryRoot, transcriptLockPath, transcriptRoot });
}
