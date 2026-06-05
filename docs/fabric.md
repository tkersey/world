# World Fabric

Environment says what the host can provide. Fabric says how admitted Boundary runs can provide for each other.

## What is World Fabric?

World Fabric is a deterministic local conduit layer over admitted or local runs in one `world.Runspace`. It answers whether a parked residual `WorldPort` can be satisfied by another explicit local provider path: adapter, generated target export, admitted run, guest, replay source, reject route, or unsupported fail-closed route.

Fabric records the causal path from parent request to provider run to provider result to parent response. It is caller-driven and in-memory. There is no background scheduler, async runtime, network transport, storage backend, or service discovery.

## Why fabric is World-side, not Boundary-side

Boundary owns algebra, normalization, certified target surfaces, import/export metadata, and module images. World owns execution timelines, host environments, run contracts, admission, runspace, guest adapters, and local composition.

Fabric is therefore World-side: it routes already-certified residual ports through already-admitted local execution surfaces. It does not alter Boundary semantics or relink providers inside Boundary.

## Fabric.Route

`world.Fabric.Route` says how one parent residual port may be satisfied.

Route kinds:

- `adapter`: represents the existing adapter path.
- `target_export`: adopts or installs a local generated provider target export.
- `admitted_run`: routes to an admitted run when safe.
- `guest`: routes through Guest.Core, NativeGuest, or configured guest execution.
- `replay`: satisfies the parent request from transcript-backed replay data.
- `reject`: emits a deterministic terminal response.
- `unsupported`: records a fail-closed unsupported path.

A route fingerprint includes route kind, parent surface/certificate/port, optional provider target/module/admission/environment/permit/guest/report/export references, value mapping, supervision policy reference, label, and metadata. It excludes handler pointers, runtime pointers, allocator or thread identity, request tokens, credentials, URLs, model clients, file handles, and network handles.

## Fabric.Plan

`world.Fabric.Plan` is the deterministic routing table for one parent target.

Plans are ordered by dense `world_port_id`. They provide:

- `routeForPort`
- `assertCoverage`
- `assertNoCycles`
- `summary`

There is no implicit lookup and no operation-name dispatch on the hot path. The plan records missing route ids, optional default route, maximum conduit depth, maximum provider runs, cycle policy, value policy, and supervision policy references.

Runspace routing requires the plan to be installed first with `installFabricPlan`. Route calls validate the supplied plan against the installed plan fingerprint before any invocation, mailbox, or response mutation. Installed plans also provide the route and value-mapping witnesses used later by `respondFromFabric`.

## Fabric.Binding

`world.Fabric.Binding` connects a parent import requirement to a provider route. It records the parent import requirement fingerprint, parent port id, route fingerprint, provider target/module/run/export references, value mapping fingerprint, route kind, required flag, and metadata.

This is separate from Environment binding. Environment binds host adapters. Fabric binds admitted runs/modules to each other inside Runspace.

## ValueMapping

`world.Fabric.ValueMapping` v1 structurally represents:

- `payload_to_provider_args`
- `unit_args`
- `provider_result_to_parent_response`

Executable Fabric plans currently reject provider request mappings (`payload_to_provider_args` and `unit_args`) until provider argument identity has a concrete witness. Provider routes use an explicit `provider_result_to_parent_response` mapping for response synthesis.

Mappings require exact value references where possible. Same-table compatibility is accepted only when already represented by Boundary/World metadata. Fabric rejects arbitrary host conversion, string conversion, JSON conversion, dynamic schema mapping, and host callback mappers.

Fail-closed blockers include payload reference mismatch, provider argument mismatch, provider result mismatch, unsupported mapping, unsupported value image, and cross-type conversion.

## Fabric.Invocation

`world.Fabric.Invocation` records one routed parent request. It binds the plan, route, parent run handle, parent pending port, parent request frame, parent port id, optional provider handle, provider target, provider run image, provider result, mapped parent response, depth, turn index, status, and metadata.

Invocation statuses include started, provider installed, provider running, provider parked, provider completed, parent responded, failed, rejected, cycle blocked, and supervision denied.

## Fabric.Receipt

`world.Fabric.Receipt` summarizes a completed or failed invocation. It binds invocation, parent run, pending port, provider run, route, provider run receipt, parent response, final status, blockers, warnings, and usage summary.

Receipts are deterministic audit records. They are not cryptographic security claims.

## Target provider routes

A `target_export` route uses a registered, admitted, or test-policy local generated target as a provider. The parent payload maps to provider arguments when supported, and the provider final result maps to one parent response.

If the provider parks on its own port, that pending port appears in the same Runspace mailbox. The parent invocation stays parked until the provider completes and `respondFromFabric` emits the parent response.

`respondFromFabric` accepts only recorded invocation occurrences from the same Runspace. A caller cannot complete a parent mailbox with a freshly constructed invocation or a different provider handle.

## Nested fabric routes

Nested routes use the same mailbox and deterministic tick model. The route stack, depth, parent run, provider target/module, and route fingerprint are tracked so cycles and depth violations fail closed.

## Guest fabric routes

Guest execution uses the existing guest boundary. Fabric v1 does not admit `.guest` routes into a plan until a dedicated guest route executor is present; provider routes that need guest-shaped evidence must use an executable provider route kind and keep guest conformance as the witness.

## Replay fabric routes

Replay routes validate the transcript image fingerprint and replay key through `routePendingFromReplay`, then emit the parent response frame from transcript-backed data. The generic `routePending` path rejects replay routes because it has no transcript witness. Missing transcript images, replay-key mismatch, target mismatch, and missing response events are rejected.

## Cycle/depth rules

Fabric tracks parent run, provider target, provider module, route fingerprint, depth, and route stack.

Default policy rejects same-run recursion, same-target cycles, excess depth, and provider run limits. Explicit recursive routing is disabled by default.

## Supervision

Supervision policies can allow or deny Fabric routes, target-export routes, replay routes, and reject routes. The guest-route policy bit is reserved until Fabric has a dedicated guest route executor. Budgets can cap Fabric invocations, provider runs, nested depth, and deterministic provider costs.

The supervisor checks Fabric work before provider installation or parent response emission. Usage ledgers count Fabric invocation count, provider run count, nested depth, provider cost, and parent response cost.

## Handoff behavior

Completed Fabric history is visible through Fabric invocation/receipt records and runspace events. Active Fabric handoff fails closed in v1 with `ActiveFabricUnsupported` unless a future format explicitly carries active invocation state safely.

## Agent tool fabric example

`examples/world_fabric_agent_tool.zig` keeps the agent model decision manual and routes the `tool.call` port through a provider target. The native tool handler is present only as a coverage declaration and is not called for the Fabric-covered tool port.

## Non-goals

Fabric does not implement Boundary provider linking, Boundary normalization, TreatyResolver hot paths, ProviderHarness hot paths, service discovery, storage, xitdb, network transport, scheduler threads, async runtime, real model/tool/file/human integrations, provider lifecycle, WASM host packages, Boundary loaded-module execution, signing, encryption, package management, artifact registry, or an agent framework.
