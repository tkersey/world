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
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

const BOUNDARY_LEGACY_URL =
  "https://github.com/tkersey/boundary/archive/refs/tags/v0.7.0.tar.gz";
const BOUNDARY_MACHINE_URL =
  "https://github.com/tkersey/boundary/archive/refs/tags/v1.0.0-rc.1.tar.gz";
const WORLD_HOST_URL =
  "https://github.com/tkersey/world-host/releases/download/v1.0.0/world-host-v1.0.0.tar.gz";
const WORLD_HOST_SHA256 =
  "f881aaf3ada062ca3d80fc46d10cb001f38504d816ecd4995faf34bcd14ecc70";
const WORLD_VERSION = "2.0.0-rc.1";
const BOUNDARY_VERSION = "1.0.0-rc.1";

const options = parseArgs(process.argv.slice(2));
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
    join(archivesRoot, "boundary-v1.0.0-rc.1.tar.gz"),
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
    "boundary-1.0.0-rc.1-flclaP0FEQApv6S-kj0cKVzgh8KgaV2afbb26rSJHF3O",
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
  const wasmBytes = readFileSync(wasmPath);

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
    archiveSha256: sha256File(world.archive),
    packageHash: consumerReceipt.world_release_hash,
    tag: `v${WORLD_VERSION}`,
  }, "capability pack and clean-room build use different World release tuples");

  runCapture(
    executablePath("bun"),
    ["run", "proof:research-v2"],
    capabilitiesRoot,
  );
  const host = await import(
    pathToFileURL(join(hostRoot, "host/src/v1/index.mjs")).href
  );
  const capability = await import(
    pathToFileURL(join(capabilitiesRoot, "src/v1/index.mjs")).href
  );
  const proof = await proveRuntime(host, capability, wasmBytes);

  const runtimePath = join(proofRoot, "runtime-path");
  mkdirSync(runtimePath);
  const zigProbe = spawnSync("zig", ["version"], {
    cwd: proofRoot,
    encoding: "utf8",
    env: { ...process.env, PATH: runtimePath },
    stdio: ["ignore", "pipe", "pipe"],
  });
  assert(
    zigProbe.error?.code === "ENOENT" || zigProbe.status !== 0,
    "runtime proof unexpectedly exposes a Zig compiler",
  );

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
  console.log("fresh_instance_resume=true");
  console.log("deterministic_retry=true");
  console.log(`replay_fresh_effect_count=${proof.replayFreshEffectCount}`);
  console.log("branching=true");
  console.log("migration=true");
  console.log("capability_authored_frame=false");
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

async function proveRuntime(host, capability, wasmBytes) {
  const blockStore = new host.MemoryBlockStore();
  const headStore = new host.MemoryBranchHeadStore();
  const effectJournal = new host.MemoryEffectJournalV1({ blockStore });
  const controller = await host.RunControllerV1.create({
    wasmBytes,
    blockStore,
    headStore,
    effectJournal,
  });
  const manifest = controller.manifest;
  assert.equal(manifest.worldApplicationAbiVersion, 1);
  assert.equal(manifest.worldPackageVersion, WORLD_VERSION);
  assert.equal(manifest.boundaryPackageVersion, BOUNDARY_VERSION);
  assert.equal(
    Buffer.from(manifest.applicationId).toString("hex"),
    capability.RESEARCH_DIGEST_APPLICATION_ID,
    "capability application allowlist differs from the built World application",
  );

  const started = await controller.initialize("world-2", "main", {
    initialArgsBytes: encodeResearchRequest({
      query: "portable algebraic effects",
      maximumItems: 2,
    }),
    fuel: 10_000n,
  });
  assert.equal(started.status, "advanced");
  assert.equal(started.frame.status, host.FrameStatus.needsEffect);
  await controller.forkBranch("world-2", "main", "retry");
  await controller.forkBranch("world-2", "main", "migration");

  const router = new capability.CapabilityRouterV1({
    bindings: [capability.researchLookupFixtureBinding()],
  });
  const effectContext = {
    attempt: 1,
    effectAttempted: 0,
    policy: { researchLookup: true },
  };
  const resolution = await router.resolve(
    effectContext,
    started.frame.pendingEffect.encodedBytes,
  );
  assert.equal(effectContext.effectAttempted, 1);
  const effectMetadata = {
    handlerId: resolution.handlerIdentity,
    handlerConfigurationId: resolution.handlerConfigurationIdentity,
    recoveryClass: resolution.recoveryClass,
  };

  const crashingMain = await crashingController(
    host,
    wasmBytes,
    blockStore,
    headStore,
    effectJournal,
  );
  await assert.rejects(
    () => crashingMain.advance("world-2", "main", {
      effectResult: resolution.result,
      effectMetadata,
      fuel: 10_000n,
    }),
    /injected process loss after result persistence/,
  );
  const completed = await controller.advance("world-2", "main");
  assert.equal(completed.frame.status, host.FrameStatus.completed);

  const retried = await controller.advance("world-2", "retry", {
    effectResult: resolution.result,
    effectMetadata,
    fuel: 10_000n,
  });
  assert.equal(retried.frame.status, host.FrameStatus.completed);
  assert.deepEqual(retried.frameBytes, completed.frameBytes);

  const crashingMigration = await crashingController(
    host,
    wasmBytes,
    blockStore,
    headStore,
    effectJournal,
  );
  await assert.rejects(
    () => crashingMigration.advance("world-2", "migration", {
      effectResult: resolution.result,
      effectMetadata,
      fuel: 10_000n,
    }),
    /injected process loss after result persistence/,
  );
  const bundle = await controller.exportBranch("world-2", "migration");
  assert(bundle.retainedEffectResultBytes !== null);
  const receiverBlockStore = new host.MemoryBlockStore();
  const receiverHeadStore = new host.MemoryBranchHeadStore();
  const imported = await host.RunControllerV1.importBranch({
    bundle,
    runId: "world-2-imported",
    branchId: "main",
    blockStore: receiverBlockStore,
    headStore: receiverHeadStore,
  });
  const migrated = await imported.controller.advance(
    "world-2-imported",
    "main",
  );
  assert.equal(migrated.frame.status, host.FrameStatus.completed);
  assert.deepEqual(migrated.frameBytes, completed.frameBytes);
  assert.equal(effectContext.effectAttempted, 1);

  const hostileBinding = capability.researchLookupFixtureBinding({
    adapter: {
      preflight: async (_context, request) => ({
        requestId: request.requestId,
        status: "ok",
        payload: { admitted: true },
      }),
      resolve: async (_context, request) => ({
        requestId: request.requestId,
        status: "ok",
        payload: { items: [] },
        frameBytes: Buffer.from("forbidden"),
      }),
    },
  });
  await assert.rejects(
    () => new capability.CapabilityRouterV1({ bindings: [hostileBinding] })
      .resolve(
        { policy: { researchLookup: true } },
        started.frame.pendingEffect.encodedBytes,
      ),
    { code: "ERR_CAPABILITY_V1_WORLD_EVIDENCE" },
  );

  return { replayFreshEffectCount: effectContext.effectAttempted - 1 };
}

