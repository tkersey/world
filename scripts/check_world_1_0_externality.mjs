import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const options = parseArgs(process.argv.slice(2));
const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const proofRoot = mkdtempSync(join(tmpdir(), "world-1.0-externality-"));
let consumerProofRoot = null;
let passed = false;

try {
  const consumer = runCapture("node", [
    join(sourceRoot, "scripts/check_world_external_consumer.mjs"),
    "--keep",
    "--world-archive",
    options.worldArchive,
    "--world-url",
    options.worldUrl,
    "--boundary-archive",
    options.boundaryArchive,
    "--zig",
    options.zig,
  ]);
  consumerProofRoot = proofPath(
    consumer.stderr,
    "world_external_consumer_proof_root",
  );
  const consumerReceipt = keyValueReceipt(consumer.stdout);
  assert.equal(consumerReceipt.clean_room_build, "true");
  assert.equal(consumerReceipt.sibling_checkout_required, "false");
  assert.equal(consumerReceipt.internal_import_count, "0");
  assert.equal(consumerReceipt.application_wasm_import_count, "0");

  const builtApplications = join(
    consumerProofRoot,
    "consumer/zig-out/world-apps",
  );
  const builtWasm = join(
    builtApplications,
    "research-digest-agent.world.wasm",
  );
  const builtManifest = join(
    builtApplications,
    "research-digest-agent.manifest.bin",
  );
  requireFile(builtWasm);
  requireFile(builtManifest);

  const runtimeRoot = join(proofRoot, "runtime-only");
  const applicationRoot = join(runtimeRoot, "application");
  const archiveRoot = join(runtimeRoot, "releases");
  const materializedRoot = join(runtimeRoot, "materialized");
  mkdirSync(applicationRoot, { recursive: true });
  mkdirSync(archiveRoot, { recursive: true });
  mkdirSync(materializedRoot, { recursive: true });

  const runtimeWasm = join(
    applicationRoot,
    "research-digest-agent.world.wasm",
  );
  const runtimeManifest = join(
    applicationRoot,
    "research-digest-agent.manifest.bin",
  );
  const hostArchive = join(archiveRoot, basename(options.worldHostArchive));
  const capabilitiesArchive = join(
    archiveRoot,
    basename(options.worldCapabilitiesRuntimeArchive),
  );
  copyFileSync(builtWasm, runtimeWasm);
  copyFileSync(builtManifest, runtimeManifest);
  copyFileSync(options.worldHostArchive, hostArchive);
  copyFileSync(
    options.worldCapabilitiesRuntimeArchive,
    capabilitiesArchive,
  );

  const hostMaterialized = join(materializedRoot, "world-host");
  const capabilitiesMaterialized = join(
    materializedRoot,
    "world-capabilities",
  );
  extractReviewedArchive(hostArchive, hostMaterialized);
  extractReviewedArchive(capabilitiesArchive, capabilitiesMaterialized);
  const hostRoot = locatePackageRoot(hostMaterialized, "manifest.json");
  const capabilitiesRoot = locatePackageRoot(
    capabilitiesMaterialized,
    "package.json",
  );
  const hostPackManifest = JSON.parse(
    readFileSync(join(hostRoot, "manifest.json"), "utf8"),
  );
  const externalApplication = hostPackManifest.applications.find(
    (application) => application.name === "research-digest-agent",
  );
  assert(externalApplication, "host pack does not declare research-digest-agent");
  assert.equal(
    externalApplication.provenance,
    "external-clean-room",
    "research application is not identified as an external clean-room artifact",
  );
  assert.equal(
    sha256File(runtimeWasm),
    externalApplication.wasmSha256,
    "clean-room application WASM differs from the released host artifact",
  );
  assert.equal(
    sha256File(runtimeManifest),
    externalApplication.manifestSha256,
    "clean-room application manifest differs from the released host artifact",
  );
  assert.equal(
    hostPackManifest.sourcePins.worldRelease.url,
    options.worldUrl,
    "host pack and clean-room build use different World release URLs",
  );
  assert.equal(
    hostPackManifest.sourcePins.worldRelease.packageHash,
    consumerReceipt.world_release_hash,
    "host pack and clean-room build use different World package hashes",
  );
  assert.equal(
    hostPackManifest.sourcePins.boundaryRelease.packageHash,
    consumerReceipt.boundary_release_hash,
    "host pack and clean-room build use different Boundary package hashes",
  );
  assert.equal(
    sha256File(capabilitiesArchive),
    hostPackManifest.sourcePins.worldCapabilitiesRelease.runtimeAssetSha256,
    "capability runtime archive differs from the host's reviewed release identity",
  );
  assertCapabilityProjection(
    capabilitiesRoot,
    join(hostRoot, "capabilities"),
  );

  runCapture("bun", ["run", "proof"], capabilitiesRoot);
  const bun = executablePath("bun");
  const runtimeEnvironment = {
    ...process.env,
    PATH: "/usr/bin:/bin",
  };
  const zigProbe = spawnSync("zig", ["version"], {
    cwd: runtimeRoot,
    encoding: "utf8",
    env: runtimeEnvironment,
    stdio: ["ignore", "pipe", "pipe"],
  });
  assert(
    zigProbe.error?.code === "ENOENT" || zigProbe.status !== 0,
    "runtime proof unexpectedly exposes a Zig compiler",
  );

  const packCheck = JSON.parse(
    runCapture(
      bun,
      ["conformance/check-pack.mjs"],
      hostRoot,
      runtimeEnvironment,
    ).stdout,
  );
  assert.equal(packCheck.sourceCheckoutRequired, false);
  assert.equal(packCheck.v0RuntimeArtifactPresent, false);
  const lifecycle = JSON.parse(
    runCapture(
      bun,
      ["conformance/run.mjs"],
      hostRoot,
      runtimeEnvironment,
    ).stdout,
  );
  assert.equal(lifecycle.sourceCheckoutRequired, false);
  assert.equal(lifecycle.sourceIndependentHost, true);
  assert.equal(lifecycle.capabilityAuthoredFrame, false);
  assert.equal(lifecycle.applicationSpecificHostLogic, false);
  assert.equal(lifecycle.scenarios.researchDigest, true);
  assert.equal(lifecycle.scenarios.researchCustomEffect, true);
  assert.equal(lifecycle.scenarios.researchInternalProvider, true);
  assert.equal(lifecycle.scenarios.researchExternalCapability, true);
  assert.equal(lifecycle.scenarios.researchFreshInstanceResume, true);
  assert.equal(lifecycle.scenarios.researchDeterministicRetry, true);
  assert.equal(lifecycle.scenarios.researchCapabilityInvocations, 1);
  assert.equal(lifecycle.scenarios.researchReplayFreshEffects, 0);
  assert.equal(lifecycle.scenarios.researchBranchingChildren, 2);
  assert.equal(
    lifecycle.scenarios.researchMigrationReceiverPreflight,
    true,
  );
  assert.deepEqual(lifecycle.scenarios.researchNegativeCases, {
    wrongApplicationManifest: true,
    wrongEffectResultTarget: true,
    staleOrDuplicateResult: true,
    wrongSchema: true,
    excessiveResponseBytes: true,
    insufficientReceiverLimits: true,
    missingCapability: true,
    capabilityPolicyDenial: true,
    alteredWasmBytes: true,
    frameForAnotherApplication: true,
  });

  console.log(`world_release_url=${options.worldUrl}`);
  console.log(`world_release_hash=${consumerReceipt.world_release_hash}`);
  console.log(
    `boundary_release_hash=${consumerReceipt.boundary_release_hash}`,
  );
  console.log(`world_host_archive_sha256=${sha256File(hostArchive)}`);
  console.log(
    `world_capabilities_runtime_archive_sha256=${sha256File(capabilitiesArchive)}`,
  );
  console.log("world_1_0_externality_gate=true");
  console.log("clean_room_build=true");
  console.log("sibling_checkout_required=false");
  console.log("internal_import_count=0");
  console.log("application_wasm_import_count=0");
  console.log("custom_effect=true");
  console.log("internal_provider=true");
  console.log("external_capability=true");
  console.log("fresh_instance_resume=true");
  console.log("deterministic_retry=true");
  console.log("replay_fresh_effect_count=0");
  console.log("branching=true");
  console.log("migration=true");
  console.log("source_independent_host=true");
  passed = true;
} finally {
  if (options.keep || !passed) {
    console.error(`world_1_0_externality_proof_root=${proofRoot}`);
    if (consumerProofRoot !== null) {
      console.error(
        `world_external_consumer_proof_root=${consumerProofRoot}`,
      );
    }
  } else {
    if (consumerProofRoot !== null) {
      rmSync(consumerProofRoot, { recursive: true, force: true });
    }
    rmSync(proofRoot, { recursive: true, force: true });
  }
}

