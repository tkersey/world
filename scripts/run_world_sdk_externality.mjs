import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const WORLD_URL =
  "https://github.com/tkersey/world/archive/refs/tags/v1.0.0.tar.gz";
const options = parseArgs(process.argv.slice(2));
const current = resolve(fileURLToPath(import.meta.url));
const embedded = basename(dirname(current)) === "external-consumer";
const sdkRoot = embedded
  ? resolve(dirname(current), "../..")
  : options.sdk;
assert(sdkRoot, "--sdk is required outside the packaged SDK");

const proofRoot = mkdtempSync(join(tmpdir(), "world-sdk-externality-"));
try {
  const worldMaterialized = join(proofRoot, "world");
  mkdirSync(worldMaterialized, { recursive: true });
  run("tar", [
    "-xzf",
    join(sdkRoot, "world/world-v1.0.0.tar.gz"),
    "-C",
    worldMaterialized,
  ]);
  const worldRoot = locateWorldRoot(worldMaterialized);
  const result = run(
    options.zig,
    [
      "build",
      "check-world-1.0-externality",
      "--",
      "--world-archive",
      join(sdkRoot, "world/world-v1.0.0.tar.gz"),
      "--world-url",
      WORLD_URL,
      "--boundary-archive",
      join(sdkRoot, "boundary/boundary-v0.7.0.tar.gz"),
      "--world-host-archive",
      join(sdkRoot, "world-host/world-host-v1.0.0.tar.gz"),
      "--world-capabilities-runtime-archive",
      join(
        sdkRoot,
        "world-capabilities/world-capabilities-v1-runtime-v1.0.0.tar.gz",
      ),
    ],
    worldRoot,
  );
  process.stdout.write(result.stdout);
} finally {
  rmSync(proofRoot, { recursive: true, force: true });
}

function locateWorldRoot(root) {
  const matches = [];
  walk(root, (candidate) => {
    if (
      existsSync(join(candidate, "build.zig")) &&
      existsSync(join(candidate, "build.zig.zon")) &&
      existsSync(join(candidate, "scripts/check_world_1_0_externality.mjs"))
    ) {
      matches.push(candidate);
    }
  });
  assert.equal(matches.length, 1, "World release package root is ambiguous");
  return matches[0];
}

function walk(root, visit) {
  visit(root);
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    if (entry.isDirectory()) walk(join(root, entry.name), visit);
  }
}

function run(command, args, cwd = undefined) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with status ${result.status}\n` +
        `${result.stdout}${result.stderr}`,
    );
  }
  return result;
}

function parseArgs(args) {
  const result = { sdk: null, zig: "zig" };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    const value = args[++index];
    if (!value) throw new Error(`missing value for ${key}`);
    if (key === "--sdk") result.sdk = resolve(value);
    else if (key === "--zig") result.zig = value;
    else throw new Error(`unknown option: ${key}`);
  }
  return result;
}
