# World Frame v1

Status: normative.

`Frame` is the sole portable application-state and causal-transition record in World Comptime v1. It replaces separate primary checkpoint, capsule, turn-closure, chronicle, archive-moment, and receipt authorities on the v1 path.

## Fields

```text
Frame {
  frame_id: sha256
  application_id: sha256
  parent_frame_id: optional sha256
  sequence: u64
  state_bytes: bytes
  pending_effect: optional EffectRequest
  accepted_effect_result_id: optional sha256
  status
  final_result_schema_id: optional sha256
  final_result_bytes: optional bytes
  failure: optional bytes
  deterministic resource counters
  semantic_warnings: u64 bit set
}
```

A Frame contains at most one pending effect. This is a semantic v1 restriction, not a host scheduling preference. Parallel external effects require an explicit later protocol version.

## Status invariants

- `needs_effect` has exactly one pending EffectRequest and no terminal result or failure.
- `completed` has a result schema and result bytes, and no pending effect or failure.
- `failed` has a deterministic failure and no pending effect or terminal result.
- `yielded_fuel` has resumable state and no pending effect or terminal outcome.
- `cancelled` has no pending effect or terminal result.

Genesis has sequence `0` and no parent. Every later Frame has a parent and a nonzero sequence. An emitted request uses the child Frame sequence and binds the prior Frame identity as `parent_frame_id`; genesis uses the all-zero parent identity for its first request.

## Identity

`frame_id` is SHA-256 over the domain `world.frame.v1`, a zero byte separator, and the complete canonical Frame bytes with `frame_id` set to zero. The nested request is included with its validated request and idempotency identities.

Diagnostics are not Frame fields. Transient host metadata therefore cannot change Frame identity.

## Lifecycle laws

Replay supplies a retained EffectResult and does not call the capability again. Retry from the same parent Frame with the same semantic EffectResult and fuel produces the same child Frame bytes. Branching retains one parent and stores distinct valid children. Migration transfers the application artifact, manifest, selected Frame, and required retained EffectResults; the receiver reapplies local policy.
