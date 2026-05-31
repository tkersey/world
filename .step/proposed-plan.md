<proposed_plan>
Iteration: 7

# World Handoff Kernel Execution Campaign

## Summary
Build World Handoff Kernel by adding deterministic target/run/environment handoff objects above the Timeline Kernel, integrating environments into `Machine`, and proving parked, replay, verify, branch, and agent transfer without storage, transport, scheduler, async, WASM, or real integrations. First wave creates stable identity/import/binding primitives; completion means `$st` tasks are complete, `$fixed-point-driver` reaches no unresolved truth-owner findings, every listed Zig command passes, and `$ship` opens/updates the PR with proof.

## Non-Goals/Out of Scope
- No storage backend, xitdb integration, network/transport, scheduler, async runtime, provider lifecycle, service discovery, security/signing/encryption, WASM ABI, or linear-memory layout.
- No real model/tool/file/human integrations, provider catalog, morphism catalog, agent framework, or service discovery.
- No Boundary closure, normalization, Boundary module image implementation, TreatyResolver hot path, ProviderHarness hot path, closure graph traversal, or operation-name string dispatch.
- No sender-supplied acceptance certificate may authorize execution on the receiver; receiver must recompute acceptance locally.

## Implementation Brief
- step=st-201 identity/import foundation; owner=implementation; success_criteria=TargetRef, ImportRequirement, ImportSet, PortAuthority, AdapterDescriptor, Binding structs/constants/fingerprints compile and focused tests pass
- step=st-202 environment acceptance; owner=implementation; success_criteria=Environment.Policy, BindingPlan, AcceptanceReport, EnvironmentCertificate validate correct/wrong/missing/extra bindings and produce stable pointer-free fingerprints
- step=st-203 Machine integration; owner=implementation; success_criteria=Machine accepts Environment, legacy `.ports` remains sugar, BindingPlan drives dense dispatch, Native/Replay/Verify/Byte adapters work through Environment
- step=st-204 run state/image; owner=implementation; success_criteria=RunState and RunImage encode/decode/validate parked/completed/failed/branch states, include required refs, and reject malformed/oversized/native identity
- step=st-205 handoff workflows; owner=implementation; success_criteria=Handoff preflight/resume/replay/verify supports parked port, replay-only, verify divergence, target mismatch rejection, pending/checkpoint mismatch rejection, branch selection/fork metadata
- step=st-206 examples/docs/build; owner=implementation; success_criteria=five requested examples/run steps added; README, `docs/environment.md`, and `docs/handoff.md` document framing and non-goals; `zig build check` includes new work
- step=st-207 fixed-point proof and ship; owner=implementation; success_criteria=`$fixed-point-driver` reports no material normal-form findings, full Zig proof bundle passes, `$st` projection is clean, PR body contains requested summary/proof, and `$ship` opens/updates PR without merge

Iteration: 7
</proposed_plan>
