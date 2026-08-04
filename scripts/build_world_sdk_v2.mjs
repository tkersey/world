import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  copyFileSync,
  cpSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const RELEASES = Object.freeze([
  Object.freeze({
    key: "boundaryLegacy",
    name: "boundary-v0.7.0.tar.gz",
    url: "https://github.com/tkersey/boundary/archive/refs/tags/v0.7.0.tar.gz",
    sha256: "25e5bd5ed45aac023ef99beee93f675ea4efb3f6eb1e98d2a13040d7451f0e9a",
    tag: "v0.7.0",
  }),
  Object.freeze({
    key: "boundaryMachine",
    name: "boundary-v1.0.0.tar.gz",
    url: "https://github.com/tkersey/boundary/archive/refs/tags/v1.0.0.tar.gz",
    sha256: "bf1ba841febf2b24b2bdafd75819a557ca8ad4bde4c463199e393c0ab7db52ab",
    tag: "v1.0.0",
  }),
  Object.freeze({
    key: "world",
    name: "world-v2.0.0.tar.gz",
    url: "https://github.com/tkersey/world/archive/refs/tags/v2.0.0.tar.gz",
    sha256: "a1c734eea799b33ea5d9638d3738ca399e94a6d9b9413d6440e41a6bcb6210cf",
    tag: "v2.0.0",
    packageHash: "world-2.0.0-XXTUeJujiQBizko3J_bHMwFB8hQk2cUDXnAlHVKZherB",
  }),
  Object.freeze({
    key: "worldHost",
    name: "world-host-v1.0.0.tar.gz",
    url: "https://github.com/tkersey/world-host/releases/download/v1.0.0/world-host-v1.0.0.tar.gz",
    sha256: "f881aaf3ada062ca3d80fc46d10cb001f38504d816ecd4995faf34bcd14ecc70",
    tag: "v1.0.0",
    repository: "tkersey/world-host",
  }),
  Object.freeze({
    key: "worldCapabilities",
    name: "world-capabilities-v2.0.1.tar.gz",
    url: "https://github.com/tkersey/world-capabilities/releases/download/v2.0.1/world-capabilities-v2.0.1.tar.gz",
    sha256: "3ed5aadb48d2d431fbb2fa4d4d704a65d8c2d6f7ebcc4d29217f02381a629250",
    tag: "v2.0.1",
    repository: "tkersey/world-capabilities",
  }),
]);

const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const options = parseArgs(process.argv.slice(2));
assert.equal(
  basename(options.out),
  "world-sdk-v2.0.0",
  "SDK output directory must be named world-sdk-v2.0.0",
);

const temporaryRoot = mkdtempSync(join(tmpdir(), "world-sdk-v2-build-"));
let outputClaimed = false;
let complete = false;
try {
  mkdirSync(dirname(options.out), { recursive: true });
  mkdirSync(options.out);
  outputClaimed = true;
  const releasesRoot = join(options.out, "releases");
  mkdirSync(releasesRoot, { recursive: true });
  for (const release of RELEASES) {
    const target = join(releasesRoot, release.name);
    download(release, target);
    assert.equal(sha256File(target), release.sha256, `${release.key} archive mismatch`);
  }

  const worldExtracted = join(temporaryRoot, "world");
  mkdirSync(worldExtracted);
  run("tar", ["-xzf", join(releasesRoot, "world-v2.0.0.tar.gz"), "-C", worldExtracted]);
  const worldRoot = singleDirectoryRoot(worldExtracted);
  cpSync(
    join(worldRoot, "templates/application-v1"),
    join(options.out, "application-template"),
    { recursive: true },
  );
  materializeApplicationTemplate(join(options.out, "application-template"));

  mkdirSync(join(options.out, "conformance"), { recursive: true });
  copyFileSync(
    join(sourceRoot, "scripts/check_world_sdk_v2.mjs"),
    join(options.out, "conformance/check-sdk.mjs"),
  );
  writeJson(join(options.out, "manifest.json"), {
    schema: "world-sdk-release/v2",
    sdkVersion: "2.0.0",
    applicationAbiVersion: 1,
    frameVersion: 1,
    effectProtocolVersion: 1,
    releases: Object.fromEntries(RELEASES.map(({ key, ...release }) => [key, release])),
  });
  writeFileSync(join(options.out, "README.md"), readme());
  writeChecksums(options.out);

  if (!options.skipCheck) {
    const receipt = JSON.parse(runCapture(process.execPath, [
      join(options.out, "conformance/check-sdk.mjs"),
      "--sdk",
      options.out,
      "--zig",
      options.zig,
    ]).stdout);
    assert.equal(receipt.receiptVersion, "world-sdk-v2-check/v1");
    assert.equal(receipt.complete, true);
  }
  complete = true;
  process.stdout.write(`${JSON.stringify({
    command: "build-world-sdk-v2",
    output: options.out,
    sdkVersion: "2.0.0",
    sourceCheckoutRequired: false,
    validated: !options.skipCheck,
    complete: !options.skipCheck,
  }, null, 2)}\n`);
} finally {
  rmSync(temporaryRoot, { recursive: true, force: true });
  if (outputClaimed && !complete) rmSync(options.out, { recursive: true, force: true });
}

