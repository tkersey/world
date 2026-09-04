import { afterAll, beforeAll, describe, expect, setDefaultTimeout, test } from "bun:test";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { pathToFileURL } from "node:url";

import {
  RUNTIME_ARCHIVE_NAME,
  WORLD_VERSION,
  assertTrackedRepositoryMatchesCommit,
  bindRetainedSnapshotsToGitHead,
  buildRuntimeArchive,
  canonicalGzip,
  checksumsBytes,
  createCanonicalTar,
  exactGitHeadCommit,
  probeBoundaryProcessKernelAbi,
  productionSourceSha256,
  repositoryRoot,
  readBoundaryLock,
  readBoundedRegularFileSnapshot,
  sha256,
  snapshotRuntimeSources,
  stableJson,
} from "../scripts/build_runtime_archive.mjs";
import {
  checkRuntimeArchive,
  parseCanonicalGzip,
  parseCanonicalTar,
} from "../scripts/check_runtime_archive.mjs";
import { writeReleaseReceipt } from "../scripts/write_release_receipt.mjs";
import { deriveGitWorkingInventory } from "../scripts/check_process_surface.mjs";
import { acquireBoundaryProcessAssets } from "../scripts/acquire_boundary_process_assets.mjs";
import { processKernelWasmFixture } from "./wasm_fixture.mjs";

setDefaultTimeout(30_000);

let temporaryRoot;

beforeAll(async () => {
  temporaryRoot = await mkdtemp(join(tmpdir(), "world-runtime-provenance-test-"));
});

afterAll(async () => {
  if (temporaryRoot) await rm(temporaryRoot, { recursive: true, force: true });
});

async function buildArchive(name) {
  const archivePath = join(temporaryRoot, name, RUNTIME_ARCHIVE_NAME);
  const checksumPath = `${archivePath}.sha256`;
  await buildRuntimeArchive({
    root: repositoryRoot,
    outputPath: archivePath,
    checksumPath,
  });
  return { archivePath, checksumPath };
}

async function forgeArchiveSourceCommit(paths, commit) {
  const parsed = parseCanonicalTar(parseCanonicalGzip(await readFile(paths.archivePath)));
  const entries = new Map(parsed.map(({ path, bytes }) => [path, Buffer.from(bytes)]));
  const manifest = JSON.parse(entries.get("runtime-manifest.json").toString("utf8"));
  entries.set("runtime-manifest.json", Buffer.from(stableJson({ ...manifest, sourceCommit: commit }), "utf8"));
  entries.set("checksums.sha256", checksumsBytes(entries));
  const archive = canonicalGzip(createCanonicalTar(entries));
  await writeFile(paths.archivePath, archive);
  await writeFile(paths.checksumPath, `${sha256(archive)}  ${basename(paths.archivePath)}\n`);
}

function git(root, arguments_) {
  return execFileSync("git", arguments_, { cwd: root, encoding: "utf8" }).trim();
}

async function cloneRepository(name) {
  const root = join(temporaryRoot, name);
  execFileSync("git", ["clone", "--quiet", "--no-local", repositoryRoot, root], { encoding: "utf8" });
  const head = git(root, ["rev-parse", "HEAD"]);
  git(root, ["-c", "advice.detachedHead=false", "checkout", "--quiet", "--detach", head]);
  return root;
}

