# Saturating addition after kernel freeze

This independent package defines `arithmetic/saturating-add`, an internal
operation from two `u64` values to `u64`. Its deep handler checks the remaining
headroom before adding and returns the maximum integer on overflow. The program
adds twice with an authored yield between the operations, retaining both results.

The package was authored after the kernel freeze recorded in `../freeze.json`.
It uses Boundary's public staged builder, compiler, and image APIs. The compiled
program runs under the previously frozen World kernel.

Place the matching Boundary source in a sibling directory named `boundary`, then
run `zig build emit > saturating-add.bpi2`. Use `-Dsource=true` to emit source terms.
Initial arguments contain three unsigned 64-bit little-endian integers. The
first operation adds the first two; the second adds the third to that result.
The result contains both unsigned 64-bit integers. No external response is needed.
