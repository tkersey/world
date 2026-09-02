import { beforeAll, describe, expect, test } from "bun:test";
import fs from "node:fs";
import { runInNewContext } from "node:vm";

import { WorldProcessHostError } from "../src/process_v1/errors.mjs";
import {
  admitProcessKernel,
  advancePrepared,
} from "../src/process_v1/kernel.mjs";
import { BOUNDARY_PROCESS_KERNEL_V1 } from
  "../src/process_v1/kernel_identity.mjs";
import {
  inspectProcessKernelWasm,
  PROCESS_KERNEL_EXPORT_NAMES,
} from "../src/process_v1/wasm.mjs";
import { processKernelWasmFixture } from "./wasm_fixture.mjs";

const KERNEL_URL = new URL(
  "../boundary-process-kernel-v1.wasm",
  import.meta.url,
);

let host;

beforeAll(async () => {
  const mutableKernelBytes = new Uint8Array(fs.readFileSync(KERNEL_URL));
  const admission = admitProcessKernel(mutableKernelBytes, {
    expectedSha256: BOUNDARY_PROCESS_KERNEL_V1.sha256,
  });
  // Admission must already own its source bytes before its first await.
  mutableKernelBytes.fill(0);
  host = await admission;
});

describe("Boundary Process kernel static admission", () => {
  test("recovers the exact released ABI profile without executing guest code", () => {
    const inspection = inspectProcessKernelWasm(fs.readFileSync(KERNEL_URL));
    expect(inspection).toEqual({
      format: "boundary-process-kernel-inspection/v1",
      wasm32: true,
      importCount: 0,
      exportCount: 13,
      hasStart: false,
      memory: {
        initialPages: 2457,
        maximumPages: 4096,
        shared: false,
        memory64: false,
      },
    });
    expect(Object.isFrozen(inspection)).toBe(true);
    expect(Object.isFrozen(inspection.memory)).toBe(true);
  });

  test("accepts export-order variation but requires the exact ABI surface", () => {
    expect(inspectProcessKernelWasm(
      processKernelWasmFixture({ reverseExports: true }),
    ).exportCount).toBe(PROCESS_KERNEL_EXPORT_NAMES.length);

    for (const options of [
      { withImport: true },
      { withStart: true },
      { memoryFlags: 0 },
      { memoryFlags: 3 },
      { memoryCount: 2 },
      { maximumPages: 4097 },
      { missingExport: "memory" },
      { missingExport: "boundary_process_kernel_execute" },
      { extraExport: true },
      { wrongExportKind: "boundary_process_kernel_error_len" },
    ]) {
      expectHostError(
        () => inspectProcessKernelWasm(processKernelWasmFixture(options)),
        "WORLD_KERNEL_PROFILE_INVALID",
      );
    }
  });

  test("requires every ABI function's exact WebAssembly signature", () => {
    for (const exportName of PROCESS_KERNEL_EXPORT_NAMES.slice(1)) {
      expectHostError(
        () => inspectProcessKernelWasm(processKernelWasmFixture({
          wrongSignature: exportName,
        })),
        "WORLD_KERNEL_PROFILE_INVALID",
      );
    }
  });

  test("rejects invalid binaries and duplicate export names", () => {
    const invalidMagic = processKernelWasmFixture();
    invalidMagic[0] = 1;
    const invalidVersion = processKernelWasmFixture();
    invalidVersion[4] = 2;
    const truncated = processKernelWasmFixture().subarray(0, 24);
    const duplicate = processKernelWasmFixture({
      duplicateExport: "memory",
    });

    for (const bytes of [invalidMagic, invalidVersion, truncated, duplicate]) {
      expectHostError(
        () => inspectProcessKernelWasm(bytes),
        "WORLD_KERNEL_WASM_INVALID",
      );
    }
  });

  test("rejects a conforming impostor by digest before compilation or ABI probe", async () => {
    const originalCompile = WebAssembly.compile;
    const originalInstantiate = WebAssembly.instantiate;
    let compileCalls = 0;
    let instantiateCalls = 0;
    WebAssembly.compile = (...arguments_) => {
      compileCalls += 1;
      return originalCompile(...arguments_);
    };
    WebAssembly.instantiate = (...arguments_) => {
      instantiateCalls += 1;
      return originalInstantiate(...arguments_);
    };
    try {
      await expect(admitProcessKernel(processKernelWasmFixture())).rejects
        .toMatchObject({ code: "WORLD_KERNEL_DIGEST_MISMATCH" });
      expect(compileCalls).toBe(0);
      expect(instantiateCalls).toBe(0);
    } finally {
      WebAssembly.compile = originalCompile;
      WebAssembly.instantiate = originalInstantiate;
    }
  });

  test("rejects a wrong dynamic Process kernel ABI version", async () => {
    const originalInstantiate = WebAssembly.instantiate;
    WebAssembly.instantiate = async (...arguments_) => {
      const instance = await originalInstantiate(...arguments_);
      return {
        exports: {
          ...instance.exports,
          boundary_process_kernel_abi_version: () => 2,
        },
      };
    };
    try {
      await expect(admitProcessKernel(fs.readFileSync(KERNEL_URL))).rejects
        .toMatchObject({ code: "WORLD_KERNEL_ABI_MISMATCH" });
    } finally {
      WebAssembly.instantiate = originalInstantiate;
    }
  });
});

