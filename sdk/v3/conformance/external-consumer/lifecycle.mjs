import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const config = JSON.parse(process.env.WORLD_SDK_V3_RUNTIME_CONFIG);
const host = await import(pathToFileURL(config.hostIndex).href);
const capabilities = await import(pathToFileURL(config.capabilitiesIndex).href);
const wasmBytes = await readFile(config.wasmPath);
const inspection = host.assertApplicationWasmSurface(host.inspectApplicationWasm(wasmBytes));
assert.equal(inspection.importCount, 0);
assert.equal(inspection.memory.minimumBytes, inspection.memory.maximumBytes);

const router = new capabilities.CapabilityRouterV1({
  bindings: [capabilities.researchLookupFixtureBinding()],
});
let freshCapabilityEffects = 0;
async function resolveCapability(request) {
  const context = {
    policy: { researchLookup: true },
    effectAttempted: 0,
    attempt: 1,
  };
  const resolved = await router.resolve(context, request.encodedBytes);
  freshCapabilityEffects += context.effectAttempted;
  assert.equal(context.effectAttempted, 1);
  return resolved;
}

let workerInstances = 0;
const workerFactory = () => {
  workerInstances += 1;
  return new host.ApplicationWorker();
};
let lostChild = null;
let loseOnce = true;
const blocks = new host.MemoryBlockStore();
const heads = new host.MemoryBranchHeadStore();
const controller = await host.RunControllerV1.create({
  wasmBytes,
  blockStore: blocks,
  headStore: heads,
  workerFactory,
  faultInjector: async (stage, context) => {
    if (stage === "after-world-step" && context.expectedHead !== null && loseOnce) {
      loseOnce = false;
      lostChild = Buffer.from(context.output.frameBytes);
      throw new Error("simulated lost child after application step");
    }
  },
});
assert.equal(hex(controller.manifest.applicationId), capabilities.RESEARCH_DIGEST_APPLICATION_ID);
assert(await blocks.hasBlock(controller.wasmRef));
assert(await blocks.hasBlock(controller.manifestRef));

