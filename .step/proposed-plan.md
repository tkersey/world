<proposed_plan>
Iteration: 7

# World Fabric Kernel Execution Plan

## Round Delta
- Converted the Fabric milestone into a dependency-ordered implementation campaign with durable tasks, proof gates, and explicit non-goal boundaries.
- Hardened the governing invariant: a parent residual WorldPort may be satisfied by Fabric only through an explicit deterministic route whose provider identity, value mapping, supervision check, causal invocation, receipt, and parent response evidence are fingerprinted in the same Runspace.
- Split declarative Fabric model, Runspace execution, supervision/admission integration, guest/replay/handoff behavior, examples/docs, and final proof into separate gates so route execution cannot precede coverage/cycle/value witnesses.

## Summary
Add World Fabric as a local deterministic composition layer for admitted Boundary runs. Environment says what the host can provide; Fabric says how admitted Boundary runs can provide for each other. The implementation must add `world.Fabric` types for routes, plans, bindings, value mappings, invocations, receipts, reports, and coverage; integrate Fabric into Runspace mailbox routing; supervise nested provider work under the caller's permit; preserve timeline and receipt causality; fail closed for cycles, depth, active handoff, unsupported shared-provider semantics, and unsupported value conversions; and demonstrate target-provider, agent-tool, nested, supervised-denial, cycle-blocked, and guest-provider scenarios.

## Non-Goals/Out of Scope
No Boundary provider linking, Boundary normalization, TreatyResolver or ProviderHarness hot path, service discovery, network transport, storage backend, xitdb, scheduler thread, async runtime, real model/tool/file/human integration, provider lifecycle manager, WASM host package, Boundary LoadedModule.Session execution, package manager, artifact registry, signing/encryption, cryptographic security claims, or agent framework.

## Interfaces/Types/APIs Impacted
- Add `world.Fabric`, with `Route`, `Plan`, `Binding`, `ValueMapping`, `Invocation`, `Receipt`, `Report`, and `CoverageReport`.
- Add route kinds: `adapter`, `target_export`, `admitted_run`, `guest`, `replay`, `reject`, and `unsupported`.
- Add version constants for Fabric route, plan, value mapping, invocation, receipt, and coverage report format/fingerprint versions.
- Extend Runspace with Fabric plan installation, deterministic route execution for pending mailbox entries, provider parking/completion handling, Fabric receipts, and Fabric event kinds.
- Extend supervision with Fabric invocation/provider/depth accounting and deny-before-provider-install checks.
- Extend admission/environment preflight with Fabric coverage.
- Extend handoff to preserve completed Fabric history and fail closed on active Fabric exports unless explicitly supported.
- Add examples and build steps for target-provider, agent-tool, nested, supervised denial, cycle rejection, and optional guest provider.

## Data Flow
1. Parent run parks on a `PendingPort`; Runspace records the mailbox entry and pending request as today.
2. Fabric plan lookup uses dense `world_port_id`, not operation-name string dispatch, and selects an explicit route.
3. Route creates or adopts a deterministic provider path in the same Runspace: target export, admitted run when safe, guest, replay source, reject, adapter, or unsupported fail-closed route.
4. Value mapping converts only supported canonical value-image relationships: payload-to-provider-args, unit-args, and provider-result-to-parent-response.
5. Provider run executes under nested supervision; if it parks, its pending port remains visible in the same mailbox while the parent invocation stays `provider_parked`.
6. Provider completion maps its final result into one parent `Frame.Response`, resumes exactly one parent mailbox entry, and records invocation, receipt, and timeline causality.
7. Replay and verify use transcript-backed images; active Fabric handoff fails closed in v1; completed Fabric history is exported as summary evidence where available.

## Tests/Acceptance
- Unit: route/plan/binding/value-mapping/invocation/receipt fingerprints, route representation, missing coverage, deterministic ordering, cycle/depth/provider-run-limit blockers, blocker/warning stability.
- Runspace: parent pending port routes to provider target run, provider parked state remains visible, provider completion resumes exactly one parent request, nested routes complete, replay route satisfies parent response, reject route is deterministic.
- Supervision: Fabric invocation/provider/depth accounting, deny-before-provider-run, depth budget, provider-run budget, and receipt blockers.
- Timeline/handoff/admission/environment: Fabric events, completed history summary, active handoff fail-closed, fabric-covered preflight accept, missing/mismatched route reject, stable coverage report.
- Guest: NativeGuest route works and conformance vector passes; actual wasm provider execution remains optional behind existing runtime config.
- Agent/examples: tool provider Fabric route works without native tool handler, nested provider Fabric works, final outputs match fixtures.
- Regression: existing Machine, Timeline, Handoff, Supervision, Admission, Runspace, and Guest tests and examples remain green.

## Rollback/Abort Criteria
- Abort or split if Fabric requires a scheduler thread, async runtime, service discovery, network/storage backend, or provider lifecycle manager.
- Abort if target-export routing needs Boundary provider linking, Boundary normalization, TreatyResolver, ProviderHarness, or Boundary LoadedModule.Session execution on the hot path.
- Abort if route fingerprints need runtime pointers, request tokens, credentials, handles, allocator identities, thread ids, or external service clients.
- Abort if value mapping requires host callbacks, JSON conversion, dynamic schema mapping, stringly conversion, or cross-type coercion.
- Abort if supervision cannot deny before provider installation or active handoff cannot fail closed.

## Implementation Brief
1. step=fabric-core-model; owner=implementation; success_criteria=version constants, `world.Fabric` namespace, route/plan/binding/value-mapping/invocation/receipt/report/coverage structs, deterministic fingerprints, and focused core model tests compile and pass.
2. step=value-coverage-cycle; owner=implementation; success_criteria=value mappings enforce exact supported conversions, coverage report accounts for fabric-covered imports, plan ordering/lookup/missing-route/cycle/depth/provider-limit checks pass.
3. step=runspace-fabric-routing; owner=implementation; success_criteria=Runspace installs Fabric plans, routes pending mailboxes to target-export/provider/replay/reject routes, records invocations/receipts/events, resumes exactly one parent request, and exposes provider parked state.
4. step=supervision-admission-environment; owner=implementation; success_criteria=Fabric invocation/provider/depth budgets and policy flags deny before provider installation; admission/environment preflight accepts fabric-covered ports and rejects missing/mismatched routes.
5. step=guest-replay-handoff-timeline; owner=implementation; success_criteria=NativeGuest and replay routes work, Fabric timeline events are stable, completed Fabric history exports in summaries, and active Fabric handoff fails closed with `ActiveFabricUnsupported`.
6. step=examples-docs-build; owner=implementation; success_criteria=Fabric examples and build steps are added; README and `docs/fabric.md` explain route kinds, value mapping, cycle/depth, supervision, Runspace, handoff, guest/replay, and non-goals.
7. step=fixed-point-review; owner=verification; success_criteria=no duplicate truth owner, no additive scaffold, no unresolved adversarial/ablation veto, no no-goal leak, and one-change challenge produces no further required code change.
8. step=proof-closeout-ship; owner=verification; success_criteria=all listed format, diff, build, check, wasm, example, filtered-test, full-test, and lint commands pass; `$st` projection is clean; `$ship` opens or updates a PR with proof.

Iteration: 7
</proposed_plan>
