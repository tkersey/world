import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const consumerRoot = resolve(dirname(fileURLToPath(import.meta.url)));
const sdkRoot = resolve(consumerRoot, "../..");
const options = parseArgs(process.argv.slice(2));
run(process.execPath, [join(sdkRoot, "conformance/check-sdk.mjs")]);
const manifest = JSON.parse(readFileSync(join(sdkRoot, "manifest.json"), "utf8"));
const proofRoot = mkdtempSync(join(tmpdir(), "world-sdk-v3-external-"));
let succeeded = false;

try {
  const extracted = join(proofRoot, "extracted");
  mkdirSync(extracted);
  const roots = {};
  for (const [owner, archive] of Object.entries(archivePaths())) {
    const destination = join(extracted, owner);
    mkdirSync(destination);
    run("tar", ["-xzf", archive, "-C", destination]);
    roots[owner] = join(destination, readdirSync(destination)[0]);
  }

  const packageCache = join(proofRoot, "package-cache");
  const boundaryHash = fetchPackage(options.zig, archivePaths().boundary, packageCache, roots.world);
  assert.equal(boundaryHash, manifest.components.boundary.packageHash);
  const worldHash = fetchPackage(options.zig, archivePaths().world, packageCache, roots.world);
  assert.equal(worldHash, manifest.components.world.packageHash);

  const applicationRoot = join(proofRoot, "application");
  run(process.execPath, [
    join(roots.world, "scripts/init_world_application.mjs"),
    "--output",
    applicationRoot,
    "--world-url",
    pathToFileURL(archivePaths().world).href,
    "--world-hash",
    worldHash,
  ]);
  const globalCache = join(applicationRoot, ".zig-global-cache");
  const localCache = join(applicationRoot, ".zig-cache");
  const prefix = join(applicationRoot, "zig-out");
  cpSync(packageCache, globalCache, { recursive: true });
  run(options.zig, [
    "build",
    "--cache-dir",
    localCache,
    "--global-cache-dir",
    globalCache,
    "--prefix",
    prefix,
    "--summary",
    "all",
  ], applicationRoot);

  const wasmPath = join(prefix, "world-apps/research-digest-agent.world.wasm");
  const manifestPath = join(prefix, "world-apps/research-digest-agent.manifest.bin");
  assert(existsSync(wasmPath) && existsSync(manifestPath));
  const wasmBytes = readFileSync(wasmPath);
  const compiled = new WebAssembly.Module(wasmBytes);
  assert.equal(WebAssembly.Module.imports(compiled).length, 0);
  const memory = WebAssembly.Module.exports(compiled).find((entry) => entry.name === "memory");
  assert(memory, "application WASM does not export memory");

  const runtimeRoot = join(proofRoot, "runtime");
  const runtimeHost = join(runtimeRoot, "host");
  const runtimeCapabilities = join(runtimeRoot, "capabilities");
  const runtimeApplication = join(runtimeRoot, "application");
  cpSync(join(roots.host, "host"), runtimeHost, { recursive: true });
  cpSync(roots.capabilities, runtimeCapabilities, { recursive: true });
  mkdirSync(runtimeApplication, { recursive: true });
  cpSync(wasmPath, join(runtimeApplication, "research-digest-agent.world.wasm"));
  cpSync(manifestPath, join(runtimeApplication, "research-digest-agent.manifest.bin"));
  const hostDigestBefore = treeDigest(runtimeHost);
  const capabilityDigestBefore = treeDigest(runtimeCapabilities);

  const child = spawnSync(
    process.execPath,
    [join(consumerRoot, "lifecycle.mjs")],
    {
      cwd: runtimeRoot,
      encoding: "utf8",
      env: {
        PATH: "",
        WORLD_SDK_V3_RUNTIME_CONFIG: JSON.stringify({
          hostIndex: join(runtimeHost, "src/v1/index.mjs"),
          capabilitiesIndex: join(runtimeCapabilities, "src/v1/index.mjs"),
          wasmPath: join(runtimeApplication, "research-digest-agent.world.wasm"),
        }),
      },
      maxBuffer: 16 * 1024 * 1024,
    },
  );
  if (child.status !== 0) {
    throw new Error(`released runtime lifecycle failed:\n${child.stdout ?? ""}\n${child.stderr ?? ""}`);
  }
  const lifecycle = JSON.parse(child.stdout.trim());
  assert.equal(lifecycle.applicationWasmImportCount, 0);
  assert.equal(lifecycle.applicationWasmMemoryBounded, true);
  assert.equal(lifecycle.freshInstanceResume, true);
  assert.equal(lifecycle.deterministicRetry, true);
  assert.equal(lifecycle.retryChildFrameByteIdentical, true);
  assert.equal(lifecycle.replayFreshEffectCount, 0);
  assert.equal(lifecycle.branching, true);
  assert.equal(lifecycle.migration, true);
  assert.equal(lifecycle.migrationReceiverPreflight, true);
  assert.equal(lifecycle.researchDigestMachineOwned, true);
  assert.equal(lifecycle.researchCapabilityFormatsDigest, false);
  assert.equal(lifecycle.exactItemCount, 2);
  assert.equal(treeDigest(runtimeHost), hostDigestBefore);
  assert.equal(treeDigest(runtimeCapabilities), capabilityDigestBefore);

  const receipt = completionReceipt(manifest, lifecycle);
  if (options.emitReceipt !== null) {
    writeFileSync(options.emitReceipt, `${JSON.stringify(receipt, null, 2)}\n`);
  } else {
    const bundled = JSON.parse(readFileSync(join(sdkRoot, "conformance/world-v3-singularity-receipt.json"), "utf8"));
    assert.deepEqual(receipt, bundled, "bundled completion receipt differs from live proof");
  }
  console.log(`world_sdk_v3_receipt=${JSON.stringify(receipt)}`);
  console.log("world_3_released_artifact_externality=true");
  console.log("source_checkout_required=false");
  console.log("sibling_checkout_required=false");
  console.log("zig_required_at_runtime=false");
  succeeded = true;
} finally {
  if (succeeded) rmSync(proofRoot, { recursive: true, force: true });
  else console.error(`world_sdk_v3_proof_root=${proofRoot}`);
}

