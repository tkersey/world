# Signed ordering after kernel freeze

This independent package defines `ordering/precedes`, an internal operation from
an `(i64, i64)` pair to `Bool`. Its deep handler compares the signed values and
resumes with the result. The program compares two pairs, yields between them,
and returns the two Boolean results.

The package was authored after the kernel freeze recorded in `../freeze.json`.
It uses Boundary's public staged builder, compiler, and image APIs. The compiled
program runs under the previously frozen World kernel.

Place the matching Boundary source in a sibling directory named `boundary`, then
run `zig build emit > ordering.bpi2`. Use `-Dsource=true` to emit source terms.
Initial arguments contain four signed 64-bit little-endian integers; the result
contains two canonical Boolean bytes. No external effect response is required.
