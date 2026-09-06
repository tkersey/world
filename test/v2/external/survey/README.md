# Survey coordinate consumer

This standalone authoring package was created after the kernel freeze recorded
in `../freeze.json`. It declares `survey/translate-point` and its own handler
through Boundary's public builder. No World source or API participates in
compilation. Put the selected Boundary source in a sibling directory named
`boundary`, then run `zig build emit > survey.bpi2`.

InitialArgs is a point: two signed little-endian i64 coordinates. The authored
handler adds `(10,-3)` twice, yielding between the two operations. For `(4,9)`,
the final point is `(24,3)`. Overflow is an authored failure. The operation and
handler have no entry in the kernel; both are serialized program data.
