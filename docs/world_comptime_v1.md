# World Comptime v1

Status: normative for the v1 release-candidate line.

World Comptime v1 replaces the proposed runtime-loaded World Image v1 architecture as the primary implementation plan. The production artifact is an application-specific, import-free WebAssembly module:

```text
Boundary program
  -> Boundary StaticMachine
  -> World comptime handler closure
  -> Zig compilation
  -> <application>.world.wasm
```

The governing rule is:

> Compile every known semantic choice. Serialize only continuation state. Externalize only genuine authority.

## Ownership

Boundary owns typed effects, program construction, closure analysis, CPS/defunctionalization, static effect-site metadata, and portable continuation-state encoding.

World owns comptime handler selection, provider composition, effect-row subtraction, schema compatibility, complete root-to-provider encoded-state bounds, deterministic limits, application manifests, the generated step kernel, and the application WASM ABI.

world-host owns artifact admission, Frame and EffectResult retention, conditional branch-head advancement, policy, secrets, capability dispatch, and operator control.

world-capabilities owns concrete external effect handlers. A capability receives an EffectRequest and returns an EffectResult. It cannot author a Frame or application state.

## Runtime boundary

The application runtime accepts one `StepInput` and returns one `Frame`. A Frame carries zero or one pending EffectRequest. The host persists accepted EffectResults separately and resubmits them through StepInput.

The production path contains no runtime Boundary module decoder, Executable.Image loader, dynamic linker, Fabric-plan loader, runtime provider registry, WASI dependency, or imported capability callback.

The current universal World runtime remains a feature-frozen v0 compatibility and oracle path. v0 TurnClosure or Capsule state is not translated into v1 Frame state. Existing runs complete on v0 or restart on v1 from application-level inputs.

## Determinism law

For one application artifact:

```text
same parent Frame
+ same semantic EffectResult
+ same fuel
-> byte-identical child Frame
```

Host metadata is transient and cannot influence Frame bytes or identity. A warm worker and a fresh worker must be observationally equivalent.

## Behavioral oracle

The required v0/v1 comparison has six scenarios:

1. one external effect;
2. skeleton agent;
3. fixture file-rewrite agent;
4. internal provider parked on an external effect;
5. deterministic retry after a persisted result;
6. branching from one parent.

Comparison is over normalized external effects, retained Boundary site identities, semantic payloads/results, terminal outcome, replay suppression, retry determinism, branch parentage, and provider suspension/resumption. v0 and v1 record bytes are intentionally unrelated.

## Non-claims

SHA-256 content identities are not signatures. Conditional head advancement is not distributed consensus. Deterministic retry is not exactly-once external execution. WASM does not protect an application from a malicious host. v1 provides no confidentiality, signing, timestamp, or branch-merge infrastructure.
