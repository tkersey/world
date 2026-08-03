# World Application v1 template

This project defines a new typed Boundary effect protocol, compiles two
Boundary Machine ABI v2 programs, closes `digest.format` with a statically
selected provider, and leaves only `research.lookup.v2` for the host.

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

`src/effects.zig` is the schema authority. The capability returns a bounded
`Vector` of `ResearchItem` products. The provider Machine iterates those items,
constructs bounded `Text`, and returns `DigestResult`; the capability never
formats the application result.
