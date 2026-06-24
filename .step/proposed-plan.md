# World Turn Closure v1 Execution Plan

## Summary
Implement World Turn Closure v1 by extending the existing World owners, not by adding a new kernel. The governing artifact is `Appliance.TurnClosure`: a proof-carrying, canonical, fresh-instance-restorable quiescent turn whose semantic references resolve only through the immutable `Executable.Image`, the authenticated parent closure, or objects embedded in the next closure.

The first execution wave is the closure and wire contract: `Appliance.Wire`, `Appliance.TurnClosure`, Continuity bundle root kinds, closure validation/materialization, and ABI v3 skeleton while preserving current one-port behavior. Later waves add universal multi-module/provider execution, active Fabric restoration, positive replay, deterministic retry, batched host turns, independent JavaScript codecs/host, bounded universal memory, final examples, docs, and v0 gates.

The work is complete only when `zig build check-world-v0` proves positive lifecycle closure with `world_v0_complete=true`, `two_program_plans_one_wasm=true`, `loaded_internal_provider_executed=true`, `active_fabric_restore_accepted=true`, `replay_supported=true`, `replay_final_result=true`, `javascript_codec_independent=true`, `deterministic_retry=true`, and `universal_memory_bound_passed=true`.

## Non-Goals
- No new top-level runtime, reactor, mailbox, route executor, Actuation state machine, Capsule family, content-addressed graph, causal ledger, or Archive format.
- No package discovery, module fetching, service discovery, package manager, marketplace, JIT, native shared-library loading, WASI, WIT/Component Model, network transport, production storage, real model API, production tool registry, filesystem authority inside World, scheduler threads, async runtime, multi-writer Archive coordination, live code upgrade, migration across different `Executable.Image` identities, exactly-once effect claims, signing, encryption, or cryptographic trust claims.
- No host-authored World evidence fingerprints. `Wire.TurnInput` and related records are untrusted input only; World authors receipts and canonical evidence.

## Implementation Brief
1. step=turn_closure_wire_contract; owner=Appliance/Continuity; success_criteria=add `Appliance.Wire` and `Appliance.TurnClosure` types, constants, codecs, validation reports, `ClosureSelfAudit`, missing Continuity object kinds, and focused roundtrip/negative tests without changing current runtime semantics.
2. step=abi_v3_memory_contract; owner=Appliance/Executable; success_criteria=replace the universal host governing surface with ABI v3 `submit_turn` and `read_closure`, keep load/reset/unload transactional, reject v2-as-v3 ambiguity, and reduce universal fixture memory to a bounded <=64 MiB profile.
3. step=universal_loaded_provider_execution; owner=Executable/Runspace/Fabric/Supervision; success_criteria=enable `supports_internal_providers=true`, accept root plus provider modules, route by residual requirement identity and provider module fingerprint, execute loaded providers through Runspace/Fabric, and prove provider parking/rollback/no native callback.
4. step=active_fabric_closure_restore; owner=Capsule/Runspace/Fabric/Appliance; success_criteria=freeze and thaw executable loaded active Fabric with root/provider sessions, mailboxes, invocation, mappings, permits, usage, requests, Chronicle and Archive anchors; positive migration completes after fresh runtime restore.
5. step=replay_retry_batch_archive; owner=Actuation/Appliance/Archive/Chronicle; success_criteria=positive replay suppresses fresh covered HostRequests with `fresh_called=false`, deterministic retry produces byte-identical closures after lost output, batched replies canonicalize and preserve partial requests, and Archive crash-window recovery follows World Archive scanning.
6. step=javascript_independent_host_codecs; owner=Appliance.Wire/JS reference host; success_criteria=add dependency-free JS Wire and loaded-value codecs, remove native reply helper and child-process reply construction, run one-port and loaded-agent flows through real WebAssembly, and pass Zig/JS positive and malformed fixture conformance.
7. step=v0_report_examples_docs; owner=build/docs/verification; success_criteria=add required examples, `WorldV0Report`, focused check steps, revised `check-world-v0`, `check-world-v0-negative`, and docs/README updates; denial-only restore, unsupported replay, same-program reload, inspection-only WASM, and helper-dependent JS no longer count as v0 completion.

## Required Proof
- `zig version`
- `node --version`
- `zig fmt --check build.zig src examples test scripts`
- `git diff --check`
- `zig build --summary all`
- `zig build check --summary all`
- `zig build check-world-turn-closure`
- `zig build check-world-universal-providers`
- `zig build check-world-active-fabric-restore`
- `zig build check-world-replay-positive`
- `zig build check-world-deterministic-retry`
- `zig build check-world-appliance-batching`
- `zig build check-world-js-codec`
- `zig build check-world-two-programs-one-wasm`
- `zig build check-world-universal-memory`
- `zig build check-world-v0-negative`
- `zig build check-world-v0`
- `zig build world-universal-appliance-wasm`
- `zig build check-world-universal-appliance-wasm`
- actual Node/WebAssembly execution
- zero-import inspection
- ABI signature inspection
- linear-memory bound inspection
