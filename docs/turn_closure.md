# World Turn Closure

A World turn is closed when its next state, outstanding effects, receipts, checkpoint, and causal history are completely represented by canonical bytes. A live process is an optimization, not part of the program's meaning.

## Portability Unit

The quiescent Appliance turn is the portable unit of World execution. Given unchanged universal runtime bytes, one sealed `Executable.Image`, a parent `Appliance.TurnClosure` or genesis, untrusted host resolutions, and receiver policy, World deterministically emits the next `TurnClosure`.

## Closure Invariant

Every semantic reference reachable from a `TurnClosure` must resolve through exactly one of:

- the immutable `Executable.Image`;
- the authenticated parent `TurnClosure`;
- canonical objects embedded in the next `TurnClosure`.

No required reference may depend on a local Target registry, generated Target type, native helper process, live WASM instance, process handle, filesystem path, implicit provider catalog, or external semantic lookup.

## Structure

`Appliance.TurnClosure` records format and fingerprint versions, executable and manifest fingerprints, parent closure identity, turn sequence, parent/result state fingerprints, Chronicle and Archive anchors, checkpoint bytes, executable Capsule bytes, TurnReceipt bytes, Continuity.Bundle evidence, optional Archive.AppendBatch bytes, pending HostRequest bytes, optional root-result bytes and ref, RunReceipt bytes, Actuation receipt and replay receipt bytes, VerifyReport bytes, blockers, warnings, and bounded diagnostics.

Advancing turns have exactly one resulting checkpoint, one executable Capsule, one TurnReceipt, one Chronicle transaction, and one Archive.AppendBatch. Completed closures include exact root-result bytes. Failed closures include deterministic failure evidence. `needs_host` closures include all currently external pending requests.

## Parent/Next Relation

The parent closure authenticates the prior state, Chronicle cursor, Archive anchors, pending requests, and receipt evidence. The next closure binds the consumed host submissions, all finalized receipts, the resulting checkpoint/Capsule, exact result bytes when complete, and the single Archive append that advances history.

## Bundle Evidence

Turn Closure uses `Continuity.Bundle`; it does not add another artifact graph. Bundle roots cover checkpoint, turn receipt, capsule image, loaded session image, run image, run receipt, frame request/response, value image, Actuation prepared/receipt/verify evidence, Fabric invocation/receipt, Archive append batch, and root result objects.

Validation checks the bundle manifest, every envelope, dependency closure, duplicate conflicts, Capsule graph, Actuation graph, Chronicle transaction, Archive parent/result anchors, HostRequest reachability from Capsule/mailbox state, consumed-host-submission correspondence, declared byte-image refs, and unresolved required references.

## Wire Input

`Appliance.Wire.TurnInput` is untrusted host input, not World evidence. It carries the operation (`boot`, `restore`, `continue`, `replay`, `verify`, `inspect`, `cancel`, or `reset`), manifest fingerprint, expected parent identities, root argument images for boot, parent closure bytes for cold restore, zero or more `ResolutionInput` records, optional `RetentionInput`, deterministic budget, evidence profile, and bounded metadata.

World decodes Wire input, validates it, canonicalizes resolution order by request identity, rejects duplicate or stale targets, validates value schemas and response kinds, and then constructs the internal Command, HostOutcome, HostReply, Actuation records, and causal evidence. Hosts cannot author Actuation receipts or TurnReceipts.

## HostRequest And ResolutionInput

`HostRequest` is World-authored prepared external work. `ResolutionInput` targets a prior HostRequest fingerprint and supplies a status, optional canonical response value image, bounded host claim bytes, attempt number, and metadata. Host claim bytes are evidence, not authority.

Partial batches are valid. Pending and deferred resolutions preserve the request. Terminal replies are consumed exactly once and finalized before newly runnable local/Fabric work advances.

## Internal Providers

The universal runtime supports one root module plus provider modules. Dispatch routes are sealed in the executable image and selected by residual requirement identity plus module fingerprint, not by operation label. Fabric performs route, depth, cycle, capacity, and supervision checks; Runspace transactionally installs the provider; provider completion commits exactly one parent response.

If a provider parks externally, the root remains parked on the Fabric invocation, the provider owns the external pending request, and the closure carries root, provider, mailbox, and invocation state.

## Active-Fabric Restore

Executable active Fabric Capsules carry executable image identity, dispatch identity, root/provider loaded session images, Runspace slots, parent/provider handles, mailbox entries, active invocation state, route/provider witnesses, value mappings, supervision evidence, usage, outstanding HostRequests, and Chronicle/Archive anchors.

Thaw validates executable and module fingerprints, loaded sessions, active routes, ownership, mailbox identities, mappings, receiver permit/policy, remaps, and restored invocation state before destination mutation.

## Replay

Replay is a positive execution mode. When a loaded session reaches a covered external import, World derives the expected intent and idempotency key, queries authenticated replay evidence, validates identity/schema/status, synthesizes a non-fresh Actuation receipt, resumes the mailbox, and continues without emitting a HostRequest.

Replay mismatch fails before mailbox consumption. Missing evidence follows explicit fallback policy or fails closed.

## Retry After Effect

World does not claim exactly-once effects. Deterministic retry means a host can retain the full World-authored idempotency key and `ResolutionInput`, lose the produced next closure before retaining the Archive append, restore the authoritative parent closure in a fresh runtime, resubmit the identical resolution, and obtain byte-identical closure, Capsule, TurnReceipt, Archive batch, root result, receipts, and state fingerprints.

## Archive Retention

Every advancing closure carries exactly one `Archive.AppendBatch`. The batch parent anchors equal the parent closure and resulting anchors equal the next closure. Hosts retain the bytes opaquely; World Archive scanning owns semantic recovery after crash windows.

## Foreign Hosts

Foreign hosts only need the independent Wire and loaded-value codecs. They decode manifests, HostRequests, TurnClosures, root results, TurnReceipts, and Archive metadata; encode untrusted TurnInput/ResolutionInput/RetentionInput; and route fixtures by ActuatorRef, descriptor fingerprint, Actuation class, and response schema. They do not implement ProgramPlan, Runspace, Fabric, Actuation receipts, Capsule thaw, Chronicle, Archive validation, or World evidence fingerprints.

## Memory Profile

The universal profile is bounded: one immutable loaded-image arena, one staging arena, image-derived memory-plan checks, fixed 64 MiB shipped WASM maximum, no allocator imports, no unbounded growth, no repeated module parsing per turn, and no second permanent full image copy.

## Non-Goals

Turn Closure does not add package discovery, module fetching, service discovery, package management, marketplaces, JIT, native shared libraries, WASI, WIT/Component Model, network transport, production storage, real model APIs, production tool registries, filesystem authority, scheduler threads, async runtime, multi-writer Archive coordination, live code upgrade, cross-image migration, exactly-once claims, signing, encryption, or cryptographic trust.
