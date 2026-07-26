import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const VERIFIER_SHA256 = Object.freeze({
  "check_world_1_0_externality.mjs":
    "1e4ad89c93c7337b0e30608a81e783b586a29bd1353d85aeafe9e7502cdee043",
  "check_world_external_consumer.mjs":
    "8e91544440b442bdca20d1feb8ee3b1e47661a725a3b53d2c87c8f5889c63a82",
});

const options = parseArgs(process.argv.slice(2));
const current = resolve(fileURLToPath(import.meta.url));
const embedded = basename(dirname(current)) === "external-consumer";
const sdkRoot = embedded
  ? resolve(dirname(current), "../..")
  : options.sdk;
assert(sdkRoot, "--sdk is required outside the packaged SDK");

const verifierRoot = join(
  sdkRoot,
  "conformance/external-consumer/verifier/scripts",
);
for (const [name, expectedSha256] of Object.entries(VERIFIER_SHA256)) {
  const actualSha256 = createHash("sha256")
    .update(readFileSync(join(verifierRoot, name)))
    .digest("hex");
  assert.equal(
    actualSha256,
    expectedSha256,
    `packaged externality verifier identity mismatch: ${name}`,
  );
}
const verifierArgs = [
  join(verifierRoot, "check_world_1_0_externality.mjs"),
  "--world-archive",
  join(sdkRoot, "world/world-v1.0.0.tar.gz"),
  "--world-url",
  "https://github.com/tkersey/world/archive/refs/tags/v1.0.0.tar.gz",
  "--boundary-archive",
  join(sdkRoot, "boundary/boundary-v0.7.0.tar.gz"),
  "--world-host-archive",
  join(sdkRoot, "world-host/world-host-v1.0.0.tar.gz"),
  "--world-capabilities-runtime-archive",
  join(
    sdkRoot,
    "world-capabilities/world-capabilities-v1-runtime-v1.0.0.tar.gz",
  ),
];
if (options.zig !== "zig") verifierArgs.push("--zig", options.zig);
const result = run("node", verifierArgs, sdkRoot);
process.stdout.write(result.stdout);

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
