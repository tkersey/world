import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const EXPECTED = Object.freeze({
  "boundary-v0.7.0.tar.gz": "25e5bd5ed45aac023ef99beee93f675ea4efb3f6eb1e98d2a13040d7451f0e9a",
  "boundary-v1.0.0.tar.gz": "bf1ba841febf2b24b2bdafd75819a557ca8ad4bde4c463199e393c0ab7db52ab",
  "world-v2.0.0.tar.gz": "a1c734eea799b33ea5d9638d3738ca399e94a6d9b9413d6440e41a6bcb6210cf",
  "world-host-v1.0.0.tar.gz": "f881aaf3ada062ca3d80fc46d10cb001f38504d816ecd4995faf34bcd14ecc70",
  "world-capabilities-v2.0.1.tar.gz": "3ed5aadb48d2d431fbb2fa4d4d704a65d8c2d6f7ebcc4d29217f02381a629250",
});
const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const options = parseArgs(process.argv.slice(2));
let generatedRoot = null;
if (options.sdk === null) {
  generatedRoot = mkdtempSync(join(tmpdir(), "world-sdk-v2-check-"));
  options.sdk = join(generatedRoot, "world-sdk-v2.0.0");
  run(process.execPath, [
    join(sourceRoot, "scripts/build_world_sdk_v2.mjs"),
    "--out",
    options.sdk,
    "--zig",
    options.zig,
    "--skip-check",
  ]);
}

try {
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
  for (const [name, expected] of Object.entries(EXPECTED)) {
    const path = join(options.sdk, "releases", name);
    assert.equal(sha256File(path), expected, `release archive mismatch: ${name}`);
  }
  assert.equal(
    manifest.releases.world.packageHash,
    "world-2.0.0-XXTUeJujiQBizko3J_bHMwFB8hQk2cUDXnAlHVKZherB",
  );

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
    assertTreesEqual(
      join(worldRoot, "templates/application-v1"),
      join(options.sdk, "application-template"),
    );
    const result = runCapture(process.execPath, [
      join(worldRoot, "scripts/check_world_2_externality.mjs"),
      "--zig",
      options.zig,
      "--world-archive",
      join(options.sdk, "releases/world-v2.0.0.tar.gz"),
      "--world-archive-sha256",
      EXPECTED["world-v2.0.0.tar.gz"],
      "--world-capabilities-archive",
      join(options.sdk, "releases/world-capabilities-v2.0.1.tar.gz"),
      "--world-capabilities-archive-sha256",
      EXPECTED["world-capabilities-v2.0.1.tar.gz"],
      "--boundary-archive",
      join(options.sdk, "releases/boundary-v0.7.0.tar.gz"),
      "--boundary-machine-archive",
      join(options.sdk, "releases/boundary-v1.0.0.tar.gz"),
      "--world-host-archive",
      join(options.sdk, "releases/world-host-v1.0.0.tar.gz"),
    ], worldRoot);
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
    releaseArchiveCount: Object.keys(EXPECTED).length,
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

function assertTreesEqual(expectedRoot, actualRoot) {
  const expected = listFiles(expectedRoot).sort();
  const actual = listFiles(actualRoot).sort();
  assert.deepEqual(actual, expected, "application template file set mismatch");
  for (const path of expected) {
    assert.equal(sha256File(join(actualRoot, path)), sha256File(join(expectedRoot, path)), `application template mismatch: ${path}`);
  }
}

function keyValueReceipt(text) {
  return Object.fromEntries(text.trim().split("\n").map((line) => {
    const index = line.indexOf("=");
    assert(index > 0, `invalid receipt row: ${line}`);
    return [line.slice(0, index), line.slice(index + 1)];
  }));
}

function run(command, args, cwd = undefined) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8", stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed with status ${result.status}`);
}

function runCapture(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed with status ${result.status}\n${result.stderr}`);
  return result;
}
