# World Runspace

Runspace is a deterministic local reactor. It does not schedule time, own storage, or perform transport.

## What is Runspace?

`world.Runspace` is an in-memory arena for admitted or local runs. It answers which runs are runnable, parked, completed, failed, exported, or rejected; which `WorldPort` requests are waiting in the mailbox; and which response resumes which parked run.

Runspace is caller-driven. There is no background thread, async runtime, wall-clock scheduler, storage backend, or network transport.

## RunHandle

`RunHandle` identifies one run inside one Runspace. Its fingerprint binds runspace fingerprint, local run id, target ref fingerprint, optional admission receipt, optional permit, optional branch id, and generation.

It is deterministic for a given runspace insertion order and inputs, but it is not globally stable. It excludes pointers, handlers, request tokens, allocators, threads, credentials, storage identities, and network identities.

## RunSlot

`RunSlot` is internal mutable state for one run. It stores the handle, target ref, run state, optional permit/admission/receipt fingerprints, optional pending mailbox id, branch/checkpoint metadata, and an optional typed machine driver.

Callers use summaries and reports. They do not mutate slots directly.

## PendingPort

`PendingPort` is one mailbox entry for a `Frame.Request` awaiting host action. It binds the run handle, mailbox id, dense `world_port_id`, request fingerprint, request frame fingerprint, residual site, target ref, optional environment and permit fingerprints, turn index, inserted event index, and status.

A pending port can be responded once. Stale mailbox ids and already-consumed entries are rejected.

## Mailbox

`Mailbox` stores pending ports and validates response routing. A response must match the pending request fingerprint, dense port id, world surface, response kind, and expected value table. Manual responses go through `runspace.respond` or `runspace.respondValue`.

## tick / step / poll

`tick()` walks runnable runs in deterministic local-run order and steps each once. If a run yields a request, Runspace enqueues a pending port and parks the run. If it completes or fails, Runspace records the state and event.

`stepOne()` steps the first runnable run. `step(handle)` steps a selected run. `poll()` and `report()` summarize counts without advancing execution.

## Manual response routing

Manual mode is the default. Runspace parks on every port request and waits for the caller:

```zig
_ = try runspace.tick();
const pending = try runspace.mailbox.get(0);
_ = try runspace.respondValue(pending.mailbox_id, value);
_ = try runspace.tick();
```

## Auto-dispatch mode

With `auto_dispatch = true`, Runspace still enqueues a pending port, then uses the existing typed `Machine`/`Environment` adapter path to dispatch the request synchronously. The mailbox entry is marked responded and runspace events record the automatic response.

Auto-dispatch does not add search, scheduler threads, async runtime, TreatyResolver, ProviderHarness, or real integrations.

## Admission integration

`installAdmitted` installs an `Admission.AdmittedRun` and records admission receipt fingerprints. Parked admitted run images populate the mailbox so a host can inspect or export the pending request.

## Environment integration

Machine-backed Runspace slots use the existing `Environment` binding plan. Manual mode exposes requests through the mailbox. Auto-dispatch calls the typed adapter path by dense `world_port_id`.

## Supervision integration

Runspace preserves the existing `Machine`/`Supervisor` membrane. Permits are validated at install/start. Budgets and policies deny before handler calls. Runspace also enforces local caps for runs, pending ports, and runspace events.

## Timeline integration

Each run keeps its own transcript/timeline behavior through Machine and Handoff primitives. Runspace has a separate event log that references run handles, pending ports, request/response frames, run states, permits, receipts, and admission receipts.

## Handoff export

`exportRun`, `exportPending`, and `exportHandoff` produce `RunImage` snapshots. Parked exports include the pending `Frame.Request`. Completed machine-backed exports include a `TranscriptImage` when the run was installed with a transcript sink.

## Branch/checkpoint operations

`checkpoint(handle)` creates deterministic `Timeline.Checkpoint` metadata and records a runspace event. `branch(handle, checkpoint, options)` creates a new local `RunHandle` and slot metadata for the branch.

## Agent runspace example

`examples/world_runspace_agent.zig` installs an agent-shaped run with manual dispatch disabled. Model and tool port requests appear in the mailbox, the fixture host responds by mailbox id, and the run completes deterministically.

## Non-goals

Runspace does not implement storage, network transport, distributed protocol, scheduler threads, async runtime, provider lifecycle, service discovery, real model/tool/file/human integrations, WASM ABI, Boundary loaded execution, Boundary closure or normalization, TreatyResolver or ProviderHarness hot paths, signing, encryption, package management, artifact registry, or an agent framework.