async function crashingController(
  host,
  wasmBytes,
  blockStore,
  headStore,
  effectJournal,
) {
  let interrupted = false;
  return await host.RunControllerV1.create({
    wasmBytes,
    blockStore,
    headStore,
    effectJournal,
    faultInjector: async (stage) => {
      if (stage === "after-result-persistence" && !interrupted) {
        interrupted = true;
        throw new Error("injected process loss after result persistence");
      }
    },
  });
}

function materializeWorldArchive(root) {
  if (options.worldArchive !== null) {
    requireFile(options.worldArchive);
    if (options.worldUrl === null) {
      throw new Error("--world-url is required with --world-archive");
    }
    return { archive: options.worldArchive, url: options.worldUrl };
  }
  requireCleanCheckout(sourceRoot, "World");
  const commit = runCapture(
    "git",
    ["-C", sourceRoot, "rev-parse", "HEAD"],
  ).stdout.trim();
  const archive = join(root, "world-v2.0.0-rc.1.tar.gz");
  runCapture("git", [
    "-C",
    sourceRoot,
    "archive",
    "--format=tar.gz",
    "--prefix=world/",
    `--output=${archive}`,
    commit,
  ]);
  return {
    archive,
    url: options.worldUrl ??
      `https://github.com/tkersey/world/archive/${commit}.tar.gz`,
  };
}

function materializeCapabilitiesArchive(root) {
  if (options.worldCapabilitiesArchive !== null) {
    requireFile(options.worldCapabilitiesArchive);
    return {
      archive: options.worldCapabilitiesArchive,
      url: options.worldCapabilitiesUrl ?? "caller-supplied",
    };
  }
  const repository = resolve(sourceRoot, "../world-capabilities");
  requireCleanCheckout(repository, "world-capabilities");
  const commit = runCapture(
    "git",
    ["-C", repository, "rev-parse", "HEAD"],
  ).stdout.trim();
  const archive = join(root, "world-capabilities-v2.0.0.tar.gz");
  runCapture("git", [
    "-C",
    repository,
    "archive",
    "--format=tar.gz",
    "--prefix=world-capabilities/",
    `--output=${archive}`,
    commit,
  ]);
  return {
    archive,
    url: options.worldCapabilitiesUrl ??
      `https://github.com/tkersey/world-capabilities/archive/${commit}.tar.gz`,
  };
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

function requireCleanCheckout(repository, label) {
  const status = runCapture("git", [
    "-C",
    repository,
    "status",
    "--porcelain=v2",
    "--untracked-files=all",
    "--ignore-submodules=none",
  ]).stdout.trim();
  if (status.length !== 0) {
    throw new Error(`${label} checkout must be clean or supplied as an archive`);
  }
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

function encodeResearchRequest(value) {
  const query = Buffer.from(value.query, "utf8");
  const queryLength = Buffer.alloc(4);
  queryLength.writeUInt32LE(query.length);
  const maximumItems = Buffer.alloc(4);
  maximumItems.writeUInt32LE(value.maximumItems);
  return Buffer.concat([queryLength, query, maximumItems]);
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
    worldArchive: null,
    worldArchiveSha256: null,
    worldCapabilitiesArchive: null,
    worldCapabilitiesArchiveSha256: null,
    worldCapabilitiesUrl: null,
    worldHostArchive: null,
    worldUrl: null,
    zig: "zig",
  };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    if (key === "--keep") {
      result.keep = true;
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
      case "--world-capabilities-url":
        result.worldCapabilitiesUrl = value;
        break;
      case "--world-host-archive":
        result.worldHostArchive = resolve(value);
        break;
      case "--world-url":
        result.worldUrl = value;
        break;
      case "--zig":
        result.zig = value.includes("/") ? resolve(value) : value;
        break;
      default:
        throw new Error(`unknown option: ${key}`);
    }
  }
  return result;
}

function digest(value, label) {
  if (!/^[0-9a-f]{64}$/.test(value)) {
    throw new Error(`${label} requires a lowercase SHA-256 digest`);
  }
  return value;
}
