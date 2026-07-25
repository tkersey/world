# World Application v1 template

This project defines a new typed Boundary effect protocol, compiles two
Boundary `StaticMachine` programs, closes `digest.format` with a static
provider, and leaves only `research.lookup.v1` for the host.

Build the checked artifacts with Zig 0.16.0 and Node.js:

```text
cd research-digest-agent
zig build
```

The install step writes:

```text
zig-out/world-apps/research-digest-agent.world.wasm
zig-out/world-apps/research-digest-agent.manifest.bin
zig-out/world-apps/research-digest-agent.manifest.txt
```

The build fails unless the application WASM imports nothing, exports the
complete Application ABI v1 surface, declares the configured initial and
maximum memory, and embeds the same canonical manifest produced by the native
application type.

`src/effects.zig` is the schema authority. StaticMachine v1 represents
portable word fields as canonical `u64` values and this template uses two
named research items rather than a dynamic product collection. Those are
deliberate v1 restrictions, not host-side adaptations.
