// Copyright (c) 2026 World contributors. MIT license.
import { createHash } from "node:crypto";
import { inspectProcessKernelWasm, wasmRange } from "./wasm.mjs";
import { encodeInput, decodeOutcome } from "./codec.mjs";
import { readProcessKernelFile } from "./kernel_file.mjs";
export { encodeInput, decodeOutcome, decodeRequest, encodeResult, validateValue } from "./codec.mjs";

export const packageVersion = "5.0.0-dev.0";

/** Load the bundled, manifest-bound kernel or an explicitly digest-bound file. */
export async function loadProcessKernel(options) {
  const selected = await readProcessKernelFile(options, packageVersion);
  return admitProcessKernel(selected.bytes, { expectedSha256: selected.expectedSha256 });
}

export async function advance(input, options) { return (await loadProcessKernel(options)).advance(input); }
export async function run(input, options) { return (await loadProcessKernel(options)).run(input); }

export async function admitProcessKernel(input, { expectedSha256 } = {}) {
  if (!(input instanceof Uint8Array)) throw new TypeError("kernel must be bytes");
  const bytes = Uint8Array.from(input);
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  if (!/^[a-f0-9]{64}$/.test(expectedSha256 ?? "") || expectedSha256 !== sha256) throw new Error("KernelIdentityMismatch");
  const inspection = inspectProcessKernelWasm(bytes);
  const module = await WebAssembly.compile(bytes);
  const invoke = async (mode, input) => {
    const bytes = encodeInput({ ...input, mode });
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
  };
  return Object.freeze({ sha256, inspection, advance: (input) => invoke("advance", input), run: (input) => invoke("run", input) });
}

function failure(exports) {
  const bytes = wasmRange(exports.memory, exports.world_process_v2_error_ptr(), BigInt.asUintN(64, exports.world_process_v2_error_len()), "error");
  return new Error(new TextDecoder("utf-8", { fatal: true }).decode(bytes) || "KernelInvocationFailed");
}
