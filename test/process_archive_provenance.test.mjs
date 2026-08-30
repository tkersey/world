import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  RUNTIME_ARCHIVE_NAME,
  assertTrackedRepositoryMatchesCommit,
  bindRetainedSnapshotsToGitHead,
  buildRuntimeArchive,
  repositoryRoot,
  snapshotRuntimeSources,
} from "../scripts/build_runtime_archive.mjs";
import { checkRuntimeArchive } from "../scripts/check_runtime_archive.mjs";
import { writeReleaseReceipt } from "../scripts/write_release_receipt.mjs";

let temporaryRoot;

beforeAll(async () => {
  temporaryRoot = await mkdtemp(join(tmpdir(), "world-runtime-provenance-test-"));
});

afterAll(async () => {
  if (temporaryRoot) await rm(temporaryRoot, { recursive: true, force: true });
});

async function buildArchive(name, commit) {
  const archivePath = join(temporaryRoot, name, RUNTIME_ARCHIVE_NAME);
  const checksumPath = `${archivePath}.sha256`;
  await buildRuntimeArchive({
    root: repositoryRoot,
    outputPath: archivePath,
    checksumPath,
    ...(commit === undefined ? {} : { commit }),
  });
  return { archivePath, checksumPath };
}

function git(root, arguments_) {
  return execFileSync("git", arguments_, { cwd: root, encoding: "utf8" }).trim();
}

async function cloneRepository(name) {
  const root = join(temporaryRoot, name);
  execFileSync("git", ["clone", "--quiet", "--no-local", repositoryRoot, root], { encoding: "utf8" });
  const head = git(repositoryRoot, ["rev-parse", "HEAD"]);
  execFileSync("git", ["checkout", "--quiet", "--detach", head], { cwd: root, encoding: "utf8" });
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
      const paths = await buildArchive(`forged-${commit[0]}`, commit);
      await expect(checkRuntimeArchive({
        root: repositoryRoot,
        ...paths,
        verifyRebuild: true,
        runInner: false,
      })).rejects.toThrow(/sourceCommit differs from exact source rebuild/);
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
});
