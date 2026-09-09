// Copyright (c) 2026 World contributors. MIT license.
import { createHash } from "node:crypto";
import { isUint8Array } from "./errors.mjs";
import { assertProcessKernelByteLength, inspectProcessKernelWasm, wasmRange } from "./wasm.mjs";
import { encodeInput, decodeOutcome } from "./codec.mjs";
import { readProcessKernelFile } from "./kernel_file.mjs";
export { encodeInput, decodeOutcome, decodeRequest, encodeResult, validateValue } from "./codec.mjs";

export const packageVersion = "5.0.0";
const typedArray = Object.getOwnPropertyDescriptors(Object.getPrototypeOf(Uint8Array.prototype));

/** Load the bundled, manifest-bound kernel or an explicitly digest-bound file. */
export async function loadProcessKernel(options) {
  return publicHost(await loadCompiledKernel(options));
}

export async function advance(input, options) {
  const bytes = encodeInput({ ...input, mode: "advance" });
  return invoke((await loadCompiledKernel(options)).module, bytes);
}
export async function run(input, options) {
  const bytes = encodeInput({ ...input, mode: "run" });
  return invoke((await loadCompiledKernel(options)).module, bytes);
}

async function loadCompiledKernel(options) {
  const selected = await readProcessKernelFile(options, packageVersion);
  return compileKernel(selected.bytes, { expectedSha256: selected.expectedSha256 });
}

export async function admitProcessKernel(input, options) {
  return publicHost(await compileKernel(input, options));
}

async function compileKernel(input, { expectedSha256 } = {}) {
  if (!isUint8Array(input)) throw new TypeError("kernel must be bytes");
  const byteLength = typedArray.byteLength.get.call(input);
  assertProcessKernelByteLength(byteLength);
  // Fix the view length before copying, including length-tracking shared views.
  const view = new Uint8Array(typedArray.buffer.get.call(input), typedArray.byteOffset.get.call(input), byteLength);
  const bytes = new Uint8Array(view);
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  if (!/^[a-f0-9]{64}$/.test(expectedSha256 ?? "") || expectedSha256 !== sha256) throw new Error("KernelIdentityMismatch");
  const inspection = inspectProcessKernelWasm(bytes);
  const module = await WebAssembly.compile(bytes);
  return { sha256, inspection, module };
}

function publicHost({ sha256, inspection, module }) {
  return Object.freeze({ sha256, inspection,
    advance: async (input) => invoke(module, encodeInput({ ...input, mode: "advance" })),
    run: async (input) => invoke(module, encodeInput({ ...input, mode: "run" })),
  });
}

async function invoke(module, bytes) {
  const { exports } = await WebAssembly.instantiate(module, {});
  if (exports.world_process_v2_abi_version() !== 2) throw new Error("InvalidAbiVersion");
  const prepared = exports.world_process_v2_prepare_input(BigInt(bytes.length));
  if (prepared !== 0 && prepared !== 1) throw failure(exports);
  if (prepared === 0) {
    const capacity = BigInt.asUintN(64, exports.world_process_v2_input_capacity());
    if (BigInt(bytes.length) > capacity) throw new Error("InputCapacityMismatch");
    const input = wasmRange(exports.memory, exports.world_process_v2_input_ptr(), BigInt(bytes.length), "input");
    input.set(bytes);
    if (exports.world_process_v2_execute(BigInt(bytes.length)) !== 0) throw failure(exports);
  }
  const result = wasmRange(exports.memory, exports.world_process_v2_output_ptr(), BigInt.asUintN(64, exports.world_process_v2_output_len()), "output").slice();
  const decoded = decodeOutcome(result);
  if (prepared === 1 && decoded.kind !== "NeedsCapacity") throw new Error("InvalidPreflightOutcome");
  return Object.freeze({ ...decoded, bytes: result });
}

function failure(exports) {
  const bytes = wasmRange(exports.memory, exports.world_process_v2_error_ptr(), BigInt.asUintN(64, exports.world_process_v2_error_len()), "error");
  return new Error(new TextDecoder("utf-8", { fatal: true }).decode(bytes) || "KernelInvocationFailed");
}
