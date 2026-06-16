# World Continuity

Capsules define the portable execution unit. Actuation receipts define host-effect evidence. Continuity remembers both as local causal facts.

## What is World Continuity?

World Continuity is World's local causal memory model for portable execution and host-effect evidence. It gives World deterministic refs, typed envelopes, an in-memory content-addressed vault, dependency graphs, portable bundles, lightweight indexes, and recovery preflight.

Continuity is not a storage backend. It defines the object model that future file stores, xitdb adapters, UIs, transfer mechanisms, and distributed runners should share.

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

## Ledger

`Continuity.Ledger` is a deterministic in-memory event log for vault operations. V1 logs vault initialization, capsule storage/validation/import/export, actuation receipt and journal storage, bundle import/export, and recovery preflight outcomes.

It deliberately does not log every Runspace, Fabric, Admission, Supervision, or scheduler event.

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

`Continuity.Recovery` validates before reconstruction. It can inspect capsules, preflight replay, preflight thaw, preflight pending actuation, replay an actuation response from stored receipt evidence, and preflight bundle import.

Recovery validates refs, capsule graph closure, actuation idempotency consistency, and missing dependencies. It does not mutate Runspace in v1, does not bypass Capsule thaw APIs, does not bypass Admission/Supervision/Actuation invariants, does not fetch network dependencies, and does not call fresh host actuators.

## Capsule store helpers

`Capsule.store`, `Capsule.load`, and `Capsule.exportBundle` delegate to `Continuity.MemoryVault` and `Continuity.Bundle`. Callers freeze first, then store the resulting image.

## Actuation store helpers

`Actuation.storeReceipt`, `Actuation.storeJournal`, `Actuation.loadReceipt`, `Actuation.loadJournal`, and `Actuation.replayFromVault` delegate to Continuity. Replay from vault returns a response from stored receipt evidence without a fresh host call.

## Future full Vault hooks

Future work can add automatic persistence hooks across Runspace, Fabric, Linker, Guest, Admission, Supervision, Capsule, and Actuation once the object model is proven.

V1 intentionally uses explicit store/load APIs first.

## Future xitdb adapter

An xitdb adapter can map `ObjectRef`, `ObjectEnvelope`, graphs, bundles, indexes, and ledger events onto durable storage later.

Continuity Core does not integrate xitdb and does not shape World around any production database.

## Non-goals

Continuity Core does not implement xitdb, a production database, file/directory storage, network transport, a scheduler, an async runtime, real model/tool/file/human integrations, provider lifecycle, service discovery, a WASM host package, Boundary closure or normalization, signing, encryption, exactly-once semantics, a package manager, an artifact registry, or credential/host-handle serialization.
