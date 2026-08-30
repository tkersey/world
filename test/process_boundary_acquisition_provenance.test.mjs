import { describe, expect, test } from "bun:test";
import { mkdtemp, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import {
  acquireBoundaryProcessAssets,
  classifyLocalBoundaryAssetProvenance,
} from "../scripts/acquire_boundary_process_assets.mjs";

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
