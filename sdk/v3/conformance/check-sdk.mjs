import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const sdkRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const expected = Object.freeze({
  boundary: {
    version: "1.0.0",
    archiveSha256: "bf1ba841febf2b24b2bdafd75819a557ca8ad4bde4c463199e393c0ab7db52ab",
    packageHash: "boundary-1.0.0-flclaPgFEQBhYvlC3eqNVK3X67InkTuaX-pHFvRLzWJ8",
  },
  world: {
    version: "3.0.0",
    archiveSha256: "2e129819a9a578eea8919c000a6002dc56e0011abbcaeb36fadeb211d2a9da52",
    packageHash: "world-3.0.0-XXTUeH4tBgDQM9BYPERe-ZyxDaT3WnPr30k6UcPYY9Vz",
    commit: "537b3ff1c67f4422b882158d9e206848f1db99ad",
  },
  host: {
    version: "1.0.0",
    archiveSha256: "f881aaf3ada062ca3d80fc46d10cb001f38504d816ecd4995faf34bcd14ecc70",
  },
  capabilities: {
    version: "2.0.2",
    archiveSha256: "e1718f14ff6c2443b52a06e35650cf8530feb7863ef120950ee7c5c6f1c951a6",
    commit: "47596758e55b288b4d35d0f459c5a8cc31b40eb0",
    applicationId: "1880383510d2cb82892827245c206d7a98afd6779a3ce3a72d1776ce813ab1e3",
  },
});

const manifest = JSON.parse(readFileSync(join(sdkRoot, "manifest.json"), "utf8"));
assert.equal(manifest.schema, "world-sdk-v3/v1");
assert.equal(manifest.sdkVersion, "3.0.0");
assert.deepEqual(manifest.components, expected);
verifyChecksums();
verifyArchiveIdentities();
verifyInventory();
verifyAuthenticatedContents();

console.log("sdk_version=3.0.0");
console.log("sdk_archives_authenticated=true");
console.log("sdk_boundary_archive_count=1");
console.log("sdk_world_archive_count=1");
console.log("sdk_host_archive_count=1");
console.log("sdk_capability_archive_count=1");
console.log("sdk_legacy_artifact_count=0");
console.log("world_sdk_v3=true");

function verifyChecksums() {
  const checksumPath = join(sdkRoot, "checksums.sha256");
  const entries = new Map(readFileSync(checksumPath, "utf8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const match = /^([0-9a-f]{64})  (.+)$/.exec(line);
      if (!match) throw new Error(`invalid SDK checksum row: ${line}`);
      return [match[2], match[1]];
    }));
  const files = walkFiles(sdkRoot)
    .map((path) => relative(sdkRoot, path))
    .filter((path) => path !== "checksums.sha256")
    .sort();
  assert.deepEqual([...entries.keys()].sort(), files, "SDK checksum inventory differs");
  for (const path of files) {
    assert.equal(sha256(readFileSync(join(sdkRoot, path))), entries.get(path), `SDK checksum mismatch: ${path}`);
  }
}

function verifyArchiveIdentities() {
  for (const [owner, path] of Object.entries(archivePaths())) {
    assert.equal(sha256(readFileSync(path)), expected[owner].archiveSha256, `${owner} archive identity differs`);
  }
}

function verifyInventory() {
  const paths = walkFiles(sdkRoot).map((path) => relative(sdkRoot, path));
  for (const marker of [
    ["boundary", "-v0.7"].join(""),
    ["universal", "-world"].join(""),
    ["executable", "-image"].join(""),
    ["turn", "-closure"].join(""),
    ["certified", "-boundary-module"].join(""),
  ]) {
    assert(!paths.some((path) => path.toLowerCase().includes(marker)), `forbidden SDK artifact: ${marker}`);
  }
  for (const [owner, path] of Object.entries(archivePaths())) {
    const prefix = relative(sdkRoot, dirname(path));
    const count = paths.filter((entry) => entry.startsWith(`${prefix}/`) && entry.endsWith(".tar.gz")).length;
    assert.equal(count, 1, `${owner} archive count differs`);
  }
}

function verifyAuthenticatedContents() {
  const root = mkdtempSync(join(tmpdir(), "world-sdk-v3-check-"));
  try {
    for (const [owner, archive] of Object.entries(archivePaths())) {
      const destination = join(root, owner);
      run("mkdir", [destination]);
      run("tar", ["-xzf", archive, "-C", destination]);
    }
    const worldRoot = exactRoot(join(root, "world"), "world-3.0.0");
    const boundaryRoot = exactRoot(join(root, "boundary"), "boundary-1.0.0");
    const hostRoot = exactRoot(join(root, "host"), "world-host-v1.0.0");
    const capabilitiesRoot = exactRoot(join(root, "capabilities"), "world-capabilities-v2.0.2");
    assert(readFileSync(join(worldRoot, "build.zig.zon"), "utf8").includes(`.version = "3.0.0"`));
    assert(readFileSync(join(boundaryRoot, "build.zig.zon"), "utf8").includes(`.version = "1.0.0"`));
    assert.equal(JSON.parse(readFileSync(join(hostRoot, "host/package.json"), "utf8")).version, "1.0.0");
    assert.equal(JSON.parse(readFileSync(join(capabilitiesRoot, "package.json"), "utf8")).version, "2.0.2");
    const corpus = JSON.parse(readFileSync(join(capabilitiesRoot, "packages/research-lookup-fixture/corpus.json"), "utf8"));
    assert.equal(corpus.applicationId, expected.capabilities.applicationId);
    assert.equal(corpus.worldRelease.tag, "v3.0.0");
    assert.equal(corpus.worldRelease.archiveSha256, expected.world.archiveSha256);
    assert.equal(corpus.worldRelease.packageHash, expected.world.packageHash);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function archivePaths() {
  return {
    boundary: join(sdkRoot, "boundary/archive/boundary-v1.0.0.tar.gz"),
    world: join(sdkRoot, "world/archive/world-v3.0.0.tar.gz"),
    host: join(sdkRoot, "world-host/archive/world-host-v1.0.0.tar.gz"),
    capabilities: join(sdkRoot, "world-capabilities/archive/world-capabilities-v2.0.2-effect-v1.tar.gz"),
  };
}

function exactRoot(root, expectedName) {
  const entries = readdirSync(root, { withFileTypes: true });
  assert.equal(entries.length, 1, `archive root count differs: ${expectedName}`);
  assert(entries[0].isDirectory() && entries[0].name === expectedName, `archive root differs: ${expectedName}`);
  return join(root, expectedName);
}

function walkFiles(root) {
  if (!existsSync(root)) return [];
  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const path = join(root, entry.name);
    return entry.isDirectory() ? walkFiles(path) : [path];
  }).sort();
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed:\n${result.stdout ?? ""}\n${result.stderr ?? ""}`);
}
