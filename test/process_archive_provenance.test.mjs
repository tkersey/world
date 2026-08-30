import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  RUNTIME_ARCHIVE_NAME,
  buildRuntimeArchive,
  repositoryRoot,
} from "../scripts/build_runtime_archive.mjs";
import { checkRuntimeArchive } from "../scripts/check_runtime_archive.mjs";

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
      })).rejects.toThrow(/sourceCommit differs from exact clean Git HEAD/);
    }
  });
});
