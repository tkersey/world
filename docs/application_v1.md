# World Application v1

Status: implementation draft.

`world.application` closes one Boundary `StaticMachine` graph at Zig comptime. The returned type contains the residual effect row, application manifest, composed portable state, and deterministic native step kernel used by the application WASM wrapper.

```zig
const App = world.application(.{
    .name = "example",
    .version = "1.0.0",
    .root = RootMachine,
    .handlers = .{
        world.v1.handle(RootSite, ProviderMachine),
    },
    .external = .{
        world.v1.external(ProviderSite, .{
            .interface = "host.example.v1",
            .authority = .file_read,
        }),
    },
});
```

The top-level `world.application` alias is the stable construction entry point. Binding constructors remain under `world.v1` while v0 declarations still occupy the primary namespace.

## Compile-time closure

Construction rejects:

- an unhandled operation site;
- multiple bindings for one site;
- an unreachable binding;
- a provider whose argument or result type does not match its parent site;
- an external response mode unsupported by its site;
- a static provider cycle or provider-depth overflow;
- a Boundary state or frame bound larger than the World application limit.

Boundary-local `after` continuations must currently be closed before World application closure. This restriction is explicit and compile-time enforced.

## Runtime state

The generated state is a bounded tagged stack. Each entry contains a dense static machine id, its exact parent binding id, and canonical Boundary `StaticMachine` state bytes. The runtime performs no Boundary module decoding, image loading, provider discovery, label dispatch, or registry lookup.

An internal provider may park on an external effect. The encoded stack then retains both provider and parent continuations. Supplying the matching `EffectResult` resumes the provider, maps its typed result into the exact parent request, and continues reduction.

`App.decodeFrame`, `App.initialFrame`, and `App.step` receive a caller-owned
`std.heap.ArenaAllocator`. Their returned Frames borrow all variable-length
storage from that arena and remain valid for its lifetime. Frame copies carry
no cleanup authority. The application WASM wrapper creates one arena over its
bounded scratch region for each call, encodes and copies the output Frame, and
then discards the arena.

## Determinism

For fixed application, parent Frame, semantic EffectResult, and fuel, `App.step` emits byte-identical child Frame bytes. Sequence and resource-counter arithmetic is checked. Schema identity treats Boundary's canonical `usize` word as target-neutral `u64`, keeping native and wasm32 application identities equal.

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
