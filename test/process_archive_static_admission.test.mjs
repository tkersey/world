import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  RUNTIME_ARCHIVE_NAME,
  RUNTIME_ROOT,
  buildRuntimeArchive,
  canonicalGzip,
  canonicalTarHeader,
  checksumsBytes,
  createCanonicalTar,
  readBoundaryLock,
  repositoryRoot,
  stableJson,
} from "../scripts/build_runtime_archive.mjs";
import {
  admitRuntimeArchiveBytes,
  parseCanonicalGzip,
} from "../scripts/check_runtime_archive.mjs";

let temporaryRoot;
let tar;
let admitted;
let lock;

beforeAll(async () => {
  temporaryRoot = await mkdtemp(join(tmpdir(), "world-process-archive-static-test-"));
  const archivePath = join(temporaryRoot, RUNTIME_ARCHIVE_NAME);
  await buildRuntimeArchive({
    root: repositoryRoot,
    outputPath: archivePath,
    checksumPath: `${archivePath}.sha256`,
  });
  const archive = await readFile(archivePath);
  tar = parseCanonicalGzip(archive);
  lock = await readBoundaryLock(repositoryRoot);
  admitted = await admitRuntimeArchiveBytes(archive, { lock });
});

afterAll(async () => {
  if (temporaryRoot) await rm(temporaryRoot, { recursive: true, force: true });
});

describe("runtime archive static admission", () => {
  test("rejects a byte-canonical archive whose entry mode is wrong for its path", async () => {
    const mutatedTar = replaceEntryMode(tar, "package.json", 0o755);
    await expect(admitRuntimeArchiveBytes(canonicalGzip(mutatedTar), { lock }))
      .rejects.toThrow("runtime USTAR mode differs: package.json");
  });

  test("rejects byte-canonical packages with postinstall or any other extra key", async () => {
    for (const extra of [
      { scripts: { postinstall: "node ./install.mjs" } },
      { description: "unexpected package surface" },
    ]) {
      const entries = cloneEntries(admitted.entries);
      const packageJson = JSON.parse(entries.get("package.json").toString("utf8"));
      entries.set("package.json", Buffer.from(stableJson({ ...packageJson, ...extra }), "utf8"));
      entries.set("checksums.sha256", checksumsBytes(entries));
      const archive = canonicalGzip(createCanonicalTar(entries));
      await expect(admitRuntimeArchiveBytes(archive, { lock }))
        .rejects.toThrow("runtime package fields are not exact");
    }
  });

  test("pins clean-room request parity to the public Uint8Array representation", async () => {
    const source = await readFile(join(repositoryRoot, "scripts", "run_clean_room_conformance.mjs"), "utf8");
    expect(source).not.toContain("outcomeRequestBytes");
    expect(source).not.toContain("request?.bytes");
    expect(source).toContain("actual.request instanceof Uint8Array");
    expect(source).toContain("reconstructed.request instanceof Uint8Array");
    expect(source).toContain("equal(actual.request, expectedRequest)");
    expect(source).toContain("equal(reconstructed.request, expectedRequest)");
  });
});

function cloneEntries(entries) {
  return new Map([...entries].map(([path, bytes]) => [path, Buffer.from(bytes)]));
}

function replaceEntryMode(input, relativePath, mode) {
  const output = Buffer.from(input);
  const expectedArchivePath = `${RUNTIME_ROOT}/${relativePath}`;
  let offset = 0;
  while (!output.subarray(offset, offset + 512).every((byte) => byte === 0)) {
    const header = output.subarray(offset, offset + 512);
    const name = nulTerminatedText(header.subarray(0, 100));
    const prefix = nulTerminatedText(header.subarray(345, 500));
    const archivePath = prefix === "" ? name : `${prefix}/${name}`;
    const size = Number.parseInt(header.subarray(124, 135).toString("ascii"), 8);
    if (archivePath === expectedArchivePath) {
      canonicalTarHeader(archivePath, size, mode).copy(output, offset);
      return output;
    }
    offset += 512 + Math.ceil(size / 512) * 512;
  }
  throw new Error(`runtime archive entry is missing: ${relativePath}`);
}

function nulTerminatedText(bytes) {
  const end = bytes.indexOf(0);
  return bytes.subarray(0, end === -1 ? bytes.length : end).toString("utf8");
}
