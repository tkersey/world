# World Linker

Fabric executes explicit routes. Linker synthesizes explicit routes from a closed set of known modules.

## What is World Linker?

World Linker is a deterministic closed-world assembly linker. Given a root target or module, root import requirements, and an explicit local catalog of candidate providers, it answers which imports can be satisfied by explicit Fabric routes, which imports remain residual environment requirements, and whether the resulting assembly is executable under policy.

It is caller-driven and in-memory. It does not fetch providers, scan filesystems, query networks, discover services, or resolve packages.

## Linker vs Fabric

Fabric owns executable routes and route evidence. `world.Fabric.Route` and `world.Fabric.Plan` are the records Runspace executes.

Linker owns route synthesis and graph reasoning. It builds matches from a closed catalog, detects blockers, emits ordinary Fabric routes, and produces witnesses that explain why those routes exist.

## Linker vs Boundary Normalization

Boundary owns algebra, normalization, Certified Boundary Modules, target-neutral WorldSurface metadata, and semantic import/export facts. World Linker consumes those facts as already-normalized metadata.

Linker does not run Boundary normalization, relink Boundary providers, call TreatyResolver, call ProviderHarness, or execute Boundary loaded modules.

## Linker vs Service Discovery

The catalog is explicit input. A missing provider remains missing unless the caller supplies it. Hints are deterministic tie-breakers inside that closed set; they are not lookup, discovery, fallback, package resolution, or registry access.

## Catalog

`world.Linker.Catalog` is the closed provider set. Entries can represent generated targets, module refs, admitted runs, guest providers, replay providers, reject routes, and environment adapters when policy permits.

Each entry fingerprints provider kind, target/module identity, export summary, import set, nested imports, admission/environment/permit witnesses, guest/replay witnesses, label, and metadata. Fingerprints exclude handler pointers, runtime pointers, allocator/thread identity, request tokens, credentials, network handles, storage handles, and discovery state.

## Import and Export Indexes

`ImportIndex` exposes root imports and provider nested imports by target ref. `ExportIndex` exposes candidate exports and provider descriptors by target ref.

Indexes are deterministic summaries, not mutable registries. They do not fetch missing providers or infer new modules.

## Matching Rules

`world.Linker.Match` records why a provider export can satisfy a parent import. Match kinds include exact value refs, same-schema compatible refs when policy allows, explicit hints, replay, adapter, guest, reject, and unsupported.

Strict policy rejects ambiguous providers, cross-type conversions, value-ref mismatches, missing providers, cycle/depth violations, unsupported nested imports, missing guest conformance, and inadmissible providers.

## Explicit Hints

`world.Linker.Hint` can name a parent target/port and a provider target/module/export. A hint can resolve ambiguity but cannot bypass value compatibility, supervision policy, admission policy, guest-conformance requirements, cycle checks, or depth checks.

## Route Synthesis

Accepted matches become ordinary `world.Fabric.Route` records. Route synthesis includes parent port identity, provider identity, export evidence, response value mapping, bindings, route witnesses, and deterministic route fingerprints.

`Linker.assertFabricInvariant(plan)` validates synthesized plans before they are exposed as executable Fabric plans.

## LinkGraph

`world.Linker.Graph` records target/module nodes, import nodes, export nodes, route nodes, environment external nodes, replay source nodes, and unresolved nodes.

Edges record target requires import, route satisfies import, route invokes provider, provider requires nested import, environment satisfies import, and replay satisfies import. The graph reports cycles, unresolved required imports, ambiguity, depth violations, and provider-run limit violations.

## LinkPlan

`world.Linker.Plan` is the synthesized output. It binds policy, catalog, graph, Fabric plans, route syntheses, unresolved imports, residual environment requirements, provider/guest/replay/reject usage, blockers, warnings, and normal form.

Normal forms are `closed_fabric`, `fabric_with_external_ports`, `partial_with_blockers`, and `inspect_only`.

## LinkReport and Certificate

`world.Linker.Report` summarizes accepted/rejected state, candidate count, import counts, route count, Fabric plan count, blocker counts, and summary text.

`world.Linker.Certificate` is deterministic witness metadata. It binds the LinkPlan, LinkGraph, Report, root target, catalog, Fabric plan fingerprints, route fingerprints, match fingerprints, hint fingerprints, policy fingerprint, and blocker/warning summary. It is not cryptographic.

## Assembly

`world.Assembly` is an executable local composition result. It binds the root target, LinkPlan fingerprint, Linker certificate fingerprint, optional environment/permit/admission witnesses, Fabric plans, residual imports, provider templates, and guest templates.

Assembly does not execute by itself. It installs explicit Fabric plans into Runspace through `installAssembly` or `assembly.installIntoRunspace`.

## Residual Environment Requirements

When Linker resolves some imports through Fabric and leaves others external, the residual import set contains only the unresolved external requirements.

For an agent root with `model.decide` and `tool.call`, a linked tool provider can cover `tool.call` while `model.decide` remains an Environment requirement.

## Linked Agent Tool Example

`examples/world_linker_agent_tool.zig` links a tool provider from a closed catalog, installs the synthesized assembly into Runspace, routes `tool.call` through Fabric, leaves the model port residual, and prints resolved and residual import counts.

## Nested Provider Example

`examples/world_linker_nested_provider.zig` synthesizes root-to-provider and provider-to-nested-provider assemblies, installs both into Runspace, and completes through the nested Fabric route chain.

## Ambiguity and Hints

`examples/world_linker_ambiguity.zig` shows strict policy rejecting two compatible providers, then accepting the same graph when an explicit hint selects one provider.

## Cycle and Depth Control

`examples/world_linker_cycle_blocked.zig` uses a self-provider candidate and reports the cycle blocker before Runspace mutation.

## Guest Conformance

`examples/world_linker_guest_conformance.zig` binds a Linker-generated assembly to a Guest conformance report fingerprint. Guest conformance is evidence attached to the assembly; Linker does not implement a guest runtime.

## Kernel Boundaries

Linker may construct `Fabric.Route` and `Fabric.Plan`. Linker may not mutate Runspace mailbox state, call handlers, resume parent requests, bypass Environment/Admission/Supervision preflight APIs, import Boundary TreatyResolver or ProviderHarness, perform Boundary normalization, or dispatch by operation-name strings on the hot path.

## Non-goals

World Linker does not implement service discovery, package management, artifact registries, network transport, storage, xitdb, scheduler threads, async runtimes, real model/tool/file/human integrations, provider lifecycle management, Boundary provider linking, Boundary normalization, TreatyResolver or ProviderHarness hot paths, Boundary loaded-module execution, WASM host packages, signing, encryption, cryptographic security, or an agent framework.
