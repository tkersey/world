# World v0

World v0 is complete only when one quiescent Appliance turn is the complete portable unit of execution.

## Completion Criteria

`WorldV0Report` passes only when every required proof bit is true and there are no blockers: Boundary v0.5.0 portable-v2 baseline, canonical executable image, actual universal WASM execution, genuinely unrelated images, internal loaded provider, multi-suspension loaded root, active loaded Fabric restore, verified replay without fresh effect, unsupported actuated replay rejection, deterministic retry, batched request/reply, independent JavaScript codec, exact root-result bytes, exact receipt bytes, exact Capsule bytes, exact Archive.AppendBatch bytes, native/WASM parity, cold/warm parity, bounded memory, malformed-input suite, and historical regression matrix.

These are not completion evidence: replay final result false, active restore rejection, same ProgramPlan under different metadata, WASM artifact inspection without execution, or Node execution dependent on a native World reply helper. Unsupported actuated replay rejection is required only as a fail-closed boundary proof and does not substitute for the verified replay-without-fresh-effect lane.

## Positive Proof Matrix

- `zig build check-world-turn-closure`: validates complete one-port and multi-module closures, bundle roots, Wire input, result/receipt/checkpoint refs, and unresolved-reference rejection.
- `zig build check-world-universal-providers`: proves loaded provider execution through Fabric/Runspace without native provider callbacks.
- `zig build check-world-active-fabric-restore`: proves loaded root/provider active Fabric restore, provider response, parent resume, and completion.
- `zig build check-world-replay-positive`: proves replay suppresses covered HostRequests and records non-fresh receipts with matching final result.
- `zig build check-world-deterministic-retry`: proves lost-output retry produces byte-identical closure evidence after one external fixture effect.
- `zig build check-world-appliance-batching`: proves multiple external requests, reverse replies, partial preservation, duplicate rejection, and one turn crossing.
- `zig build check-world-js-codec`: proves dependency-free ECMAScript codec/host execution without child-process reply construction.
- `zig build check-world-two-programs-one-wasm`: proves two unrelated executable images run through unchanged universal WASM bytes.
- `zig build check-world-universal-memory`: proves the shipped universal fixture profile stays within its bounded memory plan.
- `zig build check-world-v0`: aggregates the positive completion gate and runs the `WorldV0Report` example.

## Negative Proof Matrix

`zig build check-world-v0-negative` keeps malformed input, denial, wrong route/provider/session/receiver permit, wrong Archive parent, duplicate target, stale target, wrong schema, trailing bytes, overflow, and other rejection proofs separate from positive lifecycle evidence.

Negative gates remain required, but they never substitute for successful execution, restore, replay, retry, or codec independence.

## Runtime Profile

The supported v0 universal profile has ABI v3, exported memory, no imports, no WASI, no filesystem, no network, no clock, no randomness, no storage callback, no actuator callback, no generated application Target type, fixed-width ABI parameters, transactional image loading, reset that retains the immutable image, unload that clears image and execution, and output readable until the next mutating call.

It supports one root module, zero or more provider modules, sealed loaded-module-export routes, nested provider routes within configured depth, residual external Actuation bindings, replay routes, reject routes where supported, and bounded memory with a 64 MiB shipped maximum.

## Boundary Surface

World v0 consumes the reviewed Boundary v0.5.0 portable-v2 surface. Boundary owns ProgramPlan semantics, loaded values, loaded session continuations, and generated-versus-loaded parity. World owns execution orchestration, provider routing, Runspace slots, Actuation, Capsule, Continuity, Chronicle, Archive, Supervision, Admission, and Appliance turns.

## Universal WASM Deployment

The universal WASM is unchanged across images. A host loads an `Executable.Image`, submits Wire TurnInput bytes, reads a canonical TurnClosure, may destroy the process or WASM instance after every turn, and continues in a fresh instance using only canonical bytes.

## Host Responsibilities

Hosts own real effects, credentials, network/files/models/humans, Archive byte retention, transport, durability, and process lifecycle. Hosts submit untrusted Wire inputs and retain World-authored byte evidence; they do not mint World receipts, fingerprints, Chronicle events, Capsules, Archive validation, or Actuation receipts.

## Intentionally External

Real integrations, storage, transport, scheduling, package management, service discovery, exactly-once semantics, signing, encryption, and cryptographic trust are out of scope for World v0.
