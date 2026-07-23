# v0 to v1 Cutover

This page states the compatibility decision for World Comptime v1. The
normative release gates and repository order are in
[`cutover_v1.md`](cutover_v1.md).

There is no v0 continuation-state migration. A TurnClosure, Capsule, loaded
Boundary frame stack, or universal-runtime worker state is not translated into
a v1 Frame. Existing v0 runs either finish on the feature-frozen v0 runtime or
restart a v1 application from application-level input.

During the compatibility interval:

- Carrier v0 runs `world_universal.wasm` with Executable.Image and TurnClosure;
- Application Host v1 runs application-specific `*.world.wasm` with Frame;
- the profiles use disjoint record kinds, stores, branch heads, commands, and
  release artifacts;
- correctness and compatibility fixes may land on v0, but new runtime features
  target v1;
- selected v0 fixtures remain behavioral oracles, not v1 deployment inputs.

The source-free Agent Runtime v1 development pack proves deployment closure but
does not grant release authority. Production cutover requires reviewed and
pinned Boundary, World, world-host, and world-capabilities releases, the full
cutover gate, and an explicit decision to make v1 the default.

After the bounded compatibility interval, retirement removes v0 from default
commands and stops generating new v0 packs. The universal runtime may remain
behind an explicit legacy or measured dynamic-loading profile. Historical tags,
documentation, and selected oracle fixtures remain available for old-run
inspection and semantic comparison.
