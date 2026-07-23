import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import {
  assertStandaloneStructure,
  abiFailure,
  callStep,
  copyExported,
  decodeFrame,
  encodeOkResult,
  encodeStepInput,
  instantiate,
} from "./world_application_v1_conformance.mjs";

const wasmPath = process.argv[2];
const scenarioName = process.argv[3];
const nativeManifestPath = process.argv[4];
if (!wasmPath || !scenarioName || !nativeManifestPath) {
  throw new Error("usage: node scripts/world_application_v1_agent_conformance.mjs <application.wasm> <skeleton|fixture> <native-manifest.bin>");
}

const scenarios = {
  skeleton: {
    goal: "goal=invoke",
    interactions: [
      { interface: "agent.model.decide.v1", payload: "goal=invoke", result: "actuate" },
      { interface: "agent.model.decide.v1", payload: "actuate", result: "final=actuate skeleton complete" },
    ],
    final: "final=actuate skeleton complete",
    internalHandlerCalls: 1n,
    branch: false,
  },
  fixture: {
    goal: "goal=fixture",
    interactions: [
      { interface: "agent.model.decide.v1", payload: "goal=fixture", result: "fixture-input.txt" },
      { interface: "host.file.read.v1", payload: "fixture-input.txt", result: "rewrite this file through the agent loop\n" },
      { interface: "agent.model.decide.v1", payload: "rewrite this file through the agent loop\n", result: "fixture-output.txt\nactuate updated the fixture" },
      { interface: "host.file.write.v1", payload: "fixture-output.txt\nactuate updated the fixture", result: "write=ok" },
      { interface: "agent.model.decide.v1", payload: "write=ok", result: "final=fixture updated" },
    ],
    final: "final=fixture updated",
    internalHandlerCalls: 2n,
    branch: true,
  },
};
const scenario = scenarios[scenarioName];
if (!scenario) throw new Error(`unknown scenario: ${scenarioName}`);

const wasmBytes = await readFile(wasmPath);
assertStandaloneStructure(wasmBytes);
const module = await WebAssembly.compile(wasmBytes);
if (WebAssembly.Module.imports(module).length !== 0) throw new Error("agent application WASM must have zero imports");
const firstInstance = await instantiate(module);
if (firstInstance.memory.buffer.byteLength !== 16 * 1024 * 1024) throw new Error("unexpected agent application memory bound");
let memoryBounded = false;
try {
  firstInstance.memory.grow(1);
} catch (error) {
  if (error instanceof RangeError) memoryBounded = true;
  else throw error;
}
if (!memoryBounded) throw new Error("agent application memory is not fixed at its declared maximum");

const manifest = copyExported(firstInstance, "world_manifest_ptr", "world_manifest_len");
if (manifest.subarray(0, 8).toString("ascii") !== "WRLDMNF1") throw new Error("invalid application manifest");
const nativeManifest = await readFile(nativeManifestPath);
if (!manifest.equals(nativeManifest)) throw new Error("native and wasm32 application manifests differ");
const applicationId = manifest.subarray(12, 44);
const genesis = encodeStepInput({
  applicationId,
  initialArgs: encodeString(scenario.goal),
  fuel: 100n,
});
if (callStep(firstInstance, genesis) !== 0) throw abiFailure(firstInstance, "agent genesis failed");

