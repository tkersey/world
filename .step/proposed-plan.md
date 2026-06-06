<proposed_plan>
Iteration: 1

# World Assembly Linker Kernel Execution Plan

## Round Delta
- Converted the Linker milestone into a dependency-ordered implementation campaign with durable tasks, proof gates, explicit non-goals, and kernel-boundary checks.
- Selected a separate `src/linker.zig` kernel as the canonical owner of closed-world graph reasoning and route synthesis; `src/world.zig` remains the public facade and integration owner for Runspace, Admission, Environment, Supervision, Guest, Handoff, and Fabric execution APIs.
- Hardened the governing invariant: Fabric executes explicit witnessed routes; Linker only synthesizes those routes from a closed local catalog, and every accepted route must carry provider identity, compatible value refs, explicit mappings, policy, match, graph, and certificate witnesses without handler calls or mailbox mutation.

## Summary
Add World Linker as a deterministic closed-world assembly kernel. Linker takes a root target/module/import set plus an explicit local catalog of candidate providers, admitted runs, guest providers, replay sources, reject routes, environment adapter coverage, and hints. It indexes imports/exports, matches by stable value refs, detects ambiguity, unresolved imports, cycles, depth/provider limits, and policy blockers, synthesizes ordinary `Fabric.Route` / `Fabric.Plan` records, emits `LinkGraph`, `LinkPlan`, `LinkReport`, `LinkCertificate`, and creates executable `Assembly` values that can be preflighted, installed into Runspace, guest-checked, replayed, and handed off with metadata.

## Non-Goals/Out of Scope
No Boundary provider linking, Boundary normalization, TreatyResolver or ProviderHarness hot path, service discovery, package manager, artifact registry, network transport, storage backend, xitdb, scheduler thread, async runtime, real model/tool/file/human integration, provider lifecycle manager, WASM host package, Boundary LoadedModule.Session execution, cryptographic signing/encryption, cryptographic security claims, or agent framework.

## Interfaces/Types/APIs Impacted
- Add `src/linker.zig`, `world.Linker`, and ergonomic `world.Assembly` alias only if it does not bloat the root surface.
- Add Linker constants for policy, catalog, entry, indexes, matches, hints, route synthesis, graph, plan, report, certificate, and assembly fingerprint/format versions.
- Add `Linker.Input`, `Policy`, `Catalog`, `ImportIndex`, `ExportIndex`, `Match`, `RouteSynthesis`, `Graph`, `Plan`, `Report`, `Certificate`, and `Assembly`.
- Extend Fabric integration with `Linker.assertFabricInvariant(plan)` and synthesized ordinary Fabric routes only.
- Add additive hooks for Runspace assembly installation, Environment residual preflight, Admission assembly provenance, Supervision optional link/assembly fingerprints, Guest linked conformance metadata, and Handoff linked metadata/fail-closed active export behavior.
- Add examples, docs, build steps, tests, and lint boundary guards.

## Data Flow
1. Caller supplies a root target/module/import set and a closed local catalog; Linker does not fetch, scan, discover, or resolve externally.
2. Linker builds import/export indexes by target/module refs and stable value refs.
3. Each required import is matched against explicit candidate exports, hints, guest/replay/reject/adapter entries, and policy.
4. Ambiguous, mismatched, unresolved, cyclic, depth-exceeding, provider-limit-exceeding, inadmissible, unsupervised, or guest-unconformant candidates become deterministic blockers.
5. Accepted matches become ordinary Fabric routes with explicit value mappings, witnesses, provider identity refs, and parent response mapping.
6. LinkGraph records route/import/provider/environment/replay/guest/unresolved dependencies and blockers.
7. LinkPlan emits per-target Fabric plans, residual external environment requirements, provider usage, warnings, blockers, report, certificate, and optional executable Assembly.
8. Assembly installs the explicit Fabric plans through Runspace APIs only, and preflights residual environment/supervision/admission/guest/handoff metadata without executing handlers during linking.

