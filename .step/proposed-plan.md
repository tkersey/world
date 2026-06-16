<proposed_plan>
Iteration: 7

# World Chronicle Kernel Execution Plan

## Summary
Implement World Chronicle Kernel by making `world.Continuity.Chronicle` the canonical local causal-history layer over `MemoryVault`. The chosen path is additive and owner-boundary aligned: first build deterministic Event/Cursor/Commit/Transaction atomicity, then Session/Policy, projections/idempotency, transactional bundle/inbox/outbox, executable recovery, sinks, examples, docs, and full proof. The first execution wave is the Chronicle core in `src/world.zig` with focused tests proving staged writes do not mutate and commits replay. Done means every requested example and focused filter passes, existing kernel regressions remain green, and replay from committed Chronicle entries rebuilds the same vault-backed CapsuleIndex/ActuationIndex summaries.

## Interfaces/Types/APIs Impacted
- `world.Continuity.Chronicle`: add `Event`, `Commit`, `Transaction`, `Cursor`, `Projection`, `ProjectionReport`, `ReplayReport`, `Inbox`, `Outbox`, and `IdempotencyRegistry`.
- Version constants: add requested Chronicle, commit, cursor, transaction, and persist-policy fingerprint/format constants near existing Continuity constants.
- `Continuity.MemoryVault`: add Chronicle state, `beginTransaction(kind, options)`, current cursor, committed event/commit log, and internal commit backing entries with cloned `ObjectEnvelope` writes.
- `Continuity.Session`: add `init`, `begin`, `storeCapsule`, `storeActuationReceipt`, `storeActuationJournal`, `importBundle`, `exportBundle`, `recovery`, `projections`, and `cursor`.
- `Continuity.PersistPolicy`: add fields and presets `none`, `capsule_only`, `actuation_only`, `capsule_and_actuation`, `replay_evidence`, `full_local_evidence`, `test_fixture`; default is `none`.
- `Continuity.RecoveryPlan`, `RecoveryReport`, `RestoredCapsule`: add executable recovery evidence types and APIs under `Continuity.Recovery`.
- `Continuity.Sink`, `SinkPolicy`, `HandoffEnvelope`: add optional persistence bridge and inbox/outbox envelope model.
- `Capsule`: add `freezeToSession`, `freezeAssemblyToSession`, `freezeRunToSession`.
- `Actuation`: add `commitToSession`, `journalToSession`, `assertIdempotencyAvailable`.
- `Continuity.Bundle`: keep existing import/export helpers source-compatible; implement transaction-backed session variants and preserve existing validation semantics.
- `CapsuleIndex` and `ActuationIndex`: add `sourceCursor`, `assertFresh`, and requested query APIs.
- `build.zig`, `examples/`, `README.md`, `docs/continuity.md`, and `test/world_test.zig`: add examples, run steps, docs, and focused tests.

## Non-Goals/Out of Scope
- Do not integrate xitdb, production database storage, filesystem-backed storage, network/transport, scheduler, async runtime, provider lifecycle, service discovery, or WASM host package.
- Do not implement real model/tool/file/browser/network/human integrations.
- Do not implement Boundary closure/normalization, TreatyResolver hot-path calls, ProviderHarness hot-path calls, signing, encryption, credential serialization, request-token serialization, host-handle serialization, or exactly-once semantics.
- Do not auto-persist every kernel by default; persistence remains explicit through `Continuity.Session`, `PersistPolicy`, and optional sinks.

