# World Appliance

A World Appliance is a closed, reconstructible execution fabric. It advances deterministically to the next host boundary, emits everything the host must do, and carries everything needed to resume elsewhere.

## What is a World Appliance?

An Appliance packages a closed World target assembly behind one canonical host-turn protocol. A host submits an `Appliance.Command` byte image and receives an `Appliance.TurnOutput` byte image. The output binds the new checkpoint, host-bound work, turn receipt, and optional Archive append evidence fingerprint plus canonical ref.

## Why Appliance now?

World already has Guest, Runspace, Fabric, Linker, Capsule, Actuation, Continuity, Chronicle, and Archive kernels. Without Appliance, every host has to orchestrate those kernels itself. Appliance is the vertical integration layer that composes the existing owners at quiescent host boundaries.

## Closed-world definition

`world.Appliance.Define(RootTarget, config)` is comptime driven. It validates the root target, provider targets, residual imports, strict actuation bindings, profile, capacity, and derived memory plan before runtime. Runtime execution does not discover providers, synthesize routes, resolve by operation name, call TreatyResolver, or call ProviderHarness.

## Manifest

`Appliance.Manifest` is deterministic and immutable. It identifies the ABI version, root target, target certificate, residual import set, actuation descriptors and bindings, profile features, capacity, memory plan, supported modes, host capability flags, and metadata. It contains no function pointers, credentials, URLs, runtime identity, storage handles, or allocator identity.

## Profile

Profiles (`minimal`, `wasm_small`, `wasm_agent`, `native_debug`, `replay_only`, `full_evidence`) choose which Appliance features are instantiated: Fabric, Actuation, Capsules, Archive append planning, transcripts, guest reports, verification, checkpoint emission, archive-ack gating, manual fallback, diagnostics, and strict closed-world validation. A profile changes Manifest identity, but it is not host authority.

## Capacity and MemoryPlan

`Appliance.Capacity` bounds runs, pending ports, host requests, replies, internal ticks, event counts, evidence records, command bytes, output bytes, checkpoints, archive append bytes, errors, and metadata. `Appliance.MemoryPlan` is derived from capacity and profile and exposes bounded persistent, scratch, input, output, checkpoint, archive, and maximum linear-memory sizes.

## Quiescent turns

A turn begins from boot, restore, or resident continuation. It ends only at a quiescent boundary: local work has advanced as far as possible, internal Fabric work is not half-applied, external requests have prepared Actuation evidence, and Capsule/Chronicle/Archive evidence can be safely emitted.

## Command

`Appliance.Command` has `boot`, `restore`, `continue`, `inspect`, `cancel`, and `reset` forms. It binds the Manifest fingerprint, turn sequence, optional previous TurnReceipt, execution mode, optional receiver permit and evidence refs, boot-only root argument image, host replies, optional archive retention acknowledgment, and metadata. Core accepts only execution modes advertised by the Manifest, so profile changes alter both identity and command authority. Reset is a host-visible command that returns deterministic cancellation/reset output and then clears pending continuation anchors so the resident Core can boot fresh again. Malformed input must not mutate Core state.

## HostRequest

`Appliance.HostRequest` is the canonical external request shape. Strict appliances expose external ports as prepared Actuation requests, ordered by deterministic run/mailbox/request identity. Emitting a HostRequest performs no real host effect.

Fresh commands may emit HostRequests for required external ports. Replay, verify, and audit commands do not emit a fresh HostRequest when receiver evidence refs are supplied; Core treats those refs as replay evidence and advances locally. If such a command reaches an external port without replay evidence, it returns `blocked` instead of asking the host to perform a fresh effect.

## HostOutcome and HostReply

`Appliance.HostOutcome` records what the host claims happened: responded, rejected, failed, pending, deferred, or cancelled. Responded outcomes bind a response kind and optional canonical response bytes; every outcome may carry bounded host-evidence bytes as a local claim. Pending and deferred outcomes are nonterminal: Core records the applied reply evidence, keeps the same HostRequest outstanding, emits no finalized Actuation receipt for that turn, and returns to `needs_host`. It is not an Actuation receipt. `Appliance.HostReply` targets an outstanding HostRequest and carries the HostOutcome plus optional canonical `RetentionAck` evidence. Reply-level and command-level retention acknowledgments are equivalent evidence when they match, and conflicting acknowledgments reject the command before Core mutation. Replies may arrive in arbitrary order but are canonicalized before processing.

