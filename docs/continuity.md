# World Continuity

Capsules define the portable execution unit. Actuation receipts define host-effect evidence. Continuity remembers both as local causal facts.

## What is World Continuity?

World Continuity is World's local causal memory model for portable execution and host-effect evidence. It gives World deterministic refs, typed envelopes, an in-memory content-addressed vault, dependency graphs, portable bundles, lightweight indexes, and recovery preflight.

Continuity is not a storage backend. It defines the object model that future file stores, xitdb adapters, UIs, transfer mechanisms, and distributed runners should share.

Continuity Core stores facts. Chronicle records why those facts exist and how to replay local causal history.

## Why capsule-native?

`Capsule.Image` is the portable linked execution unit. It says what runspace, fabric, link, transcript, run, permit, receipt, admission, guest, dependency, and object evidence can move together.

Continuity stores capsules explicitly so World can answer whether a capsule has been seen, what it depends on, whether it is restorable or replayable, whether relink is required, and whether local actuators are needed before thaw.

## Why actuation-native?

`Actuation.Receipt` is the portable host-effect evidence unit. It records intent, envelope, decision, commit, response, actuator, idempotency key, target, port, mode, class, and status flags.

Continuity stores receipts and journals explicitly so World can answer whether an idempotency key has already committed, which receipts belong to a capsule, which actuation evidence can be replayed without a fresh host call, and where duplicate fresh commits would violate local policy.

## ObjectKind

`Continuity.ObjectKind` is the deterministic v1 kind set. It covers capsule objects, actuation objects, and selected core evidence objects such as frame requests/responses, value images, transcripts, run images/receipts, admissions, permits, linker certificates, assemblies, fabric receipts, guest conformance reports, and bundles.

It is intentionally not a universal dump of every World struct.

## ObjectRef

`Continuity.ObjectRef` identifies one stored object by ref format version, ref fingerprint version, ref fingerprint, object kind, object format version, object fingerprint, byte length, and optional diagnostic label/metadata.

Refs are deterministic and content-addressed. They are not cryptographic security claims. They exclude native pointers, allocator/runtime/thread identity, handlers, request tokens, credentials, URLs, file/model/network handles, and concrete ABI data.

## ObjectEnvelope

`Continuity.ObjectEnvelope` wraps canonical payload bytes with common storage metadata:

- envelope format and fingerprint versions
- object kind and object format version
- object content fingerprint and byte length
- explicit dependency refs
- payload bytes
- optional summary bytes, label, and metadata

Envelope validation checks payload fingerprint, envelope fingerprint, dependency refs, object size, and malformed encodings.

## MemoryVault

`Continuity.MemoryVault` is the v1 in-memory vault. It is append-oriented, content-addressed, and deduplicates identical objects.

It supports generic `put`, `get`, `has`, `listByKind`, `validate`, and `dependencies`, plus typed helpers for capsule images, actuation receipts, actuation journals, and idempotency-key lookup.

MemoryVault has no delete, file backend, xitdb integration, production database semantics, network fetch, signing, or encryption.

## Chronicle

`Continuity.Chronicle` is the local causal history layer for MemoryVault. It records deterministic events and commits, advances cursors, and rebuilds projections from committed events.

Chronicle is local and in-memory by default. It does not make cryptographic proof, durability, signing, encryption, transport, scheduler, async runtime, network, or exactly-once claims.

## Chronicle events

`Chronicle.Event` records why a fact exists: vault initialization, object staging/commit/rejection/validation, capsule store/import/export/recovery/replay, actuation receipt/journal/idempotency/replay/verify evidence, bundle import/export, inbox/outbox transitions, recovery preflight/execution/report storage, and guest report evidence.

Event fingerprints are deterministic. They bind event kind, parent event fingerprints, transaction fingerprint, object refs, capsule refs, actuation refs, bundle refs, recovery refs, inbox/outbox refs, target/module/assembly/run/permit/admission/environment refs, blockers, and warnings. Metadata may carry diagnostics, but authority-bearing host state is excluded: no wall-clock time, handler pointers, allocator/runtime/thread identity, request tokens, credentials, host handles, or network handles.

## Chronicle cursor

`Chronicle.Cursor` names a position in local history. It binds event index, last event fingerprint, cumulative prefix fingerprint, committed object count, committed transaction count, and optional metadata bytes.

Cursors are used for replay checkpoints, projection freshness, inbox/outbox views, and recovery provenance. A projection built at one cursor is stale at another cursor.

## Transaction lifecycle

