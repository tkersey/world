# Comptime closure

World resolves handler ownership at comptime. Starting at the root Boundary
Machine, it follows every `world.handle` edge, rejects cycles and incompatible
providers, and requires every remaining operation site to be declared once by
`world.external`.

The closed handler graph is compiled into the application WASM. Only the
residual effect row crosses the host boundary.
