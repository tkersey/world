<proposed_plan>
Iteration: 8

# World Admission Kernel Implementation Plan

## Summary
Build the World Admission Kernel as the deterministic receiver-side layer between transferred portable run data and existing World execution. Admission validates a `TransferPackage`, derives a manifest, bridges Boundary module references/images through Boundary-owned APIs, matches local generated targets, preflights local environments and permits, emits deterministic reports/receipts, and returns an executable `AdmittedRun` only when local execution is permitted.

## Non-Goals/Out of Scope
No storage backend, xitdb, network/transport, scheduler, async runtime, real model/tool/file/human integrations, provider lifecycle, service discovery, WASM ABI, Boundary loaded execution, Boundary closure/normalization, TreatyResolver or ProviderHarness hot path, signing/encryption, cryptographic security claims, agent framework, package manager, or artifact registry.

## Implementation Brief
1. step=admission_package_foundation; owner=implementation; success_criteria=version constants, `TransferPackage`, `PackageManifest`, encode/decode/validate, deterministic fingerprints, validation limits, malformed/oversized rejection, and package/manifest tests pass.
2. step=module_registry_gateway; owner=implementation; success_criteria=`ModuleRef`, `ModuleGateway`, `TargetRegistry`, `TargetMatch`, `ExportSummary`, module-derived import summaries, local target matching, inspect-only full module support, and registry/gateway/match tests pass.
3. step=admission_decision_layer; owner=implementation; success_criteria=`AdmissionMode`, `AdmissionPolicy`, `AdmissionRequest`, `AdmissionReport`, `AdmissionReceipt`, deterministic blockers/warnings/fingerprints, and policy/report/receipt tests pass.
4. step=execution_integration; owner=implementation; success_criteria=`Admitter` produces `AdmittedRun` only for accepted executable modes; RunImage, Handoff, Supervision, and Timeline carry optional module/admission links while old images/tests remain compatible.
5. step=examples_docs_build; owner=implementation; success_criteria=five admission examples, build run steps, README update, `docs/admission.md`, and check-step wiring compile and demonstrate reference, full-module inspect, parked handoff, replay/verify, and agent transfer scenarios.
6. step=fixed_point_review; owner=verification; success_criteria=no duplicate truth owner, no unretired scaffold, no unresolved material counterexample, and one-change challenge produces no further required code change.
7. step=proof_closeout_and_ship; owner=verification; success_criteria=all requested format, diff, build, check, example, filtered test, full test, and lint commands pass; `$st` projection is clean; PR is opened or updated with proof.

Iteration: 8
</proposed_plan>