function assertCapabilityProjection(releaseRoot, projectionRoot) {
  for (const projectionFile of walkRegularFiles(projectionRoot)) {
    const path = relative(projectionRoot, projectionFile);
    if (path === "package.json") continue;
    const releaseFile = join(releaseRoot, path);
    requireFile(releaseFile);
    assert.equal(
      sha256File(projectionFile),
      sha256File(releaseFile),
      `host capability projection differs from the released runtime: ${path}`,
    );
  }
}

function extractReviewedArchive(archive, destination) {
  requireFile(archive);
  const listing = runCapture("tar", ["-tzf", archive]).stdout;
  for (const entry of listing.split("\n").filter(Boolean)) {
    assert(!entry.startsWith("/"), `archive contains absolute path: ${entry}`);
    assert(
      !entry.split("/").includes(".."),
      `archive path escapes extraction root: ${entry}`,
    );
  }
  mkdirSync(destination, { recursive: true });
  runCapture("tar", ["-xzf", archive, "-C", destination]);
  walkRegularFiles(destination);
}

function locatePackageRoot(materializedRoot, marker) {
  if (existsSync(join(materializedRoot, marker))) return materializedRoot;
  const directories = readdirSync(materializedRoot)
    .map((name) => join(materializedRoot, name))
    .filter((path) => statSync(path).isDirectory());
  assert.equal(
    directories.length,
    1,
    `release archive must contain one package root with ${marker}`,
  );
  assert(
    existsSync(join(directories[0], marker)),
    `release archive package root is missing ${marker}`,
  );
  return directories[0];
}

