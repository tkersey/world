import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import {
  RUNTIME_ARCHIVE_NAME,
  RUNTIME_ROOT,
  buildRuntimeArchive,
  canonicalGzip,
  createCanonicalTar,
  crc32,
  readBoundaryLock,
  repositoryRoot,
  runtimeSourcePaths,
  sha256,
} from "../scripts/build_runtime_archive.mjs";
import {
  admitRuntimeArchiveBytes,
  checkRuntimeArchive,
  parseCanonicalGzip,
  parseCanonicalTar,
  parseChecksumSidecar,
} from "../scripts/check_runtime_archive.mjs";
import {
  acquireBoundaryProcessAssets,
  readExactBoundaryLock,
} from "../scripts/acquire_boundary_process_assets.mjs";
import {
  DEFAULT_CONFORMANCE_RECEIPT,
  writeReleaseReceipt,
} from "../scripts/write_release_receipt.mjs";

let temporaryRoot;
let archivePath;
let checksumPath;
let archive;
let tar;
let admitted;
let lock;

beforeAll(async () => {
  temporaryRoot = await mkdtemp(join(tmpdir(), "world-process-archive-test-"));
  archivePath = join(temporaryRoot, RUNTIME_ARCHIVE_NAME);
  checksumPath = `${archivePath}.sha256`;
  await buildRuntimeArchive({
    root: repositoryRoot,
    outputPath: archivePath,
    checksumPath,
  });
  archive = await readFile(archivePath);
  tar = parseCanonicalGzip(archive);
  lock = await readBoundaryLock(repositoryRoot);
  admitted = await admitRuntimeArchiveBytes(archive, {
    expectedDigest: sha256(archive),
    expectedInventory: [...await runtimeSourcePaths(repositoryRoot), "checksums.sha256", "runtime-manifest.json"],
    lock,
  });
});

afterAll(async () => {
  if (temporaryRoot) await rm(temporaryRoot, { recursive: true, force: true });
});

