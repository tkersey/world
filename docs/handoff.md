# World Handoff

World Handoff packages execution state. Environment binds the receiving host. Boundary supplies the semantic target.

## What Is World Handoff?

World Handoff is a portable execution handoff layer above World Timeline and below future storage, transport, distributed runtime, WASM, or persistence backends. It packages target identity, timeline image, run state, import requirements, acceptance evidence, and replay/verify metadata.

## TargetRef

`TargetRef` identifies the Boundary target a run belongs to. It includes target, WorldSurface, replay scope, target certificate, residual plan, normal-form, table, profile, optional module, and metadata fingerprints. It is not the target itself and contains no handlers, host pointers, request tokens, credentials, allocator/runtime/thread ids, or ABI data.

## ImportSet

`ImportSet` summarizes the WorldPort imports a receiver may need to satisfy. Requirements describe semantic residual ports, payload and response value ids, residual sites, replay-key recipe fingerprints, names, required flags, tags, and metadata.

## RunState

`RunState` records whether a run is not started, running, parked on a port, completed, or failed. It binds the target ref fingerprint, optional transcript image fingerprint, branch id, checkpoint fingerprint, pending request fingerprint, final response/value image fingerprint, turn index, and status.

## RunImage

`RunImage` is the canonical portable handoff object. It contains `TargetRef`, `ImportSet` fingerprint, optional `TranscriptImage`, current `RunState`, checkpoints, branches, optional pending `Frame.Request`, optional final `ValueImage`, optional environment/acceptance/audit references, and metadata.

The image has deterministic section ordering, explicit format versions, length-prefixed bytes, section fingerprint validation, and size limits. It excludes port handlers, credentials, concrete ABI data, network/storage transport, function pointers, allocator/runtime/thread ids, and request tokens.

## Parked Handoff

For a run parked on a WorldPort request, the image includes the pending request frame and parked run state. A receiver decodes the handoff, preflights a local target and environment, validates the pending frame, answers the request through the local adapter surface, and continues synchronously. World does not add a scheduler.

## Replay Handoff

A completed or complete transcript-backed image can be accepted in replay mode. Replay validates target, surface, certificate, and transcript fingerprints and can run without calling native fresh handlers.

## Verify Handoff

Verify-on-receive binds local fresh handlers, replays expected frames, calls the handlers, compares response fingerprints and value images, and fails on divergence.

## Branch Handoff

Run images can carry checkpoint and branch metadata. Receivers can inspect branches, replay a selected branch image, or fork from checkpoint metadata. World does not add concurrency.

## Agent Handoff Example

`examples/world_agent_handoff.zig` packages an agent-shaped target with checkpoint metadata and replays it on a receiver without model/tool handler calls. The example remains a fixture over World ports, not an agent framework.

## Future Boundary Module Images

`RunImage` can reference a future Boundary module image through `TargetRef` without requiring module-image implementation in this PR. Generated targets are the supported local `TargetLike` form today.

## What Storage Transport Must Provide

Storage or transport layers only need to carry encoded `RunImage` bytes and any future referenced target/module bytes. They own persistence, addressing, transport security, delivery, retention, and lifecycle. World owns the portable execution image and host acceptance semantics.

## Non-Goals

World Handoff does not implement storage, xitdb, network transport, scheduler, async runtime, real model/tool/file/human integrations, provider lifecycle, service discovery, WASM ABI, linear memory layout, Boundary closure, Boundary normalization, TreatyResolver hot paths, ProviderHarness hot paths, persistence backends, signing/encryption, or an agent framework.
