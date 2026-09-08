# Prefix maximum after kernel freeze

This independent package was authored after the optimized World kernel was frozen. It defines an internal running-maximum operation and a shallow handler that updates explicit handler state with `resume_with`. Four inputs produce their four prefix maxima, with one yield after the second operation.

The only dependency is the public Boundary compiler. World runs the resulting image without application-specific code. The verifier checks independent BigInt expectations, source semantics, exact native/JavaScript/Wasmtime records, and producer transfer.
