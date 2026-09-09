import { worldError } from "./errors.mjs";

export const MAXIMUM_KERNEL_BYTES = 64 * 1024 * 1024;
export const MAXIMUM_MEMORY_PAGES = 4096;

const UTF8 = new TextDecoder("utf-8", { fatal: true });
const VALUE_TYPES = new Map([
  [0x7f, "i32"],
  [0x7e, "i64"],
  [0x7d, "f32"],
  [0x7c, "f64"],
  [0x7b, "v128"],
  [0x70, "funcref"],
  [0x6f, "externref"],
]);

export const PROCESS_KERNEL_EXPORT_SIGNATURES = Object.freeze({
  boundary_process_kernel_abi_version: signature([], ["i32"]),
  boundary_process_kernel_reserve: signature(["i64"], ["i32"]),
  boundary_process_kernel_input_ptr: signature([], ["i32"]),
  boundary_process_kernel_input_capacity: signature([], ["i32"]),
  boundary_process_kernel_input_payload_ptr: signature([], ["i32"]),
  boundary_process_kernel_occupied_memory_bytes: signature([], ["i64"]),
  boundary_process_kernel_prepare_input: signature(
    ["i32", "i64", "i64", "i32", "i64"],
    ["i32"],
  ),
  boundary_process_kernel_execute: signature(["i32"], ["i32"]),
  boundary_process_kernel_output_ptr: signature([], ["i32"]),
  boundary_process_kernel_output_len: signature([], ["i64"]),
  boundary_process_kernel_error_ptr: signature([], ["i32"]),
  boundary_process_kernel_error_len: signature([], ["i32"]),
});

export const PROCESS_KERNEL_EXPORT_NAMES = Object.freeze([
  "memory",
  ...Object.keys(PROCESS_KERNEL_EXPORT_SIGNATURES),
]);

/**
 * Inspect the Process kernel without compiling or instantiating it.
 * WebAssembly.validate supplies full binary validation; the bounded reader
 * below recovers the exact ABI-relevant type and ownership facts.
 */
export function inspectProcessKernelWasm(bytes) {
  if (!(bytes instanceof Uint8Array)) {
    throw worldError(
      "WORLD_INPUT_INVALID",
      "Process kernel bytes must be a Uint8Array",
    );
  }
  if (bytes.byteLength > MAXIMUM_KERNEL_BYTES) {
    throw worldError(
      "WORLD_KERNEL_TOO_LARGE",
      "Process kernel exceeds the admission byte limit",
      { byteLength: bytes.byteLength, maximumByteLength: MAXIMUM_KERNEL_BYTES },
    );
  }
  if (bytes.byteLength < 8 ||
      bytes[0] !== 0x00 || bytes[1] !== 0x61 ||
      bytes[2] !== 0x73 || bytes[3] !== 0x6d ||
      bytes[4] !== 0x01 || bytes[5] !== 0x00 ||
      bytes[6] !== 0x00 || bytes[7] !== 0x00 ||
      !WebAssembly.validate(bytes)) {
    throw worldError(
      "WORLD_KERNEL_WASM_INVALID",
      "Process kernel is not a valid WebAssembly 1 binary",
    );
  }

  try {
    return inspectValidated(bytes);
  } catch (error) {
    if (error?.name === "WorldProcessHostError") throw error;
    throw worldError(
      "WORLD_KERNEL_WASM_INVALID",
      "Process kernel WebAssembly structure is malformed",
    );
  }
}

export function wasmOffset(value, label) {
  if (!Number.isInteger(value)) {
    throw worldError(
      "WORLD_KERNEL_RANGE_INVALID",
      `${label} is not a wasm32 offset`,
    );
  }
  const unsigned = value >>> 0;
  if (value !== unsigned && value !== (unsigned | 0)) {
    throw worldError(
      "WORLD_KERNEL_RANGE_INVALID",
      `${label} is not a wasm32 offset`,
    );
  }
  return unsigned;
}

export function wasmLength(value, label) {
  if (typeof value === "bigint") {
    if (value < 0n || value > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw worldError(
        "WORLD_LENGTH_UNSAFE",
        `${label} cannot be represented exactly by this JavaScript host`,
      );
    }
    return Number(value);
  }
  return wasmOffset(value, label);
}