`MemoryVault.beginTransaction(kind, options)` creates a staged local write group with a parent cursor. `tx.put`, `tx.putCapsule`, `tx.putActuationReceipt`, `tx.putActuationJournal`, `tx.putBundle`, and `tx.addEvent` stage objects and Chronicle events without mutating vault objects.

`tx.validate()` checks staged envelopes and conflicts. `tx.abort()` discards staged state. `tx.commit()` stores all staged objects and events atomically for MemoryVault, advances the Chronicle cursor, and records a `Chronicle.Commit` binding the transaction, parent/result cursors, committed object refs, and committed event fingerprints.

Duplicate identical objects deduplicate. Conflicting object refs reject. Strict local actuation policy rejects duplicate fresh commits under the same idempotency key. MemoryVault atomicity is in-memory only; it does not imply durable storage.

## Session and PersistPolicy

`Continuity.Session` coordinates a MemoryVault, Chronicle cursor, ledger summary, and persistence policy. It owns local continuity coordination; it does not own Runspace execution, transport, production storage durability, or real integrations.

`Continuity.PersistPolicy` is explicit and deterministic. The default persists nothing. Presets opt into capsule-only evidence, actuation-only evidence, capsule-and-actuation evidence, replay evidence, full local evidence, or test fixtures. Policy is not security authority and does not imply durability.

Session helpers store capsules, actuation receipts/journals, bundles, and recovery evidence through Chronicle transactions.

## Projection model

`Chronicle.Projection` rebuilds derived views from committed events. Projection kinds include capsule index, actuation index, object index, inbox, outbox, recovery queue, idempotency registry, and bundle history.

`Chronicle.ProjectionReport` binds projection kind, source cursor, consumed event count, consumed object refs, result summary fingerprint, blockers, and warnings. `Chronicle.ReplayReport` binds start cursor, end cursor, replayed event count, rebuilt projection count, mismatch count, blockers, and warnings.

Replaying the same committed events rebuilds the same CapsuleIndex and ActuationIndex summaries.

## IdempotencyRegistry

`Chronicle.IdempotencyRegistry` is a projection from actuation events and stored receipts. It records idempotency key refs, committed receipt refs, fresh commit count, replay receipt count, conflicts, and blockers.

Strict local policy rejects a duplicate fresh commit under the same key. Replay receipts with `fresh_called=false` do not conflict as fresh commits. This is local deterministic replay evidence, not distributed exactly-once semantics.

## ObjectGraph

`Continuity.ObjectGraph` builds a bounded dependency graph from root refs. It validates closure, reports missing dependencies, filters objects by kind, and exposes deterministic traversal order.

It does not implicitly fetch external dependencies or perform network resolution.

## CapsuleGraph

`Continuity.CapsuleGraph` is a specialized view for one stored capsule. It records capsule, manifest, certificate, runspace, fabric, link, transcript, run, permit, receipt, admission, actuation, journal, and guest refs.

It summarizes restore readiness, replay readiness, relink requirements, actuation replay feasibility, local fresh actuation requirements, and missing dependencies.

## ActuationGraph

`Continuity.ActuationGraph` is a specialized view for actuation receipts and journals. It records root receipt refs, intent/envelope/decision/commit/response/idempotency/capsule refs, pending refs, committed refs, replayable refs, verify refs, duplicate idempotency blockers, and fresh commit count.

It can build from a receipt, a journal, or an idempotency key.

## Bundle and BundleManifest

`Continuity.Bundle` is a portable collection of object envelopes. It can export roots from a vault, import into another vault, and validate serialized bundle bytes before import.

`Continuity.BundleManifest` binds roots, object count, bundle byte length, and manifest fingerprint. Strict validation rejects missing dependencies, unknown required object kinds, oversized bundles, duplicate conflicting objects, and duplicate fresh actuation commits for the same idempotency key.

Session bundle import/export is transaction-backed. Import parses bytes, validates the manifest/envelopes/dependency closure/idempotency conflicts, stages all objects, and commits only after validation passes. Export builds an ObjectGraph from roots, includes capsule and actuation dependencies according to options, validates the generated bundle, and records Chronicle export events.

## Ledger

`Continuity.Ledger` is a deterministic in-memory event log for vault operations. V1 logs vault initialization, capsule storage/validation/import/export, actuation receipt and journal storage, bundle import/export, and recovery preflight outcomes.

It deliberately does not log every Runspace, Fabric, Admission, Supervision, or scheduler event.

Ledger remains compatibility-oriented. Chronicle is the replayable event stream future storage adapters should preserve.

## CapsuleIndex

