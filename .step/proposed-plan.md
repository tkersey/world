<proposed_plan>
Iteration: 7

# World Assembly Capsule Kernel Implementation Plan

## Round Delta
- Converted the Assembly Capsule milestone into five dependency-ordered implementation waves with explicit authority boundaries, non-goals, fixed-point proof gates, examples, docs, and required Zig proof commands.
- Selected `world.Capsule` as the canonical owner for portable linked execution images, quiescence reports, freeze/thaw plans, certificates, relink verification, and restore reports.
- Locked the no-cycle rule: `Capsule.Image` fingerprints bind manifest/images/dependencies, while `Capsule.Certificate` is derived from the image plus quiescence and restore-relevant witnesses. Certificates are not embedded into the image fingerprint.
- Locked the receiver-authority rule: sender permits/receipts remain evidence only; receiver restore authority is established by local environment preflight and receiver-issued permit before Runspace mutation.
- Locked the active-Fabric rule: only parked or terminal active Fabric invocations with parent pending witness, provider witness, route witness, value mapping witness, and mailbox ownership can freeze and inspect/replay thaw; mutating restore remains fail-closed until the capsule carries an executable continuation witness.

## Summary
Add World Assembly Capsule Kernel. A Capsule freezes a quiescent linked Runspace assembly into a deterministic portable image that captures Runspace slots, pending mailbox entries, active and completed Fabric causality, Linker/Assembly provenance, admission/environment/supervision evidence, transcripts, run images, value images, and guest conformance references. A receiver can validate, inspect, replay, relink, verify, restore completed/failed states, and reissue stricter local permits without serializing handlers, credentials, native pointers, request tokens, or transport/storage state. Parked and active-Fabric capsules freeze and thaw for inspection/replay, but mutating restore is denied before Runspace mutation until an executable continuation witness exists.

## Non-Goals/Out of Scope
No storage backend, xitdb, production database, network transport, distributed protocol, scheduler thread, async runtime, real model/tool/file/human integration, provider lifecycle manager, service discovery, WASM host package, Boundary LoadedModule execution, Boundary closure/normalization, TreatyResolver hot path, ProviderHarness hot path, package manager, artifact registry, signing/encryption, cryptographic security claims, handler serialization, credential serialization, request-token serialization, or allocator/runtime/thread/file/network handle serialization.

## Governing Invariants
1. Boundary owns normalized semantics; Capsule only serializes World execution state and provenance.
2. Runspace owns execution timelines and mailbox state; Capsule images are deterministic snapshots without native execution capabilities.
3. Fabric owns explicit causality; Capsule captures and restores only witnessed routes/invocations/receipts.
4. Linker owns closed-world route synthesis; Capsule verifies embedded LinkCertificate or relinks locally and compares.
5. Receiver policy owns restore authority; sender permits are inspected as evidence, never trusted as authority.
6. Capsule restore is transactional; restore denial must happen before any Runspace mutation.
7. Capsule v1 is fail-closed for unsupported running state, parked or active-Fabric mutating restore without an executable continuation witness, unsafe active Fabric, missing witnesses, relink mismatch, environment mismatch, and permit denial.

## Interfaces/Types/APIs Impacted
- Add public `world.Capsule` namespace and ergonomic `world.AssemblyCapsule` alias only if it keeps the root surface small.
- Add constants: `world_capsule_manifest_format_version`, `world_capsule_manifest_fingerprint_version`, `world_capsule_quiescence_report_fingerprint_version`, `world_capsule_runspace_image_format_version`, `world_capsule_runspace_image_fingerprint_version`, `world_capsule_run_slot_image_fingerprint_version`, `world_capsule_mailbox_image_fingerprint_version`, `world_capsule_fabric_image_fingerprint_version`, `world_capsule_link_image_fingerprint_version`, `world_capsule_image_format_version`, `world_capsule_image_fingerprint_version`, `world_capsule_certificate_format_version`, `world_capsule_certificate_fingerprint_version`, `world_capsule_thaw_plan_fingerprint_version`, and `world_capsule_restore_report_fingerprint_version`.
- Add types: `Capsule.Kind`, `NormalForm`, `RunRole`, `RunSlotStatus`, `RestoreMode`, `RelinkStatus`, `LinkCertificateMatchStatus`, `Blocker`, `Manifest`, `QuiescenceReport`, `FreezePlan`, `ThawPlan`, `RestoreReport`, `Certificate`, `AssemblyImage`, `RunspaceImage`, `RunSlotImage`, `MailboxImage`, `FabricImage`, `LinkImage`, `Image`, `ValidationReport`, `DependencyRef`, `ObjectRef`, `HandleRemap`, `MailboxRemap`, `FabricInvocationRemap`, `FreezeOptions`, `ValidateOptions`, `ThawOptions`, `RelinkPolicy`, and `GuestRestoreOptions`.
- Add freeze APIs: `Capsule.freezeRunspace`, `Capsule.freezeAssembly`, `Capsule.freezeRun`, and `Capsule.certificate`.
- Add thaw APIs: `Capsule.validate`, `Capsule.planThaw`, `Capsule.thawIntoRunspace`, `Capsule.verifyLink`, and `Capsule.relink`.
- Add continuity-ready helpers: `Capsule.objectRefs`, `Capsule.dependencies`, and `Capsule.asBundleRoot`.
- Add internal staged restore surface: `Capsule.RestoreTransaction` with prepare, authority validation, remap construction, pre-mutation check, commit, and rollback.
- Extend Handoff with capsule bytes/images via `Handoff.fromCapsule`, `Handoff.exportCapsule`, and `Handoff.acceptCapsule`.
- Extend Admission to accept capsule packages in inspect-only, replay-only, restore-parked, relink-and-restore, and verify modes, with report/receipt capsule fingerprints.
- Add examples, build steps, README update, and `docs/capsules.md`.

