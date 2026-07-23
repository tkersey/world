# World Effect Protocol v1

Status: normative.

External authority crosses the application boundary only as `EffectRequest` and `EffectResult` data. Applications never import capability callbacks.

## EffectRequest

An EffectRequest binds:

- application and prior Frame identity;
- child sequence and ordinal `0`;
- Boundary effect-site identity;
- effect interface identity;
- payload and result schema identities;
- allowed statuses;
- semantic payload bytes;
- authority requirement bits;
- deterministic result and attempt limits.

The request identity is SHA-256 over the domain `world.effect-request.v1`, a zero byte separator, and canonical request bytes with both `request_id` and `idempotency_key` zeroed.

The idempotency key is independently derived from request identity, interface identity, and application identity under the domain `world.idempotency-key.v1`. It is a stable correlation key, not an exactly-once guarantee.

## EffectResult

An EffectResult binds request identity, status, result schema, optional result bytes, bounded semantic host claims, and a positive attempt number. Status is one of:

```text
ok
rejected
failed
deferred
cancelled
```

`ok` requires result bytes. `deferred` carries no result bytes. The result identity is SHA-256 over the domain `world.effect-result.v1`, a zero byte separator, and canonical result bytes with `result_id` zeroed.

Before reduction, the application validates pending membership, request identity, allowed status, schema identity, byte limits, and single-use behavior. A capability-authored result is untrusted until this validation succeeds.

## Authority split

The manifest and request declare requirements; they grant no authority. The manifest's required capability mask is the exact union of its residual effects' authority requirements. world-host applies receiver-local policy, approval, target validation, idempotency policy, and secret preflight before execution. Capabilities return outcomes only. They cannot author Frames, manifests, state, receipts, branch heads, or Boundary machines.

## Encoding

All integers are fixed-width little-endian. Lengths and counts are `u32`. Booleans are exactly `0` or `1`. Digests are 32 bytes. Enums reject unknown tags. Decoders check lengths before allocation, reject trailing bytes, enforce configured limits, and validate identities after decoding.
