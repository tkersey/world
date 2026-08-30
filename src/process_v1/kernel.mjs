import { createHash } from "node:crypto";

import { decodeProcessOutcome } from "./outcome.mjs";
import { worldError } from "./errors.mjs";
import { BOUNDARY_PROCESS_KERNEL_V1 } from "./kernel_identity.mjs";
import {
  inspectProcessKernelWasm,
  MAXIMUM_KERNEL_BYTES,
  PROCESS_KERNEL_EXPORT_NAMES,
  wasmLength,
  wasmOffset,
  wasmRange,
} from "./wasm.mjs";

const MAXIMUM_U64 = 0xffff_ffff_ffff_ffffn;
const MAXIMUM_KERNEL_ERROR_BYTES = 4096;
const KERNEL_INPUT_HEADER_BYTES = 40;
const admittedHosts = new WeakMap();

/**
 * Authenticate and compile the one Boundary v1.7.0 Process interpreter that
 * World 4 is allowed to execute.
 */
export async function admitProcessKernel(kernelBytes, options = undefined) {
  const bytes = snapshotBytes(kernelBytes, "Process kernel", {
    maximumByteLength: MAXIMUM_KERNEL_BYTES,
    oversizeCode: "WORLD_KERNEL_TOO_LARGE",
  });
  const expectedSha256 = readExpectedSha256(options);
  const inspection = inspectProcessKernelWasm(bytes);
  const sha256 = createHash("sha256").update(bytes).digest("hex");

  if (sha256 !== BOUNDARY_PROCESS_KERNEL_V1.sha256 ||
      bytes.byteLength !== BOUNDARY_PROCESS_KERNEL_V1.byteLength) {
    throw worldError(
      "WORLD_KERNEL_DIGEST_MISMATCH",
      "Process kernel does not match the World runtime identity",
      {
        actualSha256: sha256,
        expectedSha256: BOUNDARY_PROCESS_KERNEL_V1.sha256,
        byteLength: bytes.byteLength,
      },
    );
  }
  if (expectedSha256 !== undefined && expectedSha256 !== sha256) {
    throw worldError(
      "WORLD_KERNEL_DIGEST_MISMATCH",
      "Process kernel does not match the caller's expected identity",
      { actualSha256: sha256, expectedSha256 },
    );
  }
  assertReleaseInspection(inspection);

  let module;
  try {
    module = await WebAssembly.compile(bytes);
  } catch {
    throw worldError(
      "WORLD_KERNEL_WASM_INVALID",
      "Process kernel could not be compiled",
    );
  }
  assertCompiledSurface(module);

  let admissionInstance;
  try {
    admissionInstance = await WebAssembly.instantiate(module, {});
    const abiVersion = admissionInstance.exports
      .boundary_process_kernel_abi_version();
    if (abiVersion !== BOUNDARY_PROCESS_KERNEL_V1.abiVersion) {
      throw worldError(
        "WORLD_KERNEL_ABI_MISMATCH",
        "Process kernel ABI version is not supported",
        {
          actualAbiVersion: abiVersion,
          expectedAbiVersion: BOUNDARY_PROCESS_KERNEL_V1.abiVersion,
        },
      );
    }
  } catch (error) {
    if (error?.name === "WorldProcessHostError") throw error;
    throw worldError(
      "WORLD_KERNEL_ABI_MISMATCH",
      "Process kernel ABI probe failed",
    );
  } finally {
    admissionInstance = undefined;
  }

  let host;
  const advance = async (input) => advancePublic(host, input);
  host = Object.freeze({
    abiVersion: BOUNDARY_PROCESS_KERNEL_V1.abiVersion,
    byteLength: bytes.byteLength,
    sha256,
    inspection,
    advance,
  });
  admittedHosts.set(host, Object.freeze({ module }));
  return host;
}

/**
 * Internal descriptor-friendly execution path used by the CLI.
 *
 * Lengths reach the kernel before any payload is materialized. On capacity,
 * writePayload and beforeExecute are never called. On success writePayload
 * receives the exact writable concatenated image + instance + EffectResult
 * payload region. An optional synchronous beforeExecute callback supplies the
 * final coherence cut after asynchronous payload work and immediately before
 * guest execution.
 */
