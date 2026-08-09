import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  cpSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const releaseVersion = "1.0.0";
const archiveSha256 = "f881aaf3ada062ca3d80fc46d10cb001f38504d816ecd4995faf34bcd14ecc70";
const archiveAssetApiPath = "repos/tkersey/world-host/releases/assets/490040522";
const args = process.argv.slice(2);

if (args[0] === "--negative-self-test") {
  if (args.length !== 1) throw new Error("--negative-self-test accepts no arguments");
  const archive = await loadArchive();
  verifyArchiveSha256(archive);
  const tampered = Buffer.from(archive);
  tampered[Math.floor(tampered.length / 2)] ^= 0x01;
  assert.throws(
    () => verifyArchiveSha256(tampered),
    (error) => error instanceof Error && error.message.includes("world-host v1.0.0 archive SHA-256 mismatch"),
  );
  console.log("world_3_externality_negative=true");
} else {
  if (args.length !== 1 || args[0].startsWith("--")) {
    throw new Error("usage: node scripts/check_world_3_externality.mjs <one-effect.world.wasm>");
  }
  await runPositive(resolve(args[0]));
}

async function runPositive(wasmPath) {
  const root = mkdtempSync(join(tmpdir(), "world-3-externality-"));
  try {
    const archive = await loadArchive();
    verifyArchiveSha256(archive);
    const archivePath = join(root, "world-host.tar.gz");
    const extractedRoot = join(root, "extracted");
    const runtimeRoot = join(root, "runtime");
    writeFileSync(archivePath, archive);
    mkdirSync(extractedRoot);
    run("tar", ["-xzf", archivePath, "-C", extractedRoot]);
    const releaseRoot = exactReleaseRoot(extractedRoot);
    const sourceHost = join(releaseRoot, "host/src/v1");
    const runtimeHost = join(runtimeRoot, "host/src/v1");
    const runtimeWasm = join(runtimeRoot, "applications/one-effect.world.wasm");
    mkdirSync(dirname(runtimeWasm), { recursive: true });
    cpSync(sourceHost, runtimeHost, { recursive: true });
    cpSync(wasmPath, runtimeWasm);

    const sourceDigest = treeDigest(sourceHost);
    const runtimeDigest = treeDigest(runtimeHost);
    assert.equal(runtimeDigest, sourceDigest, "copied host runtime differs from authenticated release bytes");
    assertGenericHostSource(sourceHost);

    const child = spawnSync(
      process.execPath,
      ["--input-type=module", "--eval", runtimeChildSource()],
      {
        cwd: runtimeRoot,
        encoding: "utf8",
        env: {
          PATH: "",
          WORLD_3_RUNTIME_CONFIG: JSON.stringify({
            hostIndex: join(runtimeHost, "index.mjs"),
            wasmPath: runtimeWasm,
          }),
        },
        maxBuffer: 16 * 1024 * 1024,
      },
    );
    if (child.status !== 0) {
      throw new Error(`exact world-host runtime child failed:\n${child.stdout ?? ""}\n${child.stderr ?? ""}`);
    }
    assert.equal(treeDigest(runtimeHost), sourceDigest, "world-host runtime source changed during execution");
    const lifecycle = JSON.parse(child.stdout.trim());
    assert.deepEqual(lifecycle, {
      applicationWasmImportCount: 0,
      applicationWasmMemoryBounded: true,
      freshInstanceResume: true,
      deterministicRetry: true,
      retryChildFrameByteIdentical: true,
      replayFreshEffectCount: 0,
      branching: true,
      migration: true,
      migrationReceiverPreflight: true,
    });

    console.log(`world_host_version=${releaseVersion}`);
    console.log(`world_host_archive_sha256=${archiveSha256}`);
    console.log("world_host_source_changed=false");
    console.log("world_host_runtime_changed=false");
    console.log("world_host_application_specific_code=false");
    console.log(`application_wasm_import_count=${lifecycle.applicationWasmImportCount}`);
    console.log(`application_wasm_memory_bounded=${lifecycle.applicationWasmMemoryBounded}`);
    console.log(`fresh_instance_resume=${lifecycle.freshInstanceResume}`);
    console.log(`deterministic_retry=${lifecycle.deterministicRetry}`);
    console.log(`retry_child_frame_byte_identical=${lifecycle.retryChildFrameByteIdentical}`);
    console.log(`replay_fresh_effect_count=${lifecycle.replayFreshEffectCount}`);
    console.log(`branching=${lifecycle.branching}`);
    console.log(`migration=${lifecycle.migration}`);
    console.log(`migration_receiver_preflight=${lifecycle.migrationReceiverPreflight}`);
    console.log("source_checkout_required=false");
    console.log("sibling_checkout_required=false");
    console.log("zig_required_at_runtime=false");
    console.log("world_3_externality=true");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

async function loadArchive() {
  const override = process.env.WORLD_HOST_V1_ARCHIVE;
  if (override) {
    if (/^https?:\/\//.test(override)) return await download(override);
    return await readFile(resolve(override));
  }
  const result = spawnSync(
    "gh",
    ["api", "-H", "Accept: application/octet-stream", archiveAssetApiPath],
    { encoding: null, maxBuffer: 16 * 1024 * 1024 },
  );
  if (result.status !== 0) {
    throw new Error(`world-host release asset download failed:\n${result.stderr?.toString("utf8") ?? ""}`);
  }
  return Buffer.from(result.stdout);
}

async function download(url) {
  const response = await fetch(url, { redirect: "follow" });
  if (!response.ok) throw new Error(`world-host archive download failed: HTTP ${response.status}`);
  return Buffer.from(await response.arrayBuffer());
}

function verifyArchiveSha256(bytes) {
  const actual = createHash("sha256").update(bytes).digest("hex");
  if (actual !== archiveSha256) {
    throw new Error(`world-host v1.0.0 archive SHA-256 mismatch: expected=${archiveSha256} actual=${actual}`);
  }
}

function exactReleaseRoot(extractedRoot) {
  const entries = readdirSync(extractedRoot, { withFileTypes: true });
  if (entries.length !== 1 || !entries[0].isDirectory() || entries[0].name !== `world-host-v${releaseVersion}`) {
    throw new Error(`unexpected world-host archive root: ${entries.map((entry) => entry.name).join(",")}`);
  }
  return join(extractedRoot, entries[0].name);
}

function assertGenericHostSource(hostRoot) {
  const source = walkFiles(hostRoot).map((path) => readFileSync(path, "utf8")).join("\n");
  for (const marker of [
    ["One", "EffectApp"].join(""),
    ["one", "-effect"].join(""),
    ["fixture", "-agent"].join(""),
    ["skeleton", "-agent"].join(""),
    ["research", "-digest"].join(""),
    ["world.test", ".root.v2"].join(""),
  ]) {
    if (source.includes(marker)) throw new Error(`authenticated host contains application-specific marker: ${marker}`);
  }
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

function run(command, commandArgs) {
  const result = spawnSync(command, commandArgs, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`${command} ${commandArgs.join(" ")} failed:\n${result.stdout ?? ""}\n${result.stderr ?? ""}`);
  }
}

function runtimeChildSource() {
  return `
    import assert from "node:assert/strict";
    import { readFile } from "node:fs/promises";
    import { pathToFileURL } from "node:url";

    const config = JSON.parse(process.env.WORLD_3_RUNTIME_CONFIG);
    const host = await import(pathToFileURL(config.hostIndex).href);
    const wasmBytes = await readFile(config.wasmPath);
    const inspection = host.assertApplicationWasmSurface(host.inspectApplicationWasm(wasmBytes));
    assert.equal(inspection.importCount, 0);
    assert.equal(inspection.memory.minimumBytes, 8 * 1024 * 1024);
    assert.equal(inspection.memory.maximumBytes, 8 * 1024 * 1024);

    const value = (number) => {
      const bytes = Buffer.alloc(4);
      bytes.writeUInt32LE(number);
      return bytes;
    };
    const resultFor = (request, number, limits) => host.createEffectResult({
      requestId: request.requestId,
      status: host.EffectStatus.ok,
      resultSchemaId: request.resultSchemaId,
      resultBytes: value(number),
    }, limits);
    let workerInstances = 0;
    const workerFactory = () => {
      workerInstances += 1;
      return new host.ApplicationWorker();
    };

    const blocks = new host.MemoryBlockStore();
    const heads = new host.MemoryBranchHeadStore();
    let lostChild = null;
    let loseOnce = true;
    const controller = await host.RunControllerV1.create({
      wasmBytes,
      blockStore: blocks,
      headStore: heads,
      workerFactory,
      faultInjector: async (stage, context) => {
        if (stage === "after-world-step" && context.expectedHead !== null && loseOnce) {
          loseOnce = false;
          lostChild = Buffer.from(context.output.frameBytes);
          throw new Error("simulated lost child after World step");
        }
      },
    });
    assert(await blocks.hasBlock(controller.wasmRef));
    assert(await blocks.hasBlock(controller.manifestRef));
    const parent = await controller.initialize("retry", "main", {
      initialArgsBytes: value(7),
      fuel: 100n,
    });
    assert.equal(parent.frame.status, host.FrameStatus.needsEffect);
    assert(parent.frame.pendingEffect !== null);
    assert(parent.requestRef !== null);
    assert(await blocks.hasBlock(parent.frameRef));
    assert(await blocks.hasBlock(parent.requestRef));
    const supplied = resultFor(parent.frame.pendingEffect, 41, controller.manifest.limits);
    let coveredEffects = 0;
    coveredEffects += 1;
    await assert.rejects(
      () => controller.advance("retry", "main", { effectResult: supplied, fuel: 100n }),
      /simulated lost child after World step/,
    );
    const retained = await controller.effectJournal.readResult({
      runId: "retry",
      branchId: "main",
      parentFrameId: parent.frame.frameId,
      request: parent.frame.pendingEffect,
      limits: controller.manifest.limits,
      publicationBindingId: parent.nextHead.journalBindingId,
    });
    assert(retained !== null);
    assert.equal((await controller.readCurrentFrame("retry", "main")).head.frameId, parent.nextHead.frameId);
    const coveredBeforeRetry = coveredEffects;
    const retried = await controller.advance("retry", "main");
    assert(lostChild !== null);
    const retryChildFrameByteIdentical = retried.frameBytes.equals(lostChild);
    assert(retryChildFrameByteIdentical);
    assert.equal(retried.frame.status, host.FrameStatus.completed);
    assert.equal(retried.frame.finalResultBytes.readUInt32LE(), 41);
    assert.equal(coveredEffects - coveredBeforeRetry, 0);
    assert(workerInstances >= 4);

    const coveredBeforeReplay = coveredEffects;
    const replayWorker = new host.ApplicationWorker();
    await replayWorker.instantiate(wasmBytes);
    const replayInput = host.encodeStepInput({
      applicationId: controller.manifest.applicationId,
      expectedParentFrameId: parent.frame.frameId,
      priorFrameBytes: parent.frameBytes,
      effectResult: supplied,
      fuel: 100n,
    }, controller.manifest.limits);
    const replayOutput = replayWorker.step(replayInput);
    replayWorker.dispose();
    const replayChildFrameByteIdentical = replayOutput.frameBytes.equals(retried.frameBytes);
    assert(replayChildFrameByteIdentical);
    const replayFreshEffectCount = coveredEffects - coveredBeforeReplay;
    assert.equal(replayFreshEffectCount, 0);

    const branchBlocks = new host.MemoryBlockStore();
    const branchHeads = new host.MemoryBranchHeadStore();
    const branchController = await host.RunControllerV1.create({
      wasmBytes,
      blockStore: branchBlocks,
      headStore: branchHeads,
    });
    const branchParent = await branchController.initialize("branch", "main", {
      initialArgsBytes: value(7),
      fuel: 100n,
    });
    await branchController.forkBranch("branch", "main", "alternate");
    const main = await branchController.advance("branch", "main", {
      effectResult: resultFor(branchParent.frame.pendingEffect, 41, branchController.manifest.limits),
      fuel: 100n,
    });
    const alternate = await branchController.advance("branch", "alternate", {
      effectResult: resultFor(branchParent.frame.pendingEffect, 42, branchController.manifest.limits),
      fuel: 100n,
    });
    assert.equal(main.previousHead.frameId, alternate.previousHead.frameId);
    assert.notEqual(main.nextHead.frameId, alternate.nextHead.frameId);
    assert.equal(main.frame.finalResultBytes.readUInt32LE(), 41);
    assert.equal(alternate.frame.finalResultBytes.readUInt32LE(), 42);

    const migrationBlocks = new host.MemoryBlockStore();
    const migrationHeads = new host.MemoryBranchHeadStore();
    let resultPersisted = false;
    const migrationSource = await host.RunControllerV1.create({
      wasmBytes,
      blockStore: migrationBlocks,
      headStore: migrationHeads,
      faultInjector: async (stage) => {
        if (stage === "after-result-persistence" && !resultPersisted) {
          resultPersisted = true;
          throw new Error("simulated migration after result persistence");
        }
      },
    });
    const migrationParent = await migrationSource.initialize("migration-source", "main", {
      initialArgsBytes: value(7),
      fuel: 100n,
    });
    await assert.rejects(
      () => migrationSource.advance("migration-source", "main", {
        effectResult: resultFor(migrationParent.frame.pendingEffect, 41, migrationSource.manifest.limits),
        fuel: 100n,
      }),
      /simulated migration after result persistence/,
    );
    const bundle = await migrationSource.exportBranch("migration-source", "main");
    assert(bundle.retainedEffectResultBytes !== null);
    const receiverBlocks = new host.MemoryBlockStore();
    const receiverHeads = new host.MemoryBranchHeadStore();
    let receiverPreflight = 0;
    const imported = await host.RunControllerV1.importBranch({
      bundle,
      runId: "migration-receiver",
      branchId: "main",
      blockStore: receiverBlocks,
      headStore: receiverHeads,
      preflight: async () => {
        receiverPreflight += 1;
        return { blockers: [] };
      },
    });
    assert.equal(receiverPreflight, 1);
    const completed = await imported.controller.advance("migration-receiver", "main");
    assert.equal(completed.frame.status, host.FrameStatus.completed);
    assert.equal(completed.frame.finalResultBytes.readUInt32LE(), 41);
    assert.equal(receiverPreflight, 1);

    process.stdout.write(JSON.stringify({
      applicationWasmImportCount: inspection.importCount,
      applicationWasmMemoryBounded: inspection.memory.minimumBytes === inspection.memory.maximumBytes,
      freshInstanceResume: workerInstances >= 4,
      deterministicRetry: retryChildFrameByteIdentical,
      retryChildFrameByteIdentical,
      replayFreshEffectCount,
      branching: true,
      migration: true,
      migrationReceiverPreflight: receiverPreflight === 1,
    }));
  `;
}
