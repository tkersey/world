import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  cpSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const EXPECTED_RELEASES = Object.freeze({
  boundaryLegacy: Object.freeze({
    name: "boundary-v0.7.0.tar.gz",
    url: "https://github.com/tkersey/boundary/archive/refs/tags/v0.7.0.tar.gz",
    sha256: "25e5bd5ed45aac023ef99beee93f675ea4efb3f6eb1e98d2a13040d7451f0e9a",
    tag: "v0.7.0",
    packageHash: "boundary-0.7.0-flclaCnjkABOSWaiSkxMBDQZsBEeA-Niai-l1u0q3A7_",
  }),
  boundaryMachine: Object.freeze({
    name: "boundary-v1.0.0.tar.gz",
    url: "https://github.com/tkersey/boundary/archive/refs/tags/v1.0.0.tar.gz",
    sha256: "bf1ba841febf2b24b2bdafd75819a557ca8ad4bde4c463199e393c0ab7db52ab",
    tag: "v1.0.0",
    packageHash: "boundary-1.0.0-flclaPgFEQBhYvlC3eqNVK3X67InkTuaX-pHFvRLzWJ8",
  }),
  world: Object.freeze({
    name: "world-v2.0.0.tar.gz",
    url: "https://github.com/tkersey/world/archive/refs/tags/v2.0.0.tar.gz",
    sha256: "a1c734eea799b33ea5d9638d3738ca399e94a6d9b9413d6440e41a6bcb6210cf",
    tag: "v2.0.0",
    packageHash: "world-2.0.0-XXTUeJujiQBizko3J_bHMwFB8hQk2cUDXnAlHVKZherB",
  }),
  zlinter: Object.freeze({
    name: "zlinter-9b4d67b9725e7137ac876cc628fe5dd2ca5a2681.tar.gz",
    url: "https://github.com/KurtWagner/zlinter/archive/9b4d67b9725e7137ac876cc628fe5dd2ca5a2681.tar.gz",
    sha256: "246d941aa706fb353f4cd87c2dc83cad3f2a39a9cdfbb0357a1dcf0d461094df",
    commit: "9b4d67b9725e7137ac876cc628fe5dd2ca5a2681",
    packageHash: "zlinter-0.0.1-OjQ08c7oCwDIwhlde7eDKMACNTsqAhGXy5vB7GdfGobG",
  }),
  zls: Object.freeze({
    name: "zls-494486203c3a48927f2383aa3d5ce5fca112186d.tar.gz",
    url: "https://github.com/zigtools/zls/archive/494486203c3a48927f2383aa3d5ce5fca112186d.tar.gz",
    sha256: "dcf2d2a0d10001e313592752e9ad44a18cb76c0bf828f6b28af648f519247d76",
    commit: "494486203c3a48927f2383aa3d5ce5fca112186d",
    packageHash: "zls-0.16.0-rmm5fs_JJgBG3dk5HwYK1FylE2_LMN0BYpX57tPzT-Xc",
  }),
  knownFolders: Object.freeze({
    name: "known-folders-d6d03830968cca6b7b9f24fd97ee348346a6905d.tar.gz",
    url: "https://github.com/ziglibs/known-folders/archive/d6d03830968cca6b7b9f24fd97ee348346a6905d.tar.gz",
    sha256: "969a38a43bfde75ad4a72b0ed639953788d4383f20a235fd7a7ec3a11f664896",
    commit: "d6d03830968cca6b7b9f24fd97ee348346a6905d",
    packageHash: "known_folders-0.0.0-Fy-PJk3KAACzUg2us_0JvQQmod1ZA8jBt7MuoKCihq88",
  }),
  diffz: Object.freeze({
    name: "diffz-b39fe07e7fdbcf56e43ba2890b9f484f16969f90.tar.gz",
    url: "https://github.com/ziglibs/diffz/archive/b39fe07e7fdbcf56e43ba2890b9f484f16969f90.tar.gz",
    sha256: "df7454517b746d3782ec662da5c32d44578b02479b23ce59f066259591f2f343",
    commit: "b39fe07e7fdbcf56e43ba2890b9f484f16969f90",
    packageHash: "diffz-0.0.1-G2tlISzNAQCldmOcINavGmF1zdt20NFPXeM8d07jp_68",
  }),
  lspKit: Object.freeze({
    name: "lsp-kit-b886a2b0d5cee85ecbcc3089b863f7517cc9ff7f.tar.gz",
    url: "https://github.com/zigtools/lsp-kit/archive/b886a2b0d5cee85ecbcc3089b863f7517cc9ff7f.tar.gz",
    sha256: "11e34ecf050fc888dff416d6bbe4664183b85770bd86eb6ed0d3c632c1bb193b",
    commit: "b886a2b0d5cee85ecbcc3089b863f7517cc9ff7f",
    packageHash: "lsp_kit-0.1.0-bi_PL3IyDACfp1xdTnkiOHEok2YpPCCCJHuuOcNzjl1D",
  }),
  zprof: Object.freeze({
    name: "zprof-v4.0.0.tar.gz",
    url: "https://github.com/ANDRVV/zprof/archive/v4.0.0.tar.gz",
    sha256: "3a80a9b248ebc866a829c001b0453014e1de149dd6cd1fa321705560c6662a93",
    tag: "v4.0.0",
    packageHash: "zprof-4.0.0-Z3ILTVZ3AACiAIXUpC9F65Hr8zsqpqHc6f-Xu4ic4E8E",
  }),
  worldHost: Object.freeze({
    name: "world-host-v1.0.0.tar.gz",
    url: "https://github.com/tkersey/world-host/releases/download/v1.0.0/world-host-v1.0.0.tar.gz",
    sha256: "f881aaf3ada062ca3d80fc46d10cb001f38504d816ecd4995faf34bcd14ecc70",
    tag: "v1.0.0",
    repository: "tkersey/world-host",
  }),
  worldCapabilities: Object.freeze({
    name: "world-capabilities-v2.0.1.tar.gz",
    url: "https://github.com/tkersey/world-capabilities/releases/download/v2.0.1/world-capabilities-v2.0.1.tar.gz",
    sha256: "3ed5aadb48d2d431fbb2fa4d4d704a65d8c2d6f7ebcc4d29217f02381a629250",
    tag: "v2.0.1",
    repository: "tkersey/world-capabilities",
  }),
});
const EXPECTED_ARCHIVES = Object.freeze(Object.fromEntries(
  Object.values(EXPECTED_RELEASES).map((release) => [release.name, release.sha256]),
));
const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const options = parseArgs(process.argv.slice(2));
options.zig = executablePath(options.zig);
let generatedRoot = null;
try {
  if (options.sdk === null) {
    generatedRoot = mkdtempSync(join(tmpdir(), "world-sdk-v2-check-"));
    options.sdk = join(generatedRoot, "nested", "world-sdk-v2.0.0");
    const buildReceipt = JSON.parse(runCapture(process.execPath, [
      join(sourceRoot, "scripts/build_world_sdk_v2.mjs"),
      "--out",
      options.sdk,
      "--zig",
      options.zig,
      "--skip-check",
    ]).stdout);
    assert.deepEqual(buildReceipt, {
      command: "build-world-sdk-v2",
      output: options.sdk,
      sdkVersion: "2.0.0",
      sourceCheckoutRequired: false,
      validated: false,
      complete: false,
    });
  }

  assert.equal(basename(options.sdk), "world-sdk-v2.0.0");
  assert(lstatSync(options.sdk).isDirectory(), "SDK root must be a directory");
  const files = listFiles(options.sdk).sort();
  const checksums = parseChecksums(readFileSync(join(options.sdk, "checksums.sha256"), "utf8"));
  assert.deepEqual(
    [...checksums.keys()].sort(),
    files.filter((path) => path !== "checksums.sha256"),
    "SDK checksum coverage mismatch",
  );
  for (const [path, expected] of checksums) {
    assert.equal(sha256File(join(options.sdk, path)), expected, `SDK checksum mismatch: ${path}`);
  }

  const manifest = JSON.parse(readFileSync(join(options.sdk, "manifest.json"), "utf8"));
  assert.equal(manifest.schema, "world-sdk-release/v2");
  assert.equal(manifest.sdkVersion, "2.0.0");
  assert.equal(manifest.applicationAbiVersion, 1);
  assert.equal(manifest.frameVersion, 1);
  assert.equal(manifest.effectProtocolVersion, 1);
  assert.deepEqual(manifest.releases, EXPECTED_RELEASES, "release manifest mismatch");
  for (const [name, expected] of Object.entries(EXPECTED_ARCHIVES)) {
    const path = join(options.sdk, "releases", name);
    assert.equal(sha256File(path), expected, `release archive mismatch: ${name}`);
  }

  const templateZon = readFileSync(join(options.sdk, "application-template/build.zig.zon"), "utf8");
  assert(!templateZon.includes("__WORLD_RELEASE_"), "application template retains a World release sentinel");
  assert(templateZon.includes(EXPECTED_RELEASES.world.url), "application template has the wrong World URL");
  assert(templateZon.includes(EXPECTED_RELEASES.world.packageHash), "application template has the wrong World package hash");

  const proofRoot = mkdtempSync(join(tmpdir(), "world-sdk-v2-externality-"));
  try {
    const worldExtracted = join(proofRoot, "world");
    mkdirSync(worldExtracted);
    run("tar", [
      "-xzf",
      join(options.sdk, "releases/world-v2.0.0.tar.gz"),
      "-C",
      worldExtracted,
    ]);
    const worldRoot = singleDirectoryRoot(worldExtracted);
    assertMaterializedTemplate(
      join(worldRoot, "templates/application-v1"),
      join(options.sdk, "application-template"),
    );
    const templateRoot = join(proofRoot, "application-template");
    cpSync(join(options.sdk, "application-template"), templateRoot, { recursive: true });
    localizeWorldDependency(
      templateRoot,
      join(options.sdk, "releases", EXPECTED_RELEASES.world.name),
    );
    const packageCache = join(proofRoot, "package-cache");
    seedPackageCache(packageCache, templateRoot);
    runCapture(options.zig, [
      "build",
      "--cache-dir",
      join(proofRoot, "template-cache"),
      "--global-cache-dir",
      packageCache,
      "--summary",
      "all",
    ], templateRoot);

    const shimRoot = join(proofRoot, "release-tools");
    const worldArchive = join(options.sdk, "releases", EXPECTED_RELEASES.world.name);
    const capabilityArchive = join(options.sdk, "releases", EXPECTED_RELEASES.worldCapabilities.name);
    writeReleaseToolShims(shimRoot);
    const result = runCapture(process.execPath, [
      join(worldRoot, "scripts/check_world_2_externality.mjs"),
      "--zig",
      join(shimRoot, "zig"),
      "--world-archive",
      join(options.sdk, "releases/world-v2.0.0.tar.gz"),
      "--world-archive-sha256",
      EXPECTED_ARCHIVES["world-v2.0.0.tar.gz"],
      "--world-capabilities-archive",
      join(options.sdk, "releases/world-capabilities-v2.0.1.tar.gz"),
      "--world-capabilities-archive-sha256",
      EXPECTED_ARCHIVES["world-capabilities-v2.0.1.tar.gz"],
      "--boundary-archive",
      join(options.sdk, "releases/boundary-v0.7.0.tar.gz"),
      "--boundary-machine-archive",
      join(options.sdk, "releases/boundary-v1.0.0.tar.gz"),
      "--world-host-archive",
      join(options.sdk, "releases/world-host-v1.0.0.tar.gz"),
    ], worldRoot, {
      ...process.env,
      PATH: `${shimRoot}:${process.env.PATH ?? ""}`,
      WORLD_SDK_WORLD_ARCHIVE: worldArchive,
      WORLD_SDK_CAPABILITIES_ARCHIVE: capabilityArchive,
      WORLD_SDK_REAL_ZIG: options.zig,
      WORLD_SDK_RELEASES_DIR: join(options.sdk, "releases"),
    });
    const receipt = keyValueReceipt(result.stdout);
    for (const key of [
      "world_2_externality_gate",
      "fresh_instance_resume",
      "deterministic_retry",
      "branching",
      "migration",
    ]) assert.equal(receipt[key], "true", `externality receipt mismatch: ${key}`);
    assert.equal(receipt.world_application_abi, "1");
    assert.equal(receipt.world_frame_version, "1");
    assert.equal(receipt.effect_protocol_version, "1");
    assert.equal(receipt.world_host_runtime_changed, "false");
    assert.equal(receipt.application_wasm_import_count, "0");
    assert.equal(receipt.source_checkout_required, "false");
  } finally {
    rmSync(proofRoot, { recursive: true, force: true });
  }

  process.stdout.write(`${JSON.stringify({
    receiptVersion: "world-sdk-v2-check/v1",
    sdkVersion: "2.0.0",
    checksumCount: checksums.size,
    releaseArchiveCount: Object.keys(EXPECTED_ARCHIVES).length,
    sourceCheckoutRequired: false,
    worldHostRuntimeChanged: false,
    complete: true,
  }, null, 2)}\n`);
} finally {
  if (generatedRoot !== null) rmSync(generatedRoot, { recursive: true, force: true });
}