## Data Flow
1. `MemoryVault.init` creates empty object storage, initial Chronicle cursor, and a deterministic non-transactional `vault_initialized` event with `committed_transaction_count=0`.
2. `session.begin(kind)` or `vault.beginTransaction(kind, options)` snapshots the parent cursor and stages cloned envelopes, domain refs, validation reports, idempotency refs, and Chronicle events without mutating vault objects.
3. `tx.validate()` checks envelope validity, duplicate identical/conflicting objects, dependency closure, idempotency conflicts, event authority fields, parent event refs, and capacity/ownership needed for atomic commit.
4. `tx.commit()` pre-reserves event/commit/cursor capacity, transfers or clones staged envelopes into `MemoryVault.objects`, appends Chronicle events, records a public `Chronicle.Commit`, stores the internal backing entry with committed envelopes, advances the cursor, and emits compatibility ledger observations.
5. `tx.abort()` releases staged objects/events and leaves objects, Chronicle logs, cursor, commits, and ledger unchanged.
6. `Chronicle.replay(vault, options)` can rebuild projections from committed events and can rebuild an empty replay vault from internal commit backing entries; public reports bind start/end cursors and mismatch counts.
7. Projection rebuilds consume Chronicle events in order, read replayed vault objects for payload-derived summaries, and reject stale use through `assertFresh(cursor)`.
8. Recovery planning stores a cursor-bound plan before Runspace mutation; execution validates the plan against current cursor/idempotency/env/permit state, calls owner APIs only after blockers are empty, and records report events after mutation.
9. Inbox/outbox state is materialized only from `HandoffEnvelope` objects and Chronicle events; transport, scheduling, and network remain absent.

## Tests/Acceptance
- Add focused test groups matching the user filters: `chronicle`, `chronicle event`, `chronicle cursor`, `chronicle transaction`, `chronicle commit`, `continuity session`, `persist policy`, `projection`, `idempotency registry`, `executable recovery`, `freeze to session`, `actuation to session`, `inbox`, and `outbox`.
- Add conformance harness scenarios that execute the same capsule/actuation/bundle/recovery flow through direct session commit, Chronicle replay, and bundle import/export, then compare projection summaries.
- Add example programs and build steps: `run-world-chronicle-capsule-commit`, `run-world-chronicle-actuation-idempotency`, `run-world-chronicle-replay-projection`, `run-world-chronicle-bundle-inbox`, `run-world-chronicle-recovery`, `run-world-chronicle-agent-evidence`.
- Required proof commands after implementation: `zig fmt --check build.zig src examples test`, `git diff --check`, `zig build --summary all`, `zig build check --summary all`, `zig build world-wasm`, `zig build check-world-wasm`, all six new example steps, focused filters, and `zig build lint -- --max-warnings 0`.
- Existing Continuity, Actuation, Capsule, Linker, Fabric, Guest, Runspace, Admission, Supervision, Handoff, Timeline, Machine, and wasm checks must remain green.

## Implementation Brief
1. step=chronicle_core_records; owner=implementation_agent; success_criteria=add Chronicle constants, Event/Cursor/Commit structs, fingerprint/validation helpers, and focused event/cursor/commit tests pass.
2. step=chronicle_transaction_atomicity; owner=implementation_agent; success_criteria=add vault Chronicle state, transaction staging, validate/abort/commit, internal commit backing log, rollback tests, and no-mutation-before-commit tests pass.
3. step=session_policy_helpers; owner=implementation_agent; success_criteria=add `Continuity.Session`, `PersistPolicy`, session capsule/actuation store paths, and preserve existing direct helper compatibility.
4. step=replay_projection_registry; owner=implementation_agent; success_criteria=add replay/projection infrastructure, projection reports, replay reports, cursor freshness, and idempotency registry tests.
5. step=bundle_inbox_outbox; owner=implementation_agent; success_criteria=make bundle import/export transaction-backed in session paths and add inbox/outbox handoff envelope projections.
6. step=executable_recovery; owner=implementation_agent; success_criteria=add executable RecoveryPlan/RecoveryReport/RestoredCapsule APIs with deny-before-mutation and owner API boundary tests.
7. step=session_sink_domain_helpers; owner=implementation_agent; success_criteria=add freeze-to-session, actuation-to-session, optional ContinuitySink hooks, and sink failure/no-implicit-persistence tests.
8. step=examples_docs_build; owner=implementation_agent; success_criteria=add six Chronicle examples, build steps, README/docs updates, and deterministic stdout checks.
9. step=proof_closeout_ship; owner=implementation_agent; success_criteria=run focused Chronicle filters, all new examples, `zig fmt --check build.zig src examples test`, `git diff --check`, `zig build --summary all`, `zig build check --summary all`, `zig build world-wasm`, `zig build check-world-wasm`, and `zig build lint -- --max-warnings 0`; inspect final diff, confirm non-goals remain absent, assert `$st` projection, and ship PR.

</proposed_plan>
