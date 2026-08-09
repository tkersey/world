# Application WASM

`world.addApplicationWasm` builds a `wasm32-freestanding` executable with no
imports, bounded initial and maximum memory, and the exports defined by
Application ABI v1. It also emits the canonical binary manifest and can install
a human-readable projection.

`world.ApplicationAbiV1(App, options)` is the low-level constructor used by the
generated entrypoint. Application authors normally use the build helper.
