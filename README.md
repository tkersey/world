# World

World is the first concrete interpreter for Boundary Certified Targets. Boundary does the algebra; World handles the ports.

Boundary compiles a defunctionalized algebraic-effects program into a residual `Program.Session`, Boundary Normal Form, target-neutral `WorldSurface`, dense `WorldPortTable`, `WorldValueTable`, `WorldDispatchTable`, source/trace/evidence maps, and a `Target.Certificate`. World consumes that certified target and chooses a local Zig handler ABI for explicit residual `WorldPorts`.

## Boundary And World

Boundary owns normalization, closure, treaty resolution, provider reasoning, morphism reasoning, and target-neutral metadata. World validates the certified target surface, starts the residual `Program.Session`, steps it, dispatches residual requests by dense `world_port_id`, calls host-owned handlers in fresh mode, records deterministic transcripts, replays from transcripts, and reports audit metadata.

World does not choose for Boundary. Boundary does not choose the concrete ABI for World.

## Public API

The public root is intentionally small:

- `world.Machine`
- `world.port`
- `world.portWithOptions`
- `world.PortRequest`
- `world.PortResponse`
- `world.Mode`
- `world.Transcript`
- `world.Frame`
- `world.ValuePolicy`
- `world.TranscriptImage`
- `world.Timeline`
- `world.TargetRef`
- `world.ImportRequirement`
- `world.ImportSet`
- `world.Environment`
- `world.Binding`
- `world.PortAuthority`
- `world.AdapterDescriptor`
- `world.BindingPlan`
- `world.AcceptanceReport`
- `world.EnvironmentCertificate`
- `world.RunState`
- `world.RunImage`
- `world.Handoff`
- `world.AuditImage`
- `world.AuditReport`
- `world.Error`

Typical usage:

```zig
const ToolPort = world.port(Target, TargetProgram.protocol.operationSite("tool", "call", 0), handleTool);
const Machine = world.Machine(Target, .{
    .ports = .{ToolPort},
    .strict_handler_coverage = true,
});
```

The legacy `.ports` form remains available. It is sugar over the same import-binding shape used by `world.Environment`.

## Certified Targets

`Machine(Target, Config)` binds to a Boundary target with:

- `Target.Program`
- `Target.WorldSurface`
- `Target.WorldPortTable`
- `Target.WorldValueTable`
- `Target.WorldDispatchTable`
- `Target.Certificate`

Construction asserts the Boundary world surface is ready and that the target hot path is a dense dispatch surface.

## Modes

`world.Mode` has four modes:

- `fresh`: call handlers and record request/response events.
- `replay`: resume from transcript responses without calling handlers.
- `verify`: call handlers and compare fresh response fingerprints with transcript responses.
- `audit`: run with a configured source mode and return `AuditReport` counts.

## Port Handlers

Handlers are declared with `world.port(Target, Site, handler)`. The descriptor binds the exact target, residual site index, residual site fingerprint, payload type, response type, source ref, and world-port ref.

Handlers may accept either:

```zig
fn handle(ctx: *Ctx, payload: Port.Payload) !Port.Response
fn handle(ctx: *Ctx, request: world.PortRequest(Target, Site)) !Site.Resume
```

Fresh and verify modes require handler coverage. Strict coverage rejects missing target ports at compile time.

`world.port` treats handler responses as borrowed values: World clones the response into run/transcript storage before resuming Boundary, and the handler/context remains responsible for any source storage it owns. Handlers that return newly allocated response buffers can use `world.portWithOptions(..., .{ .response_deinit = deinitFn })`; World calls `deinitFn(ctx, response)` after it has retained the response.

## World Environment

World Environment binds the receiving host to the semantic WorldPort imports that Boundary exposed. `world.TargetRef` identifies the certified target by target, surface, certificate, plan, table, and profile fingerprints without carrying code, handlers, runtime pointers, request tokens, credentials, or allocator/thread identity.

`world.ImportRequirement` describes one residual WorldPort requirement. `world.ImportSet` summarizes the required imports for a target and exposes required port ids and per-port requirements. Requirements are semantic; implementations stay outside the requirement.

`world.Binding` connects an import requirement to a local adapter declaration. `world.PortAuthority` is a local audit/policy descriptor, not a Boundary capability and not cryptographic security. `world.AdapterDescriptor` fingerprints adapter declarations without native function pointer identity. `world.BindingPlan` is the deterministic dense table used by `Machine` for `world_port_id` dispatch.

`world.AcceptanceReport` answers whether a target/run can execute under an environment and mode. `world.EnvironmentCertificate` records the accepted target, import set, binding plan, policy, authority, adapter, and blocker fingerprints for audit and transcript provenance.

```zig
const Env = world.Environment(Target, .{
    .bindings = .{
        world.bind(Target.WorldPorts.model_decide, world.NativeAdapter(handleModel)),
    },
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const Machine = world.Machine(Target, .{ .environment = Env });
```

## Transcript And Replay

`world.Transcript` is an in-memory deterministic transcript. It records run events, port requests, fresh responses, replayed responses, failures, fingerprints, replay keys, turn indexes, and stored replay values.

Replay keys include:

- WorldSurface replay-scope fingerprint
- dense `world_port_id`
- request fingerprint
- response fingerprint

Changing any of those changes the replay key. Replay also fails on target-certificate mismatch, missing responses, port mismatch, request mismatch, response-kind mismatch, full-surface mismatch, or unused response events.

## World Timeline Kernel