## Data Flow
1. Caller supplies a Runspace and optionally an Assembly or RunHandle.
2. Capsule computes a `QuiescenceReport` over run slots, mailbox state, active Fabric routes, receipts, replay cursors, and transaction blockers.
3. Freeze rejects non-quiescent state under policy, then gathers RunspaceImage, RunSlotImage, MailboxImage, FabricImage, LinkImage, admission/environment/supervision/guest refs, transcripts, run images, value images, dependencies, manifest, and certificate.
4. Image encoding uses deterministic section order, explicit versions, length-prefixed byte sections, section fingerprints, dependency refs, and no native pointers/tokens/handlers/credentials/ABI host data.
5. Receiver validates the image, plans thaw against local registry/catalog/environment/permit policy, verifies or relinks Linker provenance, preflights residual environment requirements, and issues a receiver permit if required.
6. RestoreTransaction stages handle remaps, mailbox remaps, Fabric invocation remaps, guest conformance checks, replay/verify setup, and all blockers before mutating the destination Runspace.
7. Commit restores supported completed/failed run images, timeline/provenance refs, and restore receipt references; parked slots, pending mailbox entries, and active parked Fabric invocations are inspected/replayed only and denied for mutating restore in v1.
8. Resume/replay/verify proceeds through existing Runspace, Fabric, Handoff, Admission, Supervision, Guest, Timeline, and Machine surfaces only.

## Tests/Acceptance
- Quiescence: completed, parked, and active parked Fabric states are quiescent; mid-step, mailbox mutation, route transaction, missing provider/route/parent witnesses, replay cursor mutation, and receipt write are blockers.
- Manifest/Image: fingerprints stable; target, assembly, link certificate, run images, transcripts, Fabric refs, guest refs, pending counts, run counts, active invocation counts, and dependencies are bound; pointers/tokens/handlers/credentials are excluded; encode/decode roundtrip rejects malformed and oversized images.
- RunspaceImage/RunSlotImage/MailboxImage: captures slots, pending ports, event logs, response validation metadata, parked/completed provider/root runs, remaps, and stale/duplicate response rejection while excluding machine/allocator/runtime/thread/request-token state.
- FabricImage: captures active invocations and completed receipts, validates provider identity, route witness, value mapping, supervision evidence, parent response mapping, and mailbox ownership; rejects missing witnesses.
- LinkImage/Relink: captures LinkPlan, LinkCertificate, Assembly, residual ImportSet, providers, guest providers, and environment requirements; identical local relink passes; provider/residual/Fabric/assembly drift rejects by default.
- Freeze/Thaw: freezes completed linked assemblies, parked runs, and active parked Fabric; rejects unsafe active Fabric and non-quiescent runspace; inspect-only, replay-only, completed, failed, verify, and relink restore modes behave according to policy; parked and active-Fabric mutating restore deny before Runspace mutation until an executable continuation witness exists.
- Guest/Handoff/Admission/Supervision: guest conformance reports verify and optional NativeGuest rerun passes; capsules export through Handoff; capsule admission modes report capsule/thaw/restore fingerprints; receiver-issued permits are required/enforced when policy says so and sender permits remain evidence only.
- Agent/examples: linked completed restore, active Fabric fail-closed thaw, agent transfer denial, relink mismatch, guest verify, and supervised restore denial examples run with stable output.
- Regression: existing Linker, Fabric, Guest, Runspace, Admission, Supervision, Handoff, Timeline, Machine, wasm, lint, format, and check steps remain green.

