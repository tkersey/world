# World Executable

`world.Executable` is the public construction surface for a sealed World Seed: an `Executable.Image` that contains the immutable module closure, link witnesses, dispatch tables, residual host authority descriptors, memory bounds, and certificate metadata needed by a generic World runtime.

The image is not a Boundary module, an Assembly, a Capsule, or an Appliance instance. Boundary modules carry certified target semantics. Assembly and Fabric describe World routing. Capsules carry execution state. Appliance owns turn orchestration. `Executable.Image` binds the bytes and witnesses that let those existing owners run without a locally generated Boundary Target type.

## Builder Flow

```zig
var builder = world.Executable.Builder.init(allocator, .{});
try builder.addRootModule(root_module_bytes);
try builder.addProviderModule(provider_module_bytes);
try builder.addExternalBinding(binding);

var prepared = try builder.prepare();
defer prepared.deinit();

var image = try prepared.seal();
defer image.deinit(allocator);
```

`prepare` is transactional. It decodes Boundary full modules, derives module imports and exports, runs the existing Linker, checks residual external bindings, derives the dense dispatch image, derives memory bounds, and constructs deterministic certificate metadata. It does not mutate Runspace, Fabric, Appliance, Capsule, Archive, or host state.

`seal` succeeds only when the compatibility report has no hard blockers. A missing residual external binding blocks sealing instead of producing a partially runnable image.

## Module Set

`Executable.ModuleSet` is a finite explicit set:

- exactly one root full module;
- zero or more provider full modules;
- canonical module fingerprints and exact canonical bytes;
- duplicate identical modules deduplicated by the builder;
- conflicting duplicate module identities rejected.

The builder does not fetch modules, scan the filesystem, query registries, or pick the best available provider. Every executable dependency must be supplied before sealing.

## External Bindings

`Executable.ExternalBinding` describes residual host authority without carrying an implementation. It binds:

- parent module fingerprint;
- dense `world_port_id`;
- WorldPort and value refs when present;
- `Actuation.Ref`;
- `Actuation.Descriptor`;
- allowed response statuses, value policy, supervision/authority refs, and bounded labels.

Credentials, callbacks, URLs, file handles, and network clients remain host-owned and outside the image.

## Dispatch And Certificate

`Executable.DispatchImage` is the link-time dense side table for a generic runtime. Hot-path routing uses integer identities and fingerprints, not operation names, labels, or provider discovery.

`Executable.Certificate` is deterministic witness metadata, not a signature and not a trust root. Receivers independently validate the encoded image against their supported `Executable.RuntimeProfile`.

## Runtime Ownership

Boundary owns loaded executable semantics: executable plan images, schema-driven loaded values, target-neutral `LoadedModule.Session`, continuation images, stable failure identities, and generated-versus-loaded parity. World does not reinterpret Boundary `ProgramPlan` internals and does not add a second interpreter.

World owns admission, closed provider selection, Linker route synthesis, Runspace installation, Fabric execution, external Actuation, Capsule composition, Continuity/Chronicle/Archive evidence, Appliance turns, and the deployment ABI. Loaded roots and loaded providers enter through the same Runspace, Fabric, Actuation, and Capsule owners as generated targets.

Hosts own real effects, credentials, network/files/models/humans, durable byte retention, transport, and runtime process lifecycle. `Executable.ExternalBinding` names residual host authority without storing implementations, endpoints, credentials, callbacks, or handles.

## World Seed Proof Surface

The closeout gates are:

- `zig build check-world-seed`: runs the seven killer examples: one-port host bytes, agent plus loaded-provider shape, two images through one generic WASM implementation, migration, active Fabric restore, replay, and malformed rejection.
- `zig build check-world-universal`: runs the native universal runtime, replay, and generic universal Appliance WASM inspection lanes.
- `zig build check-world-universal-appliance-node`: uses installed Node and the built-in ECMAScript `WebAssembly` API to compile `world_universal_appliance.wasm` once, instantiate with `{}`, run two unrelated executable images in fresh instances of the same bytes, and compare canonical output with the native projection.

The normal `zig build check` lane remains free of the external Node dependency. The Node lane is a closeout proof for the generic artifact, not a runtime dependency of World.

World can execute a sealed Certified Boundary program closure independently of the compiler that produced it.