export async function advancePrepared(
  host,
  lengths,
  writePayload,
  beforeExecute = undefined,
) {
  const admitted = admittedHosts.get(host);
  if (admitted === undefined) {
    throw worldError(
      "WORLD_INPUT_INVALID",
      "advancePrepared requires an admitted Process host",
    );
  }
  if (typeof writePayload !== "function") {
    throw worldError(
      "WORLD_INPUT_INVALID",
      "advancePrepared requires a payload writer",
    );
  }
  if (beforeExecute !== undefined && typeof beforeExecute !== "function") {
    throw worldError(
      "WORLD_INPUT_INVALID",
      "advancePrepared beforeExecute must be a synchronous callback",
    );
  }
  const prepared = validatePreparedLengths(lengths);

  let instance;
  try {
    instance = await WebAssembly.instantiate(admitted.module, {});
  } catch {
    throw worldError(
      "WORLD_KERNEL_EXECUTION_FAILED",
      "A fresh Process kernel instance could not be created",
    );
  }

  const exports = instance.exports;
  let inputLength;
  try {
    inputLength = u32Return(
      exports.boundary_process_kernel_prepare_input(
        prepared.instanceKind,
        BigInt.asIntN(64, prepared.imageLength),
        BigInt.asIntN(64, prepared.instanceLength),
        prepared.effectResultPresent ? 1 : 0,
        BigInt.asIntN(64, prepared.effectResultLength),
      ),
      "prepared input length",
    );
  } catch (error) {
    if (error?.name === "WorldProcessHostError") throw error;
    throw worldError(
      "WORLD_KERNEL_PREPARE_FAILED",
      "Process kernel input preparation trapped",
    );
  }

  if (inputLength === 0) return preparedZero(exports);

  const payloadLengthBigInt = prepared.imageLength +
    prepared.instanceLength + prepared.effectResultLength;
  if (payloadLengthBigInt > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw worldError(
      "WORLD_LENGTH_UNSAFE",
      "Prepared Process payload cannot be represented exactly by this JavaScript host",
    );
  }
  const payloadLength = Number(payloadLengthBigInt);
  if (inputLength !== payloadLength + KERNEL_INPUT_HEADER_BYTES) {
    throw worldError(
      "WORLD_KERNEL_PREPARE_FAILED",
      "Process kernel returned an inconsistent prepared input length",
      { inputLength, payloadLength },
    );
  }

  const memory = requireMemory(exports);
  const inputCapacity = callU32(
    exports,
    "boundary_process_kernel_input_capacity",
    "WORLD_KERNEL_PREPARE_FAILED",
    "Process kernel input capacity could not be read",
  );
  if (inputLength > inputCapacity) {
    throw worldError(
      "WORLD_KERNEL_PREPARE_FAILED",
      "Process kernel prepared input exceeds its declared capacity",
      { inputLength, inputCapacity },
    );
  }
  const inputPointer = callU32(
    exports,
    "boundary_process_kernel_input_ptr",
    "WORLD_KERNEL_RANGE_INVALID",
    "Process kernel input pointer could not be read",
  );
  const payloadPointer = callU32(
    exports,
    "boundary_process_kernel_input_payload_ptr",
    "WORLD_KERNEL_RANGE_INVALID",
    "Process kernel payload pointer could not be read",
  );
  if (payloadPointer < inputPointer ||
      payloadPointer - inputPointer !== KERNEL_INPUT_HEADER_BYTES) {
    throw worldError(
      "WORLD_KERNEL_RANGE_INVALID",
      "Process kernel payload pointer does not follow its input header",
      { inputPointer, payloadPointer },
    );
  }
  wasmRange(memory, inputPointer, inputLength, "Process kernel input");
  const payload = wasmRange(
    memory,
    payloadPointer,
    payloadLength,
    "Process kernel input payload",
  );

  const writeResult = writePayload(payload);
  if (writeResult !== null &&
      (typeof writeResult === "object" || typeof writeResult === "function") &&
      typeof writeResult.then === "function") {
    await writeResult;
  }
  if (payload.buffer !== memory.buffer || payload.byteLength !== payloadLength) {
    throw worldError(
      "WORLD_KERNEL_RANGE_INVALID",
      "Process kernel input memory changed while the payload was prepared",
    );
  }
  if (beforeExecute !== undefined) {
    const beforeExecuteResult = beforeExecute();
    if (beforeExecuteResult !== undefined) {
      throw worldError(
        "WORLD_INPUT_INVALID",
        "advancePrepared beforeExecute must complete synchronously",
      );
    }
  }

  let status;
  try {
    status = u32Return(
      exports.boundary_process_kernel_execute(inputLength),
      "kernel execution status",
    );
  } catch (error) {
    if (error?.name === "WorldProcessHostError") throw error;
    throw worldError(
      "WORLD_KERNEL_EXECUTION_FAILED",
      "Process kernel execution trapped",
    );
  }
  if (status !== 0) return executionFailed(exports, status);

  const errorLength = readErrorLength(exports);
  if (errorLength !== 0) {
    copyKernelError(exports, errorLength);
    throw worldError(
      "WORLD_KERNEL_EXECUTION_FAILED",
      "Process kernel reported an error after successful execution",
      { kernelErrorByteLength: errorLength },
    );
  }
  const output = copyKernelOutput(exports);
  if (output.byteLength === 0) {
    throw worldError(
      "WORLD_KERNEL_EXECUTION_FAILED",
      "Process kernel returned no outcome after successful execution",
    );
  }
  return decodeProcessOutcome(output);
}