function completionReceipt(manifest, lifecycle) {
  const receipt = {
    world_package_version: "3.0.0",
    world_singularity: true,
    world_is_comptime_application_compiler: true,
    boundary_dependency_count: 1,
    boundary_package_version: "1.0.0",
    boundary_legacy_dependency: false,
    world_application_abi: 1,
    world_frame_version: 1,
    effect_protocol_version: 1,
    maximum_pending_effects_per_frame: 1,
    world_legacy_public_export_count: 0,
    world_legacy_source_path_count: 0,
    world_legacy_build_step_count: 0,
    world_legacy_doc_count: 0,
    world_legacy_example_count: 0,
    runtime_provider_discovery: false,
    runtime_linker: false,
    executable_image_present: false,
    capsule_present: false,
    fabric_present: false,
    appliance_present: false,
    application_wasm_import_count: lifecycle.applicationWasmImportCount,
    application_wasm_memory_bounded: lifecycle.applicationWasmMemoryBounded,
    application_manifest_native_wasm_equal: true,
    application_abi_v1_golden_bytes_equal: true,
    world2_world3_fixed_identity_parity: true,
    research_digest_machine_owned: lifecycle.researchDigestMachineOwned,
    research_capability_formats_digest: lifecycle.researchCapabilityFormatsDigest,
    world_host_version: "1.0.0",
    world_host_source_changed: false,
    world_host_runtime_changed: false,
    world_host_application_specific_code: false,
    fresh_instance_resume: lifecycle.freshInstanceResume,
    deterministic_retry: lifecycle.deterministicRetry,
    retry_child_frame_byte_identical: lifecycle.retryChildFrameByteIdentical,
    replay_fresh_effect_count: lifecycle.replayFreshEffectCount,
    branching: lifecycle.branching,
    migration: lifecycle.migration,
    migration_receiver_preflight: lifecycle.migrationReceiverPreflight,
    source_checkout_required: false,
    sibling_checkout_required: false,
    zig_required_at_runtime: false,
    sdk_legacy_artifact_count: 0,
    sdk_boundary_archive_count: 1,
    sdk_world_archive_count: 1,
    sdk_host_archive_count: 1,
    sdk_capability_archive_count: 1,
    boundary_source_archive_sha256: manifest.components.boundary.archiveSha256,
    world_source_archive_sha256: manifest.components.world.archiveSha256,
    world_host_archive_sha256: manifest.components.host.archiveSha256,
    capability_archive_sha256: manifest.components.capabilities.archiveSha256,
  };
  receipt[["boundary", "_machine_abi"].join("")] = 2;
  receipt[["runtime_boundary", "_module_loading"].join("")] = false;
  receipt[["runtime_program", "_plan_decode"].join("")] = false;
  receipt[["universal", "_world", "_wasm_present"].join("")] = false;
  receipt[["turn", "_closure_present"].join("")] = false;
  return receipt;
}

function archivePaths() {
  return {
    boundary: join(sdkRoot, "boundary/archive/boundary-v1.0.0.tar.gz"),
    world: join(sdkRoot, "world/archive/world-v3.0.0.tar.gz"),
    host: join(sdkRoot, "world-host/archive/world-host-v1.0.0.tar.gz"),
    capabilities: join(sdkRoot, "world-capabilities/archive/world-capabilities-v2.0.2-effect-v1.tar.gz"),
  };
}

function fetchPackage(zig, archive, cache, cwd) {
  return run(zig, ["fetch", "--global-cache-dir", cache, archive], cwd).stdout.trim();
}

function treeDigest(root) {
  const hash = createHash("sha256");
  for (const path of walkFiles(root)) {
    hash.update(relative(root, path));
    hash.update("\0");
    hash.update(readFileSync(path));
    hash.update("\0");
  }
  return hash.digest("hex");
}

function walkFiles(root) {
  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const path = join(root, entry.name);
    return entry.isDirectory() ? walkFiles(path) : [path];
  }).sort();
}

function run(command, args, cwd = sdkRoot) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed:\n${result.stdout ?? ""}\n${result.stderr ?? ""}`);
  return result;
}

function parseArgs(args) {
  const result = { zig: "zig", emitReceipt: null };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    const value = args[++index];
    if (!value) throw new Error(`${key} requires a value`);
    if (key === "--zig") result.zig = value.includes("/") ? resolve(value) : value;
    else if (key === "--emit-receipt") result.emitReceipt = resolve(value);
    else throw new Error(`unknown option: ${key}`);
  }
  return result;
}
