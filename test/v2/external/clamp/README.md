# Range clamping after kernel freeze

This independent package defines `range/clamp`, an internal operation from
three `u64` values to `u64`. Its deep handler orders the two range endpoints
and limits the value to that inclusive interval. The program clamps once,
yields, then clamps the first result to a second range. Both results are returned.

The package was authored after the kernel freeze recorded in `../freeze.json`.
It uses Boundary's public staged builder, compiler, and image APIs. The compiled
program runs under the previously frozen World kernel.

Place the matching Boundary source in a sibling directory named `boundary`, then
run `zig build emit > clamp.bpi2`. Use `-Dsource=true` to emit source terms.
Initial arguments contain five unsigned 64-bit little-endian integers: the
initial value and two pairs of endpoints. Reversed endpoints are accepted.
The result contains two unsigned 64-bit integers. No external response is needed.
