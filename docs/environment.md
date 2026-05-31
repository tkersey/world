# World Environment

World Handoff packages execution state. Environment binds the receiving host. Boundary supplies the semantic target.

## What Is A World Environment?

`world.Environment(Target, Config)` is the host-side import binder for a certified Boundary target. It validates that local adapter declarations cover the target's residual WorldPorts under a selected policy and produces deterministic acceptance metadata.

It is not a provider lifecycle manager, service discovery layer, scheduler, transport, storage backend, or security system.

## Binding Boundary Target WorldPorts

Boundary emits a dense `WorldPortTable`. World derives `ImportRequirement` records from those entries and lets the host bind adapters with:

```zig
const Env = world.Environment(Target, .{
    .bindings = .{
        world.bind(ToolPort, world.NativeAdapter(handleTool)),
    },
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
```

The binding fingerprint is based on declared target, port, value, adapter, authority, label, and metadata. Native function pointer addresses are excluded.

## BindingPlan

`BindingPlan` is the deterministic adapter table consumed by `Machine`. Entries are ordered by dense `world_port_id` and support O(1)-shape lookup from `world_port_id` to adapter slot. Machine construction can accept `.environment = Env`; legacy `.ports = .{...}` remains sugar for direct native bindings.

## AcceptanceReport

`AcceptanceReport` answers whether the environment can run in `fresh`, `replay`, `verify`, or `audit` mode. It records required and bound counts, missing/extra bindings, adapter kind counts, portable-value compatibility counts, blockers, warnings, and a stable report fingerprint.

Common blockers include `MissingBinding`, `ExtraBinding`, `WrongWorldSurface`, `WrongTargetCertificate`, `WrongPortId`, `AdapterModeNotAllowed`, `PortableValuesRequired`, `ReplaySourceMissing`, `VerifyTranscriptMissing`, and transcript/handoff mismatch blockers.

## EnvironmentCertificate

`EnvironmentCertificate` is deterministic audit metadata, not cryptographic proof. It binds the `TargetRef`, `ImportSet`, `BindingPlan`, `AcceptanceReport`, policy, authority descriptors, adapter descriptors, accepted modes, and blocker count.

## PortAuthority

`PortAuthority` is a local policy descriptor for audit and preflight. Kinds include fixture, replay source, native function, byte adapter, model-like, tool-like, file-like, human-like, and custom. It describes allowed modes and value portability constraints but does not execute anything.

## Adapter Kinds

World includes adapter declaration kinds for native, replay, verify, byte, null-reject, pending-stub, and custom adapters. This PR keeps adapters target-neutral and storage/transport-neutral; real model/tool/file/human integrations stay outside World.

## Fresh Replay Verify Audit Preflight

Environment policies fail closed for missing required ports in fresh and verify modes. Replay can be accepted without native handlers only when a complete transcript image supplies the responses needed by replay.

## Replay-Only Environments

Replay-only handoff can preflight without native bindings when a transcript image is complete. Running typed replay still needs local target metadata so World can decode response values and resume the generated target.

## Verify Environments

Verify mode binds local fresh-capable handlers and compares their responses to transferred transcript frames. Divergence is reported as verify failure, not silently accepted.
