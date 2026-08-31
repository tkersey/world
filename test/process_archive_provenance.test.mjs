import { afterAll, beforeAll, describe, expect, setDefaultTimeout, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { pathToFileURL } from "node:url";

import {
  RUNTIME_ARCHIVE_NAME,
  assertTrackedRepositoryMatchesCommit,
  bindRetainedSnapshotsToGitHead,
  buildRuntimeArchive,
  canonicalGzip,
  checksumsBytes,
  createCanonicalTar,
  repositoryRoot,
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
    await expect(writeReleaseReceipt({
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
