# Effect protocol v1

Status: normative.

External authority crosses World only as `world.protocol.v1.EffectRequest` and
`EffectResult` data. A request binds application, parent Frame, operation site,
interface, payload/result schemas, statuses, authority requirements, limits,
and deterministic correlation identity.

A result binds the request, status, result schema, bounded bytes, claims, and a
positive attempt. Before reduction, the application validates pending
membership, identities, status, schemas, limits, and single-use behavior.
`validateResultForRequest` owns that wire-level check.

Capability packs return outcomes only. They cannot author Frames, manifests,
application state, or Boundary Machines.
