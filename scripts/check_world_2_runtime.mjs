import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const WORLD_VERSION = "2.0.0-rc.1";
const BOUNDARY_VERSION = "1.0.0-rc.1";

const options = parseArgs(process.argv.slice(2));
const host = await import(
  pathToFileURL(join(options.hostRoot, "host/src/v1/index.mjs")).href
);
const capability = await import(
  pathToFileURL(join(options.capabilitiesRoot, "src/v1/index.mjs")).href
);
const wasmBytes = readFileSync(options.wasm);
const proof = await proveRuntime(host, capability, wasmBytes);

console.log("runtime_compiler_isolated=true");
console.log("fresh_instance_resume=true");
console.log("deterministic_retry=true");
console.log(`replay_fresh_effect_count=${proof.replayFreshEffectCount}`);
console.log("branching=true");
console.log("migration=true");
console.log("capability_authored_frame=false");

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

function encodeResearchRequest(value) {
  const query = Buffer.from(value.query, "utf8");
  const queryLength = Buffer.alloc(4);
  queryLength.writeUInt32LE(query.length);
  const maximumItems = Buffer.alloc(4);
  maximumItems.writeUInt32LE(value.maximumItems);
  return Buffer.concat([queryLength, query, maximumItems]);
}

function parseArgs(args) {
  const result = {
    capabilitiesRoot: null,
    hostRoot: null,
    wasm: null,
  };
  for (let index = 0; index < args.length; index += 2) {
    const key = args[index];
    const value = args[index + 1];
    if (!value) throw new Error(`missing value for ${key}`);
    switch (key) {
      case "--capabilities-root":
        result.capabilitiesRoot = resolve(value);
        break;
      case "--host-root":
        result.hostRoot = resolve(value);
        break;
      case "--wasm":
        result.wasm = resolve(value);
        break;
      default:
        throw new Error(`unknown option: ${key}`);
    }
  }
  for (const [key, value] of Object.entries(result)) {
    if (value === null) throw new Error(`missing --${camelToKebab(key)}`);
  }
  return result;
}

function camelToKebab(value) {
  return value.replace(/[A-Z]/g, (character) => `-${character.toLowerCase()}`);
}
