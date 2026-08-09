World is a Zig comptime application compiler for Boundary Machines.

```text
Boundary Machine -> world.application -> application.world.wasm -> world-host -> Effect v1 capabilities
```

World closes one comptime-known Boundary Machine graph into one import-free,
bounded-memory WebAssembly application. The generated artifact carries its
canonical manifest and Application ABI v1 exports; a Frame remains the complete
portable semantic state between calls.

```zig
const world = @import("world");

pub const Application = world.application(.{
    .name = "example",
    .version = "1.0.0",
    .root = RootMachine,
    .handlers = .{world.handle(RootMachine, 0, "example.local.v1", ProviderMachine)},
    .external = .{world.external(ProviderMachine, 0, .{
        .site_identity = "example.lookup.v1",
        .interface = "example.lookup.v1",
        .authority = world.Authority.network,
    })},
});
```

Package it from a dependent build with `world.addApplicationWasm`. The helper
targets `wasm32-freestanding`, supplies only the public `world` and `boundary`
modules, emits the canonical manifest, rejects imports and incompatible memory,
and installs `<name>.world.wasm`.

Wire records are under `world.protocol.v1`; the WASM constructor is
`world.ApplicationAbiV1`. Start with [Application](docs/application.md),
[zero to application](docs/zero_to_world_application.md), and the normative
[Application ABI v1](docs/application_abi_v1.md).