function walkRegularFiles(root, directory = root, result = []) {
  for (const name of readdirSync(directory)) {
    const path = join(directory, name);
    const info = lstatSync(path);
    assert(!info.isSymbolicLink(), `release artifact contains symlink: ${path}`);
    if (info.isDirectory()) walkRegularFiles(root, path, result);
    else if (info.isFile()) result.push(path);
    else assert.fail(`release artifact contains unsupported entry: ${path}`);
  }
  return result.sort();
}

function requireFile(path) {
  assert(
    existsSync(path) && statSync(path).isFile() && statSync(path).size > 0,
    `required artifact is missing or empty: ${path}`,
  );
}

function sha256File(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function executablePath(command) {
  const result = runCapture("which", [command]);
  const path = result.stdout.trim();
  requireFile(path);
  return path;
}

function proofPath(stderr, key) {
  const prefix = `${key}=`;
  const line = stderr
    .split("\n")
    .find((candidate) => candidate.startsWith(prefix));
  assert(line, `${key} was not reported`);
  const path = resolve(line.slice(prefix.length));
  assert(existsSync(path), `${key} does not exist: ${path}`);
  return path;
}

function keyValueReceipt(stdout) {
  const result = {};
  for (const line of stdout.split("\n")) {
    const index = line.indexOf("=");
    if (index > 0) result[line.slice(0, index)] = line.slice(index + 1);
  }
  return result;
}

function runCapture(command, args, cwd = undefined, env = process.env) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    env,
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
  const options = {
    boundaryArchive: null,
    keep: false,
    worldArchive: null,
    worldCapabilitiesRuntimeArchive: null,
    worldHostArchive: null,
    worldUrl: null,
    zig: "zig",
  };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    if (key === "--keep") {
      options.keep = true;
      continue;
    }
    const value = args[++index];
    if (!value) throw new Error(`missing value for ${key}`);
    switch (key) {
      case "--boundary-archive":
        options.boundaryArchive = resolve(value);
        break;
      case "--world-archive":
        options.worldArchive = resolve(value);
        break;
      case "--world-capabilities-runtime-archive":
        options.worldCapabilitiesRuntimeArchive = resolve(value);
        break;
      case "--world-host-archive":
        options.worldHostArchive = resolve(value);
        break;
      case "--world-url":
        options.worldUrl = value;
        break;
      case "--zig":
        options.zig = resolve(value);
        break;
      default:
        throw new Error(`unknown option: ${key}`);
    }
  }
  for (const [name, value] of Object.entries({
    "--boundary-archive": options.boundaryArchive,
    "--world-archive": options.worldArchive,
    "--world-capabilities-runtime-archive":
      options.worldCapabilitiesRuntimeArchive,
    "--world-host-archive": options.worldHostArchive,
    "--world-url": options.worldUrl,
  })) {
    if (value === null) throw new Error(`${name} is required`);
  }
  return options;
}