## Rollback/Abort Criteria
- Abort or split if restore requires serializing handlers, credentials, request tokens, allocator/runtime/thread state, file/network handles, native stack state, or ABI-specific host data.
- Abort if freeze/thaw needs service discovery, package lookup, storage, transport, xitdb, scheduler, async runtime, provider lifecycle manager, real integrations, Boundary LoadedModule execution, TreatyResolver/ProviderHarness hot path, or cryptographic claims.
- Abort mutating active Fabric restore unless the capsule can prove parent pending witness, provider witness, route witness, value mapping witness, supervision evidence, parent response mapping, mailbox ownership, and an executable continuation witness before mutation.
- Abort if receiver permit denial or environment mismatch can mutate Runspace before rejection.
- Abort if Linker/Fabric/Runspace become duplicate owners of capsule image semantics instead of witnesses consumed by `world.Capsule`.

## Implementation Brief
1. step=capsule-core-image-model; owner=implementation; success_criteria=Capsule namespace, version constants, enums, block/warning types, manifest, image, certificate, dependency/object helpers, deterministic fingerprints, encode/decode skeleton, and forbidden-field tests compile and pass.
2. step=quiescence-runspace-mailbox-images; owner=implementation; success_criteria=QuiescenceReport, RunspaceImage, RunSlotImage, MailboxImage, slot status derivation, pending/consumed port summaries, event refs, and quiescence blocker tests pass.
3. step=fabric-link-images; owner=implementation; success_criteria=FabricImage and LinkImage capture active/completed Fabric causality and Linker/Assembly provenance, validate witnesses, bind residual imports/providers/guest/env requirements, and focused fabric/link image tests pass.
4. step=freeze-certificate; owner=implementation; success_criteria=freezeRunspace/freezeAssembly/freezeRun collect refs, enforce options/limits, reject non-quiescent or unsafe active Fabric, produce stable image/certificate, and focused freeze tests pass.
5. step=thaw-relink-transaction; owner=implementation; success_criteria=validate/planThaw/thawIntoRunspace/verifyLink/relink support inspect/replay/completed/failed/verify/relink restore modes, fail-closed parked and active-Fabric mutating restore, local target/module matching, environment preflight, receiver permit issuance, run-handle remaps for accepted terminal restores, deny-before-mutation, and focused thaw/relink/restore tests pass.
6. step=handoff-admission-supervision-guest-integrations; owner=implementation; success_criteria=Handoff capsule APIs, Admission capsule package/modes/report refs, receiver-issued permit receipts, guest conformance verification/rerun option, replay-only/verify behavior, and focused integration tests pass.
7. step=examples-docs-build; owner=implementation; success_criteria=six capsule examples, build run steps, README update, `docs/capsules.md`, and check-step wiring compile and demonstrate linked completed restore, active Fabric fail-closed thaw, agent transfer denial, relink mismatch, guest verify, and supervised restore denial.
8. step=fixed-point-review; owner=verification; success_criteria=no duplicate truth owner, no unretired additive scaffold, no unresolved adversarial/ablation veto, no non-goal leak, no unsafe restore path, and one-change challenge produces no further required code change.
9. step=proof-closeout-ship; owner=verification; success_criteria=all requested format, diff, build, check, wasm, capsule examples, existing example matrix, focused filters, full tests, and lint commands pass; `$st` projection is clean; `$ship` opens or updates a PR with proof.

## Proof Commands
- `zig version`
- `zig fmt --check build.zig src examples test`
- `git diff --check`
- `zig build --summary all`
- `zig build check --summary all`
- `zig build world-wasm`
- `zig build check-world-wasm`
- `zig build run-world-capsule-linked-restore`
- `zig build run-world-capsule-active-fabric`
- `zig build run-world-capsule-agent-transfer`
- `zig build run-world-capsule-relink-mismatch`
- `zig build run-world-capsule-guest-verify`
- `zig build run-world-capsule-supervised-restore`
- existing Linker/Fabric/Guest/Runspace/Admission/Supervision/Handoff/Timeline/Machine example matrix
- `zig build test --summary none -- --test-filter "capsule"`
- `zig build test --summary none -- --test-filter "quiescence"`
- `zig build test --summary none -- --test-filter "capsule manifest"`
- `zig build test --summary none -- --test-filter "runspace image"`
- `zig build test --summary none -- --test-filter "run slot image"`
- `zig build test --summary none -- --test-filter "mailbox image"`
- `zig build test --summary none -- --test-filter "fabric image"`
- `zig build test --summary none -- --test-filter "link image"`
- `zig build test --summary none -- --test-filter "freeze"`
- `zig build test --summary none -- --test-filter "thaw"`
- `zig build test --summary none -- --test-filter "relink"`
- `zig build test --summary none -- --test-filter "active fabric restore"`
- `zig build test --summary none -- --test-filter "capsule handoff"`
- `zig build test --summary none -- --test-filter "capsule agent"`
- `zig build lint -- --max-warnings 0`

Iteration: 7
</proposed_plan>
