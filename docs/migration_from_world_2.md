# Migration from World 2

This migration is application-specific only. v0 consumers pin World 1 or World
2; there is no TurnClosure or Capsule migration, and World 3 has no Boundary
v0.7 dependency.

World 2 application authors update the dependency to World 3.1 and Boundary 1.4.0,
then replace `world.v1.application`, `world.v1.handle`, and
`world.v1.external` with the canonical top-level names. Wire records move to
`world.protocol.v1`, and the WASM constructor becomes
`world.ApplicationAbiV1`.

Application ABI v1 remains exact-host compatible: its exports, result codes,
canonical records, and bytes do not change. Production manifest identity does
change because World now fixes World 3.1.2 and Boundary 1.4.0 package identity;
authors cannot override it.

In-flight Frames stay with their old WASM. Continue or restart those runs with
the old artifact; do not present an old Frame to a newly identified World 3
application.
