# World kernel ABI 3 and byte embedding

`src/kernel/main.zig` compiles one import-free wasm32 module from the stable
evaluator. It defines unshared memory with a declared maximum (256 MiB by default)
and no start function. Programs are BPI3 data; adding an application does not
recompile the kernel. Production construction imports Boundary's pure data module
only. Fixture compilation is an explicit, separate test build.

## Exports and buffers

The only non-function export is memory. All pointers/statuses below use wasm i32
(pointers interpreted unsigned); identities, handles, lengths and quanta use i64
(interpreted unsigned). Every function returning status uses 0 success, 1 physical
capacity, 2 rejection. Capacity status publishes PKO3 `needs_capacity`; rejection
publishes only a bounded diagnostic name and zero output length.

| Export | Parameters | Result |
| --- | --- | --- |
| world_abi_version | none | i32 = 3 |
| world_initialize | instance:i64 | status |
| world_set_limits | instance, input_limit, working_limit, output_limit:i64 | status |
| world_prepare_input | instance, length:i64 | status |
| world_input_ptr | none | i32 |
| world_input_capacity | none | i64 |
| world_output_ptr | none | i32 |
| world_output_len | none | i64 |
| world_error_ptr | none | i32 |
| world_error_len | none | i64 |
| world_prepared_handle | none | i64 |
| world_session_handle | none | i64 |
| world_working_live | none | i64 |
| world_working_peak | none | i64 |
| world_invoke | instance, length:i64 | status |
| world_prepare | instance, length:i64 | status |
| world_release_prepared | instance, handle:i64 | status |
| world_start | instance, prepared_handle, length:i64 | status |
| world_restore | instance, prepared_handle, length:i64 | status |
| world_drive | instance:i64, session_handle:i64, control:i32, quantum_present:i32, quantum:i64, checkpoint:i32, length:i64 | status |
| world_checkpoint | instance:i64, session_handle:i64, transfer:i32 | status |
| world_close | instance, session_handle:i64 | status |

Initialize once with a nonzero host-selected instance namespace. Every subsequent
command checks it. Handles increase monotonically within that instance, never
reuse a released generation, and do not enter Program, State or application values.
There is one externally owned preparation slot and one resident slot. A Session
retains its preparation after `world_release_prepared`. Creating a second object
in an occupied slot rejects. These names are local handles, not global uniqueness
or distributed ownership claims.

Call prepare_input, then reacquire memory.buffer and input_ptr before copying bytes.
The consuming call must use exactly the prepared length. There are no arbitrary
caller-supplied memory pointers. Memory growth can invalidate old host views;
reacquire output pointer/length afterward and detach output before the next command.
Set_limits invalidates staged input. Each command may invalidate prior output.

Invoke consumes PKI3 and publishes PKO3. Prepare consumes BPI3 and publishes a
prepared handle. Start consumes typed initial-argument bytes; restore consumes
PST3. Both publish a session handle. Drive payloads are: control 0 none (empty),
1 ERS3 reply, 2 resume_yield (empty), 3 UTF-8 cancellation text, 4 cancellation
bytes. Quantum-present/checkpoint are exactly 0 or 1; absent quantum requires a
zero quantum argument. Resident drive publishes PKO3 with optional checkpoints.
Checkpoint publishes PST3, with transfer 1 relinquishing the resident only after
successful output allocation. Close requires terminal state. Stale/wrong handles,
wrong instance, malformed controls and reentry reject without advancing State.

## Capacity and publication

Initial input/working/output budgets are 64 KiB / 1 MiB / 64 KiB. The initial
working backing is 1 MiB. A coalescing allocator reuses freed storage and grows
within the module's declared maximum. Live-byte budgets are separate from reserved
linear memory and allocator metadata; fixed emergency capacity/diagnostic buffers
also remain outside those dynamic budgets. Working includes immutable preparation,
execution storage and temporary analysis/transaction work; input and final output
buffers have distinct budgets. The working counters report requested live/peak
bytes, not RSS or a claim about allocator slack.

