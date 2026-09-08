# World Process v2 ABI and native API

World runs admitted Boundary 2 Program data with one Zig interpreter, compiled
natively and to an import-free WASM module. Applications and handlers are input
data. The kernel imports neither application code nor environmental callbacks.
This document describes the current development ABI; release receipts bind the
eventual frozen kernel bytes and physical profile.

The six portable record formats and hash preimages are specified by the matching
Boundary package's `docs/bpi2-wire.md`. All integers crossing the WASM API below
are unsigned bit patterns. Hosts must interpret i64 results without precision
loss, for example with JavaScript BigInt.

## Exports

The module exports one unshared 32-bit memory named `memory` and exactly these
functions. It has no imports, start function, imported memory, or host scheduler.

| Export | WASM signature | Meaning |
| --- | --- | --- |
| world_process_v2_abi_version | `() -> i32` | Exactly 2. |
| world_process_v2_prepare_input | `(i64) -> i32` | Prepare capacity for the input byte length. |
| world_process_v2_input_ptr | `() -> i32` | Current input offset; reread after preparation. |
| world_process_v2_input_capacity | `() -> i64` | Available input bytes. |
| world_process_v2_execute | `(i64) -> i32` | Consume one prepared input and produce an outcome. |
| world_process_v2_output_ptr | `() -> i32` | Current output offset. |
| world_process_v2_output_len | `() -> i64` | Exact output record length. |
| world_process_v2_error_ptr | `() -> i32` | Diagnostic offset after rejection. |
| world_process_v2_error_len | `() -> i64` | Exact diagnostic byte length. |

Preparation returns 0 when ready, 1 when a PKO2 NeedsCapacity record is available,
or 2 on rejection with a UTF-8 diagnostic. Execution returns 0 for a PKO2 outcome,
including NeedsCapacity, or 2 for rejection. Rejection sets output length to
zero. Diagnostic strings are debugging information, not a versioned structured
error protocol. Malformed requests do not become authored Failed outcomes.

## Invocation

1. Verify the kernel's expected SHA-256 and inspect its complete import/export
   signatures and memory declarations before instantiating it.
2. Instantiate with no imports and require ABI version 2.
3. Encode one complete PKI2 and call prepare_input with its exact length.
4. For result 0, read the current input pointer/capacity, check the entire range
   against the current memory size, and copy PKI2 into it. Then call execute with
   the exact input length, once. For result 1, skip execution and read PKO2.
5. After any call that may grow memory, obtain a fresh memory view. Check the
   output or diagnostic range with overflow-safe arithmetic before reading it.
6. Copy the complete output out of guest memory before reuse or disposal. Decode
   one strict PKO2. Retain a returned PST2 and any associated ERQ2 as detached
   host bytes.

Preparation resets invocation scratch and invalidates prior output. Execution
requires preparation and consumes it. The JavaScript adapter uses a fresh
instance for every invocation, so portable State is the only cross-invocation
execution state. It never interprets handlers or schedules application tasks.

The guest begins with configured input, working, and output reservations, then
grows memory as operational demand requires. Development defaults are 65,536
input bytes, 1,048,576 working bytes, 65,536 output bytes, a 65,536-byte stack, and
a 256 MiB maximum memory. These reservations are not semantic program limits.
Build options `v2-input-capacity`, `v2-working-capacity`, `v2-output-capacity`, and
`v2-maximum-memory` select a physical profile. Final memory minima and kernel
size come from inspection of the actual release bytes.

An input length larger than the WASM32 addressable range is rejected. A genuine
failed memory growth reports the observed lower bound in pages, along with the
responsible arena's demand. NeedsCapacity publishes no successor State. A host
may retry the unchanged input under a larger permitted profile. Terminating a
worker also publishes no successor and proves no cleanup took place.

## Native Zig interface

Import the World `world` module and use `world.process_v2`. The runtime module
depends only on `boundary_data_v2` and pure support. The caller supplies storage
through a Zig allocator:

```zig
var outcome = try world.process_v2.run(allocator, .{
    .program = .{ .image = image_bytes },
    .instance = .{ .initial_args = argument_bytes },
});
defer outcome.deinit();
// outcome.record is a Boundary data.protocol.Outcome.
```

ProgramInput alternatives are `records: Program` and `image: []const u8`.
Instance alternatives are `initial_args: []const u8`, `records: State`, and
`snapshot: []const u8`. Native Program records are admitted and normalized;
native State records receive full program-relative admission before graph
normalization. Inputs are borrowed for the call. The returned Outcome owns its
record and all bytes until deinit; the caller may release or change its input
after the call returns.

`advance` executes through one internal transition boundary, returning Progressed
when execution remains internal. `run` continues internal transitions until
Requested, Yielded, Completed, Failed, or Cancelled. Both share the same evaluator
and have no semantic fuel. Running a program that never reaches a boundary may
therefore remain in the call. `invoke` accepts a decoded portable Input and
selects its mode. Direct allocator exhaustion is `error.OutOfMemory`; a caller
can use Workspace to observe demand and provide growth. The WASM boundary turns
that operational failure into PKO2 NeedsCapacity.

`Invocation.control` is `.continue_value = null` by default. Supply ERS2 bytes
as `.continue_value = result_bytes` only for the current parked ERQ2. Cancel with
`.cancel = .{ .text = reason }` or `.cancel = .{ .bytes = reason_bytes }`, against
saved State only. In-progress cleanup is resumed rather than restarted; any
changed State rebinds its request, and an existing primary failure keeps priority.

Optional Statistics count transitions, direct clauses, one-shot captures,
multi templates, and branch activations. They are transient, saturating
observations and are never serialized or used as an execution limit.

## JavaScript embedding

`admitProcessKernel(bytes, { expectedSha256 })` verifies the expected lowercase
hex digest and static ABI, compiles the kernel, and returns `advance(input)` and
`run(input)`. Inputs have `image` and exactly one of `initialArgs` or `state`.
Optional `result` is a complete ERS2; optional `cancel` is a string or byte array.
Result and cancellation cannot both be supplied. Returned objects include the
decoded outcome and the complete copied PKO2 in `bytes`.

Kernel admission checks the 64 MiB byte limit before copying or hashing.
`loadProcessKernel({ kernelPath, expectedSha256 })` accepts a regular-file path,
file URL, or symlink to a regular file. It checks the opened file before
allocation, bounds reads to its initial size, and rejects changes during the
read. Omitting these options selects the bundled kernel and identity manifest.
CLI data inputs and the bundled identity use the same regular-file reader;
their reads stay within the opened extent and reject observed changes.

`decodeRequest` validates canonical descriptors, payload, and request hashes.
`encodeResult` validates a typed value against that request and binds the ERS2.
`decodeOutcome` checks the PKO2 frame and its nested request-to-State digest
binding; complete program-relative PST2 admission remains in the kernel. The
adapter does not assert environmental truth, external rollback, or whole-State
anti-replay. The independently implemented Wasmtime test embedding calls this
same ABI directly and contains no handler evaluator.