export function wasmRange(memory, pointerValue, lengthValue, label) {
  if (!(memory instanceof WebAssembly.Memory)) {
    throw worldError(
      "WORLD_KERNEL_PROFILE_INVALID",
      "Process kernel did not export its linear memory",
    );
  }
  const start = wasmOffset(pointerValue, `${label} pointer`);
  const length = wasmLength(lengthValue, `${label} length`);
  const view = new Uint8Array(memory.buffer);
  if (start > view.byteLength || length > view.byteLength - start) {
    throw worldError(
      "WORLD_KERNEL_RANGE_INVALID",
      `${label} range is outside exported memory`,
      { pointer: start, length, memoryByteLength: view.byteLength },
    );
  }
  return view.subarray(start, start + length);
}

function inspectValidated(bytes) {
  const reader = new Reader(bytes, "WebAssembly module");
  reader.skip(8);

  let types = null;
  let functions = null;
  let memory = null;
  let exports = null;
  let importCount = 0;
  let hasStart = false;

  while (!reader.done) {
    const sectionId = reader.byte();
    const sectionLength = reader.varUint32();
    const section = reader.child(sectionLength, `WebAssembly section ${sectionId}`);
    switch (sectionId) {
      case 0:
        break;
      case 1:
        types = parseTypes(section);
        break;
      case 2:
        importCount = section.varUint32();
        if (importCount !== 0) {
          throw profileError("Process kernel must not import host capabilities", {
            importCount,
          });
        }
        section.expectDone();
        break;
      case 3:
        functions = parseFunctions(section);
        break;
      case 5:
        memory = parseMemory(section);
        break;
      case 7:
        exports = parseExports(section);
        break;
      case 8:
        hasStart = true;
        throw profileError("Process kernel must not have a start section");
      default:
        break;
    }
  }

  if (types === null || functions === null || memory === null || exports === null) {
    throw profileError("Process kernel is missing required WebAssembly sections");
  }
  requireExports(exports, functions, types);

  return deepFreeze({
    format: "boundary-process-kernel-inspection/v1",
    wasm32: true,
    importCount,
    exportCount: exports.size,
    hasStart,
    memory: {
      initialPages: memory.initialPages,
      maximumPages: memory.maximumPages,
      shared: false,
      memory64: false,
    },
  });
}

function parseTypes(reader) {
  const count = boundedCount(reader.varUint32(), reader, "type");
  const types = [];
  for (let index = 0; index < count; index += 1) {
    if (reader.byte() !== 0x60) {
      throw profileError("Process kernel contains a non-function type");
    }
    const parameterCount = boundedCount(
      reader.varUint32(),
      reader,
      "function parameter",
    );
    const parameters = [];
    for (let parameter = 0; parameter < parameterCount; parameter += 1) {
      parameters.push(valueType(reader));
    }
    const resultCount = boundedCount(
      reader.varUint32(),
      reader,
      "function result",
    );
    const results = [];
    for (let result = 0; result < resultCount; result += 1) {
      results.push(valueType(reader));
    }
    types.push(signature(parameters, results));
  }
  reader.expectDone();
  return types;
}

function parseFunctions(reader) {
  const count = boundedCount(reader.varUint32(), reader, "function");
  const functions = [];
  for (let index = 0; index < count; index += 1) {
    functions.push(reader.varUint32());
  }
  reader.expectDone();
  return functions;
}

function parseMemory(reader) {
  const count = reader.varUint32();
  if (count !== 1) {
    throw profileError("Process kernel must define exactly one linear memory", {
      memoryCount: count,
    });
  }
  const flags = reader.varUint32();
  if (flags !== 0x01) {
    throw profileError(
      "Process kernel memory must be unshared wasm32 memory with a declared maximum",
      { memoryFlags: flags },
    );
  }
  const initialPages = reader.varUint32();
  const maximumPages = reader.varUint32();
  reader.expectDone();
  if (maximumPages > MAXIMUM_MEMORY_PAGES) {
    throw profileError("Process kernel memory maximum exceeds the host limit", {
      maximumPages,
      supportedMaximumPages: MAXIMUM_MEMORY_PAGES,
    });
  }
  return { initialPages, maximumPages };
}

function parseExports(reader) {
  const count = boundedCount(reader.varUint32(), reader, "export");
  const exports = new Map();
  for (let index = 0; index < count; index += 1) {
    const name = reader.name();
    const kind = reader.byte();
    const itemIndex = reader.varUint32();
    if (exports.has(name)) {
      throw profileError("Process kernel contains duplicate export names", {
        exportName: name,
      });
    }
    exports.set(name, { kind, index: itemIndex });
  }
  reader.expectDone();
  return exports;
}

