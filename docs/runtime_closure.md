# World Runtime Closure

Runtime Closure closes the gap between a sealed semantic World Seed and a program-independent runtime. One unchanged `world_universal_appliance.wasm` accepts canonical `world.Executable.Image` bytes, validates the embedded Boundary module closure, derives the Appliance manifest, starts Boundary loaded sessions, installs them in World Runspace/Fabric/Actuation, returns canonical result bytes, freezes continuations into Capsules, emits Archive append bytes, unloads, and repeats with an unrelated image.

The Runtime Closure invariant is:

```text
identical universal runtime bytes
  + canonical Executable.Image bytes
  + canonical host replies
  =
deterministic real World execution
```

## Baseline Invariants

World pins the reviewed Boundary v0.5.0 release that carries portable-v2 loaded execution. The v0.4.1 hardening remains baseline law: entry-reachable profile validation, runtime-profile codec enforcement, exact residual-site binding, executable-plan validation, loaded-session image validation, and response safety all remain fail-closed.

## Portable-v2 Loaded Execution

Boundary owns ProgramPlan instruction semantics, `LoadedValue`, `LoadedModule.Session`, loaded continuation encoding, and generated-versus-loaded parity. Portable-v2 adds portable word semantics, frame-stack continuations, multiple residual suspensions, helper frames that can park, structured product/sum/string-list values, deterministic declared failure, fuel exhaustion, and bounded frame/value arenas.

World owns executable-image closure, admission, provider selection, Runspace lifecycle, Fabric routing, Actuation, supervision, Capsule composition, causal evidence, Appliance turns, and the WASM ABI. Loaded roots and providers are ordinary Runspace slots and Fabric participants; no generated application Target type is linked into the universal runtime.

## Canonical Universal ABI

The universal WASM exposes ABI v3 runtime manifest, load/unload, manifest read, turn submit, closure read, last-error, reset, memory, and bounded allocation exports. It has zero imports, no WASI, no filesystem, no network, no clock, no randomness, no host effect callback, no storage callback, and bounded linear memory.

Host exchange is canonical: hosts submit untrusted `Appliance.Wire.TurnInput` and receive `Appliance.TurnClosure`. HostRequests carry request/payload/idempotency/Actuation evidence bytes; closures carry root result bytes, result refs, finalized receipts, RunReceipt, checkpoint, executable Capsule evidence, Continuity.Bundle evidence, and Archive.AppendBatch bytes. Batched turns preserve missing and nonterminal requests, canonicalize reply order, reject duplicate or stale replies, and stop at the next quiescent boundary.

## Reference Host

The dependency-free ECMAScript host is split into codec, host, and conformance modules. It compiles the WASM once, instantiates with `{}`, reads the runtime manifest, loads real executable images, reads real Appliance manifests, submits canonical commands, decodes host-request and result surfaces, routes fixture effects by stable identity, submits canonical responses, unloads, and repeats in the same and fresh instances. JavaScript does not implement ProgramPlan execution, Runspace, Fabric, Actuation receipt creation, Capsule, Chronicle, or Archive validation.

## Proof Gates

- `zig build check-world-runtime-closure` covers loaded Runspace, loaded Admission, loaded Fabric, loaded Capsule, migration, replay, native universal runtime, universal WASM, and Node external runtime proof.
- `zig build check-world-v0` is the positive Turn Closure completion gate over executable image validation, one-port execution, unrelated programs, loaded providers, multi-suspension agents, active Fabric restore, replay, deterministic retry, batched requests, JavaScript codec independence, Archive evidence, memory bounds, native/WASM parity, and the `WorldV0Report`.
- `zig build check-world-v0-negative` keeps malformed and denial proofs separate from positive lifecycle proof.
- `zig build check-world-universal-appliance-node` proves two unrelated canonical images run through one unchanged WASM artifact and repeat in a fresh instance.

World v0 completion means: World can execute, suspend, migrate, replay, retry, batch, and audit a sealed Certified Boundary program closure in one generic native or WASM runtime, and the next quiescent state is fully represented by canonical bytes.
