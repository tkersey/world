import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const BOUNDARY_LEGACY_URL =
  "https://github.com/tkersey/boundary/archive/refs/tags/v0.7.0.tar.gz";
const BOUNDARY_MACHINE_URL =
  "https://github.com/tkersey/boundary/archive/refs/tags/v1.0.0.tar.gz";
const WORLD_HOST_URL =
  "https://github.com/tkersey/world-host/releases/download/v1.0.0/world-host-v1.0.0.tar.gz";
const WORLD_HOST_SHA256 =
  "f881aaf3ada062ca3d80fc46d10cb001f38504d816ecd4995faf34bcd14ecc70";
const WORLD_VERSION = "2.0.0";
const WORLD_RELEASE_URL =
  `https://github.com/tkersey/world/archive/refs/tags/v${WORLD_VERSION}.tar.gz`;
const WORLD_CAPABILITIES_VERSION = "2.0.1";
const WORLD_CAPABILITIES_REPOSITORY =
  "github.com/tkersey/world-capabilities";
const WORLD_CAPABILITIES_ASSET =
  `world-capabilities-v${WORLD_CAPABILITIES_VERSION}.tar.gz`;
const WORLD_CAPABILITIES_URL =
  `https://${WORLD_CAPABILITIES_REPOSITORY}/releases/download/v${WORLD_CAPABILITIES_VERSION}/${WORLD_CAPABILITIES_ASSET}`;

const options = parseArgs(process.argv.slice(2));
if (options.negative) {
  proveCallerArchiveChecksumAdmission();
  console.log("caller_archive_checksum_admission=true");
  console.log("caller_archive_checksum_negative=true");
  process.exit(0);
}
const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const proofRoot = mkdtempSync(join(tmpdir(), "world-2-externality-"));
let consumerProofRoot = null;
let passed = false;

