# SDK

The World package is the application compiler SDK. A dependent Zig build calls
`world.addApplicationWasm` and imports application source through the public
`world` and `boundary` modules. No source checkout, internal module path, or
runtime code loader is part of the contract.

At runtime, world-host needs only the checked `.world.wasm` artifact and the
receiver-selected Effect v1 capability packs.

The published `world-sdk-v3.0.0` bundle contains exactly one authenticated
archive for Boundary v1.0.0, World v3.0.0, world-host v1.0.0, and
world-capabilities v2.0.2. Its verifier authenticates every owner archive
before extraction or execution. The bundled external-consumer proof builds
with isolated Zig caches and runs the complete Research Digest lifecycle after
removing Zig from runtime `PATH`.

```sh
node conformance/check-sdk.mjs
node conformance/external-consumer/run.mjs --zig zig
```
