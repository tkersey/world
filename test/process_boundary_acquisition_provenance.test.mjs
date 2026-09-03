import { describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { mkdir, mkdtemp, readdir, rename, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import {
  acquireBoundaryProcessAssets,
  assertPhysicalBoundaryKernelDescendant,
  classifyLocalBoundaryAssetProvenance,
  defaultBoundaryKernelOutput,
  exactBoundarySource,
} from "../scripts/acquire_boundary_process_assets.mjs";
import { readBoundedRegularFileSnapshot } from "../scripts/build_runtime_archive.mjs";
import {
  BOUNDARY_PROCESS_PROOF,
  acquireBoundaryProcessConformanceAssets,
  assertConformanceAcquisitionCustody,
  materializeExactFiles,
  validateBoundaryProcessReleaseIdentity,
} from "../scripts/acquire_process_conformance_assets.mjs";
import { acquireRepositoryRepairTranscript } from "../scripts/acquire_repository_repair_transcript.mjs";

const repositoryRoot = resolve(import.meta.dir, "..");

describe("Boundary development asset provenance", () => {
  test("separates the current runtime kernel from historical release acquisition", () => {
    expect(defaultBoundaryKernelOutput(repositoryRoot, "local")).toBe(
      join(repositoryRoot, "boundary-process-kernel-v1.wasm"),
    );
    expect(defaultBoundaryKernelOutput(repositoryRoot, "release")).toBe(
      join(repositoryRoot, "dist", "boundary-v1.7.0-process-kernel-v1.wasm"),
    );
  });

  test("does not claim that an authenticated checkout asset was emitted by that checkout", () => {
    expect(classifyLocalBoundaryAssetProvenance(null)).toBe("local-kernel-override");
    expect(classifyLocalBoundaryAssetProvenance("/exact-boundary-checkout")).toBe("local-checkout-asset");
  });

  test("rejects historical lock selection in local mode", async () => {
    await expect(acquireBoundaryProcessAssets({
      root: repositoryRoot,
      lockPath: "/definitely/missing-boundary.lock.json",
      checkOnly: true,
    })).rejects.toThrow(/local acquisition forbids a historical Boundary lock/);
  });

  test("reserves the opposite current and historical identity paths", async () => {
    await expect(acquireBoundaryProcessAssets({
      root: repositoryRoot,
      outputPath: join(repositoryRoot, "conformance", "boundary.lock.json"),
      checkOnly: true,
    })).rejects.toThrow(/protected input/);
    await expect(acquireBoundaryProcessAssets({
      root: repositoryRoot,
      mode: "release",
      outputPath: join(repositoryRoot, "boundary-process-kernel-v1.wasm"),
      checkOnly: true,
    })).rejects.toThrow(/protected input/);
    await expect(acquireBoundaryProcessAssets({
      root: repositoryRoot,
      outputPath: join(repositoryRoot, "src", "process_v1", "kernel_identity.json"),
      checkOnly: true,
    })).rejects.toThrow(/protected input/);
  });

  test("admits physical descendants, including paths through an internal symlink", async () => {
    const root = await mkdtemp(join(tmpdir(), "world-boundary-physical-positive-"));
    try {
      const sourceRoot = join(root, "boundary");
      const physicalKernel = join(sourceRoot, "artifacts", "kernel.wasm");
      await mkdir(join(sourceRoot, "artifacts"), { recursive: true });
      await writeFile(physicalKernel, "kernel");
      await symlink(join(sourceRoot, "artifacts"), join(sourceRoot, "artifact-alias"));

      await expect(assertPhysicalBoundaryKernelDescendant(sourceRoot, physicalKernel)).resolves.toBeUndefined();
      await expect(assertPhysicalBoundaryKernelDescendant(
        sourceRoot,
        join(sourceRoot, "artifact-alias", "kernel.wasm"),
      )).resolves.toBeUndefined();
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("rejects explicit and default kernels that escape through a parent symlink before Git or byte admission", async () => {
    const root = await mkdtemp(join(tmpdir(), "world-boundary-physical-negative-"));
    try {
      const sourceRoot = join(root, "boundary");
      const external = join(root, "external");
      await mkdir(sourceRoot, { recursive: true });
      await mkdir(external, { recursive: true });
      await writeFile(join(external, "kernel.wasm"), "not wasm");
      await writeFile(join(external, "boundary-process-kernel-v1.wasm"), "not wasm");
      await symlink(external, join(sourceRoot, "external-alias"));
      await symlink(external, join(sourceRoot, "zig-out"));

      for (const kernelPath of [join(sourceRoot, "external-alias", "kernel.wasm"), null]) {
        await expect(acquireBoundaryProcessAssets({
          root: repositoryRoot,
          sourceRoot,
          kernelPath,
          checkOnly: true,
        })).rejects.toThrow(/physically located inside WORLD_BOUNDARY_SOURCE/);
      }
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("rejects case, symlink-parent, and local-input output aliases before writing", async () => {
    const root = await mkdtemp(join(tmpdir(), "world-boundary-custody-"));
    try {
      await expect(acquireBoundaryProcessAssets({
        root: repositoryRoot,
        mode: "release",
        lockPath: join(root, "Boundary.lock.json"),
        outputPath: join(root, "boundary.lock.json"),
        checkOnly: true,
      })).rejects.toThrow(/physically distinct/);

      const conformanceAlias = join(root, "conformance-alias");
      await symlink(join(repositoryRoot, "conformance"), conformanceAlias);
      await expect(acquireBoundaryProcessAssets({
        root: repositoryRoot,
        mode: "release",
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

  test("binds the admitted path generation to the opened descriptor and rechecks it after reading", async () => {
    const root = await mkdtemp(join(tmpdir(), "world-boundary-descriptor-binding-"));
    try {
      const input = join(root, "kernel.wasm");
      const replacement = join(root, "replacement.wasm");
      await writeFile(input, "first");
      await writeFile(replacement, "other");

      await expect(readBoundedRegularFileSnapshot(input, 1024, "test Boundary kernel", {
        afterPathStat: async () => rename(replacement, input),
      })).rejects.toThrow(/path generation does not match opened descriptor/);

      await writeFile(input, "first");
      await writeFile(replacement, "other");
      await expect(readBoundedRegularFileSnapshot(input, 1024, "test Boundary kernel", {
        afterDescriptorRead: async () => rename(replacement, input),
      })).rejects.toThrow(/path changed during read/);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("ignores ambient Git repository selection and binds the selected checkout root", async () => {
    const root = await mkdtemp(join(tmpdir(), "world-boundary-selected-checkout-"));
    const sourceRoot = join(root, "selected");
    const ambientRoot = join(root, "ambient");
    await mkdir(sourceRoot, { recursive: true });
    await mkdir(ambientRoot, { recursive: true });
    execFileSync("git", ["init", "--quiet"], { cwd: ambientRoot });
    await writeFile(join(ambientRoot, "fixture"), "ambient\n");
    execFileSync("git", ["add", "fixture"], { cwd: ambientRoot });
    execFileSync("git", [
      "-c", "user.name=World Test",
      "-c", "user.email=world-test@example.invalid",
      "commit", "--quiet", "-m", "ambient checkout",
    ], { cwd: ambientRoot });
    const commit = execFileSync("git", ["rev-parse", "HEAD"], { cwd: ambientRoot, encoding: "utf8" }).trim();
    const priorGitDir = process.env.GIT_DIR;
    const priorGitWorkTree = process.env.GIT_WORK_TREE;
    process.env.GIT_DIR = join(ambientRoot, ".git");
    process.env.GIT_WORK_TREE = sourceRoot;
    try {
      await expect(exactBoundarySource(sourceRoot, { boundaryCommit: commit }))
        .rejects.toThrow();
    } finally {
      if (priorGitDir === undefined) delete process.env.GIT_DIR;
      else process.env.GIT_DIR = priorGitDir;
      if (priorGitWorkTree === undefined) delete process.env.GIT_WORK_TREE;
      else process.env.GIT_WORK_TREE = priorGitWorkTree;
      await rm(root, { recursive: true, force: true });
    }
  });
});

describe("published conformance acquisition provenance", () => {
  test("rejects a symlinked existing destination even when its bytes match", async () => {
    const root = await mkdtemp(join(tmpdir(), "world-conformance-materialization-carrier-"));
    try {
      const physical = join(root, "physical");
      const destination = join(root, "destination");
      const bytes = Buffer.from("exact fixture");
      await mkdir(join(physical, "artifacts"), { recursive: true });
      await writeFile(join(physical, "artifacts", "fixture.bin"), bytes);
      await symlink(physical, destination, "dir");

      await expect(materializeExactFiles(
        destination,
        new Map([["fixture.bin", bytes]]),
      )).rejects.toMatchObject({ code: "WORLD_CONFORMANCE_DESTINATION_CONFLICT" });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("removes its owned staging tree when materialization fails", async () => {
    const root = await mkdtemp(join(tmpdir(), "world-conformance-materialization-cleanup-"));
    try {
      const destination = join(root, "destination");
      await expect(materializeExactFiles(
        destination,
        new Map([["missing/fixture.bin", Buffer.from("fixture")]]),
      )).rejects.toMatchObject({ code: "WORLD_CONFORMANCE_WRITE_FAILED" });
      expect((await readdir(root)).filter((name) => name.startsWith("destination.tmp-"))).toEqual([]);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("bounds an oversized preexisting artifact by its exact expected length", async () => {
    const root = await mkdtemp(join(tmpdir(), "world-conformance-existing-bound-"));
    try {
      const destination = join(root, "destination");
      await mkdir(join(destination, "artifacts"), { recursive: true });
      await writeFile(join(destination, "artifacts", "fixture.bin"), Buffer.alloc(4096));
      await expect(materializeExactFiles(
        destination,
        new Map([["fixture.bin", Buffer.from("x")]]),
      )).rejects.toMatchObject({ code: "WORLD_CONFORMANCE_DESTINATION_CONFLICT" });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

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
