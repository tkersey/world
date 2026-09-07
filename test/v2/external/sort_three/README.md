# Sorting three integers after kernel freeze

This package was first initialized with Zig 0.16.0 and authored on
2026-09-07 after 23:47 UTC, after the freeze at
2026-09-07T23:45:51.749Z in `../freeze.json`. The frozen kernel is 392401 bytes,
with SHA-256 `bb401ca875cb731eb9689afdb1271369bba1cc4493aabb8b43012e006e9c17e8`.
This operation, handler, and composition are new to this freeze; the earlier
`saturating_add` package remains as a historical consumer.

The new `ordering/compare-pair-descending` operation accepts two `u64` values and
returns `(maximum, minimum)`. Its deep handler uses an unsigned comparison and
resumes with the ordered pair. The application sorts three integers in descending
order with three comparisons: first compare the first two inputs, then compare
their minimum with the third input, and finally compare the first maximum with
the second maximum. An explicit yield between the second and third comparisons
retains both earlier pairs. The final result is the third ordered pair followed
by the second minimum. There is no external request or response.

Only Boundary's public staged builder, compiler, and image APIs are imported.
The package contains no copied catalog, internal IR, compiler, or runtime code.
The runner builds it in a fresh scratch directory against Boundary 2.0.0,
compares independent BigInt sorting expectations with the source oracle, and
checks exact native, JavaScript, and Wasmtime bytes at each advance and run
boundary. Cases include zero, ascending and descending inputs, duplicate values,
the high bit, and the maximum unsigned 64-bit value. Kernel identity is checked
before and after execution.

Place the matching Boundary source in a sibling directory named `boundary`, then
run `zig build emit > sort-three.bpi2`. Add `-Dsource=true` to emit source terms.
Initial arguments and the final result each contain three unsigned 64-bit
little-endian integers.