async function advancePublic(host, input) {
  if (input === null || typeof input !== "object") {
    throw worldError(
      "WORLD_INPUT_INVALID",
      "advance input must be an object",
    );
  }
  const image = snapshotBytes(input.image, "Process image");
  const instance = input.instance;
  if (instance === null || typeof instance !== "object") {
    throw worldError(
      "WORLD_INPUT_INVALID",
      "advance instance must select InitialArgs or Process State",
    );
  }
  const hasInitialArgs = Object.hasOwn(instance, "initialArgs");
  const hasState = Object.hasOwn(instance, "state");
  if (hasInitialArgs === hasState) {
    throw worldError(
      "WORLD_INPUT_INVALID",
      "advance requires exactly one of initialArgs or state",
    );
  }
  const instanceBytes = snapshotBytes(
    hasInitialArgs ? instance.initialArgs : instance.state,
    hasInitialArgs ? "InitialArgs" : "Process State",
  );
  const effectResultPresent = input.effectResult !== undefined;
  const effectResult = effectResultPresent
    ? snapshotBytes(input.effectResult, "EffectResult")
    : new Uint8Array(0);

  return advancePrepared(
    host,
    {
      instanceKind: hasInitialArgs ? 0 : 1,
      imageLength: BigInt(image.byteLength),
      instanceLength: BigInt(instanceBytes.byteLength),
      effectResultPresent,
      effectResultLength: BigInt(effectResult.byteLength),
    },
    (payload) => {
      let cursor = 0;
      payload.set(image, cursor);
      cursor += image.byteLength;
      payload.set(instanceBytes, cursor);
      cursor += instanceBytes.byteLength;
      payload.set(effectResult, cursor);
    },
  );
}

function preparedZero(exports) {
  const outputLength = readOutputLength(exports);
  const errorLength = readErrorLength(exports);
  if (errorLength > MAXIMUM_KERNEL_ERROR_BYTES) {
    throw worldError(
      "WORLD_KERNEL_ERROR_OVERSIZED",
      "Process kernel error exceeds the host diagnostic limit",
      {
        kernelErrorByteLength: errorLength,
        maximumKernelErrorByteLength: MAXIMUM_KERNEL_ERROR_BYTES,
      },
    );
  }
  if (outputLength !== 0 && errorLength !== 0) {
    copyKernelError(exports, errorLength);
    throw worldError(
      "WORLD_KERNEL_PREPARE_FAILED",
      "Process kernel preparation returned both outcome and error",
      { outputByteLength: outputLength, kernelErrorByteLength: errorLength },
    );
  }
  if (errorLength !== 0) {
    copyKernelError(exports, errorLength);
    throw worldError(
      "WORLD_KERNEL_PREPARE_FAILED",
      "Process kernel could not prepare the input",
      { kernelErrorByteLength: errorLength },
    );
  }
  if (outputLength === 0) {
    throw worldError(
      "WORLD_KERNEL_PREPARE_FAILED",
      "Process kernel could not prepare the input and returned no requirement",
    );
  }
  const output = copyKernelOutput(exports, outputLength);
  let outcome;
  try {
    outcome = decodeProcessOutcome(output);
  } catch {
    throw worldError(
      "WORLD_KERNEL_PREPARE_FAILED",
      "Process kernel returned a malformed capacity outcome",
      { outputByteLength: output.byteLength },
    );
  }
  if (outcome.kind !== "NeedsCapacity") {
    throw worldError(
      "WORLD_KERNEL_PREPARE_FAILED",
      "Process kernel preparation did not return a capacity requirement",
      { outcomeKind: outcome.kind },
    );
  }
  return outcome;
}