`Continuity.CapsuleIndex` is a linear-scan index over the memory vault. It answers:

- capsules by target
- capsules by module
- parked capsules
- completed capsules
- active Fabric capsules
- pending actuation capsules
- committed actuation capsules
- capsules needing relink

## ActuationIndex

`Continuity.ActuationIndex` is a linear-scan index over stored receipts and journals. It answers:

- receipts by actuator
- receipts by target
- receipts by target and dense world port id
- receipts by capsule
- intents by capsule
- pending actuations
- deferred actuations
- fresh commits
- replayed actuations
- lookup by idempotency key

## Recovery preflight

`Continuity.Recovery` validates before reconstruction. It can inspect capsules, preflight replay, preflight thaw, preflight pending actuation, replay an actuation response from stored receipt evidence, preflight bundle import, and record executable recovery evidence.

`Continuity.RecoveryPlan` binds the source Chronicle cursor, requested mode, capsule ref, target/module match refs, link verification status, environment/permit refs, actuation replay refs, local-fresh requirements, idempotency conflict blockers, runspace mutation plan, handle/mailbox remap plans, blockers, and warnings.

`Continuity.RecoveryReport` binds the plan, accepted flag, resulting Chronicle cursor, restored capsule ref, restored run handles, pending ports, actuation refs, receiver permit ref, blockers, and warnings.

Executable recovery denies before Runspace mutation when blockers exist. When ready, it calls Capsule thaw/replay owner APIs and records Chronicle events for preflight, readiness/rejection, execution, and report storage. Recovery does not bypass Capsule quiescence, Linker relink checks, Admission/Supervision/Actuation invariants, fetch network dependencies, deserialize handlers or host handles, or call fresh host actuators outside local policy.

## Capsule store helpers

`Capsule.store`, `Capsule.load`, and `Capsule.exportBundle` delegate to `Continuity.MemoryVault` and `Continuity.Bundle`. Callers freeze first, then store the resulting image.

`Capsule.freezeToSession`, `Capsule.freezeAssemblyToSession`, and `Capsule.freezeRunToSession` freeze through owner Capsule APIs, stage the resulting image in a Chronicle transaction, validate closure, commit atomically, and emit capsule store/validation events. Non-quiescent state fails before commit.

## Actuation store helpers

`Actuation.storeReceipt`, `Actuation.storeJournal`, `Actuation.loadReceipt`, `Actuation.loadJournal`, and `Actuation.replayFromVault` delegate to Continuity. Replay from vault returns a response from stored receipt evidence without a fresh host call.

`Actuation.commitToSession`, `Actuation.journalToSession`, and `Actuation.assertIdempotencyAvailable` route actuation evidence through `Continuity.Session`. Fresh commits register idempotency evidence; duplicate fresh commits reject under strict local policy; replay receipts with `fresh_called=false` are accepted as evidence.

## Inbox and Outbox

`Chronicle.Inbox` and `Chronicle.Outbox` are local projections over `Continuity.HandoffEnvelope` refs and Chronicle events. Outbox can stage a capsule and export a bundle. Inbox can import bundle bytes, inspect, validate, plan recovery, accept, or reject.

Inbox/outbox do not implement network, transport, scheduling, or delivery. They are local causal state.

## Persistence sinks

`Continuity.Sink` is an optional bridge from kernel events into a `Continuity.Session`. It can record configured capsule, actuation receipt, actuation journal, and guest report evidence.

No sink means no automatic persistence. Sink failure is explicit. Sink does not own Runspace, Fabric, Supervision, transport, or real integrations and cannot bypass owner APIs.

## Future full Vault hooks

Future work can add automatic persistence hooks across Runspace, Fabric, Linker, Guest, Admission, Supervision, Capsule, and Actuation once the object model is proven.

V1 intentionally uses explicit store/load APIs first.

## Future xitdb adapter

An xitdb adapter can map `ObjectRef`, `ObjectEnvelope`, committed Chronicle events, cursor checkpoints, commits, projection reports, bundles, and compatibility ledger events onto durable storage later.

Chronicle gives future adapters one local append-only event stream and transaction model to persist instead of inventing adapter-specific semantics. Continuity still does not integrate xitdb and does not shape World around any production database.

## Non-goals

Continuity and Chronicle do not implement xitdb, a production database, file/directory storage, network transport, a scheduler, an async runtime, real model/tool/file/human integrations, provider lifecycle, service discovery, a WASM host package, Boundary closure or normalization, signing, encryption, exactly-once semantics, a package manager, an artifact registry, broad implicit persistence, or credential/host-handle serialization.
