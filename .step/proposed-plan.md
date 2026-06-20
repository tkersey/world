# World Appliance Kernel Implementation Plan

## Summary
Implement `world.Appliance` as an isolated vertical integration kernel that composes existing Runspace, Fabric, Linker, Actuation, Capsule, Continuity, Chronicle, Archive, and Supervision owner APIs into one canonical quiescent host-turn protocol.

The first execution wave is the static contract layer: `src/appliance.zig`, a single root re-export, format/fingerprint constants, manifest/profile/capacity/memory plan types, and deterministic fingerprint helpers. Later waves add closed-world validation, turn orchestration, Actuation host preparation/finalization, Capsule checkpointing, Archive append evidence, Native/WASM ABI, examples, docs, and conformance tests.

The work is complete only when the closed agent appliance proves resident versus reconstructed equivalence, emits one bounded canonical `TurnOutput` per turn, and passes the requested Zig, WASM-inspection, example, and appliance-focused proof commands.

## Non-Goals
- No real model API, tool registry, filesystem effect, network transport, storage adapter, scheduler, async runtime, WIT, Component Model binding, WASI, external WASM runtime dependency, signing, encryption, exactly-once host-effect claim, credential serialization, arbitrary loaded Boundary module execution, operation-name dispatch, TreatyResolver/ProviderHarness hot-path use, or hidden process state across completed turns.
- Appliance must not duplicate owner state machines. Actuation owns effect semantics, Capsule owns freeze/thaw, Archive owns canonical sealed bytes, Runspace owns mailbox state, Fabric owns internal routes, and Supervision owns permits/budgets/receipts.

## Implementation Brief
1. step=appliance_static_contract; owner=implementation; success_criteria=add `src/appliance.zig`, `world.Appliance` root re-export, format/fingerprint constants, Manifest/Profile/Capacity/MemoryPlan types, deterministic fingerprint helpers, and focused manifest/memory-plan tests.
2. step=closed_world_define; owner=implementation; success_criteria=implement `Appliance.Define` compile-time validation and static tables against existing Linker/Fabric/Assembly/Actuation/Supervision inputs; reject unresolved ports, missing bindings, loaded modules, runtime discovery, string dispatch, and hot-path TreatyResolver/ProviderHarness use.
3. step=actuation_host_membrane; owner=implementation; success_criteria=add `Actuation.Membrane.prepareHost`, `Actuation.Membrane.finalizeHost`, Prepared/Finalized records, and Appliance HostRequest/HostOutcome/HostReply validation with stale, duplicate, wrong request, wrong schema, replay, and no-host-call tests.
4. step=core_quiescent_turn; owner=implementation; success_criteria=implement Core state machine, canonical Command decode/validate, submit/execute/read/reset/restore operations, deterministic quiescence loop, bounded buffers, capacity failures, inspect/cancel behavior, and no-mutation malformed-input tests.
5. step=capsule_archive_receipts; owner=implementation; success_criteria=integrate Capsule checkpoint emission/restore, Continuity/Chronicle object evidence, Archive.AppendBatch planning, RetentionAck validation, TurnReceipt creation, and resident/reconstructed reconstruction reports.
6. step=examples_agent_docs; owner=implementation; success_criteria=build one-port and canonical agent appliances plus examples for one-port, agent, reconstruct, archive, replay, and wasm-probe; update README and `docs/appliance.md` with host responsibility doctrine and non-goals.
7. step=appliance_abi_wasm; owner=implementation; success_criteria=add Appliance ABI v1 exports, Native ABI-shaped simulation, `world-appliance-wasm`, `check-world-appliance-wasm`, and WASM inspection proving required exports, matching manifest, and zero forbidden imports.
8. step=conformance_fixed_point; owner=verification; success_criteria=add ConformanceVector/ConformanceReport coverage for native owner APIs, Appliance.Native, resident Core, reconstructed Core, WASM artifact inspection, replay, archive ack/unack, and bounded equivalence trace digest; no duplicate truth owner or unretired scaffold remains.
9. step=proof_closeout; owner=verification; success_criteria=run requested proof commands: `zig version`; `zig fmt --check build.zig src examples test`; `git diff --check`; `zig build --summary all`; `zig build check --summary all`; existing world/archive wasm checks; new appliance wasm checks; all appliance examples; focused appliance filters; `zig build lint -- --max-warnings 0`; inspect diff and update or open PR only if PR publication is explicitly in scope.

## Required Proof
- `zig version`
- `zig fmt --check build.zig src examples test`
- `git diff --check`
- `zig build --summary all`
- `zig build check --summary all`
- `zig build world-wasm`
- `zig build check-world-wasm`
- `zig build world-archive-wasm`
- `zig build check-world-archive-wasm`
- `zig build world-appliance-wasm`
- `zig build check-world-appliance-wasm`
- `zig build run-world-appliance-one-port`
- `zig build run-world-appliance-agent`
- `zig build run-world-appliance-reconstruct`
- `zig build run-world-appliance-archive`
- `zig build run-world-appliance-replay`
- `zig build run-world-appliance-wasm-probe`
- `zig build test --summary none -- --test-filter "appliance"`
- Focused appliance filters for definition, manifest, capacity, memory plan, command, host request, host reply, quiescence, checkpoint, reconstruction, actuation, archive, agent, and wasm.
- `zig build lint -- --max-warnings 0`
