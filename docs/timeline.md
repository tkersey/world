# World Timeline Kernel

## What Is A World Timeline?

A World timeline is the deterministic, target-neutral execution record under `WorldMachine`. Boundary still owns algebra, normalization, world-surface construction, value tables, dispatch tables, source maps, trace maps, evidence maps, and certificates. World owns the concrete port ABI and records every residual `WorldPort` interaction as frames.

The timeline is frame-based, replayable, checkpointable, branchable, and independent of native Zig handler function pointers.

## Frame.Request

`world.Frame.Request` represents a residual port request. It binds the frame format version, frame fingerprint, WorldSurface fingerprint, optional replay-scope fingerprint, target certificate fingerprint, dense `world_port_id`, residual site index/fingerprint, request fingerprint, turn index, value-table ids, optional payload image, replay-key seed, optional summary refs, and flags.

It never stores request tokens, runtime pointers, allocator pointers, handler function pointers, thread ids, or host-owned pointer identities.

## Frame.Response

`world.Frame.Response` represents a port response. It binds the frame format version, frame fingerprint, WorldSurface fingerprint, target certificate fingerprint, dense `world_port_id`, request fingerprint, response kind, response fingerprint, optional response value image, replay key, status, optional error/reason bytes, and flags.

The synchronous `responded` path is executable. `rejected` and `failed` are represented and encoded. `pending` is structural only; it does not add a scheduler.

## ValueImage

`world.Frame.ValueImage` is a portable image for values World can safely encode: scalar values, byte slices, and simple product/sum values used by the current targets. Unsupported values fail closed through `UnsupportedValueImage`, `NativeOnlyValue`, or `MissingValueImage`.

`world.ValuePolicy.portable` requires replayable images. `native_compatible` preserves typed in-memory sidecars. `audit_only` reports blockers without making them replay authority.

## TimelineEvent

`world.Timeline.Event` records deterministic event metadata: kind, surface/certificate fingerprints, optional request/response frame fingerprints, replay key, checkpoint fingerprint, branch id, turn index, and status.

## TranscriptImage

`world.TranscriptImage` is a pointer-free image derived from `world.Transcript`. It stores event images, request/response frames, replay keys, final status, and counts. It does not store `StoredValue`, `*anyopaque`, allocator/runtime/thread pointers, request tokens, or handlers.

Replay from a transcript image consumes response frames and decodes `ValueImage` data. The machine must still be configured with compile-time port descriptors because the Boundary session resumes with typed site/response values, but replay does not call native handlers or require a handler context.

## Checkpoints

`world.Timeline.Checkpoint` records event index, turn index, optional current request/last response fingerprints, optional capsule image fingerprint, transcript prefix fingerprint, branch id, and status. This milestone records metadata only.

## Branches

`world.Timeline.Branch` records branch id, optional parent branch id, checkpoint fingerprint, label, start/final event indexes, final status, and summary counts. Branches do not imply concurrency or scheduling.

## Fresh, Replay, Verify, Audit

Fresh mode calls native handlers through the native adapter path and records frame-capable transcript data. Replay mode can consume an in-memory transcript or a transcript image. Verify mode calls fresh handlers and compares against transcript or image response authority. Audit mode returns counts and can be projected into `world.AuditImage`.

## NativeAdapter

`world.port` and `world.portWithOptions` keep the native Zig handler ABI ergonomic. Handler responses are cloned before resume and optional `response_deinit` remains honored.

## ReplayAdapter

Replay consumes a request frame seed, finds the expected response frame/event, validates surface, certificate, port id, request fingerprint, response kind, and replay key, then returns a decoded response through the port descriptor without calling handlers.

## VerifyAdapter

Verify combines fresh native behavior with replay authority. A mismatched response fingerprint or value image fails with precise verification errors.

## ByteAdapter

The byte adapter example encodes `Frame.Request` to canonical bytes, lets a fake host decode and dispatch by `world_port_id`, encodes `Frame.Response`, decodes it in World, and resumes the session. This proves byte-frame integration without defining WASM ABI.

## Agent Timeline Example

`zig build run-world-agent-timeline` records an agent-shaped fresh run and replays from `TranscriptImage` without model/tool handler calls.

## Future world-wasm

Future world-wasm can derive an ABI from frames and the WorldSurface. This milestone does not define WASM ABI or linear memory.

## Future Storage Backend

Future storage backends can persist transcript images and timeline metadata. This milestone does not add a storage engine.

## Non-Goals

No WASM ABI, linear-memory layout, storage backend, network transport, scheduler, async runtime, provider lifecycle, service discovery, real model/tool/file/human integrations, security/signing/encryption, Boundary closure, Boundary normalization, TreatyResolver hot path, ProviderHarness hot path, provider catalog lookup, morphism catalog lookup, closure graph traversal, evidence graph traversal, or agent framework.