function requireExports(exports, functions, types) {
  if (exports.size !== PROCESS_KERNEL_EXPORT_NAMES.length) {
    throw profileError("Process kernel export set does not match ABI v1", {
      exportCount: exports.size,
      expectedExportCount: PROCESS_KERNEL_EXPORT_NAMES.length,
    });
  }
  for (const name of PROCESS_KERNEL_EXPORT_NAMES) {
    if (!exports.has(name)) {
      throw profileError("Process kernel is missing a required ABI v1 export", {
        exportName: name,
      });
    }
  }

  const memoryExport = exports.get("memory");
  if (memoryExport.kind !== 2 || memoryExport.index !== 0) {
    throw profileError("Process kernel memory export has the wrong kind or index");
  }

  for (const [name, expected] of Object.entries(
    PROCESS_KERNEL_EXPORT_SIGNATURES,
  )) {
    const exported = exports.get(name);
    if (exported.kind !== 0) {
      throw profileError("Process kernel ABI export has the wrong kind", {
        exportName: name,
      });
    }
    const typeIndex = functions[exported.index];
    const actual = types[typeIndex];
    if (actual === undefined || !sameSignature(actual, expected)) {
      throw profileError("Process kernel ABI export has the wrong signature", {
        exportName: name,
      });
    }
  }
}

function valueType(reader) {
  const encoded = reader.byte();
  const type = VALUE_TYPES.get(encoded);
  if (type === undefined) {
    throw profileError("Process kernel contains an unsupported value type", {
      valueType: encoded,
    });
  }
  return type;
}

function signature(parameters, results) {
  return Object.freeze({
    parameters: Object.freeze([...parameters]),
    results: Object.freeze([...results]),
  });
}

function sameSignature(actual, expected) {
  return sameVector(actual.parameters, expected.parameters) &&
    sameVector(actual.results, expected.results);
}

function sameVector(left, right) {
  return left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

function boundedCount(count, reader, label) {
  if (count > reader.remaining + 1) {
    throw profileError(`Process kernel ${label} count exceeds its section`);
  }
  return count;
}

function profileError(message, details = undefined) {
  return worldError("WORLD_KERNEL_PROFILE_INVALID", message, details);
}

function deepFreeze(value) {
  for (const nested of Object.values(value)) {
    if (nested !== null && typeof nested === "object") deepFreeze(nested);
  }
  return Object.freeze(value);
}

class Reader {
  constructor(bytes, label, start = 0, end = bytes.byteLength) {
    this.bytes = bytes;
    this.label = label;
    this.cursor = start;
    this.end = end;
  }

  get done() {
    return this.cursor === this.end;
  }

  get remaining() {
    return this.end - this.cursor;
  }

  byte() {
    if (this.cursor >= this.end) throw new RangeError(`${this.label} is truncated`);
    return this.bytes[this.cursor++];
  }

  skip(length) {
    this.take(length);
  }

  take(length) {
    if (!Number.isSafeInteger(length) || length < 0 || length > this.remaining) {
      throw new RangeError(`${this.label} range is truncated`);
    }
    const start = this.cursor;
    this.cursor += length;
    return this.bytes.subarray(start, this.cursor);
  }

  child(length, label) {
    if (!Number.isSafeInteger(length) || length < 0 || length > this.remaining) {
      throw new RangeError(`${this.label} section is truncated`);
    }
    const child = new Reader(this.bytes, label, this.cursor, this.cursor + length);
    this.cursor += length;
    return child;
  }

  varUint32() {
    let result = 0;
    for (let index = 0; index < 5; index += 1) {
      const byte = this.byte();
      if (index === 4 && (byte & 0xf0) !== 0) {
        throw new RangeError(`${this.label} unsigned LEB128 overflows u32`);
      }
      result += (byte & 0x7f) * 2 ** (index * 7);
      if ((byte & 0x80) === 0) return result;
    }
    throw new RangeError(`${this.label} unsigned LEB128 is unterminated`);
  }

  name() {
    const encoded = this.take(this.varUint32());
    try {
      return UTF8.decode(encoded);
    } catch {
      throw new RangeError(`${this.label} contains invalid UTF-8`);
    }
  }

  expectDone() {
    if (!this.done) throw new RangeError(`${this.label} has trailing bytes`);
  }
}