const initialArgsBytes = encodeResearchRequest({
  query: "portable algebraic effects",
  maximumItems: 2,
});
const parent = await controller.initialize("retry", "main", {
  initialArgsBytes,
  fuel: 10_000n,
});
assert.equal(parent.frame.status, host.FrameStatus.needsEffect);
assert(parent.frame.pendingEffect !== null);
assert(await blocks.hasBlock(parent.frameRef));
assert(await blocks.hasBlock(parent.requestRef));
const supplied = await resolveCapability(parent.frame.pendingEffect);
const capabilityItems = capabilities.decodeResearchResponse(supplied.result.resultBytes);
assert.equal(capabilityItems.items.length, 2);
const effectsBeforeRetry = freshCapabilityEffects;
await assert.rejects(
  () => controller.advance("retry", "main", {
    effectResult: supplied.result,
    fuel: 10_000n,
    effectMetadata: metadata(supplied),
  }),
  /simulated lost child after application step/,
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
const retried = await controller.advance("retry", "main");
assert(lostChild !== null);
assert(retried.frameBytes.equals(lostChild));
assert.equal(freshCapabilityEffects, effectsBeforeRetry);
assert.equal(retried.frame.status, host.FrameStatus.completed);
const digestResult = decodeDigestResult(retried.frame.finalResultBytes);
assert.deepEqual(digestResult, {
  digest: "Effect rows as application boundaries\nStatic closure leaves authority outside the guest.\nPortable continuations\nCanonical Frames resume in fresh WASM instances.\n",
  itemCount: 2,
});
assert(workerInstances >= 4);

const effectsBeforeReplay = freshCapabilityEffects;
const replayWorker = new host.ApplicationWorker();
await replayWorker.instantiate(wasmBytes);
const replayInput = host.encodeStepInput({
  applicationId: controller.manifest.applicationId,
  expectedParentFrameId: parent.frame.frameId,
  priorFrameBytes: parent.frameBytes,
  effectResult: supplied.result,
  fuel: 10_000n,
}, controller.manifest.limits);
const replayOutput = replayWorker.step(replayInput);
replayWorker.dispose();
assert(replayOutput.frameBytes.equals(retried.frameBytes));
const replayFreshEffectCount = freshCapabilityEffects - effectsBeforeReplay;
assert.equal(replayFreshEffectCount, 0);

const branchController = await host.RunControllerV1.create({
  wasmBytes,
  blockStore: new host.MemoryBlockStore(),
  headStore: new host.MemoryBranchHeadStore(),
});
const branchParent = await branchController.initialize("branch", "main", {
  initialArgsBytes,
  fuel: 10_000n,
});
await branchController.forkBranch("branch", "main", "alternate");
const branchResult = await resolveCapability(branchParent.frame.pendingEffect);
const main = await branchController.advance("branch", "main", {
  effectResult: branchResult.result,
  fuel: 10_000n,
  effectMetadata: metadata(branchResult),
});
const alternate = await branchController.advance("branch", "alternate", {
  effectResult: branchResult.result,
  fuel: 10_000n,
  effectMetadata: metadata(branchResult),
});
assert.equal(main.previousHead.frameId, alternate.previousHead.frameId);
assert.equal(main.frame.status, host.FrameStatus.completed);
assert.equal(alternate.frame.status, host.FrameStatus.completed);

let resultPersisted = false;
const migrationSource = await host.RunControllerV1.create({
  wasmBytes,
  blockStore: new host.MemoryBlockStore(),
  headStore: new host.MemoryBranchHeadStore(),
  faultInjector: async (stage) => {
    if (stage === "after-result-persistence" && !resultPersisted) {
      resultPersisted = true;
      throw new Error("simulated migration after result persistence");
    }
  },
});
const migrationParent = await migrationSource.initialize("migration-source", "main", {
  initialArgsBytes,
  fuel: 10_000n,
});
const migrationResult = await resolveCapability(migrationParent.frame.pendingEffect);
await assert.rejects(
  () => migrationSource.advance("migration-source", "main", {
    effectResult: migrationResult.result,
    fuel: 10_000n,
    effectMetadata: metadata(migrationResult),
  }),
  /simulated migration after result persistence/,
);
const bundle = await migrationSource.exportBranch("migration-source", "main");
assert(bundle.retainedEffectResultBytes !== null);
let receiverPreflight = 0;
const imported = await host.RunControllerV1.importBranch({
  bundle,
  runId: "migration-receiver",
  branchId: "main",
  blockStore: new host.MemoryBlockStore(),
  headStore: new host.MemoryBranchHeadStore(),
  preflight: async () => {
    receiverPreflight += 1;
    return { blockers: [] };
  },
});
const effectsBeforeMigrationResume = freshCapabilityEffects;
const completed = await imported.controller.advance("migration-receiver", "main");
assert.equal(completed.frame.status, host.FrameStatus.completed);
assert.deepEqual(decodeDigestResult(completed.frame.finalResultBytes), digestResult);
assert.equal(freshCapabilityEffects, effectsBeforeMigrationResume);
assert.equal(receiverPreflight, 1);

process.stdout.write(JSON.stringify({
  applicationWasmImportCount: inspection.importCount,
  applicationWasmMemoryBounded: inspection.memory.minimumBytes === inspection.memory.maximumBytes,
  freshInstanceResume: workerInstances >= 4,
  deterministicRetry: true,
  retryChildFrameByteIdentical: retried.frameBytes.equals(lostChild),
  replayFreshEffectCount,
  branching: true,
  migration: true,
  migrationReceiverPreflight: receiverPreflight === 1,
  researchDigestMachineOwned: true,
  researchCapabilityFormatsDigest: false,
  exactDigest: digestResult.digest,
  exactItemCount: digestResult.itemCount,
  capabilityFreshEffectCount: freshCapabilityEffects,
}));

function metadata(resolved) {
  return {
    handlerId: resolved.handlerIdentity,
    handlerConfigurationId: resolved.handlerConfigurationIdentity,
    recoveryClass: resolved.recoveryClass,
  };
}

function encodeResearchRequest(value) {
  return Buffer.concat([encodeString(value.query), u32(value.maximumItems)]);
}

function decodeDigestResult(bytes) {
  const digestLength = bytes.readUInt32LE(0);
  const digestEnd = 4 + digestLength;
  assert.equal(digestEnd + 4, bytes.length);
  return {
    digest: bytes.subarray(4, digestEnd).toString("utf8"),
    itemCount: bytes.readUInt32LE(digestEnd),
  };
}

function encodeString(value) {
  const bytes = Buffer.from(value, "utf8");
  return Buffer.concat([u32(bytes.length), bytes]);
}

function u32(value) {
  const bytes = Buffer.alloc(4);
  bytes.writeUInt32LE(value);
  return bytes;
}

function hex(bytes) {
  return Buffer.from(bytes).toString("hex");
}