function executionFailed(exports, status) {
  const outputLength = readOutputLength(exports);
  const errorLength = readErrorLength(exports);
  if (errorLength > MAXIMUM_KERNEL_ERROR_BYTES) {
    throw worldError(
      "WORLD_KERNEL_ERROR_OVERSIZED",
      "Process kernel error exceeds the host diagnostic limit",
      {
        kernelStatus: status,
        kernelErrorByteLength: errorLength,
        maximumKernelErrorByteLength: MAXIMUM_KERNEL_ERROR_BYTES,
      },
    );
  }
  if (outputLength !== 0 || errorLength === 0) {
    throw worldError(
      "WORLD_KERNEL_EXECUTION_FAILED",
      "Process kernel execution returned inconsistent output and error channels",
      {
        kernelStatus: status,
        outputByteLength: outputLength,
        kernelErrorByteLength: errorLength,
      },
    );
  }
  copyKernelError(exports, errorLength);
  throw worldError(
    "WORLD_KERNEL_EXECUTION_FAILED",
    "Process kernel rejected the prepared input",
    { kernelStatus: status, kernelErrorByteLength: errorLength },
  );
}

function validatePreparedLengths(lengths) {
  if (lengths === null || typeof lengths !== "object") {
    throw worldError(
      "WORLD_INPUT_INVALID",
      "Prepared Process lengths must be an object",
    );
  }
  if (lengths.instanceKind !== 0 && lengths.instanceKind !== 1) {
    throw worldError(
      "WORLD_INPUT_INVALID",
      "Prepared Process instance kind must be InitialArgs or Process State",
    );
  }
  if (typeof lengths.effectResultPresent !== "boolean") {
    throw worldError(
      "WORLD_INPUT_INVALID",
      "Prepared Process result presence must be boolean",
    );
  }
  const imageLength = requireU64(lengths.imageLength, "Process image length");
  const instanceLength = requireU64(
    lengths.instanceLength,
    "Process instance length",
  );
  const effectResultLength = requireU64(
    lengths.effectResultLength,
    "EffectResult length",
  );
  if (!lengths.effectResultPresent && effectResultLength !== 0n) {
    throw worldError(
      "WORLD_INPUT_INVALID",
      "Absent EffectResult must have zero length",
    );
  }
  return {
    instanceKind: lengths.instanceKind,
    imageLength,
    instanceLength,
    effectResultPresent: lengths.effectResultPresent,
    effectResultLength,
  };
}

function requireU64(value, label) {
  if (typeof value !== "bigint" || value < 0n || value > MAXIMUM_U64) {
    throw worldError(
      "WORLD_LENGTH_UNSAFE",
      `${label} must be an exact unsigned 64-bit BigInt`,
    );
  }
  return value;
}

function readExpectedSha256(options) {
  if (options === undefined) return undefined;
  if (options === null || typeof options !== "object" || Array.isArray(options)) {
    throw worldError(
      "WORLD_INPUT_INVALID",
      "Process kernel admission options must be an object",
    );
  }
  const expected = options.expectedSha256;
  if (expected === undefined) return undefined;
  if (typeof expected !== "string" || !/^[0-9a-f]{64}$/.test(expected)) {
    throw worldError(
      "WORLD_INPUT_INVALID",
      "expectedSha256 must be a lowercase hexadecimal SHA-256 digest",
    );
  }
  return expected;
}

function snapshotBytes(value, label, limits = undefined) {
  if (!(value instanceof Uint8Array)) {
    throw worldError(
      "WORLD_INPUT_INVALID",
      `${label} must be a Uint8Array`,
    );
  }
  if (limits?.maximumByteLength !== undefined &&
      value.byteLength > limits.maximumByteLength) {
    throw worldError(
      limits.oversizeCode,
      `${label} exceeds the admission byte limit`,
      {
        byteLength: value.byteLength,
        maximumByteLength: limits.maximumByteLength,
      },
    );
  }
  try {
    return new Uint8Array(value);
  } catch {
    throw worldError(
      "WORLD_INPUT_INVALID",
      `${label} could not be snapshotted`,
    );
  }
}

