# Zero to a World application

Create a Zig package that depends on the exact World 3.1.2 release. Declare a
Boundary Machine, close its operation sites with `world.handle` and
`world.external`, and export the resulting `world.application` as
`Application`.

In `build.zig`:

```zig
const std = @import("std");
const world = @import("world");

pub fn build(b: *std.Build) void {
    _ = world.addApplicationWasm(b, .{
        .name = "application",
        .root_source_file = b.path("src/application.zig"),
    });
}
```

Run `zig build --summary all`. The checked result is
`zig-out/world-apps/application.world.wasm`. Install it in world-host and
provide only the Effect v1 capability packs named by its canonical manifest.
