<proposed_plan>
Iteration: 7

# World Guest Conformance Kernel Execution Plan

## Round Delta
- Converted the spec-pipeline handoff into a dependency-ordered implementation campaign with concrete owners, proof gates, rollback triggers, and required build/example/test surfaces.
- Hardened the core risk: guest proof must compare behavior, not just wasm shape; NativeGuest/native conformance and no-handler-call checks are mandatory.
- Added `Guest.Abi.Contract` as the ABI drift guard: a fingerprinted manifest of exports, status codes, buffer limits, and forbidden imports used by tests and the wasm inspector.

## Summary
Build World Guest Conformance by extending the existing Runspace manual-frame boundary, not by creating a second execution engine. First wave: add `world.Guest` API, `GuestCore`, ABI status/buffer contracts, and NativeGuest over canonical `Frame.Request` / `Frame.Response` bytes. Done means normal Runspace and NativeGuest produce matching pending frames, statuses, final result, transcript and receipt evidence, while a wasm32-freestanding one-port guest builds and passes export/import inspection in default checks.

Implementation is additive under `world.Guest`; Boundary remains WASM-free and target-neutral. External wasm runtime execution stays optional, with default CI limited to native conformance plus wasm artifact compile/inspection.

## Non-Goals/Out of Scope
No Boundary WASM, WASI filesystem, storage/xitdb, network transport, async runtime, scheduler thread, real model/tool/file/human integrations, provider lifecycle, service discovery, cryptographic signing/encryption, browser package, Component Model/WIT, arbitrary loaded Boundary module execution, TreatyResolver hot path, or ProviderHarness hot path.

## Interfaces/Types/APIs Impacted
- Add `world.Guest` with `Core`, `Abi`, `Status`, `Buffer`, `NativeGuest`, `ConformanceVector`, `ConformanceReport`, and optional nested `Wasm`.
- Add constants: `world_guest_abi_version = 1`, `world_guest_abi_contract_fingerprint_version = 1`, `world_guest_conformance_vector_fingerprint_version = 1`, `world_guest_conformance_report_fingerprint_version = 1`.
- ABI exports: `world_abi_version`, `world_init`, `world_tick`, `world_status`, `world_pending_count`, pending/result/receipt/transcript/error len+read functions, `world_submit_response`, optional `world_alloc/world_free`.
- Build additions: `world-wasm`, `check-world-wasm`, `run-world-guest-one-port`, `run-world-guest-conformance`, `run-world-wasm-export-check`, `run-world-guest-agent-conformance`, optional `run-world-wasm-one-port`.

## Data Flow
1. Normal path: `AdmittedRun` or local target installs into `Runspace`; `tick` parks on `PendingPort`; host submits typed/native response; Runspace completes.
2. Guest path: `Guest.Core` installs the same run in manual mode; `tick` parks; core encodes pending `Frame.Request`; host decodes and submits canonical `Frame.Response`; core routes by mailbox/request identity.
3. NativeGuest path: struct methods mirror ABI calls and compare outputs with normal path.
4. Wasm path: freestanding one-port artifact embeds known target, exports ABI functions and memory, and is inspected for required exports and forbidden imports; optional runtime executes the same byte exchange.

## Tests/Acceptance
- Unit: GuestCore init/tick/park/read/submit/resume/done/result/receipt/transcript/error states.
- ABI: stable version/status/function list/`Guest.Abi.Contract`, buffer caps, invalid state, invalid frame, stale/unknown pending.
- Conformance: one-port native vs NativeGuest exact pending frame bytes, final result, transcript summary, receipt summary; agent native vs NativeGuest; supervised denial; parked handoff native/NativeGuest when supported.
- Wasm: one-port wasm compiles non-empty, required exports exist, memory convention present, forbidden imports absent.
- Examples: all new guest examples print stable fingerprints and are wired into `zig build check --summary all`.

## Rollback/Abort Criteria
- Abort or split if GuestCore needs duplicated Machine/Runspace execution logic.
- Abort if wasm one-port requires WASI or unknown imports.
- Abort if NativeGuest/native conformance cannot prove no-handler execution.
- Abort if existing `zig build check --summary all` regresses without a directly related, invariant-preserving fix.

## Implementation Brief
1. step=guest-api-contract; owner=implementation; success_criteria=`world.Guest` API/status/buffer/ABI contract constants compile and focused ABI tests pass.
2. step=guest-core; owner=implementation; success_criteria=`Guest.Core` installs one run, parks, reads request bytes, accepts response bytes, completes, and exposes evidence without native dispatch.
3. step=native-guest-conformance; owner=implementation; success_criteria=`NativeGuest` methods match ABI shape and conformance reports pass for one-port, agent, supervised denial, and supported parked handoff.
4. step=wasm-artifact-inspector; owner=implementation; success_criteria=wasm32-freestanding one-port artifact builds; inspector validates exports, memory, ABI contract, and forbidden imports.
5. step=examples-docs; owner=implementation; success_criteria=new examples run with stable output and docs explain GuestCore, ABI v0, conformance, optional runtime, and non-goals.
6. step=proof-ship; owner=verification; success_criteria=all listed proof commands pass, optional runtime is either proven or explicitly skipped, `$st` projection is clean, and `$ship` opens or updates the PR with proof.

Iteration: 7
</proposed_plan>