describe("fixed-kernel admitted host", () => {
  test("is immutable and exposes only release identity, inspection, and advance", () => {
    expect(Object.keys(host).sort()).toEqual([
      "abiVersion",
      "advance",
      "byteLength",
      "inspection",
      "sha256",
    ]);
    expect(host.abiVersion).toBe(1);
    expect(host.byteLength).toBe(648639);
    expect(host.sha256).toBe(BOUNDARY_PROCESS_KERNEL_V1.sha256);
    expect(Object.isFrozen(host)).toBe(true);
    expect(Object.isFrozen(host.inspection)).toBe(true);
  });

  test("requires lowercase exact expected digest syntax and identity", async () => {
    const bytes = fs.readFileSync(KERNEL_URL);
    await expect(admitProcessKernel(bytes, {
      expectedSha256: BOUNDARY_PROCESS_KERNEL_V1.sha256.toUpperCase(),
    })).rejects.toMatchObject({ code: "WORLD_INPUT_INVALID" });
    await expect(admitProcessKernel(bytes, {
      expectedSha256: "0".repeat(64),
    })).rejects.toMatchObject({ code: "WORLD_KERNEL_DIGEST_MISMATCH" });
  });

  test("admits exact kernel bytes from another realm", async () => {
    const admitted = await admitProcessKernel(
      foreignBytes(fs.readFileSync(KERNEL_URL)),
      { expectedSha256: BOUNDARY_PROCESS_KERNEL_V1.sha256 },
    );
    expect(admitted.sha256).toBe(BOUNDARY_PROCESS_KERNEL_V1.sha256);
  });

  test("returns typed NeedsCapacity without invoking the payload writer", async () => {
    let writerCalls = 0;
    const outcome = await capacityAdvance(() => {
      writerCalls += 1;
    });
    expect(writerCalls).toBe(0);
    expect(outcome.kind).toBe("NeedsCapacity");
    expect(outcome.requirement.minimumInputBytes).toBe(33_554_473n);
    expect(new TextDecoder().decode(outcome.bytes.subarray(0, 8))).toBe(
      "ABL_PKO1",
    );
  });

  test("uses a distinct fresh instance for every prepared advance", async () => {
    const originalInstantiate = WebAssembly.instantiate;
    let instantiateCalls = 0;
    WebAssembly.instantiate = (...arguments_) => {
      instantiateCalls += 1;
      return originalInstantiate(...arguments_);
    };
    try {
      await capacityAdvance(() => {
        throw new Error("capacity must not materialize payload");
      });
      await capacityAdvance(() => {
        throw new Error("capacity must not materialize payload");
      });
      expect(instantiateCalls).toBe(2);
    } finally {
      WebAssembly.instantiate = originalInstantiate;
    }
  });

  test("copies capacity outcomes away from each discarded instance", async () => {
    const first = await capacityAdvance(() => {});
    first.bytes.fill(0);
    const second = await capacityAdvance(() => {});
    expect(new TextDecoder().decode(second.bytes.subarray(0, 8))).toBe(
      "ABL_PKO1",
    );
    expect(second.requirement.minimumInputBytes).toBe(33_554_473n);
  });

  test("triages preparation overflow and never calls the payload writer", async () => {
    let writerCalls = 0;
    await expect(advancePrepared(host, {
      instanceKind: 0,
      imageLength: 0x7fff_ffff_ffff_ffffn,
      instanceLength: 0x7fff_ffff_ffff_ffd9n,
      effectResultPresent: false,
      effectResultLength: 0n,
    }, () => {
      writerCalls += 1;
    })).rejects.toMatchObject({ code: "WORLD_KERNEL_PREPARE_FAILED" });
    expect(writerCalls).toBe(0);
  });

  test("copies a successful preparation payload then reports bounded execution failure", async () => {
    let observedLength = -1;
    await expect(advancePrepared(host, {
      instanceKind: 0,
      imageLength: 0n,
      instanceLength: 0n,
      effectResultPresent: false,
      effectResultLength: 0n,
    }, (payload) => {
      observedLength = payload.byteLength;
    })).rejects.toMatchObject({
      code: "WORLD_KERNEL_EXECUTION_FAILED",
      details: { kernelStatus: 2 },
    });
    expect(observedLength).toBe(0);
  });

  test("fail-closes every prepare-zero channel combination", async () => {
    let writerCalls = 0;
    const capacityBytes = needsCapacityOutcome(123n);
    const cases = [
      {
        instance: fakeKernelInstance({ prepareOutput: capacityBytes }),
        expectedCode: null,
      },
      {
        instance: fakeKernelInstance({ prepareError: Uint8Array.of(1) }),
        expectedCode: "WORLD_KERNEL_PREPARE_FAILED",
      },
      {
        instance: fakeKernelInstance(),
        expectedCode: "WORLD_KERNEL_PREPARE_FAILED",
      },
      {
        instance: fakeKernelInstance({
          prepareOutput: capacityBytes,
          prepareError: Uint8Array.of(1),
        }),
        expectedCode: "WORLD_KERNEL_PREPARE_FAILED",
      },
    ];

    for (const item of cases) {
      const operation = withNextInstance(item.instance, () =>
        advancePrepared(host, zeroLengths(), () => {
          writerCalls += 1;
        })
      );
      if (item.expectedCode === null) {
        expect((await operation).kind).toBe("NeedsCapacity");
      } else {
        await expect(operation).rejects.toMatchObject({
          code: item.expectedCode,
        });
      }
    }
    expect(writerCalls).toBe(0);
  });

  test("bounds guest pointers, output lengths, and error lengths before copying", async () => {
    const memoryBytes = 65_536;
    const cases = [
      {
        instance: fakeKernelInstance({
          preparedInputLength: 40,
          inputPointer: memoryBytes - 1,
          payloadPointer: memoryBytes + 39,
        }),
        code: "WORLD_KERNEL_RANGE_INVALID",
      },
      {
        instance: fakeKernelInstance({
          preparedInputLength: 40,
          executeStatus: 0,
          executionOutput: needsCapacityOutcome(1n),
          outputPointer: memoryBytes - 1,
        }),
        code: "WORLD_KERNEL_RANGE_INVALID",
      },
      {
        instance: fakeKernelInstance({
          preparedInputLength: 40,
          executeStatus: 0,
          outputLength: 9_007_199_254_740_992n,
        }),
        code: "WORLD_LENGTH_UNSAFE",
      },
      {
        instance: fakeKernelInstance({
          preparedInputLength: 40,
          executeStatus: 2,
          executionErrorLength: 4097,
        }),
        code: "WORLD_KERNEL_ERROR_OVERSIZED",
      },
    ];

    for (const item of cases) {
      await expect(withNextInstance(item.instance, () =>
        advancePrepared(host, zeroLengths(), () => {})
      )).rejects.toMatchObject({ code: item.code });
    }
  });

  test("reacquires exported memory after execution grows it", async () => {
    const expected = needsCapacityOutcome(777n);
    const fake = fakeKernelInstance({
      preparedInputLength: 40,
      growOnExecute: true,
      executionOutput: expected,
      outputPointer: 65_536,
    });
    const outcome = await withNextInstance(fake, () =>
      advancePrepared(host, zeroLengths(), () => {})
    );
    expect(outcome.kind).toBe("NeedsCapacity");
    expect(outcome.requirement.minimumInputBytes).toBe(777n);
  });

  test("runs the synchronous coherence cut on the same turn immediately before execute", async () => {
    const events = [];
    let queuedMutation = false;
    const fake = fakeKernelInstance({
      preparedInputLength: 40,
      executionOutput: needsCapacityOutcome(9n),
      executionError: new Uint8Array(),
      onExecute() {
        events.push("execute");
      },
    });
    const outcome = await withNextInstance(fake, () =>
      advancePrepared(host, zeroLengths(), () => {
        events.push("write");
        queueMicrotask(() => {
          queuedMutation = true;
          events.push("queued-mutation");
        });
      }, () => {
        expect(queuedMutation).toBe(false);
        events.push("coherence-cut");
      })
    );
    expect(outcome.kind).toBe("NeedsCapacity");
    expect(events.slice(0, 3)).toEqual([
      "write",
      "coherence-cut",
      "execute",
    ]);
    await Promise.resolve();
    expect(events[3]).toBe("queued-mutation");
  });

  test("snapshots public inputs and rejects invalid instance selection", async () => {
    await expect(host.advance({
      image: new Uint8Array(),
      instance: {},
    })).rejects.toMatchObject({ code: "WORLD_INPUT_INVALID" });
    await expect(host.advance({
      image: new Uint8Array(),
      instance: {
        initialArgs: new Uint8Array(),
        state: new Uint8Array(),
      },
    })).rejects.toMatchObject({ code: "WORLD_INPUT_INVALID" });

    const image = new Uint8Array();
    const initialArgs = new Uint8Array();
    const advance = host.advance({ image, instance: { initialArgs } });
    image.fill(1);
    initialArgs.fill(1);
    await expect(advance).rejects.toMatchObject({
      code: "WORLD_KERNEL_EXECUTION_FAILED",
    });
  });

  test("accepts public advance bytes from another realm", async () => {
    await expect(host.advance({
      image: foreignBytes(new Uint8Array()),
      instance: { initialArgs: foreignBytes(new Uint8Array()) },
      effectResult: foreignBytes(new Uint8Array()),
    })).rejects.toMatchObject({
      code: "WORLD_KERNEL_EXECUTION_FAILED",
    });
  });

  test("rejects other views and spoofed objects at kernel byte boundaries", async () => {
    const spoofedTypedArray = new Uint16Array(1);
    Object.defineProperty(spoofedTypedArray, Symbol.toStringTag, {
      value: "Uint8Array",
    });
    const invalid = [
      new DataView(new ArrayBuffer(8)),
      new Uint16Array(1),
      spoofedTypedArray,
      {},
      { [Symbol.toStringTag]: "Uint8Array" },
    ];
    for (const value of invalid) {
      await expect(admitProcessKernel(value)).rejects.toMatchObject({
        code: "WORLD_INPUT_INVALID",
      });
    }

    await expect(host.advance({
      image: new DataView(new ArrayBuffer(0)),
      instance: { initialArgs: new Uint8Array() },
    })).rejects.toMatchObject({ code: "WORLD_INPUT_INVALID" });
    await expect(host.advance({
      image: new Uint8Array(),
      instance: { initialArgs: new Uint16Array() },
    })).rejects.toMatchObject({ code: "WORLD_INPUT_INVALID" });
    await expect(host.advance({
      image: new Uint8Array(),
      instance: { initialArgs: new Uint8Array() },
      effectResult: {},
    })).rejects.toMatchObject({ code: "WORLD_INPUT_INVALID" });
  });
});

