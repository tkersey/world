World is a Zig comptime system linker for Boundary Programs.

```text
Boundary Programs -> world.system -> BPI1 -> fixed Boundary Process kernel
```

`world.system` composes typed Boundary Program components, internal handlers,
effect morphisms, and intentionally residual effects into one ordinary Boundary
Program. `System.Program.image()` is canonical BPI1; no World graph, manifest,
Frame, scheduler, or application-specific WebAssembly remains at runtime.

```zig
const world = @import("world");

pub const System = world.system(.{
    .name = "example",
    .root = RootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = RootProgram,
        .site = LocalPolicy,
        .provider = PolicyProgram,
    })},
    .morphisms = .{},
    .external = .{world.systemExternal(.{
        .consumer = RootProgram,
        .site = Lookup,
    })},
});
```

A bare Site type remains accepted when it identifies exactly one reachable
component-site occurrence. Use `world.systemExternal` when the same Site type
occurs in more than one component or ordinal.

The existing `world.application` path remains available as an optional
specialization and compatibility surface:

```text
Boundary Machine -> world.application -> application.world.wasm -> world-host
```

Wire records are under `world.protocol.v1`; the WASM constructor is
`world.ApplicationAbiV1`. Start with [System Linker v1](docs/system.md),
[Application](docs/application.md),
[zero to application](docs/zero_to_world_application.md), and the normative
[Application ABI v1](docs/application_abi_v1.md).