## Actuation preparation/finalization

Actuation owns the host-effect membrane. `Actuation.Membrane.prepareHost` validates intent, envelope, descriptor, binding, policy, and supervision evidence without calling the host. `Actuation.Membrane.finalizeHost` accepts a matching host outcome and constructs World-owned Commit, Response, Receipt, optional VerifyReport, and mailbox-ready response evidence.

## TurnOutput

`Appliance.TurnOutput` binds status, state fingerprints, quiescence report, ordered host requests, finalized Actuation receipt refs, optional root result, optional RunReceipt ref, checkpoint, TurnReceipt, optional Archive append batch fingerprint and canonical ref, blockers, warnings, and diagnostic metadata. Creating output performs no host effect.

## Checkpoint

`Appliance.Checkpoint` is the portable reconstruction unit. It carries Manifest identity, turn sequence, Capsule fingerprint, explicit Capsule image bytes or a canonical Capsule image ref, archive/chronicle anchors, the pending Archive append batch fingerprint awaiting host retention acknowledgment, previous TurnReceipt, outstanding request fingerprints, execution mode, and metadata. It contains no live Runspace pointers, allocator state, handler pointers, credentials, storage handles, or WASM engine identity.

## TurnReceipt

`Appliance.TurnReceipt` binds one host-visible state transition: Manifest, turn sequence, Command, applied replies, emitted requests, source/resulting Capsule fingerprints, Archive append fingerprint, result anchors, status, run receipt, blockers, and warnings. It is deterministic local evidence, not a signature.

## Resident fast path

The resident path may keep `Appliance.Core` and underlying execution state alive between turns. It must still submit canonical commands and read canonical outputs.

## Fresh-instance reconstruction

The portable path may discard the process or WASM instance after a completed turn. A fresh Core restores from the emitted checkpoint, accepts the same replies, and should produce the same next semantic output. `Appliance.ReconstructionReport` records that equivalence.

## Capsule integration

Appliance uses Capsule as the freeze/thaw owner. It does not introduce a competing snapshot format. Restoration verifies Manifest identity, target identity, assembly/link evidence, residual environment, actuation bindings, receiver permits, pending host requests, and archive anchors before mutating Runspace state.

## Archive integration

When Archive evidence is enabled, an advancing turn plans at most one `Archive.AppendBatch`. The batch commits Appliance checkpoint, receipt, output, Capsule, and Actuation evidence according to policy and binds the expected Chronicle parent cursor. The host owns byte retention and may return `Appliance.RetentionAck` on a later command or with a `HostReply`. Strict archive-ack profiles reject the next advancing command until the pending append batch is acknowledged. Non-strict profiles may continue, but the next TurnOutput, TurnReceipt, and QuiescenceReport carry a deterministic unacknowledged-archive warning.

## Supervision

Supervision remains the owner of permits, budgets, checks, usage ledgers, and receipts. Appliance-driven Fabric and Actuation work must be accounted through those owner APIs.

## Native ABI simulation

`Appliance.Native` exposes ABI-shaped operations over `Appliance.Core` for CI and deterministic conformance without requiring an external WASM runtime. It does not bypass canonical Command or TurnOutput encoding.

## Conformance

`Appliance.ConformanceVector` names one of the canonical vector kinds and binds the expected initial command, TurnOutput, HostReply sequence, status sequence, HostRequest sequence, Checkpoint sequence, final result, Archive append sequence, and resident/reconstructed equivalence claim. `Appliance.ConformanceReport` records the comparison evidence for direct native owner/API execution, `Appliance.Native`, resident Core, reconstructed Core, WASM manifest/export inspection, optional external runtime execution, replay output, and Archive replay projection evidence.

## WASM ABI