Limits may be raised explicitly. Working may not shrink below its current live
allocation. Capacity reports distinguish the failed budget from memory.grow
failure, with exact final-output demand or observed lower bounds as appropriate.
Internal decoder limits remain separate physical limits and may report unknown
required working capacity. They are not authored value bounds.

Fresh and resident output allocation use separate working/output allocators.
Resident encoding allocates the final output inside its transaction; capacity
failure retains the same checkpoint, handle and pending response binding. A host
can raise capacity and resend the already obtained ERS3 without repeating the
external operation. Checkpoint transfer likewise retains custody on failure.

## Environment-neutral JavaScript

`src/embedding/kernel.mjs`, `codec.mjs` and their helpers use supplied bytes,
WebAssembly, TextEncoder/TextDecoder and Web Crypto, with no Node or filesystem
imports. `Kernel.create` requires an exact expected SHA-256, owns the bytes before
the asynchronous hash, statically verifies the export signatures/memory profile,
then instantiates. It has no authentication bypass option.
The expected digest must come from the embedding's trusted artifact metadata;
computing it from an untrusted incoming kernel would not establish authenticity.

The wrapper's prepared/session tokens belong to the actual Kernel object through
a private WeakMap; copied, released and cross-instance tokens reject. Returned
bytes are detached copies. Shared mutable input buffers and forged Uint8Array
brands reject. Invocation codecs retain the schema-directed value rules, including
zero-size cardinality, bounds and UTF-8. Environmental tool semantics and checkpoint
persistence remain the caller's responsibility.

## Reproduction and qualification

Install only browser conformance tooling when needed:

```sh
npm ci --prefix test/current/browser-tools
node test/current/browser-tools/node_modules/playwright-core/cli.js install chromium firefox
```

The independent Wasmtime lane uses the existing locked Python 3.14.7 / Wasmtime
48.0.0 environment through uv. Run:

```sh
zig build build-kernel check-kernel check-transfer check-browser check-codecs \
  -Dboundary-v2-source=/absolute/path/to/boundary-compositional-execution \
  --global-cache-dir .zig-global-cache --summary all
```

The development source override is explicit. The normal dependency now selects
Boundary 3 development source, and the package root exports the current byte API.
Final namespace retirement and coordinated Agent cutover remain open. `build-kernel`
alone never constructs the source compiler. Qualification commands print the exact
kernel digest and engine versions; local emitted fixture/tool files are not releases.

Current witnesses use the same kernel bytes for twelve staged/linked Programs:
115 native/Node matched boundaries, 16 transfers between kernel instances, and
29 independent Wasmtime boundaries. The linked cases include a reusable effectful
callable, private counter interpretation, owned suspension/cleanup, a second
wrapper, and mutually recursive components. Their independent expected results
are 83, 166, and true for even(100). Wasmtime disables threads, memory64, GC,
exceptions, tail calls and SIMD. Real Chromium 153.0.8010.12 and Firefox 155.0
Workers export a resource suspension, terminate, restore its native-produced
successor in a fresh Worker, and complete retained cleanup. Wrong kernel identity
rejects in each browser. Repeated prepared Sessions show stable live and reserved
memory after warm-up. Input/work/output capacity, stale handles, transfer failure,
and old-family rejection have negative checks.

This qualifies the core runtime/embedding paths. It is not the required Agent
compiled-tool/file witness, extracted-package
qualification, or final performance acceptance. Those remain part of the full goal.

`zig build build-runtime check-package` builds a standalone current package and
checks its API and CLI after npm packing and extraction. The 64-installation
fixture demonstrates working-capacity rejection at the initial 1 MiB budget and
successful unchanged-input retry with an explicit 8 MiB budget. It does not claim
that all applications fit the initial budget. The CLI writes PKO3 to stdout and
keeps filesystem loading in the Node-only shell.