The timeline kernel makes residual port interactions portable. `world.Frame.Request` describes a port request without a request token, runtime pointer, allocator pointer, handler function pointer, thread id, or host-owned pointer identity. `world.Frame.Response` describes the response, status, replay key, response fingerprint, and optional portable value image.

`world.Frame.ValueImage` is a byte-oriented value image for scalar values, byte slices, and simple product/sum shapes already represented by Boundary value metadata and Zig types. Unsupported values fail closed with `UnsupportedValueImage`, `NativeOnlyValue`, or `MissingValueImage` depending on `world.ValuePolicy`.

Native Zig handlers remain ergonomic through `world.port` and `world.portWithOptions`; they are one adapter over frame semantics. The frame step API is:

```zig
var run = try Machine.start(runtime, args, options);
switch (try run.nextFrame()) {
    .port_request => |request_frame| try run.resumeFrame(response_frame),
    .done => |value| ...,
    .failed => ...,
}
```

`world.TranscriptImage` is the portable image form of a transcript. It contains ordered event images, request/response frames, replay keys, final status, and summary counts. It does not store `StoredValue`, `*anyopaque`, allocator/runtime/thread pointers, request tokens, or handler functions. Image-backed replay requires the machine's compile-time port descriptors so World can recover the residual site and response type, but it does not call native handlers or require a handler context when response frames carry portable `ValueImage` data.

`world.Timeline.Checkpoint` records deterministic metadata for a resumable or branchable point: event index, turn index, prefix fingerprint, branch id, and optional current request/last response fingerprints. `world.Timeline.Branch` records a branch id, parent, checkpoint fingerprint, event range, final status, and counts. These are metadata primitives only; World does not add persistence, scheduling, or concurrency.

`world.AuditImage` summarizes frame counts, replay/verify/failure counts, checkpoint/branch counts, portable-value blockers, and the transcript image fingerprint when available.

## World Handoff

World Handoff packages execution state. Environment binds the receiving host. Boundary supplies the semantic target.

`world.RunState` describes whether a run is not started, running, parked on a port, completed, or failed. It binds the target ref, optional transcript image, branch id, checkpoint, pending request frame fingerprint, final response/value image fingerprint, turn index, and status.

`world.RunImage` is the portable handoff object. It contains a `TargetRef`, `ImportSet` fingerprint, transcript image, current `RunState`, checkpoint and branch metadata, optional pending `Frame.Request`, optional final `ValueImage`, and optional environment/acceptance/audit fingerprints. It does not contain handlers, credentials, concrete ABI data, network or storage transport, host function pointers, allocator/runtime/thread ids, or request tokens.

`world.Handoff` decodes and validates a `RunImage`, preflights it against a local target and environment, validates parked pending frames, supports replay-only and verify-on-receive flows through transcript images, and keeps branch metadata portable. Future Boundary module images can be referenced by `TargetRef`/`RunImage` without making World a storage, transport, or module-image implementation.

## Audit Reports

`world.AuditReport` includes the WorldSurface fingerprint, target certificate fingerprint, run mode, final status, request counts, fresh/replayed/rejected/failed counts, replay mismatches, missing handlers, and per-port counts.

## Examples

Run the examples with:

```sh
zig build run-world-strict
zig build run-world-ports
zig build run-world-replay-ports
zig build run-world-agent-loop
zig build run-world-frame-ports
zig build run-world-transcript-image-replay
zig build run-world-byte-adapter
zig build run-world-agent-timeline
zig build run-world-agent-branch
zig build run-world-environment-preflight
zig build run-world-handoff-parked
zig build run-world-handoff-replay
zig build run-world-handoff-verify
zig build run-world-agent-handoff
```

`world_run_strict` runs a strict closed zero-port target.

`world_run_ports` dispatches one residual WorldPort by dense `world_port_id`.

`world_replay_ports` records a fresh transcript and replays without fresh handler calls.

`world_agent_loop` demonstrates an agent-shaped residual surface with `model.decide` and `tool.call` ports. It is not an agent framework; it is a port dispatch and replay fixture.

`world_frame_ports` steps to a `Frame.Request`, resumes from a `Frame.Response`, and records frame fingerprints.

`world_transcript_image_replay` records a fresh transcript image, decodes it, and replays without native handler calls.

`world_byte_adapter` encodes request/response frames as canonical bytes through a fake byte host. It is not WASM and does not define a concrete ABI.

`world_agent_timeline` replays an agent-shaped transcript image without model/tool handler calls.

`world_agent_branch` records baseline and alternate agent transcripts from checkpoint metadata and shows different final results.

`world_environment_preflight` shows a missing fresh binding rejected while replay with a complete transcript image passes without a native handler.

`world_handoff_parked` packages a run parked on a port request, decodes it on the receiver side, validates the pending frame, and completes the run.

`world_handoff_replay` transfers a completed run image and replays it from a transcript image without calling a native fresh handler.

`world_handoff_verify` verifies a transferred transcript against matching local handlers and detects a changed handler.

`world_agent_handoff` packages an agent-shaped run image with checkpoint metadata and replays it on the receiver side.

## Validation

Run the full local validation gate with:

```sh
zig build check --summary all
```

The `check` step runs unit tests, the forged-descriptor compile-fail fixture, all examples, formatting, and hot-path source guards.

## Non-Goals

World v0 does not implement a scheduler, async runtime, storage backend, xitdb integration, network transport, provider lifecycle manager, service discovery, real model/tool/file/human integrations, WASM ABI, security/signing/encryption, distributed execution, Boundary closure, Boundary normalization, treaty resolution, provider harness execution, provider catalog lookup, morphism catalog lookup, closure graph traversal, or evidence graph traversal.