function foreignBytes(bytes) {
  return runInNewContext("(input) => new Uint8Array(input)")(bytes);
}

async function capacityAdvance(writePayload) {
  return advancePrepared(host, {
    instanceKind: 0,
    imageLength: 33_554_432n,
    instanceLength: 1n,
    effectResultPresent: false,
    effectResultLength: 0n,
  }, writePayload);
}

function expectHostError(action, code) {
  try {
    action();
    throw new Error("expected Process host error");
  } catch (error) {
    expect(error).toBeInstanceOf(WorldProcessHostError);
    expect(error.code).toBe(code);
  }
}

function zeroLengths() {
  return {
    instanceKind: 0,
    imageLength: 0n,
    instanceLength: 0n,
    effectResultPresent: false,
    effectResultLength: 0n,
  };
}

async function withNextInstance(instance, operation) {
  const originalInstantiate = WebAssembly.instantiate;
  WebAssembly.instantiate = async () => instance;
  try {
    return await operation();
  } finally {
    WebAssembly.instantiate = originalInstantiate;
  }
}

function fakeKernelInstance(options = {}) {
  const memory = new WebAssembly.Memory({ initial: 1, maximum: 2 });
  const prepareOutput = options.prepareOutput ?? new Uint8Array();
  const prepareError = options.prepareError ?? new Uint8Array();
  const executionOutput = options.executionOutput ?? new Uint8Array();
  const executionError = options.executionError ??
    ((options.executeStatus ?? 0) === 0
      ? new Uint8Array()
      : Uint8Array.of(1));
  const inputPointer = options.inputPointer ?? 0;
  const payloadPointer = options.payloadPointer ?? 40;
  const outputPointer = options.outputPointer ?? 1024;
  const errorPointer = options.errorPointer ?? 2048;
  let phase = "prepare";

  write(memory, outputPointer, prepareOutput);
  write(memory, errorPointer, prepareError);

  return {
    exports: {
      memory,
      boundary_process_kernel_prepare_input() {
        return options.preparedInputLength ?? 0;
      },
      boundary_process_kernel_input_capacity() {
        return 65_536;
      },
      boundary_process_kernel_input_ptr() {
        return inputPointer;
      },
      boundary_process_kernel_input_payload_ptr() {
        return payloadPointer;
      },
      boundary_process_kernel_execute() {
        phase = "execute";
        options.onExecute?.();
        if (options.growOnExecute === true) memory.grow(1);
        write(memory, outputPointer, executionOutput);
        write(memory, errorPointer, executionError);
        return options.executeStatus ?? 0;
      },
      boundary_process_kernel_output_ptr() {
        return outputPointer;
      },
      boundary_process_kernel_output_len() {
        if (phase === "prepare") return BigInt(prepareOutput.byteLength);
        return options.outputLength ?? BigInt(executionOutput.byteLength);
      },
      boundary_process_kernel_error_ptr() {
        return errorPointer;
      },
      boundary_process_kernel_error_len() {
        if (phase === "prepare") return prepareError.byteLength;
        return options.executionErrorLength ?? executionError.byteLength;
      },
    },
  };
}

function needsCapacityOutcome(minimumInputBytes) {
  const bytes = new Uint8Array(64);
  bytes.set(new TextEncoder().encode("ABL_PKO1"), 0);
  new DataView(bytes.buffer).setUint16(8, 1, true);
  bytes[10] = 5;
  new DataView(bytes.buffer).setBigUint64(12, 32n, true);
  new DataView(bytes.buffer).setBigUint64(
    32,
    minimumInputBytes,
    true,
  );
  new DataView(bytes.buffer).setBigUint64(40, 64n, true);
  return bytes;
}

function write(memory, pointer, bytes) {
  if (pointer >= 0 && pointer <= memory.buffer.byteLength &&
      bytes.byteLength <= memory.buffer.byteLength - pointer) {
    new Uint8Array(memory.buffer).set(bytes, pointer);
  }
}
