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
  maximumItems: 1,
};
const initialArgs = encodeResearchRequest(request);
const genesis = encodeStepInput({
  applicationId,
  initialArgs,
  fuel: 10_000n,
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
  throw new Error("Research Digest genesis did not park on research.lookup.v2");
}
if (!parent.request.payload.equals(initialArgs)) {
  throw new Error("research.lookup.v2 payload differs from the typed initial request");
}
if (parent.resourceCounters.internalHandlerCalls !== 1n) {
  throw new Error("Digest Formatter was not entered exactly once");
}

const expected = {
  items: [
    {
      title: "Effect rows as application boundaries",
      summary: "Static closure leaves authority outside the guest.",
    },
    {
      title: "Portable continuations",
      summary: "Canonical Frames resume in fresh WASM instances.",
    },
  ],
};
const expectedResult = {
  digest:
    "Effect rows as application boundaries\nStatic closure leaves authority outside the guest.\n",
  itemCount: 1,
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
  fuel: 10_000n,
});
const firstChildBytes = await complete(module, continuation, expectedResult);
const retryChildBytes = await complete(module, continuation, expectedResult);
if (!firstChildBytes.equals(retryChildBytes)) {
  throw new Error("Research Digest retry produced different child Frame bytes");
}

const alternate = {
  items: [
    {
      title: "A different research corpus",
      summary: "The same parent may accept another valid result.",
    },
    {
      title: "Branch isolation",
      summary: "The parent Frame remains immutable.",
    },
  ],
};
const alternateResultValue = {
  digest:
    "A different research corpus\nThe same parent may accept another valid result.\n",
  itemCount: 1,
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
  fuel: 10_000n,
});
const alternateChildBytes = await complete(
  module,
  alternateInput,
  alternateResultValue,
);
if (firstChildBytes.equals(alternateChildBytes)) {
  throw new Error("two valid Research Digest results produced one child Frame");
}

console.log("custom_effect=true");
console.log("internal_provider=true");
console.log("fresh_instance_resume=true");
console.log("deterministic_retry=true");
console.log("branching=true");
console.log(`digest=${expectedResult.digest}`);
console.log(`item_count=${expectedResult.itemCount}`);

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
  return Buffer.concat([encodeString(value.query), u32(value.maximumItems)]);
}

function encodeResearchResponse(value) {
  return Buffer.concat([
    u32(value.items.length),
    ...value.items.flatMap((item) => [
      encodeString(item.title),
      encodeString(item.summary),
    ]),
  ]);
}

function decodeDigestResult(bytes) {
  const digestLength = bytes.readUInt32LE(0);
  const digestEnd = 4 + digestLength;
  if (digestEnd + 4 !== bytes.length) {
    throw new Error("invalid DigestResult encoding");
  }
  return {
    digest: bytes.subarray(4, digestEnd).toString("utf8"),
    itemCount: bytes.readUInt32LE(digestEnd),
  };
}

function encodeString(value) {
  const bytes = Buffer.from(value, "utf8");
  const length = Buffer.alloc(4);
  length.writeUInt32LE(bytes.length);
  return Buffer.concat([length, bytes]);
}

function u32(value) {
  const bytes = Buffer.alloc(4);
  bytes.writeUInt32LE(value);
  return bytes;
}
