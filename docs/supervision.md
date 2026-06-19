# World Supervision

Environment says what the host can provide. Supervision says what the host is willing to allow.

World Supervision is the deterministic host policy membrane around `world.Machine` execution. It bounds execution of Certified Boundary Targets and transferred runs without adding storage, networking, scheduling, async runtime, WASM ABI, real integrations, billing, signing, or encryption.

## RunPermit

`world.RunPermit` is the local authorization-to-run object. It binds target, surface, certificate, environment certificate, binding plan, mode, policy, budget, cost model, branch policy, handoff policy, metadata bytes, and label.

Permit fingerprints exclude host function pointers, allocator/runtime/thread pointers, and request tokens. A permit does not contain credentials, host implementations, or an ABI decision.

## SupervisionPolicy

`world.SupervisionPolicy` controls whether fresh, replay, verify, audit-only, native, byte, replay adapters, pending/rejected/failed responses, branches, checkpoints, handoff export/accept, native-only values, and replay-without-image behavior are allowed.

Presets:

- `strict_fresh`
- `strict_replay`
- `verify_replay`
- `agent_fixture`
- `audit_only`
- `handoff_receiver`
- `branch_limited`

Defaults fail closed for fresh/native calls, missing environment certificates, and budget overruns unless a preset or explicit policy opens them.

## Budget

`world.Budget` carries deterministic quotas for session steps, port requests/responses, fresh/replay/verify calls, failed/rejected/pending calls, frame bytes, value image bytes, transcript events, transcript image bytes, checkpoints, branches, branch depth, handoff export/accept, total cost units, and per-port limits.

## CostModel

`world.CostModel` accounts deterministic integer units. Units are not money, do not depend on wall-clock time, and do not use external price feeds. Hosts may map units to money outside World.

## PortRule

`world.PortRule` constrains one dense `world_port_id`: adapter kinds, authority kinds, modes, fresh/replay/verify permission, pending/reject/fail permission, portable value requirements, payload/response byte caps, request caps, and cost caps.

## UsageLedger

`world.UsageLedger` records deterministic usage: steps, requests, responses, fresh/replay/verify calls, failed/rejected/pending calls, bytes, transcript events, branches, checkpoints, handoffs, total cost, per-port usage, and the first exceeded budget.

## SupervisionCheck

`world.SupervisionCheck` records one policy decision before or after a supervised event. Checks bind the permit, event kind, optional port id, usage-before and usage-after fingerprints, allowed/denied state, blocker, rule/budget references, and summary text.

## PolicyMembrane

`world.Supervisor` is the policy membrane. It denies disallowed requests before native handlers are called, checks adapter kind and authority, checks response status, updates the ledger, and produces receipts. Replay-only permits prevent native handler calls.

## RunReceipt

`world.RunReceipt` is the deterministic post-run summary. It binds the permit, environment certificate, target ref, optional run/transcript images, ledger, final run state, final status, exceeded budgets, blockers, warnings, and summary counts. It is not cryptographic.

## Supervised Machine Execution

Pass a permit in run options:

```zig
const permit = world.Supervision.issue(Target, Env, .{
    .mode = .fresh,
    .policy = world.SupervisionPolicy.strict_fresh,
    .budget = world.Budget.init(.{ .max_port_requests = 3 }),
});

var result = try Machine.run(runtime, args, .{
    .allocator = allocator,
    .mode = world.Mode.fresh,
    .ctx = ctx,
    .permit = permit,
});
```

Without a permit, existing `Machine` behavior is preserved.

## Supervised Handoff

Handoff receivers may issue a new local permit:

```zig
const permit = world.Supervision.issue(Target, ReceiverEnv, .{
    .mode = .fresh,
    .policy = world.SupervisionPolicy.handoff_receiver,
    .handoff_policy = .allow,
});

const report = handoff.preflightWithPermit(Target, ReceiverEnv, .accept_fresh, permit);
```

`RunImage` may carry prior permit and receipt fingerprints. The receiver can inspect them, but the receiver permit is authoritative.

## Supervised Branches And Checkpoints

Branch and checkpoint creation call the same supervisor ledger. Policies can deny branching/checkpoints, set max branch/checkpoint counts, set branch depth, and account deterministic cost units.

## Replay/Verify Supervision

Replay-only permits require replay-compatible adapters and prevent native handler calls. Verify permits require replay source material plus fresh adapter execution; changed handler behavior produces verify divergence.

## Agent Supervision Example

`zig build run-world-supervised-agent` runs the agent-shaped fixture under model/tool budgets and prints model calls, tool calls, deterministic cost units, and final result.

## Non-goals

World Supervision is not storage, network transport, scheduler, async runtime, provider lifecycle, service discovery, WASM ABI, real integration, Boundary module image implementation, Boundary closure/normalization, TreatyResolver hot path, ProviderHarness hot path, agent framework, billing layer, signing layer, encryption layer, or cryptographic security boundary.
