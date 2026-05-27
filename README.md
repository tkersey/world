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
- `world.PortRequest`
- `world.PortResponse`
- `world.Mode`
- `world.Transcript`
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
fn handle(ctx: *Ctx, request: world.PortRequest(Target, Port)) !Port.Response
```

Fresh and verify modes require handler coverage. Strict coverage rejects missing target ports at compile time.

## Transcript And Replay

`world.Transcript` is an in-memory deterministic transcript. It records run events, port requests, fresh responses, replayed responses, failures, fingerprints, replay keys, turn indexes, and stored replay values.

Replay keys include:

- WorldSurface fingerprint
- dense `world_port_id`
- request fingerprint
- response kind

Changing any of those changes the replay key. Replay also fails on target-certificate mismatch, missing responses, port mismatch, request mismatch, response-kind mismatch, surface mismatch, or unused response events.

## Audit Reports

`world.AuditReport` includes the WorldSurface fingerprint, target certificate fingerprint, run mode, final status, request counts, fresh/replayed/rejected/failed counts, replay mismatches, missing handlers, and per-port counts.

## Examples

Run the examples with:

```sh
zig build run-world-strict
zig build run-world-ports
zig build run-world-replay-ports
zig build run-world-agent-loop
```

`world_run_strict` runs a strict closed zero-port target.

`world_run_ports` dispatches one residual WorldPort by dense `world_port_id`.

`world_replay_ports` records a fresh transcript and replays without fresh handler calls.

`world_agent_loop` demonstrates an agent-shaped residual surface with `model.decide` and `tool.call` ports. It is not an agent framework; it is a port dispatch and replay fixture.

## Non-Goals

World v0 does not implement a scheduler, async runtime, storage backend, xitdb integration, network transport, provider lifecycle manager, service discovery, real model/tool/file/human integrations, WASM ABI, security/signing/encryption, distributed execution, Boundary closure, Boundary normalization, treaty resolution, provider harness execution, provider catalog lookup, morphism catalog lookup, closure graph traversal, or evidence graph traversal.