function assertReleaseInspection(inspection) {
  const expected = BOUNDARY_PROCESS_KERNEL_V1;
  if (inspection.importCount !== expected.importCount ||
      inspection.exportCount !== expected.exportCount ||
      inspection.memory.initialPages !== expected.memoryInitialPages ||
      inspection.memory.maximumPages !== expected.memoryMaximumPages) {
    throw worldError(
      "WORLD_KERNEL_PROFILE_INVALID",
      "Process kernel does not match the Boundary release profile",
    );
  }
}

function assertCompiledSurface(module) {
  const imports = WebAssembly.Module.imports(module);
  const exports = WebAssembly.Module.exports(module);
  if (imports.length !== 0 || exports.length !== PROCESS_KERNEL_EXPORT_NAMES.length) {
    throw worldError(
      "WORLD_KERNEL_PROFILE_INVALID",
      "Compiled Process kernel surface does not match ABI v1",
    );
  }
  const actual = new Map(exports.map((item) => [item.name, item.kind]));
  for (const name of PROCESS_KERNEL_EXPORT_NAMES) {
    const expectedKind = name === "memory" ? "memory" : "function";
    if (actual.get(name) !== expectedKind) {
      throw worldError(
        "WORLD_KERNEL_PROFILE_INVALID",
        "Compiled Process kernel export surface does not match ABI v1",
        { exportName: name },
      );
    }
  }
}

function requireMemory(exports) {
  if (!(exports.memory instanceof WebAssembly.Memory)) {
    throw worldError(
      "WORLD_KERNEL_PROFILE_INVALID",
      "Process kernel did not export its linear memory",
    );
  }
  return exports.memory;
}

function callU32(exports, name, code, message) {
  try {
    return u32Return(exports[name](), name);
  } catch (error) {
    if (error?.name === "WorldProcessHostError") throw error;
    throw worldError(code, message);
  }
}

function u32Return(value, label) {
  return wasmOffset(value, label);
}

function readOutputLength(exports) {
  try {
    return wasmLength(
      exports.boundary_process_kernel_output_len(),
      "Process kernel output length",
    );
  } catch (error) {
    if (error?.name === "WorldProcessHostError") throw error;
    throw worldError(
      "WORLD_KERNEL_RANGE_INVALID",
      "Process kernel output length could not be read",
    );
  }
}

function readErrorLength(exports) {
  try {
    return u32Return(
      exports.boundary_process_kernel_error_len(),
      "Process kernel error length",
    );
  } catch (error) {
    if (error?.name === "WorldProcessHostError") throw error;
    throw worldError(
      "WORLD_KERNEL_RANGE_INVALID",
      "Process kernel error length could not be read",
    );
  }
}

function copyKernelOutput(exports, knownLength = undefined) {
  const length = knownLength ?? readOutputLength(exports);
  let pointer;
  try {
    pointer = exports.boundary_process_kernel_output_ptr();
  } catch {
    throw worldError(
      "WORLD_KERNEL_RANGE_INVALID",
      "Process kernel output pointer could not be read",
    );
  }
  return wasmRange(
    requireMemory(exports),
    pointer,
    length,
    "Process kernel output",
  ).slice();
}

function copyKernelError(exports, knownLength) {
  if (knownLength > MAXIMUM_KERNEL_ERROR_BYTES) {
    throw worldError(
      "WORLD_KERNEL_ERROR_OVERSIZED",
      "Process kernel error exceeds the host diagnostic limit",
      {
        kernelErrorByteLength: knownLength,
        maximumKernelErrorByteLength: MAXIMUM_KERNEL_ERROR_BYTES,
      },
    );
  }
  let pointer;
  try {
    pointer = exports.boundary_process_kernel_error_ptr();
  } catch {
    throw worldError(
      "WORLD_KERNEL_RANGE_INVALID",
      "Process kernel error pointer could not be read",
    );
  }
  return wasmRange(
    requireMemory(exports),
    pointer,
    knownLength,
    "Process kernel error",
  ).slice();
}
