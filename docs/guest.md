# World Guest Conformance

Runspace makes execution local and deterministic. Guest Conformance proves that local execution can cross a runtime boundary.

## What is a World Guest?

A World Guest is a Runspace-backed execution core driven through canonical World bytes. It installs one admitted or local run, ticks deterministically, parks on `Frame.Request`, accepts `Frame.Response` bytes, resumes the matching pending port, and exposes result, receipt-summary, transcript, and error bytes.

The guest boundary is World-owned. Boundary remains target-neutral and does not define a WASM ABI.

## GuestCore

`world.Guest.Core` owns one `world.Runspace` in manual-dispatch mode. It does not call native handlers while parked, start threads, use wall-clock time, own storage, use network transport, call TreatyResolver, call ProviderHarness, or dispatch by operation name.

State moves through initialized, running, parked, done, and failure/error statuses. Response routing is by decoded `Frame.Response` identity against the pending mailbox entry.

## WASM ABI v1

`world.Guest.Abi` defines ABI version 1 and the stable export list:

- `world_abi_version`
- `world_init`
- `world_tick`
- `world_status`
- `world_pending_count`
- `world_pending_request_len`
- `world_read_pending_request`
- `world_submit_response`
- `world_result_len`
- `world_read_result`
- `world_receipt_len`
- `world_read_receipt`
- `world_transcript_len`
- `world_read_transcript`
- `world_last_error_len`
- `world_read_last_error`

Optional linear-memory helpers are `world_alloc` and `world_free`.

## Status Enum

`world.Guest.Status` uses stable `u32` ordinals: `ok`, `initialized`, `running`, `parked`, `done`, `failed`, `buffer_too_small`, `invalid_frame`, `invalid_state`, `unknown_pending`, `stale_pending`, `supervision_denied`, `target_mismatch`, and `admission_failed`.

## Linear Memory Exchange

The v1 memory exchange is bounded. Request, response, result, receipt, transcript, error, and pending-port caps live in `world.Guest.Buffer`.

Read methods return the required byte length when the caller buffer is too small. Response submission rejects oversized or malformed canonical frame bytes.

## Frame Bytes

`Frame.Request` and `Frame.Response` are the guest payload format. They do not carry request tokens, handler pointers, allocator pointers, runtime pointers, thread ids, credentials, storage identities, or network identities.

## NativeGuest Simulation

`world.Guest.NativeGuest` exposes ABI-shaped Zig methods over `Guest.Core`. Default CI uses it to prove native Runspace and ABI-style guest driving produce the same pending frame fingerprints, response validation behavior, final result fingerprint, transcript evidence, and supervised denial behavior without requiring wasmtime or wasmer.

## ConformanceVector

`world.Guest.ConformanceVector` records deterministic vector identity: name, kind, target ref fingerprint, optional admission/permit fingerprints, input fingerprints, expected pending frames, response frames, expected final result, transcript/receipt summaries, and expected status sequence.

Vector kinds are one-port, agent, supervised-denial, parked-handoff, and replay.

## ConformanceReport

`world.Guest.ConformanceReport` compares normal native Runspace, NativeGuest ABI simulation, wasm build/inspection, and optional wasm runtime execution. It records status, pending-frame, result, transcript, and receipt matches plus blockers and warnings.

## One-port Guest

`examples/world_guest_one_port.zig` drives a one-port target through NativeGuest ABI-style calls. It reads request bytes, submits response bytes, and prints request, response, and result fingerprints.

## Agent Guest

`examples/world_guest_agent_conformance.zig` drives an agent-shaped target through model/tool pending frames. Host responses are submitted as canonical response bytes. The example prints model/tool pending counts and final result fingerprint.

## Supervised Denial Guest

Tests cover a permit with `max_port_requests = 0`. Native Runspace and NativeGuest both deny before a handler call and expose no pending port.

## WASM Export Inspection

`zig build world-wasm` builds `world_wasm_guest_one_port.wasm` for `wasm32-freestanding-none`.

`zig build check-world-wasm` compiles that artifact and runs `examples/world_wasm_export_check.zig`, which verifies required exports, memory/alloc convention, ABI version, and forbidden imports.

Forbidden imports include WASI filesystem, random, clock, network, scheduler, unknown host callbacks, Boundary treaty/provider symbols, and native handler symbols.

## Optional Runtime Execution

Default checks do not require an external wasm runtime. A future explicit runtime step can wrap the same ABI without re-inventing semantics.

## Why this is not WASI / Component Model / WIT

The milestone proves World-owned canonical frame crossing. It does not add WASI filesystem access, Component Model bindings, WIT interfaces, browser packaging, arbitrary loaded Boundary module execution, or host callback imports for model/tool/file/human calls.

## Future Host Package

A future `world-wasm` host package can call the ABI, manage linear memory, feed response bytes, and compare reports. It should reuse World frame bytes and conformance vectors rather than defining a second semantic protocol.

## Non-goals

Guest Conformance does not implement storage, xitdb, network transport, distributed protocol, scheduler threads, async runtime, provider lifecycle, service discovery, real model/tool/file/human integrations, cryptographic signing or encryption, package management, artifact registry, WASI filesystem, browser JS packages, Component Model, WIT bindings, Boundary loaded module execution, Boundary closure/normalization, TreatyResolver hot paths, or ProviderHarness hot paths.
