<proposed_plan>
Iteration: 7

# World Port Machine v0 Execution Plan

## Summary
Build World Port Machine v0 as a new Zig 0.16 package that consumes Boundary Certified Targets through public APIs, dispatches explicit residual WorldPorts by dense `world_port_id`, and proves deterministic fresh/replay/verify/audit behavior. The chosen path is a host-local Zig callback ABI with exact fingerprint validation, in-memory transcript, and no persistence or scheduler.

## Implementation Brief
- step=1; owner=implementation; success_criteria=`world` is a Zig package with `build.zig`, `build.zig.zon`, `src/world.zig`, tests, examples, docs, local `boundary` dependency, and public root exports compile.
- step=2; owner=implementation; success_criteria=Boundary-backed strict, one-port, replay, and agent-shaped fixture targets are built only through public Boundary APIs.
- step=3; owner=implementation; success_criteria=descriptors, `world.port`, `world.portById`, handler coverage, and target/surface assertions reject forged ids, refs, targets, and fingerprints.
- step=4; owner=implementation; success_criteria=`Machine.run` and `Machine.start` drive `Program.Session`, dispatch by `WorldDispatchTable.lookup`, resume typed responses, and expose full-run plus step APIs.
- step=5; owner=implementation; success_criteria=fresh/replay/verify/audit modes, transcript, replay cursor, replay keys, pending structural result, and audit report pass focused tests.
- step=6; owner=implementation; success_criteria=examples print requested fingerprints/counts/final results and agent skeleton/fixture scenarios match exact final text, event counts, tool calls, responses, output file, and no replay handler calls.
- step=7; owner=implementation; success_criteria=README and `docs/boundary_world_contract.md` document contract, modes, handlers, transcript/replay, audit, examples, hot-path invariants, and non-goals.
- step=8; owner=implementation; success_criteria=run `zig version`, `zig fmt --check build.zig src examples test`, `git diff --check`, `zig build --summary all`, all four run steps, full/filtered tests, and `zig build lint -- --max-warnings 0` if configured.

Iteration: 7
</proposed_plan>
