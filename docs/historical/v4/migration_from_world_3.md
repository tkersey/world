# Migrating from World 3

World 3.1.4 at commit `a0fa4600e4a4c8afdccce60a16e10226e9c8d8a3` is the
final World Application ABI v1 compiler release. Its source, tags, SDK artifacts,
Application ABI v1, and Frame v1 records remain immutable compatibility history.

Existing application-specific `.world.wasm` artifacts, persisted Frame v1 runs,
and Application ABI v1 integrations continue to belong to World 3.1.4 and
`world-host` 1.x. World 4 neither loads those artifacts nor contains a second
legacy compiler implementation.

World 4 is a dependency-free JavaScript host for portable Boundary processes,
not a Zig source-language package or application compiler. Its portable runtime
tuple is:

```text
BPI1
+ InitialArgs or ABL_PST1
+ optional ABL_ERS1
+ fixed Boundary Process kernel
    -> ABL_PKO1
```

Moving an application to this model requires its authoring frontend to produce
a BPI1 image and its environment to retain portable Process State and answer
typed residual requests. World only advances and relays those bytes.

There is no automatic migration from a World Frame to Boundary Process State,
no renamed equivalent of `world.application`, and no compatibility route that
loads application-specific World WASM through World 4. Keep existing runs on
the frozen World 3/world-host stack unless a separately specified migration is
available.
