# Bitmask transformation after kernel freeze

This independent package defines `bitmask/toggle`, an internal operation from
an `(u64, u64)` pair to `u64`. Its deep handler applies bitwise XOR and resumes
with the transformed value. The program applies one mask, yields, then applies
a second mask to the first result. It returns both intermediate and final values.

The package was authored after the kernel freeze recorded in `../freeze.json`.
It uses Boundary's public staged builder, compiler, and image APIs. The compiled
program runs under the previously frozen World kernel.

Place the matching Boundary source in a sibling directory named `boundary`, then
run `zig build emit > bitmask.bpi2`. Use `-Dsource=true` to emit source terms.
Initial arguments contain three unsigned 64-bit little-endian integers: the
initial value and two masks. The result contains two unsigned 64-bit integers.
No external effect response is required.