try {
  const archivesRoot = join(proofRoot, "archives");
  mkdirSync(archivesRoot, { recursive: true });
  const world = materializeWorldArchive(archivesRoot);
  const boundaryLegacy = materializeArchive(
    options.boundaryArchive,
    BOUNDARY_LEGACY_URL,
    join(archivesRoot, "boundary-v0.7.0.tar.gz"),
  );
  const boundaryMachine = materializeArchive(
    options.boundaryMachineArchive,
    BOUNDARY_MACHINE_URL,
    join(archivesRoot, "boundary-v1.0.0.tar.gz"),
  );
  const worldHost = options.worldHostArchive ?? downloadReleaseAsset(
    "tkersey/world-host",
    "v1.0.0",
    "world-host-v1.0.0.tar.gz",
    archivesRoot,
  );
  requireFile(worldHost);
  assert.equal(
    sha256File(worldHost),
    WORLD_HOST_SHA256,
    "world-host archive differs from the released v1.0.0 runtime artifact",
  );
  const capabilities = materializeCapabilitiesArchive(archivesRoot);
  assertExpectedSha("World", world.archive, options.worldArchiveSha256);
  assertExpectedSha(
    "world-capabilities",
    capabilities.archive,
    options.worldCapabilitiesArchiveSha256,
  );

  const consumer = runCapture("node", [
    join(sourceRoot, "scripts/check_world_external_consumer.mjs"),
    "--keep",
    "--world-archive",
    world.archive,
    "--world-url",
    world.url,
    "--boundary-archive",
    boundaryLegacy,
    "--boundary-machine-archive",
    boundaryMachine,
    "--zig",
    executablePath(options.zig),
  ]);
  consumerProofRoot = proofPath(
    consumer.stderr,
    "world_external_consumer_proof_root",
  );
  const consumerReceipt = keyValueReceipt(consumer.stdout);
  assert.equal(consumerReceipt.clean_room_build, "true");
  assert.equal(consumerReceipt.sibling_checkout_required, "false");
  assert.equal(consumerReceipt.application_wasm_import_count, "0");
  assert.equal(
    consumerReceipt.boundary_machine_release_hash,
    "boundary-1.0.0-flclaPgFEQBhYvlC3eqNVK3X67InkTuaX-pHFvRLzWJ8",
  );

  const wasmPath = join(
    consumerProofRoot,
    "consumer/zig-out/world-apps/research-digest-agent.world.wasm",
  );
  const manifestPath = join(
    consumerProofRoot,
    "consumer/zig-out/world-apps/research-digest-agent.manifest.bin",
  );
  requireFile(wasmPath);
  requireFile(manifestPath);

  const materializedRoot = join(proofRoot, "materialized");
  const hostMaterialized = join(materializedRoot, "world-host");
  const capabilitiesMaterialized = join(
    materializedRoot,
    "world-capabilities",
  );
  extractArchive(worldHost, hostMaterialized);
  extractArchive(capabilities.archive, capabilitiesMaterialized);
  const hostRoot = locatePackageRoot(hostMaterialized, "manifest.json");
  const capabilitiesRoot = locatePackageRoot(
    capabilitiesMaterialized,
    "package.json",
  );
  const capabilityCorpus = JSON.parse(readFileSync(join(
    capabilitiesRoot,
    "packages/research-lookup-fixture/corpus.json",
  ), "utf8"));
  assert.deepEqual(capabilityCorpus.worldRelease, {
    applicationManifestSha256: sha256File(manifestPath),
    applicationWasmSha256: sha256File(wasmPath),
    tag: `v${WORLD_VERSION}`,
  }, "capability pack and clean-room build use different World release tuples");

  runCapture(
    executablePath("bun"),
    ["run", "proof:research-v2"],
    capabilitiesRoot,
  );
  const runtimePath = join(proofRoot, "runtime-path");
  mkdirSync(runtimePath);
  const runtime = runCapture(
    process.execPath,
    [
      join(sourceRoot, "scripts/check_world_2_runtime.mjs"),
      "--host-root",
      hostRoot,
      "--capabilities-root",
      capabilitiesRoot,
      "--wasm",
      wasmPath,
    ],
    proofRoot,
    { ...process.env, PATH: runtimePath },
  );
  const runtimeReceipt = keyValueReceipt(runtime.stdout);
  assert.equal(runtimeReceipt.runtime_compiler_isolated, "true");
  assert.equal(runtimeReceipt.fresh_instance_resume, "true");
  assert.equal(runtimeReceipt.deterministic_retry, "true");
  assert.equal(runtimeReceipt.replay_fresh_effect_count, "0");
  assert.equal(runtimeReceipt.branching, "true");
  assert.equal(runtimeReceipt.migration, "true");
  assert.equal(runtimeReceipt.capability_authored_frame, "false");

  console.log(`world_release_url=${world.url}`);
  console.log(`world_archive_sha256=${sha256File(world.archive)}`);
  console.log(`world_release_hash=${consumerReceipt.world_release_hash}`);
  console.log(`boundary_legacy_release_url=${BOUNDARY_LEGACY_URL}`);
  console.log(
    `boundary_legacy_release_hash=${consumerReceipt.boundary_release_hash}`,
  );
  console.log(`boundary_machine_release_url=${BOUNDARY_MACHINE_URL}`);
  console.log(
    `boundary_machine_release_hash=${consumerReceipt.boundary_machine_release_hash}`,
  );
  console.log(`world_host_release_url=${WORLD_HOST_URL}`);
  console.log(`world_host_archive_sha256=${sha256File(worldHost)}`);
  console.log(`world_capabilities_release_url=${capabilities.url}`);
  console.log(
    `world_capabilities_archive_sha256=${sha256File(capabilities.archive)}`,
  );
  console.log("world_2_externality_gate=true");
  console.log("world_application_abi=1");
  console.log("world_frame_version=1");
  console.log("effect_protocol_version=1");
  console.log("world_host_runtime_changed=false");
  console.log("application_wasm_import_count=0");
  console.log("source_checkout_required=false");
  console.log(`runtime_compiler_isolated=${runtimeReceipt.runtime_compiler_isolated}`);
  console.log(`fresh_instance_resume=${runtimeReceipt.fresh_instance_resume}`);
  console.log(`deterministic_retry=${runtimeReceipt.deterministic_retry}`);
  console.log(`replay_fresh_effect_count=${runtimeReceipt.replay_fresh_effect_count}`);
  console.log(`branching=${runtimeReceipt.branching}`);
  console.log(`migration=${runtimeReceipt.migration}`);
  console.log(`capability_authored_frame=${runtimeReceipt.capability_authored_frame}`);
  passed = true;
} finally {
  if (options.keep || !passed) {
    console.error(`world_2_externality_proof_root=${proofRoot}`);
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

function materializeWorldArchive(root) {
  return materializeReviewedArchive(
    "World",
    options.worldArchive,
    options.worldArchiveSha256,
    WORLD_RELEASE_URL,
    () => materializeArchive(
      null,
      WORLD_RELEASE_URL,
      join(root, `world-v${WORLD_VERSION}.tar.gz.reviewed`),
    ),
  );
}

function materializeCapabilitiesArchive(root) {
  return materializeReviewedArchive(
    "world-capabilities",
    options.worldCapabilitiesArchive,
    options.worldCapabilitiesArchiveSha256,
    WORLD_CAPABILITIES_URL,
    () => downloadReleaseAsset(
      WORLD_CAPABILITIES_REPOSITORY,
      `v${WORLD_CAPABILITIES_VERSION}`,
      WORLD_CAPABILITIES_ASSET,
      root,
    ),
  );
}

function materializeReviewedArchive(
  label,
  input,
  expectedSha256,
  releaseUrl,
  materializeReviewed,
) {
  if (input === null) {
    throw new Error(`${label} reviewed archive and SHA-256 are required`);
  }

  requireFile(input);
  const reviewedArchive = materializeReviewed();
  assertReviewedArchiveCopy(label, input, expectedSha256, reviewedArchive);
  return { archive: input, url: releaseUrl };
}

function materializeArchive(input, url, destination) {
  if (input !== null) {
    requireFile(input);
    return input;
  }
  const response = runCapture("curl", [
    "--fail",
    "--location",
    "--silent",
    "--show-error",
    "--output",
    destination,
    url,
  ]);
  assert.equal(response.status, 0);
  requireFile(destination);
  return destination;
}

function downloadReleaseAsset(repository, tag, asset, destination) {
  runCapture("gh", [
    "release",
    "download",
    tag,
    "--repo",
    repository,
    "--pattern",
    asset,
    "--dir",
    destination,
  ]);
  return join(destination, asset);
}

function assertExpectedSha(label, archive, expected) {
  if (expected !== null) {
    assert.equal(
      sha256File(archive),
      expected,
      `${label} archive SHA-256 mismatch`,
    );
  }
}

function assertReviewedArchiveCopy(label, archive, expected, reviewedArchive) {
  assertExpectedSha(label, archive, expected);
  assert.equal(
    sha256File(reviewedArchive),
    expected,
    `${label} archive differs from the fixed release URL`,
  );
}

function extractArchive(archive, destination) {
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
}

function locatePackageRoot(root, marker) {
  if (existsSync(join(root, marker))) return root;
  const directories = readdirSync(root)
    .map((name) => join(root, name))
    .filter((path) => statSync(path).isDirectory());
  assert.equal(directories.length, 1, `archive must contain one ${marker}`);
  assert(existsSync(join(directories[0], marker)), `archive is missing ${marker}`);
  return directories[0];
}

function proofPath(stderr, key) {
  const prefix = `${key}=`;
  const line = stderr.split("\n").find((candidate) => candidate.startsWith(prefix));
  if (!line) throw new Error(`missing ${key} from proof output`);
  return resolve(line.slice(prefix.length));
}

function keyValueReceipt(stdout) {
  return Object.fromEntries(
    stdout.split("\n").filter((line) => line.includes("=")).map((line) => {
      const index = line.indexOf("=");
      return [line.slice(0, index), line.slice(index + 1)];
    }),
  );
}

function sha256File(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function requireFile(path) {
  if (!existsSync(path) || !statSync(path).isFile() || statSync(path).size === 0) {
    throw new Error(`required file is missing: ${path}`);
  }
}

function executablePath(command) {
  if (command.includes("/")) return resolve(command);
  return runCapture("which", [command]).stdout.trim();
}

function runCapture(command, args, cwd = undefined, env = process.env) {
  const result = spawnSync(command, args, {
    cwd,
    env,
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
  const result = {
    boundaryArchive: null,
    boundaryMachineArchive: null,
    keep: false,
    negative: false,
    worldArchive: null,
    worldArchiveSha256: null,
    worldCapabilitiesArchive: null,
    worldCapabilitiesArchiveSha256: null,
    worldHostArchive: null,
    zig: "zig",
  };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    if (key === "--keep" || key === "--negative") {
      result[key.slice(2)] = true;
      continue;
    }
    const value = args[++index];
    if (!value) throw new Error(`missing value for ${key}`);
    switch (key) {
      case "--boundary-archive":
        result.boundaryArchive = resolve(value);
        break;
      case "--boundary-machine-archive":
        result.boundaryMachineArchive = resolve(value);
        break;
      case "--world-archive":
        result.worldArchive = resolve(value);
        break;
      case "--world-archive-sha256":
        result.worldArchiveSha256 = digest(value, key);
        break;
      case "--world-capabilities-archive":
        result.worldCapabilitiesArchive = resolve(value);
        break;
      case "--world-capabilities-archive-sha256":
        result.worldCapabilitiesArchiveSha256 = digest(value, key);
        break;
      case "--world-host-archive":
        result.worldHostArchive = resolve(value);
        break;
      case "--zig":
        result.zig = value.includes("/") ? resolve(value) : value;
        break;
      default:
        throw new Error(`unknown option: ${key}`);
    }
  }
  requireArchiveDigestPair(
    "--world-archive",
    result.worldArchive,
    "--world-archive-sha256",
    result.worldArchiveSha256,
  );
  requireArchiveDigestPair(
    "--world-capabilities-archive",
    result.worldCapabilitiesArchive,
    "--world-capabilities-archive-sha256",
    result.worldCapabilitiesArchiveSha256,
  );
  return result;
}

function requireArchiveDigestPair(archiveLabel, archive, digestLabel, sha256) {
  if ((archive === null) !== (sha256 === null)) {
    throw new Error(`${archiveLabel} and ${digestLabel} must be supplied together`);
  }
}

function proveCallerArchiveChecksumAdmission() {
  const sha256 = "0".repeat(64);
  assert.equal(
    WORLD_CAPABILITIES_REPOSITORY,
    "github.com/tkersey/world-capabilities",
    "world-capabilities release acquisition must remain pinned to github.com",
  );
  assert.throws(
    () => materializeReviewedArchive(
      "World",
      null,
      null,
      WORLD_RELEASE_URL,
      () => "unused-world.tar.gz",
    ),
    /World reviewed archive and SHA-256 are required/,
  );
  assert.throws(
    () => materializeReviewedArchive(
      "world-capabilities",
      null,
      null,
      WORLD_CAPABILITIES_URL,
      () => "unused-world-capabilities",
    ),
    /world-capabilities reviewed archive and SHA-256 are required/,
  );
  assert.throws(
    () => parseArgs(["--world-archive", "world.tar.gz"]),
    /--world-archive and --world-archive-sha256 must be supplied together/,
  );
  assert.throws(
    () => parseArgs(["--world-archive-sha256", sha256]),
    /--world-archive and --world-archive-sha256 must be supplied together/,
  );
  assert.throws(
    () => parseArgs(["--world-capabilities-archive", "capabilities.tar.gz"]),
    /--world-capabilities-archive and --world-capabilities-archive-sha256 must be supplied together/,
  );
  assert.throws(
    () => parseArgs(["--world-capabilities-archive-sha256", sha256]),
    /--world-capabilities-archive and --world-capabilities-archive-sha256 must be supplied together/,
  );
  assert.equal(parseArgs([
    "--world-archive",
    "world.tar.gz",
    "--world-archive-sha256",
    sha256,
  ]).worldArchiveSha256, sha256);
  assert.equal(parseArgs([
    "--world-capabilities-archive",
    "capabilities.tar.gz",
    "--world-capabilities-archive-sha256",
    sha256,
  ]).worldCapabilitiesArchiveSha256, sha256);
  assert.throws(
    () => parseArgs(["--world-url", "https://example.invalid/world.tar.gz"]),
    /unknown option: --world-url/,
  );
  assert.throws(
    () => parseArgs([
      "--world-capabilities-url",
      "https://example.invalid/capabilities.tar.gz",
    ]),
    /unknown option: --world-capabilities-url/,
  );

  const proofRoot = mkdtempSync(join(tmpdir(), "world-2-checksum-negative-"));
  try {
    const archive = join(proofRoot, "world.tar.gz");
    const reviewedArchive = join(proofRoot, "reviewed-world.tar.gz");
    writeFileSync(archive, "checksum admission witness");
    writeFileSync(reviewedArchive, "different reviewed release bytes");
    const actual = sha256File(archive);
    assert.notEqual(actual, sha256);
    assert.throws(
      () => assertExpectedSha("World", archive, sha256),
      /World archive SHA-256 mismatch/,
    );
    assert.doesNotThrow(() => assertExpectedSha("World", archive, actual));
    assert.throws(
      () => assertReviewedArchiveCopy(
        "World",
        archive,
        actual,
        reviewedArchive,
      ),
      /World archive differs from the fixed release URL/,
    );
  } finally {
    rmSync(proofRoot, { recursive: true, force: true });
  }
}

function digest(value, label) {
  if (!/^[0-9a-f]{64}$/.test(value)) {
    throw new Error(`${label} requires a lowercase SHA-256 digest`);
  }
  return value;
}
