import { describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import {
  acquireBoundaryProcessAssets,
  classifyLocalBoundaryAssetProvenance,
} from "../scripts/acquire_boundary_process_assets.mjs";
import {
  BOUNDARY_PROCESS_PROOF,
  acquireBoundaryProcessConformanceAssets,
  assertConformanceAcquisitionCustody,
  validateBoundaryProcessReleaseIdentity,
} from "../scripts/acquire_process_conformance_assets.mjs";
import { acquireRepositoryRepairTranscript } from "../scripts/acquire_repository_repair_transcript.mjs";

const repositoryRoot = resolve(import.meta.dir, "..");

describe("Boundary development asset provenance", () => {
  test("does not claim that an authenticated checkout asset was emitted by that checkout", () => {
    expect(classifyLocalBoundaryAssetProvenance(null)).toBe("local-kernel-override");
    expect(classifyLocalBoundaryAssetProvenance("/exact-boundary-checkout")).toBe("local-checkout-asset");
  });

  test("rejects case, symlink-parent, and local-input output aliases before writing", async () => {
    const root = await mkdtemp(join(tmpdir(), "world-boundary-custody-"));
    try {
      await expect(acquireBoundaryProcessAssets({
        root: repositoryRoot,
        lockPath: join(root, "Boundary.lock.json"),
        outputPath: join(root, "boundary.lock.json"),
        checkOnly: true,
      })).rejects.toThrow(/physically distinct/);

      const conformanceAlias = join(root, "conformance-alias");
      await symlink(join(repositoryRoot, "conformance"), conformanceAlias);
      await expect(acquireBoundaryProcessAssets({
        root: repositoryRoot,
        lockPath: join(repositoryRoot, "conformance", "boundary.lock.json"),
        outputPath: join(conformanceAlias, "boundary.lock.json"),
        checkOnly: true,
      })).rejects.toThrow(/physically distinct/);

      const kernel = join(repositoryRoot, "boundary-process-kernel-v1.wasm");
      await expect(acquireBoundaryProcessAssets({
        root: repositoryRoot,
        outputPath: kernel,
        kernelPath: kernel,
        sourceRoot: null,
      })).rejects.toThrow(/physically distinct/);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});

describe("published conformance acquisition provenance", () => {
  test("admits a lock output that is physically outside the destination namespace", async () => {
    const root = await mkdtemp(join(tmpdir(), "world-conformance-custody-positive-"));
    try {
      await expect(assertConformanceAcquisitionCustody({
        destination: join(root, "artifacts"),
        lockPath: join(root, "locks", "proof.json"),
      })).resolves.toBeUndefined();
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("rejects Boundary and transcript locks inside or physically aliased into their artifact destinations before fetching", async () => {
    const root = await mkdtemp(join(tmpdir(), "world-conformance-custody-negative-"));
    try {
      const boundaryDestination = join(root, "boundary");
      let boundaryFetches = 0;
      await expect(acquireBoundaryProcessConformanceAssets({
        destination: boundaryDestination,
        lockPath: join(boundaryDestination, "proof.lock.json"),
        fetchImpl: async () => {
          boundaryFetches += 1;
          throw new Error("fetch must not run");
        },
      })).rejects.toMatchObject({ code: "WORLD_CONFORMANCE_DESTINATION_CONFLICT" });
      expect(boundaryFetches).toBe(0);

      const transcriptDestination = join(root, "transcript");
      await mkdir(transcriptDestination, { recursive: true });
      const transcriptAlias = join(root, "transcript-alias");
      await symlink(transcriptDestination, transcriptAlias);
      let transcriptFetches = 0;
      await expect(acquireRepositoryRepairTranscript({
        destination: transcriptDestination,
        lockPath: join(transcriptAlias, "lock.json"),
        fetchImpl: async () => {
          transcriptFetches += 1;
          throw new Error("fetch must not run");
        },
      })).rejects.toMatchObject({ code: "WORLD_CONFORMANCE_DESTINATION_CONFLICT" });
      expect(transcriptFetches).toBe(0);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("requires the exact non-draft Boundary v1.7.0 containing release identity", () => {
    const exactRelease = {
      draft: false,
      tag_name: BOUNDARY_PROCESS_PROOF.releaseTag,
      html_url: BOUNDARY_PROCESS_PROOF.releaseUrl,
    };
    expect(validateBoundaryProcessReleaseIdentity(exactRelease)).toBe(exactRelease);

    for (const release of [
      { ...exactRelease, draft: true },
      { ...exactRelease, tag_name: "v1.7.0-forged" },
      { ...exactRelease, html_url: "https://github.com/tkersey/boundary/releases/tag/v1.7.0-forged" },
    ]) {
      expect(() => validateBoundaryProcessReleaseIdentity(release)).toThrow(expect.objectContaining({
        code: "WORLD_CONFORMANCE_RELEASE_INVALID",
      }));
    }
  });

  test("rejects a draft Boundary release on the acquisition path before resolving tags or downloading assets", async () => {
    const root = await mkdtemp(join(tmpdir(), "world-conformance-release-negative-"));
    try {
      let fetches = 0;
      await expect(acquireBoundaryProcessConformanceAssets({
        destination: join(root, "artifacts"),
        lockPath: join(root, "proof.lock.json"),
        fetchImpl: async () => {
          fetches += 1;
          return {
            ok: true,
            status: 200,
            json: async () => ({
              draft: true,
              tag_name: BOUNDARY_PROCESS_PROOF.releaseTag,
              html_url: BOUNDARY_PROCESS_PROOF.releaseUrl,
              assets: [],
            }),
          };
        },
      })).rejects.toMatchObject({ code: "WORLD_CONFORMANCE_RELEASE_INVALID" });
      expect(fetches).toBe(1);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