let frameBytes = copyExported(firstInstance, "world_output_ptr", "world_output_len");
let frame = decodeFrame(frameBytes);
let firstChildBytes = null;
for (const [index, interaction] of scenario.interactions.entries()) {
  if (frame.status !== 0 || frame.request === null) throw new Error(`interaction ${index} did not expose an EffectRequest`);
  const expectedInterface = digestLabel("world.effect-interface.v1", interaction.interface);
  if (!frame.request.interfaceId.equals(expectedInterface)) throw new Error(`interaction ${index} exposed the wrong effect interface`);
  if (decodeString(frame.request.payload) !== interaction.payload) throw new Error(`interaction ${index} exposed the wrong payload`);

  const result = encodeOkResult(frame.request, encodeString(interaction.result));
  const input = encodeStepInput({
    applicationId,
    expectedParentFrameId: frame.frameId,
    priorFrame: frameBytes,
    effectResult: result.bytes,
    fuel: 100n,
  });
  const nextInstance = await instantiate(module);
  const status = callStep(nextInstance, input);
  if (status !== 0) throw abiFailure(nextInstance, `interaction ${index} failed with status ${status}`);
  const nextBytes = copyExported(nextInstance, "world_output_ptr", "world_output_len");
  const nextFrame = decodeFrame(nextBytes);
  if (!nextFrame.parentFrameId?.equals(frame.frameId)) throw new Error(`interaction ${index} lost exact parentage`);
  if (!nextFrame.acceptedResultId?.equals(result.resultId)) throw new Error(`interaction ${index} lost accepted result identity`);
  if (nextFrame.sequence !== frame.sequence + 1n) throw new Error(`interaction ${index} advanced the wrong sequence`);

  const retryInstance = await instantiate(module);
  if (callStep(retryInstance, input) !== status) throw new Error(`interaction ${index} retry status diverged`);
  const retryBytes = copyExported(retryInstance, "world_output_ptr", "world_output_len");
  if (!retryBytes.equals(nextBytes)) throw new Error(`interaction ${index} retry bytes diverged`);

  if (index === 0) firstChildBytes = nextBytes;
  frameBytes = nextBytes;
  frame = nextFrame;
}

if (frame.status !== 1 || frame.finalResult === null) throw new Error("agent application did not complete");
if (decodeString(frame.finalResult) !== scenario.final) throw new Error("agent application returned the wrong final result");
if (frame.resourceCounters.internalHandlerCalls !== scenario.internalHandlerCalls) {
  throw new Error("agent application recorded the wrong internal handler count");
}

let branching = false;
if (scenario.branch) {
  const branchInstance = await instantiate(module);
  if (callStep(branchInstance, genesis) !== 0) throw abiFailure(branchInstance, "branch genesis failed");
  const branchParentBytes = copyExported(branchInstance, "world_output_ptr", "world_output_len");
  const branchParent = decodeFrame(branchParentBytes);
  const branchResult = encodeOkResult(branchParent.request, encodeString("alternate-input.txt"));
  const branchInput = encodeStepInput({
    applicationId,
    expectedParentFrameId: branchParent.frameId,
    priorFrame: branchParentBytes,
    effectResult: branchResult.bytes,
    fuel: 100n,
  });
  const branchChildInstance = await instantiate(module);
  if (callStep(branchChildInstance, branchInput) !== 0) throw abiFailure(branchChildInstance, "branch child failed");
  const branchChildBytes = copyExported(branchChildInstance, "world_output_ptr", "world_output_len");
  branching = !branchChildBytes.equals(firstChildBytes);
  if (!branching) throw new Error("distinct valid model results did not produce distinct child Frames");
}

console.log(`scenario=${scenarioName}`);
console.log(`application_wasm_bytes=${wasmBytes.length}`);
console.log("imports=0");
console.log("dynamic_runtime_markers=0");
console.log("bounded_memory=true");
console.log("fresh_instance_every_step=true");
console.log("native_wasm_manifest_identity=true");
console.log("byte_identical_retry=true");
console.log(`branching=${branching}`);
console.log(`final_result=${scenario.final}`);

function encodeString(value) {
  const payload = Buffer.from(value, "utf8");
  const bytes = Buffer.alloc(4 + payload.length);
  bytes.writeUInt32LE(payload.length, 0);
  payload.copy(bytes, 4);
  return bytes;
}

function decodeString(bytes) {
  if (bytes.length < 4) throw new Error("truncated string value");
  const length = bytes.readUInt32LE(0);
  if (length !== bytes.length - 4) throw new Error("non-canonical string value");
  return bytes.subarray(4).toString("utf8");
}

function digestLabel(domain, label) {
  return createHash("sha256")
    .update(Buffer.from(domain))
    .update(Buffer.from([0]))
    .update(Buffer.from(label))
    .digest();
}