function parseArgs(args) {
  const result = { sdk: null, zig: "zig" };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    const value = args[++index];
    if (!value) throw new Error(`missing value for ${key}`);
    if (key === "--sdk") result.sdk = resolve(value);
    else if (key === "--zig") result.zig = value.includes("/") ? resolve(value) : value;
    else throw new Error(`unknown option: ${key}`);
  }
  return result;
}

function listFiles(root, current = root) {
  const paths = [];
  for (const entry of readdirSync(current, { withFileTypes: true })) {
    const absolute = join(current, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`SDK must not contain symlinks: ${absolute}`);
    if (entry.isDirectory()) paths.push(...listFiles(root, absolute));
    else if (entry.isFile()) paths.push(relative(root, absolute));
    else throw new Error(`unsupported SDK entry: ${absolute}`);
  }
  return paths;
}

function parseChecksums(text) {
  const result = new Map();
  for (const line of text.trimEnd().split("\n")) {
    const match = /^([0-9a-f]{64})  (.+)$/.exec(line);
    assert(match, `invalid checksum row: ${line}`);
    assert(!result.has(match[2]), `duplicate checksum row: ${match[2]}`);
    result.set(match[2], match[1]);
  }
  return result;
}

function sha256File(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function singleDirectoryRoot(root) {
  const entries = readdirSync(root, { withFileTypes: true });
  assert.equal(entries.length, 1, "release archive must contain one root");
  assert(entries[0].isDirectory(), "release archive root must be a directory");
  return join(root, entries[0].name);
}

function assertMaterializedTemplate(releasedRoot, bundledRoot) {
  const releasedFiles = listFiles(releasedRoot).sort();
  const bundledFiles = listFiles(bundledRoot).sort();
  assert.deepEqual(bundledFiles, releasedFiles, "application template file set mismatch");
  for (const path of releasedFiles) {
    const released = readFileSync(join(releasedRoot, path));
    const expected = path === "build.zig.zon"
      ? Buffer.from(released.toString("utf8")
        .replaceAll("__WORLD_RELEASE_URL__", EXPECTED_RELEASES.world.url)
        .replaceAll("__WORLD_RELEASE_HASH__", EXPECTED_RELEASES.world.packageHash))
      : released;
    assert.deepEqual(
      readFileSync(join(bundledRoot, path)),
      expected,
      `application template mismatch: ${path}`,
    );
  }
}

function localizeWorldDependency(root, archive) {
  const zonPath = join(root, "build.zig.zon");
  const source = readFileSync(zonPath, "utf8");
  assert(source.includes(EXPECTED_RELEASES.world.url));
  writeFileSync(
    zonPath,
    source.replaceAll(EXPECTED_RELEASES.world.url, pathToFileURL(archive).href),
  );
}

function seedPackageCache(cache, cwd) {
  for (const release of Object.values(EXPECTED_RELEASES)) {
    if (release.packageHash === undefined) continue;
    const archive = join(options.sdk, "releases", release.name);
    const actual = runCapture(options.zig, [
      "fetch",
      "--global-cache-dir",
      cache,
      archive,
    ], cwd).stdout.trim();
    assert.equal(actual, release.packageHash, `${release.name} package hash mismatch`);
  }
}

function writeReleaseToolShims(root) {
  mkdirSync(root);
  const ghPath = join(root, "gh");
  writeFileSync(ghPath, `#!/bin/sh
set -eu
destination=
pattern=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) destination="$2"; shift 2 ;;
    --pattern) pattern="$2"; shift 2 ;;
    *) shift ;;
  esac
done
test "$pattern" = "world-capabilities-v2.0.1.tar.gz"
cp "$WORLD_SDK_CAPABILITIES_ARCHIVE" "$destination/$pattern"
`);
  chmodSync(ghPath, 0o755);

  const curlPath = join(root, "curl");
  writeFileSync(curlPath, `#!/bin/sh
set -eu
destination=
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) destination="$2"; shift 2 ;;
    --fail|--location|--silent|--show-error) shift ;;
    *) url="$1"; shift ;;
  esac
done
test "$url" = "https://github.com/tkersey/world/archive/refs/tags/v2.0.0.tar.gz"
cp "$WORLD_SDK_WORLD_ARCHIVE" "$destination"
`);
  chmodSync(curlPath, 0o755);

  const zigPath = join(root, "zig");
  const cacheSeeds = Object.values(EXPECTED_RELEASES)
    .filter((release) => release.packageHash !== undefined)
    .map((release) => ({ name: release.name, packageHash: release.packageHash }));
  writeFileSync(zigPath, `#!/usr/bin/env node
import { spawnSync } from "node:child_process";

const args = process.argv.slice(2);
const cacheIndex = args.indexOf("--global-cache-dir");
if (cacheIndex >= 0) {
  const cache = args[cacheIndex + 1];
  if (!cache) throw new Error("missing --global-cache-dir value");
  for (const release of ${JSON.stringify(cacheSeeds)}) {
    const seeded = spawnSync(process.env.WORLD_SDK_REAL_ZIG, [
      "fetch",
      "--global-cache-dir",
      cache,
      process.env.WORLD_SDK_RELEASES_DIR + "/" + release.name,
    ], { encoding: "utf8" });
    if (seeded.error) throw seeded.error;
    if (seeded.status !== 0) {
      process.stderr.write(seeded.stderr);
      process.exit(seeded.status ?? 1);
    }
    if (seeded.stdout.trim() !== release.packageHash) {
      throw new Error(release.name + " package hash mismatch");
    }
  }
}
const result = spawnSync(process.env.WORLD_SDK_REAL_ZIG, args, { stdio: "inherit" });
if (result.error) throw result.error;
process.exit(result.status ?? 1);
`);
  chmodSync(zigPath, 0o755);
}

function keyValueReceipt(text) {
  return Object.fromEntries(text.trim().split("\n").map((line) => {
    const index = line.indexOf("=");
    assert(index > 0, `invalid receipt row: ${line}`);
    return [line.slice(0, index), line.slice(index + 1)];
  }));
}

function executablePath(command) {
  if (command.includes("/")) return resolve(command);
  const path = runCapture("which", [command]).stdout.trim();
  assert(path.length > 0 && !path.includes("\n"), `cannot resolve executable: ${command}`);
  return resolve(path);
}

function run(command, args, cwd = undefined) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8", stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed with status ${result.status}`);
}

function runCapture(command, args, cwd, env = process.env) {
  const result = spawnSync(command, args, { cwd, env, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed with status ${result.status}\n${result.stderr}`);
  return result;
}
