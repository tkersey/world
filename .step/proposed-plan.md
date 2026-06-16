<proposed_plan>
Iteration: 7

# World Continuity Core Execution Plan

## Summary
Build World Continuity Core as an additive `world.Continuity` namespace in `src/world.zig`, with first execution wave focused on deterministic object identity, typed envelopes, minimal Actuation receipt/journal codecs, and `MemoryVault`. Later waves layer graphs, bundles, ledger, indexes, recovery preflight, helpers, examples, docs, and build wiring. Done means the requested APIs exist, existing Capsule/Actuation authority remains intact, all Continuity examples and focused tests pass, `zig build check --summary all` remains green, and wasm checks still pass.

Chosen strategy: keep Continuity capsule-and-actuation-native, in-memory, explicit-store/load only, and non-authoritative. Storage and transport remain future adapters; recovery preflight validates and reports but never mutates `Runspace`.

## Implementation Brief
1. step=core_identity_envelope; owner=implementation agent; success_criteria=`world.Continuity` constants, ObjectKind, ObjectRef, ObjectEnvelope, ObjectValidationReport, and internal ObjectCodec compile with focused ObjectRef/ObjectEnvelope tests.
2. step=typed_codecs_memory_vault; owner=implementation agent; success_criteria=Actuation receipt/journal encode/decode round-trip, MemoryVault typed capsule/receipt/journal put/get/list/dedup/idempotency tests pass.
3. step=graphs; owner=implementation agent; success_criteria=ObjectGraph, CapsuleGraph, and ActuationGraph build deterministic closures, report missing deps/cycles, and classify replayable/pending/fresh/duplicate evidence.
4. step=bundles_ledger; owner=implementation agent; success_criteria=Bundle export/import/validate is all-or-nothing, strict duplicate fresh commit checks work, ledger event order/fingerprints are stable.
5. step=indexes_recovery; owner=implementation agent; success_criteria=CapsuleIndex and ActuationIndex answer all requested linear-scan queries; Recovery APIs inspect/preflight/replay without mutating Runspace.
6. step=helper_apis; owner=implementation agent; success_criteria=Capsule and Actuation store/load/export/replay helpers delegate to Continuity without root API sprawl.
7. step=examples_build_docs; owner=implementation agent; success_criteria=five examples exist, `build.zig` run steps and expected stdout are added, README and `docs/continuity.md` explain Continuity and non-goals.
8. step=fixed_point_review; owner=verification; success_criteria=no duplicate truth owner, no unretired additive scaffold, no unresolved adversarial/ablation veto, no non-goal leak, no envelope-only authority path, and one-change challenge produces no further required code change.
9. step=proof_closeout_ship; owner=verification; success_criteria=all proof commands pass, `$st` projection is clean, and `$ship` opens or updates a PR with proof.

## Interfaces/Types/APIs Impacted
- Add public `world.Continuity` namespace and optional `world.MemoryVault` alias.
- Add Continuity constants, `ObjectKind`, `ObjectRef`, `ObjectEnvelope`, `ObjectValidationReport`, `ObjectGraph`, `CapsuleGraph`, `ActuationGraph`, `MemoryVault`, `Bundle`, `BundleManifest`, `Ledger`, `CapsuleIndex`, `ActuationIndex`, and `Recovery`.
- Add minimal canonical encode/decode for `Actuation.Receipt` and `Actuation.Journal`.
- Add `Capsule.store`, `Capsule.load`, `Capsule.exportBundle`, `Actuation.storeReceipt`, `Actuation.storeJournal`, `Actuation.loadReceipt`, `Actuation.loadJournal`, and `Actuation.replayFromVault`.
- Add five `examples/world_continuity_*.zig` files and corresponding build run steps.
- Update `README.md` and add `docs/continuity.md`.

## Non-Goals/Out of Scope
No xitdb, production database, file/directory storage backend, network/transport, scheduler, async runtime, provider lifecycle, service discovery, real model/tool/file/browser/human integrations, WASM host package, Boundary closure/normalization, TreatyResolver hot path, ProviderHarness hot path, package manager, artifact registry, signing, encryption, cryptographic security claims, exactly-once semantics, credential serialization, host-handle serialization, request-token serialization, URL/file/model/network handle serialization, or broad auto-persistence hooks.

## Proof Commands
- `zig version`
- `zig fmt --check build.zig src examples test`
- `git diff --check`
- `zig build --summary all`
- `zig build check --summary all`
- `zig build world-wasm`
- `zig build check-world-wasm`
- `zig build run-world-continuity-capsule-basic`
- `zig build run-world-continuity-actuation`
- `zig build run-world-continuity-bundle-roundtrip`
- `zig build run-world-continuity-pending-actuation`
- `zig build run-world-continuity-agent-evidence`
- `zig build test --summary none -- --test-filter "continuity"`
- `zig build test --summary none -- --test-filter "object ref"`
- `zig build test --summary none -- --test-filter "object envelope"`
- `zig build test --summary none -- --test-filter "memory vault"`
- `zig build test --summary none -- --test-filter "object graph"`
- `zig build test --summary none -- --test-filter "capsule graph"`
- `zig build test --summary none -- --test-filter "actuation graph"`
- `zig build test --summary none -- --test-filter "bundle"`
- `zig build test --summary none -- --test-filter "ledger"`
- `zig build test --summary none -- --test-filter "capsule index"`
- `zig build test --summary none -- --test-filter "actuation index"`
- `zig build test --summary none -- --test-filter "recovery"`
- `zig build test --summary none -- --test-filter "vault capsule"`
- `zig build test --summary none -- --test-filter "vault actuation"`
- `zig build lint -- --max-warnings 0`

</proposed_plan>