function parseArgs(args) {
  const result = { out: null, skipCheck: false, zig: "zig" };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    if (key === "--skip-check") {
      result.skipCheck = true;
      continue;
    }
    const value = args[++index];
    if (!value) throw new Error(`missing value for ${key}`);
    if (key === "--out") result.out = resolve(value);
    else if (key === "--zig") result.zig = value.includes("/") ? resolve(value) : value;
    else throw new Error(`unknown option: ${key}`);
  }
  if (result.out === null) throw new Error("--out is required");
  return result;
}

function download(release, target) {
  if (release.repository !== undefined) {
    run("gh", [
      "release",
      "download",
      release.tag,
      "--repo",
      release.repository,
      "--pattern",
      release.name,
      "--dir",
      dirname(target),
    ]);
    return;
  }
  run("curl", ["--fail", "--location", "--silent", "--show-error", "--output", target, release.url]);
}

function singleDirectoryRoot(root) {
  const entries = readdirSync(root, { withFileTypes: true });
  assert.equal(entries.length, 1, "release archive must contain one root");
  assert(entries[0].isDirectory(), "release archive root must be a directory");
  return join(root, entries[0].name);
}

function materializeApplicationTemplate(root) {
  const world = RELEASES.find((release) => release.key === "world");
  assert(world !== undefined);
  const zonPath = join(root, "build.zig.zon");
  const source = readFileSync(zonPath, "utf8");
  const materialized = source
    .replaceAll("__WORLD_RELEASE_URL__", world.url)
    .replaceAll("__WORLD_RELEASE_HASH__", world.packageHash);
  assert.notEqual(materialized, source, "application template has no World release sentinels");
  assert(!materialized.includes("__WORLD_RELEASE_"), "application template retains a World release sentinel");
  writeFileSync(zonPath, materialized);
}

function writeChecksums(root) {
  const lines = listFiles(root)
    .filter((path) => path !== "checksums.sha256")
    .sort()
    .map((path) => `${sha256File(join(root, path))}  ${path}`);
  writeFileSync(join(root, "checksums.sha256"), `${lines.join("\n")}\n`);
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

function sha256File(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function run(command, args, cwd = undefined) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8", stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed with status ${result.status}`);
}

function runCapture(command, args, cwd = undefined) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with status ${result.status}\n${result.stdout}${result.stderr}`,
    );
  }
  return result;
}

function readme() {
  return `# World SDK v2.0.0

This checksum-bound bundle contains the exact released Boundary, World,
world-host, and world-capabilities artifacts needed to build and run a World 2
application without sibling source checkouts.

Start from \`application-template/\`. Verify the complete bundle with:

\`node conformance/check-sdk.mjs --sdk . --zig zig\`

The runtime host is the unchanged released world-host v1.0.0 artifact.
`;
}
