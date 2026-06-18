# World Assembly Capsules

RunImage moves one run. Assembly Capsule moves a linked execution fabric.

## What is an Assembly Capsule?

An Assembly Capsule is World's deterministic portable image for a quiescent linked Runspace assembly. It collects root and provider run metadata, pending mailbox entries, active Fabric causality, transcripts, run images, permits, receipts, admissions, Linker witnesses, guest conformance refs, dependencies, and restore metadata into one object.

The capsule certificate is deterministic witness metadata. It is not a cryptographic signature.

## Capsule vs RunImage

`RunImage` describes one run. `Capsule.Image` describes the linked assembly around one or more runs, including run slots, mailbox state, Linker provenance, Fabric refs, environment/admission/supervision refs, guest refs, dependency refs, and object refs.

## Capsule vs TransferPackage

`TransferPackage` is an admission and handoff package for target/module/run facts. It does not own the whole linked causal fabric. `Capsule.Image` is the executable assembly image above Runspace, Linker, and Fabric.

## Capsule vs Continuity Store

Capsules are store-ready, not a store. Deterministic encoding, dependency refs, object refs, and bundle-root helpers prepare Continuity Store without implementing storage, a database, transport, signing, or encryption.

## Quiescence

Capsules freeze only at safe boundaries: completed, failed, interrupted, or parked runs; active Fabric whose parent/provider runs are parked or terminal; no mid-step run; no half-applied mailbox, replay, receipt, or Fabric response transaction; and active routes with invocation, provider, and parent-pending witnesses.

## Capsule.Manifest

`Capsule.Manifest` binds kind, root TargetRef, optional ModuleRef, LinkPlan, LinkCertificate, Assembly, admission/environment/permit/receipt/run/transcript/Fabric/guest fingerprints, pending-port count, run-slot count, active Fabric invocation count, normal form, and metadata.

## RunspaceImage

`RunspaceImage` captures quiescent Runspace metadata: handle mappings, run slots, mailbox image, event refs, root/provider handles, branch/checkpoint refs, transcript/run/receipt refs, admission/permit refs, active Fabric refs, and metadata.

It never serializes Machine pointers, allocators, handlers, request tokens, native stacks, thread identity, file handles, network handles, or credentials.

## RunSlotImage

`RunSlotImage` records each root, provider, replay, verify, guest, branch, or exported slot. Runnable or running non-parked slots are blocked in v1.

## MailboxImage

`MailboxImage` records pending port entries, consumed summaries, single-use status fingerprints, response-routing status fingerprints, and next mailbox generation state. Pending entries carry portable `Frame.Request` images so thaw can rehydrate mailbox entries under fresh receiver mailbox IDs while recording old-to-new mappings.

## FabricImage

`FabricImage` records active invocation fingerprints, completed receipt fingerprints, parent pending refs, provider run refs, provider state summaries, route fingerprints, value mapping fingerprints, route depth, replay cursor refs, and status summary. Active Fabric is fail-closed unless provider identity, route witness, value mapping, supervision evidence, parent response mapping, and mailbox ownership are explicit.

## LinkImage

`LinkImage` captures LinkPlan, LinkCertificate, Assembly, Linker policy, optional catalog fingerprint, route synthesis refs, residual import set, provider targets, guest providers, and external environment requirements. The receiver may accept the included witness or relink locally and compare.

## Freeze

`Capsule.freezeRunspace`, `Capsule.freezeAssembly`, and `Capsule.freezeRun` compute quiescence, enforce policy and limits, collect runspace/fabric/link/admission/supervision/timeline refs, validate dependencies, encode the image, and produce a certificate witness.

## Thaw

`Capsule.validate`, `Capsule.planThaw`, and `Capsule.thawIntoRunspace` validate image format, match the local root target-ref witness and optional local catalog fingerprint, preflight environment refs, require a receiver permit fingerprint when configured, plan handle/mailbox remaps, reject blockers before mutation, and restore supported completed/failed slot metadata into the destination Runspace. Receivers configured with `require_supervision` reject capsule restore until a receiver-local permit object verifier exists; the current API records permit fingerprints as restore evidence only.

## Relink verification

`Capsule.verifyLink` and `Capsule.relink` compare local catalog/link evidence against capsule LinkImage data. Default policy rejects drift through blockers such as `link_certificate_missing`, `local_provider_missing`, `link_plan_mismatch`, `assembly_mismatch`, `residual_import_mismatch`, `fabric_plan_mismatch`, `guest_conformance_missing`, and `relink_drift_rejected`.

## Active Fabric / parked restore

Active Fabric and parked capsules are fail-closed for mutating restore in this API surface. They can be frozen and inspected, but `restore_parked` and parked relink restore reject before destination mutation until capsules carry an executable continuation witness. Active Fabric proofs still report blockers such as `active_fabric_unsupported`, `non_quiescent_fabric`, `fabric_witness_missing`, `provider_state_unsupported`, or `mailbox_ownership_mismatch`.

## Replay/verify restore

Replay-only thaw restores enough capsule metadata and transcript refs to inspect or replay without native handlers. Verify-and-restore is fail-closed in this API surface: until a receiver-local verifier supplies fresh handler replay and transcript comparison evidence, thaw returns `verification_witness_missing` before mutating the destination Runspace.

## Guest conformance restore

Guest conformance report fingerprints can be embedded in the manifest and surfaced in thaw/restore reports. NativeGuest rerun is optional and does not require a wasm runtime by default.

## Supervision and receiver permits

Sender permits and receipts are evidence, not authority. A receiver can require a fresh local permit fingerprint, deny before mutation, and bind that receiver permit fingerprint into restored state and reports. Object-level receiver permit validation is a future verifier boundary, so supervised and parked restores remain fail-closed in this API surface.

## Handoff integration

`Handoff.exportCapsule` encodes local capsule bytes. `Handoff.fromCapsule` decodes them. `Handoff.acceptCapsule` thaws into a receiver Runspace. Admission can bind capsule image, certificate, thaw plan, and restore report fingerprints.

## Agent transfer example

`examples/world_capsule_agent_transfer.zig` links an agent root to a tool provider while leaving the model port residual. It freezes the parked assembly, attempts receiver thaw, and prints capsule, residual import, permit, restore-denial, and final-output witnesses.

## Non-goals

Capsules do not implement a storage backend, production database, network transport, distributed protocol, scheduler thread, async runtime, real model/tool/file/human integration, provider lifecycle manager, service discovery, WASM host package, Boundary LoadedModule execution, Boundary closure/normalization, TreatyResolver hot path, ProviderHarness hot path, package manager, artifact registry, signing, encryption, cryptographic security, or an agent framework.