## Tests/Acceptance
- Catalog: stable fingerprints, target/module/admitted-run/guest/replay/reject/environment entries, no pointer identity in fingerprints.
- Indexes: root/provider imports and exports are indexed deterministically and fingerprints are stable.
- Match and hints: exact value-ref matches pass; payload/response/count mismatches fail; ambiguity rejects under strict policy; hints resolve ambiguity without bypassing value, cycle, depth, supervision, admission, or guest policy.
- Route synthesis and invariant: target/export, replay, reject, guest/audit, and adapter coverage routes synthesize as ordinary Fabric routes; witnesses are complete; Fabric invariant check passes.
- Graph/Plan/Report/Certificate: unresolved/external/cycle/depth/provider-limit blockers are deterministic; closed, external, and partial plans are distinguished; certificates bind plan/graph/routes/matches/hints/policy.
- Assembly/integrations: assembly fingerprints are stable, residual ImportSet is correct, Environment preflight only requires residual imports, Runspace installs plans through public APIs, supervision budgets bind linked work, no handler calls occur during creation.
- Executable examples: one-provider, agent-tool residual environment, nested provider, ambiguity + hint, cycle rejection, and linked guest conformance.
- Regression: Fabric, Guest, Runspace, Admission, Supervision, Handoff, Timeline, Machine tests and examples remain green.

## Rollback/Abort Criteria
- Abort or split if Linker needs service discovery, package registry, artifact registry, network/storage/xitdb, scheduler, async runtime, provider lifecycle, real integrations, Boundary normalization/linking, TreatyResolver, ProviderHarness, Boundary LoadedModule execution, or cryptographic claims.
- Abort if route matching needs operation-name string dispatch, runtime handler pointer identity, allocator/thread/request-token identity, host callbacks, or cross-type coercion.
- Abort if Assembly installation requires direct Runspace mailbox mutation, parent resume bypass, or handler invocation during linking.
- Abort if Admission, Environment, Supervision, Guest, or Handoff invariants cannot be preserved through additive preflight/provenance hooks.

## Implementation Brief
1. step=linker-kernel-boundary; owner=implementation; success_criteria=`src/linker.zig`, `world.Linker`, version constants, root aliases, and kernel-boundary lint/test scaffolding compile and keep `src/world.zig` as facade.
2. step=policy-catalog-indexes; owner=implementation; success_criteria=Policy presets/fingerprints, Catalog entries/fingerprints, ImportIndex, ExportIndex, explicit provider descriptors, and stable value-ref compatibility tests pass.
3. step=matching-graph-blockers; owner=implementation; success_criteria=Match, Hint, blockers/warnings, ambiguity resolution, unresolved/external classification, graph nodes/edges, cycle/depth/provider-limit detection, and deterministic graph fingerprints pass focused tests.
4. step=route-plan-certificate; owner=implementation; success_criteria=RouteSynthesis emits ordinary Fabric routes/plans, mandatory Fabric invariant check passes, LinkPlan/Report/Certificate fingerprints bind policy/catalog/graph/routes/matches/hints and focused tests pass.
5. step=assembly-integrations; owner=implementation; success_criteria=Assembly residual import derivation, Runspace installation delegation, Environment preflight, Admission provenance, Supervision fingerprints/budget hooks, Guest linked conformance metadata, and Handoff metadata/fail-closed behavior pass focused tests.
6. step=examples-docs-build; owner=implementation; success_criteria=six linker examples, build run steps, README update, `docs/linker.md`, and check-step wiring compile and demonstrate one-provider, agent-tool, nested, ambiguity, cycle, and guest-conformance scenarios.
7. step=fixed-point-review; owner=verification; success_criteria=no duplicate truth owner, no unretired additive scaffold, no unresolved adversarial/ablation veto, no non-goal leak, no kernel-boundary breach, and one-change challenge produces no further required code change.
8. step=proof-closeout-ship; owner=verification; success_criteria=all requested format, diff, build, check, wasm, linker examples, existing examples, focused filters, full tests, and lint commands pass; `$st` projection is clean; `$ship` opens or updates a PR with proof.

Iteration: 1
</proposed_plan>