describe("World Process Host runtime archive", () => {
  test("builds byte-identically with canonical inventory, modes, checksums, and gzip", async () => {
    const second = join(temporaryRoot, "second", RUNTIME_ARCHIVE_NAME);
    await buildRuntimeArchive({
      root: repositoryRoot,
      outputPath: second,
      checksumPath: `${second}.sha256`,
    });
    expect(await readFile(second)).toEqual(archive);
    expect(parseChecksumSidecar(await readFile(checksumPath))).toBe(sha256(archive));
    expect(canonicalGzip(tar)).toEqual(archive);
    expect(admitted.runtimeInventory).toEqual([...admitted.runtimeInventory].sort(compareUtf8));
    expect(admitted.parsed.find(({ path }) => path === "bin/world.mjs")?.mode).toBe(0o755);
    expect(admitted.parsed.find(({ path }) => path === "verify-runtime.mjs")?.mode).toBe(0o755);
    expect(admitted.parsed.find(({ path }) => path === "package.json")?.mode).toBe(0o644);
    expect(admitted.manifest.productionSourceSha256).toMatch(/^[0-9a-f]{64}$/);
    const runtimeReadme = admitted.entries.get("README.md").toString("utf8");
    expect(runtimeReadme).toContain("https://github.com/tkersey/world/blob/v4.0.0/docs/process_host_v1.md");
    expect(runtimeReadme).toContain("https://github.com/tkersey/world/blob/v4.0.0/docs/security_model.md");
    expect(runtimeReadme).toContain("https://github.com/tkersey/world/blob/v4.0.0/docs/migration_from_world_3.md");
    expect(runtimeReadme).not.toMatch(/\]\(docs\//);
  });

  test("rejects archive and checksum path aliasing before writing", async () => {
    const samePath = join(temporaryRoot, "aliased-runtime-output");
    await expect(buildRuntimeArchive({
      root: repositoryRoot,
      outputPath: samePath,
      checksumPath: join(temporaryRoot, ".", "aliased-runtime-output"),
    })).rejects.toThrow(/physically distinct/);
    await expect(readFile(samePath)).rejects.toThrow();
  });

  test("rejects portable case collisions, symlink-parent source aliases, and invalid sidecar names before writing", async () => {
    const caseRoot = join(temporaryRoot, "portable-case");
    await expect(buildRuntimeArchive({
      root: repositoryRoot,
      outputPath: join(caseRoot, "Runtime.tar.gz"),
      checksumPath: join(caseRoot, "runtime.tar.gz"),
    })).rejects.toThrow(/physically distinct/);

    const aliasRoot = join(temporaryRoot, "repository-alias");
    await symlink(repositoryRoot, aliasRoot);
    await expect(buildRuntimeArchive({
      root: repositoryRoot,
      outputPath: join(aliasRoot, "README.md"),
      checksumPath: join(temporaryRoot, "safe-checksum"),
    })).rejects.toThrow(/protected input/);

    const invalid = join(temporaryRoot, "runtime archive.tar.gz");
    await expect(buildRuntimeArchive({
      root: repositoryRoot,
      outputPath: invalid,
      checksumPath: `${invalid}.sha256`,
    })).rejects.toThrow(/sidecar grammar/);
    await expect(readFile(invalid)).rejects.toThrow();
  });

  test("authenticates, manually extracts, and runs the embedded verifier with an empty PATH", async () => {
    const result = await checkRuntimeArchive({
      root: repositoryRoot,
      archivePath,
      checksumPath,
      verifyRebuild: false,
      runInner: true,
    });
    expect(result.archiveSha256).toBe(sha256(archive));
    expect(result.innerVerified).toBe(true);
    expect(result.innerStdout).toMatch(/^world_runtime_verify=pass$/m);
    expect(result.innerStdout).toMatch(/^world_runtime_dependency_count=0$/m);
    expect(result.innerStdout).toMatch(/^world_runtime_kernel_imports=0$/m);
  });

  test("validates the exact Boundary lock and local development override without changing source provenance", async () => {
    expect(await readExactBoundaryLock()).toEqual(lock);
    const outputPath = join(temporaryRoot, "acquired", "boundary-process-kernel-v1.wasm");
    const result = await acquireBoundaryProcessAssets({
      root: repositoryRoot,
      outputPath,
      mode: "local",
      kernelPath: resolve(repositoryRoot, "boundary-process-kernel-v1.wasm"),
      sourceRoot: null,
    });
    expect(result.provenance).toBe("local-kernel-override");
    expect(result.kernelSha256).toBe(lock.kernelSha256);
    expect(await readFile(outputPath)).toEqual(await readFile(join(repositoryRoot, "boundary-process-kernel-v1.wasm")));
  });

  test("rejects noncanonical or corrupt gzip before parsing USTAR", () => {
    const metadata = Buffer.from(archive);
    metadata[9] = 3;
    expect(() => parseCanonicalGzip(metadata)).toThrow(/gzip header is not canonical/);

    const crc = Buffer.from(archive);
    crc.writeUInt32LE((crc.readUInt32LE(crc.length - 8) + 1) >>> 0, crc.length - 8);
    expect(() => parseCanonicalGzip(crc)).toThrow(/CRC32 differs/);

    const trailingMember = Buffer.concat([archive, canonicalGzip(Buffer.alloc(0))]);
    expect(() => parseCanonicalGzip(trailingMember)).toThrow();
  });

  test("rejects traversal, links, duplicates, out-of-order entries, and extra terminators", () => {
    const traversal = patchFirstHeader(tar, (header) => {
      header.fill(0, 0, 100);
      Buffer.from(`${RUNTIME_ROOT}/../escape`, "ascii").copy(header, 0);
    });
    expect(() => parseCanonicalTar(traversal)).toThrow(/path is unsafe/);

    const link = patchFirstHeader(tar, (header) => { header[156] = 0x32; });
    expect(() => parseCanonicalTar(link)).toThrow(/not a regular file/);

    const spans = entrySpans(tar);
    const duplicate = Buffer.concat([tar.subarray(0, spans[0].end), tar.subarray(spans[0].start, spans[0].end), tar.subarray(spans[0].end)]);
    expect(() => parseCanonicalTar(duplicate)).toThrow(/duplicate entry/);

    const swapped = Buffer.concat([
      tar.subarray(spans[1].start, spans[1].end),
      tar.subarray(spans[0].start, spans[0].end),
      tar.subarray(spans[1].end),
    ]);
    expect(() => parseCanonicalTar(swapped)).toThrow(/canonical UTF-8 order/);

    expect(() => parseCanonicalTar(Buffer.concat([tar, Buffer.alloc(512)]))).toThrow(/exactly two zero blocks/);
  });

  test("rejects missing checksum coverage and unexpected application data", async () => {
    const entries = new Map([...admitted.entries].map(([path, bytes]) => [path, Buffer.from(bytes)]));
    const rows = entries.get("checksums.sha256").toString("utf8").trimEnd().split("\n");
    entries.set("checksums.sha256", Buffer.from(`${rows.slice(1).join("\n")}\n`, "utf8"));
    await expect(admitRuntimeArchiveBytes(canonicalGzip(createCanonicalTar(entries)), { lock })).rejects.toThrow(/checksum coverage is not exact/);

    const application = new Map([...admitted.entries].map(([path, bytes]) => [path, Buffer.from(bytes)]));
    application.set("application.bpi1", Buffer.from("not application data"));
    await expect(admitRuntimeArchiveBytes(canonicalGzip(createCanonicalTar(application)), { lock })).rejects.toThrow(/forbidden application or source data/);

    const withoutChecksums = new Map([...admitted.entries].filter(([path]) => path !== "checksums.sha256"));
    await expect(admitRuntimeArchiveBytes(canonicalGzip(createCanonicalTar(withoutChecksums)), { lock })).rejects.toThrow(/missing: checksums.sha256/);
  });

  test("binds the release receipt to exact published Process corpus parity", async () => {
    const releaseArchivePath = join(temporaryRoot, "release", RUNTIME_ARCHIVE_NAME);
    const releaseChecksumPath = `${releaseArchivePath}.sha256`;
    const outputPath = join(temporaryRoot, "release-receipt.json");
    const conformanceOutputPath = join(temporaryRoot, DEFAULT_CONFORMANCE_RECEIPT);
    await buildRuntimeArchive({
      root: repositoryRoot,
      outputPath: releaseArchivePath,
      checksumPath: releaseChecksumPath,
    });
    await writeFile(conformanceOutputPath, "fabricated stale conformance metadata\n");
    const result = await writeReleaseReceipt({
      root: repositoryRoot,
      archivePath: releaseArchivePath,
      checksumPath: releaseChecksumPath,
      outputPath,
    });
    expect(result.receipt.publishedProcessCorpusParityClaimed).toBe(true);
    expect(result.receipt.publishedProcessCorpusParity).toEqual({
      boundaryVectorCount: 20,
      boundaryByteIdenticalCount: 20,
      repositoryRepairReductionCount: 96,
      repositoryRepairResidualBoundaryCount: 17,
      requestReconstructionCount: 17,
      transferAfterBoundary: 8,
      transferRecovered: true,
      terminalResultSha256: "6a473b2e74e2f8229d10061d1b613ad71ab2ad5b139c21bd9a898b7a2778f75c",
    });
    expect(result.receipt.negativeGateCoverageClaimed).toBe(false);
    expect(result.receipt).not.toHaveProperty("semanticConformanceClaimed");
    expect(result.receipt).not.toHaveProperty("semanticConformance");
    const directConformance = JSON.parse(await readFile(conformanceOutputPath, "utf8"));
    expect(directConformance.result).toBe("passed");
    expect(directConformance.cleanRoom.runtimeArchiveSha256).toBe(result.receipt.archiveSha256);
  }, 120_000);

  test("rejects aliased release custody paths before proof or writes", async () => {
    const base = join(temporaryRoot, "release-path-aliases");
    const distinct = {
      archivePath: join(base, "runtime.tar.gz"),
      checksumPath: join(base, "runtime.tar.gz.sha256"),
      outputPath: join(base, "release-receipt.json"),
    };
    const cases = [
      { ...distinct, checksumPath: join(base, ".", "runtime.tar.gz") },
      { ...distinct, outputPath: join(base, ".", "runtime.tar.gz") },
      { ...distinct, outputPath: join(base, ".", "runtime.tar.gz.sha256") },
      { ...distinct, archivePath: join(base, DEFAULT_CONFORMANCE_RECEIPT) },
      { ...distinct, checksumPath: join(base, DEFAULT_CONFORMANCE_RECEIPT) },
      { ...distinct, outputPath: join(base, DEFAULT_CONFORMANCE_RECEIPT) },
    ];
    for (const paths of cases) {
      await expect(writeReleaseReceipt({ root: repositoryRoot, ...paths })).rejects.toThrow(/physically distinct/);
    }
  });

  test("rejects release custody case and tracked-source aliases before proof", async () => {
    const base = join(temporaryRoot, "release-physical-aliases");
    await expect(writeReleaseReceipt({
      root: repositoryRoot,
      archivePath: join(base, "Runtime.tar.gz"),
      checksumPath: join(base, "runtime.tar.gz"),
      outputPath: join(base, "receipt.json"),
    })).rejects.toThrow(/physically distinct/);

    const aliasRoot = join(temporaryRoot, "release-repository-alias");
    await symlink(repositoryRoot, aliasRoot);
    await expect(writeReleaseReceipt({
      root: repositoryRoot,
      archivePath: join(base, "archive.tar.gz"),
      checksumPath: join(base, "archive.tar.gz.sha256"),
      outputPath: join(aliasRoot, "README.md"),
    })).rejects.toThrow(/outside the repository or a file beneath dist/);

    for (const outputPath of [
      join(repositoryRoot, "src", "process_v1", "generated-release-receipt.json"),
      join(repositoryRoot, "scripts", "generated-release-receipt.json"),
      join(repositoryRoot, "generated-release-receipt.json"),
    ]) {
      await expect(writeReleaseReceipt({
        root: repositoryRoot,
        archivePath: join(base, "archive.tar.gz"),
        checksumPath: join(base, "archive.tar.gz.sha256"),
        outputPath,
      })).rejects.toThrow(/outside the repository or a file beneath dist/);
    }
  });

  test("has no release-claim route for fabricated, missing, or malformed conformance receipt files", async () => {
    const paths = [
      join(temporaryRoot, "missing-conformance.json"),
      join(temporaryRoot, "fabricated-conformance.json"),
      join(temporaryRoot, "malformed-conformance.json"),
    ];
    await writeFile(paths[1], '{"result":"passed"}\n');
    await writeFile(paths[2], "not json\n");
    for (const path of paths) {
      const execution = spawnSync(
        process.execPath,
        [join(repositoryRoot, "scripts", "write_release_receipt.mjs"), "--conformance-receipt", path],
        { cwd: repositoryRoot, encoding: "utf8" },
      );
      expect(execution.status).not.toBe(0);
      expect(execution.stderr).toContain("unknown release-receipt argument: --conformance-receipt");
    }
  });
});

function compareUtf8(left, right) {
  return Buffer.from(left, "utf8").compare(Buffer.from(right, "utf8"));
}

function recomputeHeaderChecksum(header) {
  header.fill(0x20, 148, 156);
  const sum = header.reduce((value, byte) => value + byte, 0);
  header.write(`${sum.toString(8).padStart(6, "0")}\0 `, 148, 8, "ascii");
}

function patchFirstHeader(input, mutation) {
  const output = Buffer.from(input);
  const header = output.subarray(0, 512);
  mutation(header);
  recomputeHeaderChecksum(header);
  return output;
}

function entrySpans(input) {
  const spans = [];
  let offset = 0;
  while (!input.subarray(offset, offset + 512).every((byte) => byte === 0)) {
    const start = offset;
    const size = Number.parseInt(input.subarray(offset + 124, offset + 135).toString("ascii"), 8);
    offset += 512 + Math.ceil(size / 512) * 512;
    spans.push({ start, end: offset });
  }
  return spans;
}
