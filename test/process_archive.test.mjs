import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  RUNTIME_ARCHIVE_NAME,
  RUNTIME_ROOT,
  assertRepositoryOutputNamespaces,
  buildRuntimeArchive,
  canonicalGzip,
  checksumsBytes,
  createCanonicalTar,
  crc32,
  productionSourceSha256,
  readBoundaryLock,
  repositoryRoot,
  runtimeSourcePaths,
  sha256,
  stableJson,
} from "../scripts/build_runtime_archive.mjs";
import {
  admitRuntimeArchiveBytes,
  checkRuntimeArchive,
  extractAdmittedRuntime,
  parseCanonicalGzip,
  parseCanonicalTar,
  parseChecksumSidecar,
} from "../scripts/check_runtime_archive.mjs";
import { readExactBoundaryLock } from "../scripts/acquire_boundary_process_assets.mjs";
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
    expect(runtimeReadme).toContain("https://github.com/tkersey/world/blob/v4.1.0/docs/process_host_v1.md");
    expect(runtimeReadme).toContain("https://github.com/tkersey/world/blob/v4.1.0/docs/security_model.md");
    expect(runtimeReadme).toContain("https://github.com/tkersey/world/blob/v4.1.0/docs/migration_from_world_3.md");
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
    })).rejects.toThrow(/outside the repository or a file beneath dist/);

    const invalid = join(temporaryRoot, "runtime archive.tar.gz");
    await expect(buildRuntimeArchive({
      root: repositoryRoot,
      outputPath: invalid,
      checksumPath: `${invalid}.sha256`,
    })).rejects.toThrow(/sidecar grammar/);
    await expect(readFile(invalid)).rejects.toThrow();
  });

  test("rejects archive outputs inside repository source namespaces", async () => {
    await expect(buildRuntimeArchive({
      root: repositoryRoot,
      outputPath: join(repositoryRoot, "src", "process_v1", "runtime.tar.gz"),
      checksumPath: join(repositoryRoot, "src", "process_v1", "runtime.tar.gz.sha256"),
    })).rejects.toThrow(/outside the repository or a file beneath dist/);
  });

  test("rejects a dist symlink as the in-repository output namespace", async () => {
    const root = join(temporaryRoot, "symlinked-dist-namespace");
    await mkdir(join(root, "src", "process_v1"), { recursive: true });
    await symlink(join(root, "src", "process_v1"), join(root, "dist"), "dir");
    await expect(assertRepositoryOutputNamespaces(root, [
      { label: "release receipt", path: join(root, "dist", "release-receipt.json") },
    ], "release receipt")).rejects.toThrow(/dist namespace must be a real directory/);
    await expect(assertRepositoryOutputNamespaces(root, [
      { label: "external receipt", path: join(temporaryRoot, "external-receipt.json") },
    ], "release receipt")).resolves.toBeUndefined();
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
    expect(result.innerStdout).toMatch(/^world_runtime_internal_consistency=pass$/m);
    expect(result.innerStdout).toMatch(/^world_runtime_dependency_count=0$/m);
    expect(result.innerStdout).toMatch(/^world_runtime_kernel_imports=0$/m);
  });

  test("does not let the embedded verifier mint its own expected identity", async () => {
    const extractedRoot = join(temporaryRoot, "standalone-verifier-without-trust-root");
    await extractAdmittedRuntime(admitted, extractedRoot);
    const result = spawnSync(process.execPath, ["./verify-runtime.mjs"], {
      cwd: extractedRoot,
      encoding: "utf8",
      env: {},
    });
    expect(result.status).not.toBe(0);
    expect(result.stderr).toMatch(/external expected identity|usage: verify-runtime/);
    expect(result.stdout).not.toMatch(/internal_consistency=pass/);
  });

  test("preserves the historical Boundary lock separately from the current runtime kernel", async () => {
    const historical = await readExactBoundaryLock();
    expect(historical.boundaryVersion).toBe("1.7.0");
    expect(historical.kernelSha256).toBe("178f9c2fb79402a85ab5a7905586879347ad5c99f988127eec001c9ecfd813f0");
    expect(lock.boundaryVersion).toBe("1.8.0");
    const kernel = await readFile(join(repositoryRoot, "boundary-process-kernel-v1.wasm"));
    expect(kernel.byteLength).toBe(lock.kernelByteLength);
    expect(sha256(kernel)).toBe(lock.kernelSha256);
  });

  test("rejects an archived canonical identity that contradicts the selected lock", async () => {
    const entries = new Map([...admitted.entries].map(([path, bytes]) => [path, Buffer.from(bytes)]));
    const identityPath = "src/process_v1/kernel_identity.json";
    const identity = JSON.parse(entries.get(identityPath).toString("utf8"));
    entries.set(identityPath, Buffer.from(stableJson({ ...identity, boundaryCommit: "a".repeat(40) }), "utf8"));
    const manifest = JSON.parse(entries.get("runtime-manifest.json").toString("utf8"));
    entries.set("runtime-manifest.json", Buffer.from(stableJson({
      ...manifest,
      productionSourceSha256: productionSourceSha256(entries),
    }), "utf8"));
    entries.set("checksums.sha256", checksumsBytes(entries));
    await expect(admitRuntimeArchiveBytes(canonicalGzip(createCanonicalTar(entries)), { lock }))
      .rejects.toThrow(/runtime kernel identity differs from the selected Boundary lock/);
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
      boundaryCorpusIdentity: {
        producerTag: "v1.7.0",
        producerCommit: "4fd4cd959ea283a6b5af12a228f0d80a102683e3",
        manifestSha256: "5ef2fb9fc3667ce97eae74d5bf9b635da46596fd7f0b3e68a04a43b24b7bb331",
        payloadSha256: "17a74f8adfdd7fe9aced05d01fe0432f7ad6720b69cf353bc57a695378bb527f",
      },
      repositoryRepairCorpusIdentity: {
        producerTag: "v2.7.0",
        producerCommit: "f8609bc68f2a9c798df3511cfc3a2af60a359d41",
        manifestSha256: "c2e0e63192c19cbb8e5d0d1d3b6951fcd428f9496c015471f69524286cf236c1",
        payloadSha256: "f0ddf27f8402168e76360178b532da37323ada5c97a4294ca9d1c98e1c4838dd",
        programImageSha256: "7440076a8078220d9d4000b871423d981bbbee19aedba499afaa4a86239fe6a6",
      },
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
    expect(directConformance.boundary).toEqual({
      version: lock.boundaryVersion,
      commit: lock.boundaryCommit,
      kernelSha256: lock.kernelSha256,
    });
    expect(directConformance.boundaryCorpus.producerTag).toBe("v1.7.0");
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

  test("classifies rename targets by their parent and leaf rather than following leaf symlinks", async () => {
    const inRepository = join(repositoryRoot, ".cache", `release-leaf-symlink-${process.pid}`);
    const externalReceipt = join(temporaryRoot, "external-release-receipt.json");
    const externalConformance = join(temporaryRoot, "external-conformance-receipt.json");
    await mkdir(inRepository, { recursive: true });
    await writeFile(externalReceipt, "external\n");
    await writeFile(externalConformance, "external\n");
    const outputPath = join(inRepository, "release-receipt.json");
    const conformancePath = join(inRepository, DEFAULT_CONFORMANCE_RECEIPT);
    await symlink(externalReceipt, outputPath);
    await symlink(externalConformance, conformancePath);
    try {
      await expect(writeReleaseReceipt({
        root: repositoryRoot,
        archivePath,
        checksumPath,
        outputPath,
      })).rejects.toThrow(/outside the repository or a file beneath dist/);
    } finally {
      await rm(inRepository, { recursive: true, force: true });
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
