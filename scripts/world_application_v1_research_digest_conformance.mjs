import { readFile } from "node:fs/promises";
import {
  callStep,
  copyExported,
  decodeFrame,
  encodeOkResult,
  encodeStepInput,
  instantiate,
} from "./world_application_v1_conformance.mjs";

const [wasmPath, manifestPath] = process.argv.slice(2);
if (!wasmPath || !manifestPath) {
  throw new Error(
    "usage: node world_application_v1_research_digest_conformance.mjs <research-digest-agent.world.wasm> <research-digest-agent.manifest.bin>",
  );
}
const wasmBytes = await readFile(wasmPath);
const manifest = await readFile(manifestPath);
const module = await WebAssembly.compile(wasmBytes);
const applicationId = manifest.subarray(12, 44);
const request = {
  query: "portable algebraic effects",
  maximumItems: 2n,
};
const initialArgs = encodeResearchRequest(request);
const genesis = encodeStepInput({
  applicationId,
  initialArgs,
  fuel: 100n,
});

const parentInstance = await instantiate(module);
if (callStep(parentInstance, genesis) !== 0) {
  throw new Error("Research Digest genesis failed");
}
const parentBytes = copyExported(
  parentInstance,
  "world_output_ptr",
  "world_output_len",
);
const parent = decodeFrame(parentBytes);
if (parent.status !== 0 || parent.request === null) {
  throw new Error("Research Digest genesis did not park on research.lookup.v1");
}
if (!parent.request.payload.equals(initialArgs)) {
  throw new Error("research.lookup.v1 payload differs from the typed initial request");
}
if (parent.resourceCounters.internalHandlerCalls !== 1n) {
  throw new Error("Digest Formatter was not entered exactly once");
}

const expected = {
  first: {
    title: "Effect rows as application boundaries",
    summary: "Static closure leaves authority outside the guest.",
  },
  second: {
    title: "Portable continuations",
    summary: "Canonical Frames resume in fresh WASM instances.",
  },
  digest:
    "Static closure keeps authority external; canonical Frames keep continuation portable.",
  itemCount: 2n,
};
const firstResult = encodeOkResult(
  parent.request,
  encodeResearchResponse(expected),
);
const continuation = encodeStepInput({
  applicationId,
  expectedParentFrameId: parent.frameId,
  priorFrame: parentBytes,
  effectResult: firstResult.bytes,
  fuel: 100n,
});
const firstChildBytes = await complete(module, continuation, expected);
const retryChildBytes = await complete(module, continuation, expected);
if (!firstChildBytes.equals(retryChildBytes)) {
  throw new Error("Research Digest retry produced different child Frame bytes");
}

const alternate = {
  first: {
    title: "A different research corpus",
    summary: "The same parent may accept another valid result.",
  },
  second: {
    title: "Branch isolation",
    summary: "The parent Frame remains immutable.",
  },
  digest: "Alternate valid research creates a distinct deterministic branch.",
  itemCount: 2n,
};
const alternateResult = encodeOkResult(
  parent.request,
  encodeResearchResponse(alternate),
);
const alternateInput = encodeStepInput({
  applicationId,
  expectedParentFrameId: parent.frameId,
  priorFrame: parentBytes,
  effectResult: alternateResult.bytes,
  fuel: 100n,
});
const alternateChildBytes = await complete(module, alternateInput, alternate);
if (firstChildBytes.equals(alternateChildBytes)) {
  throw new Error("two valid Research Digest results produced one child Frame");
}

console.log("custom_effect=true");
console.log("internal_provider=true");
console.log("fresh_instance_resume=true");
console.log("deterministic_retry=true");
console.log("branching=true");
console.log(`digest=${expected.digest}`);
console.log(`item_count=${expected.itemCount}`);

async function complete(compiled, input, expectedResult) {
  const instance = await instantiate(compiled);
  if (callStep(instance, input) !== 0) {
    throw new Error("Research Digest continuation failed");
  }
  const bytes = copyExported(instance, "world_output_ptr", "world_output_len");
  const frame = decodeFrame(bytes);
  if (frame.status !== 1 || frame.finalResult === null) {
    throw new Error("Research Digest application did not complete");
  }
  const result = decodeDigestResult(frame.finalResult);
  if (
    result.digest !== expectedResult.digest ||
    result.itemCount !== expectedResult.itemCount
  ) {
    throw new Error("Research Digest application returned the wrong result");
  }
  return bytes;
}

function encodeResearchRequest(value) {
  return Buffer.concat([encodeString(value.query), u64(value.maximumItems)]);
}

function encodeResearchResponse(value) {
  return Buffer.concat([
    encodeString(value.first.title),
    encodeString(value.first.summary),
    encodeString(value.second.title),
    encodeString(value.second.summary),
    encodeString(value.digest),
    u64(value.itemCount),
  ]);
}

function decodeDigestResult(bytes) {
  const digestLength = bytes.readUInt32LE(0);
  const digestEnd = 4 + digestLength;
  if (digestEnd + 8 !== bytes.length) {
    throw new Error("invalid DigestResult encoding");
  }
  return {
    digest: bytes.subarray(4, digestEnd).toString("utf8"),
    itemCount: bytes.readBigUInt64LE(digestEnd),
  };
}

function encodeString(value) {
  const bytes = Buffer.from(value, "utf8");
  const length = Buffer.alloc(4);
  length.writeUInt32LE(bytes.length);
  return Buffer.concat([length, bytes]);
}

function u64(value) {
  const bytes = Buffer.alloc(8);
  bytes.writeBigUInt64LE(value);
  return bytes;
}
