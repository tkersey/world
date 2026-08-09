# World SDK v3.0.0

This SDK contains the exact Boundary v1.0.0, World v3.0.0, world-host
v1.0.0, and world-capabilities v2.0.2 release artifacts needed to author and
run a World application.

Verify every owner artifact before use:

```sh
node conformance/check-sdk.mjs
node conformance/external-consumer/run.mjs --zig zig
```

The external-consumer proof builds from the bundled archives with isolated
Zig caches, copies only runtime artifacts into a second directory, removes Zig
from runtime `PATH`, and proves fresh-instance resume, deterministic retry,
replay, branching, and receiver-preflight migration.

The runtime remains split by authority: application state is authored by the
application WASM, persistence and lifecycle are owned by world-host, and
external results are authored by Effect v1 capability packs.
