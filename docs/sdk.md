# SDK

The World package is the application compiler SDK. A dependent Zig build calls
`world.addApplicationWasm` and imports application source through the public
`world` and `boundary` modules. No source checkout, internal module path, or
runtime code loader is part of the contract.

At runtime, world-host needs only the checked `.world.wasm` artifact and the
receiver-selected Effect v1 capability packs.
