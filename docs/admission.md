# World Admission

Admission is the receiver-side proof that a transferred run can be interpreted locally under local environment and permit.

Boundary does the algebra and serializes Certified Boundary Modules. World handles ports, chooses the ABI, owns timelines, environments, run contracts, and admits transferred runs.

## TransferPackage

`world.Admission.TransferPackage` is a local deterministic envelope for admission. It may contain a `TargetRef`, `ModuleRef`, full Boundary module bytes, `RunImage`, `TranscriptImage`, checkpoint refs, branch refs, prior permit/receipt refs, requested mode, supervision hint, and metadata.

It is not storage, transport, trust, signing, encryption, credential handling, native handler transport, request-token transport, or a package manager.

## PackageManifest

`PackageManifest` summarizes package content: package kind, target/module/run/transcript fingerprints, checkpoint and branch counts, prior receipt count, requested mode, and summary metadata. The manifest fingerprint is checked during package decode/validation.

## TargetRegistry

`TargetRegistry` is an in-memory receiver-side registry of generated Boundary targets World can execute locally. Entries bind `TargetRef`, World surface, target certificate, program plan hash, `ImportSet`, normal form, and label metadata. Function pointer identity, handlers, credentials, and fetching are excluded.

## ModuleGateway

`ModuleGateway` bridges Boundary module images into World through Boundary-owned `Target.Module` APIs. It can decode/validate module bytes, derive `ModuleRef`, derive `ImportSet`, derive `ExportSummary`, and match a module ref against a local target registry.

World does not parse private Boundary module internals and does not execute full module bytes directly. Boundary `LoadedModule.Session` remains fail-closed, so full modules are inspect-only unless matched to a local generated target.

## ModuleRef

`ModuleRef` records Boundary module fingerprint, module kind, target ref fingerprint, World surface fingerprint, target certificate fingerprint, optional program plan/import/export/graph fingerprints, normal form, world-port count, label, and metadata. It excludes handlers, host pointers, credentials, ABI details, and request tokens.

## TargetMatch

`TargetMatch` compares transferred target/module identity with local executable target identity. It reports exact/reference/full-module-to-local-target matches and mismatches for surface, certificate, program plan, normal form, and available table/import summaries.

## AdmissionPolicy

`AdmissionPolicy` controls accepted package kinds and modes: reference targets, full modules, inspect-only modules, local target requirement, environment preflight, permit requirement, replay/verify/parked/branch/completed modes, mismatch rejection, and package limits.

Presets:

- `strict_local_execution`
- `inspect_modules`
- `replay_only`
- `handoff_receiver`
- `verify_receiver`
- `test_fixture`

## AdmissionRequest

`AdmissionRequest` records the receiver-requested operation: package fingerprint, mode, policy fingerprint, optional registry/environment/permit fingerprints, requested branch/checkpoint, and metadata.

## AdmissionReport

`AdmissionReport` is the deterministic decision report. It records accepted/rejected state, mode, package and manifest fingerprints, target/module/match/import/environment/permit/preflight fingerprints, blockers, warnings, and summary text.

Blockers include invalid package, unsupported kind, missing target, target/module mismatch, unsupported loaded execution, missing import set, missing/rejected environment, missing/rejected permit, run/transcript/checkpoint/branch/prior-receipt mismatch, disallowed mode, and package limits.

## AdmissionReceipt

`AdmissionReceipt` records accepted admission. It binds request, report, package, target, optional module/local-target/match/environment/permit/admitted-run fingerprints, accepted mode, warnings, and metadata. It is deterministic but not cryptographic.

## AdmittedRun

`AdmittedRun` is the executable admission result. It carries receipt fingerprint, local target ref, optional environment certificate, receiver permit, run image, transcript image, selected branch/checkpoint, and mode. It delegates execution to existing Machine and Handoff APIs.

Inspect-only module admission does not produce an `AdmittedRun`.

## Reference Target Admission

`examples/world_admission_reference.zig` builds a target-reference package, registers the local target, admits it, and runs the admitted target.

## Full Module Inspect-Only Admission

`examples/world_admission_full_module_inspect.zig` packages full Boundary module bytes, admits in inspect-only mode, derives import/export information, and reports loaded execution as unsupported without treating that as an inspect failure.

## Parked Handoff Admission

`examples/world_admission_parked_handoff.zig` packages a parked module-aware `RunImage`, matches a receiver target, checks environment/permit, emits an admission receipt, and resumes through Handoff.

## Replay/Verify Admission

`examples/world_admission_replay_verify.zig` admits a completed run package for replay and verify, replays without fresh handlers, then verifies with changed handler behavior and detects divergence.

## Agent Transfer Admission

`examples/world_admission_agent_transfer.zig` admits an agent-shaped package with module reference, model/tool imports, receiver permit, and replayed final output.

## Why Storage And Transport Stay Out Of Scope

Admission answers what was received, whether it matches local executable targets, which environment and permit apply, and what receipt proves the decision. It deliberately does not decide where packages live, how bytes move, how peers discover each other, or how cryptographic trust is established.

## Future Boundary LoadedModule Execution

If Boundary later supports loaded module execution, World can add an execution path behind `ModuleGateway` and Admission policy. Until then, full module bytes remain inspect-only unless matched to a generated local target.

## Non-Goals

World Admission does not implement storage, network transport, scheduler, async runtime, real model/tool/file/human integrations, provider lifecycle, service discovery, WASM ABI, linear memory layout, Boundary closure/normalization, TreatyResolver or ProviderHarness hot paths, signing, encryption, agent framework, package manager, or artifact registry.
