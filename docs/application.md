# Application

`world.application` compiles a comptime-known root Boundary Machine, internal
handlers, and residual external effects into one application type. Construction
derives the handler closure, residual effect row, manifest, limits, and stable
application identity. Package identity is fixed by World and is not an author
input.

Use `world.handle` for a statically compiled provider and `world.external` for
an Effect v1 boundary. Every operation site must have exactly one owner.