describe("runtime archive source provenance", () => {
  test("rejects invalid identity bytes from the selected root without falling back", async () => {
    const root = await cloneRepository("selected-root-kernel-identity");
    const identityPath = join(root, "src", "process_v1", "kernel_identity.json");
    const identity = JSON.parse(await readFile(identityPath, "utf8"));
    await writeFile(identityPath, stableJson({ ...identity, unexpected: true }));
    git(root, ["add", "src/process_v1/kernel_identity.json"]);
    git(root, ["-c", "user.name=World Test", "-c", "user.email=world-test@example.invalid", "commit", "-m", "invalid kernel identity"]);
    await expect(readBoundaryLock(root)).rejects.toThrow(/fields are not exact/);
    await expect(acquireBoundaryProcessAssets({ root, checkOnly: true })).rejects.toThrow(/fields are not exact/);
  });

  test("does not execute the selected root's identity projection", async () => {
    const root = await cloneRepository("selected-root-inert-identity");
    const projectionPath = join(root, "src", "process_v1", "kernel_identity.mjs");
    const markerPath = join(root, "identity-side-effect");
    await writeFile(
      projectionPath,
      `await Bun.write(${JSON.stringify(markerPath)}, "executed");\n${await readFile(projectionPath, "utf8")}`,
    );
    await expect(readBoundaryLock(root)).resolves.toMatchObject({ boundaryVersion: "1.8.0" });
    expect(await readdir(root)).not.toContain("identity-side-effect");
  });

  test("rejects a declared kernel profile that differs from the selected Wasm", async () => {
    const root = await cloneRepository("selected-root-kernel-profile");
    const identityPath = join(root, "src", "process_v1", "kernel_identity.json");
    const identity = JSON.parse(await readFile(identityPath, "utf8"));
    await writeFile(identityPath, stableJson({ ...identity, abiVersion: identity.abiVersion + 1 }));
    git(root, ["add", "src/process_v1/kernel_identity.json"]);
    git(root, ["-c", "user.name=World Test", "-c", "user.email=world-test@example.invalid", "commit", "-m", "mismatched kernel profile"]);
    await expect(acquireBoundaryProcessAssets({ root, checkOnly: true }))
      .rejects.toThrow(/ABI version is not supported/);
    await expect(buildRuntimeArchive({
      root,
      outputPath: join(root, "dist", RUNTIME_ARCHIVE_NAME),
      checksumPath: join(root, "dist", `${RUNTIME_ARCHIVE_NAME}.sha256`),
    })).rejects.toThrow(/ABI version is not supported/);
  });

  test("bounds dynamic execution of the selected kernel ABI probe", () => {
    expect(() => probeBoundaryProcessKernelAbi(
      processKernelWasmFixture({ abiLoop: true }),
      100,
    )).toThrow(/ABI probe timed out/);
  });

  test("reproduces an archive labeled with the exact clean Git HEAD", async () => {
    const paths = await buildArchive("exact");
    const result = await checkRuntimeArchive({
      root: repositoryRoot,
      ...paths,
      verifyRebuild: true,
      runInner: false,
    });
    const head = execFileSync("git", ["rev-parse", "HEAD"], {
      cwd: repositoryRoot,
      encoding: "utf8",
    }).trim();
    expect(result.manifest.sourceCommit).toBe(head);
    expect(result.reproducible).toBe(true);
  });

  test("rejects forged source labels during rebuild verification", async () => {
    for (const commit of ["0".repeat(40), "f".repeat(40)]) {
      const paths = await buildArchive(`forged-${commit[0]}`);
      await forgeArchiveSourceCommit(paths, commit);
      await expect(checkRuntimeArchive({
        root: repositoryRoot,
        ...paths,
        verifyRebuild: true,
        runInner: false,
      })).rejects.toThrow(/tracked repository HEAD differs from archive sourceCommit/);
    }
  });

  test("rejects assume-unchanged runtime bytes that Git status hides", async () => {
    const root = await cloneRepository("assume-unchanged");
    git(root, ["update-index", "--assume-unchanged", "README.md"]);
    await writeFile(join(root, "README.md"), "hidden assume-unchanged runtime divergence\n");
    expect(git(root, ["status", "--porcelain=v1", "--", "README.md"])).toBe("");
    await expect(buildRuntimeArchive({
      root,
      outputPath: join(root, "dist", RUNTIME_ARCHIVE_NAME),
    })).rejects.toThrow(/retained runtime bytes differ from Git blob at HEAD: README\.md/);
  });

  test("rejects skip-worktree runtime bytes that Git status hides", async () => {
    const root = await cloneRepository("skip-worktree");
    git(root, ["update-index", "--skip-worktree", "README.md"]);
    await writeFile(join(root, "README.md"), "hidden skip-worktree runtime divergence\n");
    expect(git(root, ["status", "--porcelain=v1", "--", "README.md"])).toBe("");
    await expect(buildRuntimeArchive({
      root,
      outputPath: join(root, "dist", RUNTIME_ARCHIVE_NAME),
    })).rejects.toThrow(/retained runtime bytes differ from Git blob at HEAD: README\.md/);
  });

  test("disables Git replacement objects while binding source provenance", async () => {
    const root = await cloneRepository("replacement-object");
    const original = git(root, ["rev-parse", "HEAD"]);
    const replacementReadme = "replacement-object runtime divergence\n";
    await writeFile(join(root, "README.md"), replacementReadme);
    git(root, ["add", "README.md"]);
    git(root, ["-c", "user.name=World Test", "-c", "user.email=world-test@example.invalid", "commit", "-m", "replacement tree"]);
    const replacement = git(root, ["rev-parse", "HEAD"]);
    git(root, ["-c", "advice.detachedHead=false", "checkout", "--quiet", "--detach", original]);
    git(root, ["replace", original, replacement]);
    await writeFile(join(root, "README.md"), replacementReadme);

    await expect(buildRuntimeArchive({
      root,
      outputPath: join(root, "dist", RUNTIME_ARCHIVE_NAME),
    })).rejects.toThrow(/retained runtime bytes differ from Git blob at HEAD: README\.md/);
  });

  test("ignores ambient Git selectors for archive and surface provenance", async () => {
    const root = await cloneRepository("ambient-git-selector");
    const expectedHead = git(root, ["rev-parse", "HEAD"]);
    const priorGitDir = process.env.GIT_DIR;
    process.env.GIT_DIR = join(root, "missing-ambient.git");
    try {
      expect(exactGitHeadCommit(root)).toBe(expectedHead);
      expect(deriveGitWorkingInventory(root).some((entry) => entry.path === "package.json"))
        .toBe(true);
    } finally {
      if (priorGitDir === undefined) delete process.env.GIT_DIR;
      else process.env.GIT_DIR = priorGitDir;
    }
  });

  test("binds retained snapshots rather than a later restored worktree", async () => {
    const root = await cloneRepository("snapshot-restore");
    const readmePath = join(root, "README.md");
    const committed = await readFile(readmePath);
    await writeFile(readmePath, "transient divergent snapshot\n");
    const retained = await snapshotRuntimeSources(root);
    await writeFile(readmePath, committed);
    expect(git(root, ["status", "--porcelain=v1", "--", "README.md"])).toBe("");
    expect(() => bindRetainedSnapshotsToGitHead(root, retained)).toThrow(/retained runtime bytes differ from Git blob at HEAD: README\.md/);
  });

  test("bounds descriptor reads when the file grows after admission", async () => {
    const path = join(temporaryRoot, "bounded-growth.bin");
    await writeFile(path, Buffer.from("seed"));
    await expect(readBoundedRegularFileSnapshot(path, 16, "bounded growth fixture", {
      afterDescriptorStat: async () => writeFile(path, Buffer.alloc(64), { flag: "a" }),
    })).rejects.toThrow(/changed during read/);
  });

  test("executes rebuilds from the authenticated on-disk builder generation", async () => {
    const root = await cloneRepository("cached-dirty-builder");
    const builderPath = join(root, "scripts", "build_runtime_archive.mjs");
    const checkerPath = join(root, "scripts", "check_runtime_archive.mjs");
    const committedBuilder = await readFile(builderPath, "utf8");
    const dirtyBuilder = committedBuilder.replace(
      "const entries = new Map(sourceEntries);",
      "const entries = new Map(sourceEntries);\n  entries.set(\"README.md\", Buffer.concat([entries.get(\"README.md\"), Buffer.from(\"\\n\")]));",
    );
    expect(dirtyBuilder).not.toBe(committedBuilder);
    await writeFile(builderPath, dirtyBuilder);

    const checker = await import(`${pathToFileURL(checkerPath).href}?cached-dirty-builder`);
    const cachedBuilder = await import(pathToFileURL(builderPath).href);
    const archivePath = join(root, "dist", RUNTIME_ARCHIVE_NAME);
    const checksumPath = `${archivePath}.sha256`;
    try {
      await cachedBuilder.buildRuntimeArchive({ root, outputPath: archivePath, checksumPath });
    } finally {
      await writeFile(builderPath, committedBuilder);
    }

    await expect(checker.checkRuntimeArchive({
      root,
      archivePath,
      checksumPath,
      verifyRebuild: true,
      runInner: false,
    })).rejects.toThrow(/runtime archive differs from an exact source rebuild/);
  });

  test("cleans an owned extraction root when the embedded verifier fails", async () => {
    const paths = await buildArchive("failing-inner-verifier");
    const parsed = parseCanonicalTar(parseCanonicalGzip(await readFile(paths.archivePath)));
    const entries = new Map(parsed.map(({ path, bytes }) => [path, Buffer.from(bytes)]));
    entries.set("verify-runtime.mjs", Buffer.from("throw new Error(\"expected verifier failure\");\n", "utf8"));
    entries.set("checksums.sha256", checksumsBytes(entries));
    const archive = canonicalGzip(createCanonicalTar(entries));
    await writeFile(paths.archivePath, archive);
    await writeFile(paths.checksumPath, `${sha256(archive)}  ${basename(paths.archivePath)}\n`);

    const ownedRoots = async () => (await readdir(tmpdir()))
      .filter((name) => name.startsWith("world-runtime-admitted-"))
      .sort();
    const before = await ownedRoots();
    await expect(checkRuntimeArchive({
      root: repositoryRoot,
      ...paths,
      verifyRebuild: false,
      runInner: true,
      expectedWorldIdentity: {
        worldVersion: WORLD_VERSION,
        worldSourceCommit: exactGitHeadCommit(repositoryRoot),
        worldProductionSourceSha256: productionSourceSha256(
          await snapshotRuntimeSources(repositoryRoot),
        ),
      },
      expectedArchiveSha256: sha256(archive),
    })).rejects.toThrow(/embedded runtime verifier failed/);
    expect(await ownedRoots()).toEqual(before);
  });

  test("loads release proof modules only inside the fresh receipt process", async () => {
    const root = await cloneRepository("cached-dirty-release-proof");
    const archivePath = join(root, "dist", RUNTIME_ARCHIVE_NAME);
    const checksumPath = `${archivePath}.sha256`;
    await buildRuntimeArchive({ root, outputPath: archivePath, checksumPath });

    const checkerPath = join(root, "scripts", "check_runtime_archive.mjs");
    const writerPath = join(root, "scripts", "write_release_receipt.mjs");
    const committedChecker = await readFile(checkerPath, "utf8");
    await writeFile(checkerPath, `throw new Error("dirty proof module loaded in parent");\n${committedChecker}`);
    let writer;
    try {
      writer = await import(`${pathToFileURL(writerPath).href}?cached-dirty-release-proof`);
    } finally {
      await writeFile(checkerPath, committedChecker);
    }

    const outputPath = join(root, "dist", "fresh-release-receipt.json");
    const result = await writer.writeReleaseReceipt({
      root,
      archivePath,
      checksumPath,
      outputPath,
    });
    expect(result.receipt.sourceCommit).toBe(git(root, ["rev-parse", "HEAD"]));
    expect(result.receipt.byteReproducible).toBe(true);
    expect(result.receipt.cleanRoomRuntimeVerified).toBe(true);
  }, 120_000);

  test("rejects a direct receipt CLI root that differs from its executing checkout", async () => {
    const root = await cloneRepository("cross-checkout-release-root");
    const result = spawnSync(process.execPath, [
      join(repositoryRoot, "scripts", "write_release_receipt.mjs"),
      "--root",
      root,
    ], {
      cwd: repositoryRoot,
      encoding: "utf8",
    });
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("release receipt root must match the executing World checkout");
  });

  test("programmatic receipt generation never executes a caller-selected checkout script", async () => {
    const root = join(temporaryRoot, "caller-selected-receipt-script");
    const outputPath = join(root, "fake-receipt.json");
    await mkdir(join(root, "scripts"), { recursive: true });
    await writeFile(join(root, "scripts", "write_release_receipt.mjs"), [
      'import { writeFileSync } from "node:fs";',
      'const out = process.argv[process.argv.indexOf("--out") + 1];',
      'writeFileSync(out, "{}\\n");',
      'console.log("world_release_receipt_write=pass");',
      "",
    ].join("\n"));
    await expect(writeReleaseReceipt({ root, outputPath }))
      .rejects.toThrow(/release receipt root must match the executing World checkout/);
  });

  test("release receipt preflight rejects hidden drift in any tracked proof input", async () => {
    const root = await cloneRepository("proof-state");
    const archivePath = join(root, "dist", RUNTIME_ARCHIVE_NAME);
    const checksumPath = `${archivePath}.sha256`;
    await buildRuntimeArchive({ root, outputPath: archivePath, checksumPath });
    const proofPath = "test/process_kernel.test.mjs";
    git(root, ["update-index", "--assume-unchanged", proofPath]);
    await writeFile(join(root, proofPath), "hidden non-runtime proof divergence\n");
    expect(git(root, ["status", "--porcelain=v1", "--", proofPath])).toBe("");
    const sourceCommit = git(root, ["rev-parse", "HEAD"]);
    await expect(assertTrackedRepositoryMatchesCommit(root, sourceCommit)).rejects.toThrow(/tracked working bytes differ from source commit: test\/process_kernel\.test\.mjs/);
    const writer = await import(`${pathToFileURL(join(root, "scripts", "write_release_receipt.mjs")).href}?proof-state`);
    await expect(writer.writeReleaseReceipt({
      root,
      archivePath,
      checksumPath,
      outputPath: join(root, "dist", "release-receipt.json"),
    })).rejects.toThrow(/tracked working bytes differ from source commit: test\/process_kernel\.test\.mjs/);
  });

  for (const proofPath of [
    "scripts/build_runtime_archive.mjs",
    "scripts/check_runtime_archive.mjs",
    "scripts/run_clean_room_conformance.mjs",
  ]) {
    test(`rebuild verification rejects tracked drift in ${proofPath}`, async () => {
      const root = await cloneRepository(`rebuild-proof-drift-${basename(proofPath, ".mjs")}`);
      const archivePath = join(root, "dist", RUNTIME_ARCHIVE_NAME);
      const checksumPath = `${archivePath}.sha256`;
      await buildRuntimeArchive({ root, outputPath: archivePath, checksumPath });
      await writeFile(join(root, proofPath), `tracked proof divergence in ${proofPath}\n`);

      const structural = await checkRuntimeArchive({
        root,
        archivePath,
        checksumPath,
        verifyRebuild: false,
        runInner: false,
      });
      expect(structural.reproducible).toBe(false);

      await expect(checkRuntimeArchive({
        root,
        archivePath,
        checksumPath,
        verifyRebuild: true,
        runInner: false,
      })).rejects.toThrow(new RegExp(`tracked working bytes differ from source commit: ${proofPath.replaceAll(".", "\\.")}`));
    });
  }
});