Appliance ABI v1 is a deployment ABI above Guest ABI v1. Required exports include ABI version, canonical Manifest byte length/read, command submission, output length/read, last-error length/read, and reset. Output-producing submit statuses include `needs_host`, `completed`, `failed`, `blocked`, `cancelled`, and `output_ready`; these leave canonical TurnOutput bytes readable. `Appliance.Native` mirrors those ABI-shaped operations directly over Core, including bounded last-error bytes for rejected commands. The canonical WASM artifact also exposes Capacity and MemoryPlan fingerprints plus required linear-memory bounds before command submission. The artifact requires no WASI, filesystem, network, clock, randomness, actuator imports, storage imports, or host allocator callbacks.

## Universal Appliance ABI v2

`world_universal_appliance.wasm` is a target-neutral ABI v2 conformance artifact for the generic World Seed host surface. It is not compiled for a particular Boundary Target. It accepts canonical `world.Executable.Image` v2 bytes, decodes and validates the embedded Boundary module closure, derives the Appliance manifest from the loaded image, and executes through the existing Appliance/Core, Runspace, Fabric, Actuation, Capsule, Continuity, Chronicle, and Archive owners.

- `world_appliance_abi_version`
- `world_appliance_runtime_manifest_len`
- `world_appliance_read_runtime_manifest`
- `world_appliance_load_executable`
- `world_appliance_unload_executable`
- `world_appliance_manifest_len`
- `world_appliance_read_manifest`
- `world_appliance_submit_command`
- `world_appliance_output_len`
- `world_appliance_read_output`
- `world_appliance_last_error_len`
- `world_appliance_read_last_error`
- `world_appliance_reset`
- bounded allocation helpers

The runtime manifest is readable before image load. The executable manifest is canonical `Appliance.Manifest` bytes and is readable only after successful load. Load is transactional, `reset` clears execution state while retaining the loaded image, `unload` clears image and execution state, and output remains readable until the next mutating call. The artifact has zero imports, no WASI, no host callbacks, and bounded linear memory.

`zig build check-world-universal-appliance-wasm` builds and inspects the artifact. `zig build check-world-universal-appliance-node` is the external runtime proof and is part of `zig build check-world-universal`: installed Node compiles the same WASM bytes once, instantiates with an empty import object, loads two unrelated canonical `Executable.Image` byte images into one instance, repeats the same images in a fresh instance, and checks exact canonical host-request, result, and Archive append bytes.

## Agent appliance walkthrough

The canonical agent appliance is modeled as an external model Actuation boundary plus an internal linked tool provider. The model request crosses the HostRequest/HostReply protocol; the tool provider is declared as static assembly-covered Fabric work in the Manifest, with provider target, LinkPlan, LinkCertificate, Assembly, residual import, and Fabric.Plan fingerprints available before boot. Every turn emits a checkpoint and Archive append plan.

## Host implementation contract

The host owns real effects, credentials, network clients, files, humans and approval systems, Archive byte retention, Checkpoint transport, WASM runtime choice, process lifecycle, and durability policy.

The host must not forge World receipts, resume arbitrary mailbox entries, bypass Actuation preparation, reinterpret ObjectRef or Archive identity, mutate checkpoints, or redefine request ordering.

The dependency-free ECMAScript reference host is split into `scripts/world_universal_appliance_codec.mjs`, `scripts/world_universal_appliance_host.mjs`, and `scripts/world_universal_appliance_conformance.mjs`. It compiles and instantiates the WASM, reads manifests and TurnOutput bytes, routes fixture effects by stable identity, asks the fixture generator for canonical response commands, and submits those commands back to the runtime. It does not execute ProgramPlan semantics, implement Runspace/Fabric/Actuation/Capsule/Chronicle/Archive, or validate Archive contents.

## Non-goals

World Appliance does not implement real model APIs, tool registries, filesystem effects, human workflow, network transport, storage adapters, WASI, WIT, runtime-required external WASM dependencies, scheduler threads, async runtime, service discovery, provider lifecycle, unsealed arbitrary loaded-module execution, operation-name dispatch, exactly-once host effects, signing, encryption, credential serialization, or hidden process state across completed turns.
