# World application template

This template contains one public `world.application` declaration. It imports
only the released `world` package and its public `boundary` dependency; it has
no sibling-checkout or internal-source dependency.

Run `zig build --summary all`. The public build helper installs
`zig-out/world-apps/research-digest-agent.world.wasm` and its canonical
manifest after import, export, identity, and memory checks.
