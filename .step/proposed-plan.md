<proposed_plan>
Iteration: 7

# World Supervision Kernel Implementation Plan

## Summary
Build the World Supervision Kernel by adding deterministic supervision primitives to `src/world.zig`, wiring them through the existing Machine/Handoff/Environment/Timeline boundaries, and proving that supervised execution is bounded without changing unsupervised behavior. First wave is the core value model and fingerprint tests; done means all supervised examples, filtered supervision tests, existing examples, `zig build check`, and lint pass.

## Non-Goals/Out of Scope
No storage backend, xitdb, network/transport, scheduler, async runtime, real model/tool/file/human integrations, provider lifecycle, service discovery, WASM ABI, Boundary module image implementation, Boundary closure/normalization, TreatyResolver or ProviderHarness hot path, signing/encryption, cryptographic security claims, agent framework, billing/money, or wall-clock time in deterministic fingerprints.

## Implementation Brief
1. step=core_model; owner=implementation; success_criteria=version constants, supervision structs, fingerprint helpers, and isolated fingerprint/exclusion tests compile and pass.
2. step=policy_accounting; owner=implementation; success_criteria=policy presets, budgets, per-port budgets, cost model, port rules, ledger, and checks enforce deterministic limits.
3. step=membrane; owner=implementation; success_criteria=single `Supervisor`/`PolicyMembrane` path denies before adapter calls, transcript appends, branch/checkpoint, and handoff side effects.
4. step=machine_integration; owner=implementation; success_criteria=optional permit, strict permit enforcement, receipt availability, no-permit compatibility.
5. step=timeline_environment_handoff; owner=implementation; success_criteria=supervision timeline events, Environment blockers, receiver-issued handoff permit APIs, prior receipt inspection.
6. step=branch_checkpoint_handoff_budgets; owner=implementation; success_criteria=max counts/depth/cost/inherit/new-permit policies tested.
7. step=examples_docs_build; owner=implementation; success_criteria=five new examples, run steps, README update, `docs/supervision.md`, check step coverage.
8. step=proof_closeout; owner=implementation; success_criteria=run required proof commands, inspect diff, report any blockers with exact failing command.

Iteration: 7
</proposed_plan>
