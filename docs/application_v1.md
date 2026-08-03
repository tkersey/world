# World Application v1

Status: Application ABI v1, implemented by World 2.0.

`world.application` closes one graph of Boundary Machine ABI v2 programs at Zig
comptime. The returned type contains the residual effect row, application
manifest, composed portable state, and deterministic native step kernel used by
the application WASM wrapper.

```zig
const App = world.application(.{
    .name = "example",
    .version = "1.0.0",
    .root = RootMachine,
    .handlers = .{
        world.v1.handle(
            RootMachine,
            0,
            "example.lookup.v1",
            ProviderMachine,
        ),
    },
    .external = .{
        world.v1.external(ProviderMachine, 0, .{
            .site_identity = "host.example.request.v1",
            .interface = "host.example.v1",
            .authority = .file_read,
        }),
    },
});
```

The top-level `world.application` alias is the stable construction entry point. Binding constructors remain under `world.v1` while v0 declarations still occupy the primary namespace.

World `v2.0.0-rc.1` embeds its World 2 release identity and Boundary Machine ABI v2
dependency in each application manifest. This source-incompatible compiler
cutover intentionally changes manifest, Machine state, and application WASM
bytes. Application ABI v1, Frame v1, and Effect protocol v1 remain unchanged.

## External build API

A consumer imports World’s `build.zig` and calls the supported packaging
helper:

```zig
const std = @import("std");
const world = @import("world");

pub fn build(b: *std.Build) void {
    _ = world.addApplicationWasm(b, .{
        .name = "lookup-agent",
        .root_source_file = b.path("src/application.zig"),
        .application_decl = "Application",
        .memory = .{
            .initial_pages = 512,
            .maximum_pages = 512,
        },
        .install_human_readable_manifest = true,
    });
}
```

The application declaration remains the source of semantics. The helper owns
only packaging: exact Boundary/World module wiring, the freestanding target,
Application ABI exports, bounded reusable regions, canonical manifest
emission, artifact inspection, and installation under `zig-out/world-apps/`.
It rejects a missing or non-type application declaration at compile time and
rejects an import-bearing, unbounded, incomplete, or manifest-divergent WASM
before its install steps become reachable.

The official
[`application-v1` template](../templates/application-v1/README.md) uses only
this public surface. `scripts/init_world_application.mjs` copies it into an
empty directory and binds the exact reviewed World archive URL and package
hash supplied by the release workflow.

## Compile-time closure

Construction rejects:

- an unhandled operation site;
- multiple bindings for one site;
- an unreachable binding;
- a provider whose argument or result type does not match its parent site;
- an external response mode unsupported by its site;
- a static provider cycle or provider-depth overflow;
- a Boundary state or frame bound larger than the World application limit.

An internal provider's `InitialArgs` must exactly equal the handled site's
`Payload`, and its `Result` must exactly equal that site's `Resume` type.
Bindings name the owning Machine, the site ordinal within that Machine, and the
expected source-authored site identity, so source reordering cannot silently
retarget a binding.

Boundary-local `after` continuations are compiled into the Machine. A Machine
admitted by World exposes `EffectRow.after_site_count == 0`.

## Runtime state

The generated state is a bounded tagged stack. Each entry contains a dense
Machine id, its exact parent binding id, and canonical Boundary RNF Machine state
bytes. The runtime performs no Boundary module decoding, image loading, provider
discovery, label dispatch, or registry lookup.

An internal provider may park on an external effect. The encoded stack then retains both provider and parent continuations. Supplying the matching `EffectResult` resumes the provider, maps its typed result into the exact parent request, and continues reduction.

`App.decodeFrame`, `App.initialFrame`, and `App.step` receive a caller-owned
`std.heap.ArenaAllocator`. Their returned Frames borrow all variable-length
storage from that arena and remain valid for its lifetime. Frame copies carry
no cleanup authority. The application WASM wrapper creates one arena over its
bounded scratch region for each call, encodes and copies the output Frame, and
then discards the arena.

## Determinism

For fixed application, parent Frame, semantic EffectResult, and fuel, `App.step`
emits byte-identical child Frame bytes. Sequence and resource-counter arithmetic
is checked. Boundary's fixed-width portable value schemas keep native and wasm32
application identities equal.

## Current v1 restriction

One Frame carries at most one pending external effect. The generated closer therefore rejects a configured `maximum_effects_per_frame` other than `1`. Parallel residual effects require a later protocol version.

## Reference applications

```text
zig build world-skeleton-agent-wasm
zig build world-fixture-agent-wasm
```

These steps install `*.world.wasm` and canonical binary manifests under `zig-out/world-apps/`. Both artifacts have zero imports, fixed linear-memory maxima, native/wasm-identical manifests, and fresh-instance continuation. The fixture application also proves a provider parked on `file.read`, byte-identical retry, and two distinct children from one parent.

`zig build check-world-comptime-v0-v1-oracle` runs the frozen v0 agent corpus beside the six required v1 scenarios. v0 and v1 bytes are intentionally not compared; both paths are bound to the same exact effect sequence and terminal outcomes.

Independently deployed children remain external through `agent.invoke.v1`; see
[`dynamic_subagents.md`](dynamic_subagents.md). Existing v0 runs follow the
restart and compatibility policy in [`v0_v1_cutover.md`](v0_v1_cutover.md).
