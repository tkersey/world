# World Actuation

Environment says what the host can provide. Actuation says how the host is allowed to commit an effect, and what receipt proves happened.

World Actuation is the deterministic protocol for host-side side effects. It does not add real model, tool, file, browser, network, storage, scheduler, async, signing, encryption, or human workflow integrations. It defines the object model those future integrations must satisfy.

## Actuation vs native handler

A native handler is an ergonomic Zig callback for a residual `WorldPort`. Actuation is the protocol around host effects: intent, envelope, policy decision, commit, response, receipt, journal, replay, and verify.

Native handlers may lower to `NativeFunctionActuator`, but function pointer identity is never part of an actuation fingerprint.

## Actuation vs Fabric provider

Fabric answers whether one admitted run can provide for another run. Actuation answers what happens when a residual port reaches the host boundary.

Fabric routes can now carry explicit actuation metadata. A route may satisfy a parent port through a provider run or through an actuator, but actuation is not discovered implicitly.

## Actuation vs Environment binding

Environment binds the host to imports. `Actuation.Binding` is one kind of host coverage: it connects an `ImportRequirement` to an `Actuation.Descriptor`.

Environment preflight can report actuation binding counts, missing actuators, policy blockers, value-policy blockers, and receipt requirements.

## Actuation classes

`Actuation.Class` is policy metadata:

- `observation`: read-only or externally non-mutating.
- `deterministic_fixture`: deterministic local test behavior.
- `idempotent_mutation`: retry with the same idempotency key is intended to be safe.
- `non_idempotent_mutation`: retry may duplicate effects.
- `irreversible_mutation`: cannot be safely undone.
- `compensatable_mutation`: may have a future compensation protocol.
- `human_gated`: requires explicit approval or defer.
- `unknown_effect`: fails closed under strict policy.

World does not prove real-world idempotency, reversibility, or compensation. It records local claims and enforces declared policy.

## ActuatorRef

`ActuatorRef` identifies an actuator declaration by stable metadata:

- kind and class
- label
- supported modes: fresh, replay, verify, audit
- supported response statuses
- value-policy fingerprint
- optional authority and protocol descriptor fingerprints
- metadata bytes

It excludes handler pointers, allocator/runtime/thread identity, credentials, URLs, request tokens, file/model/network handles, and host-owned implementation objects.

## ActuationDescriptor

`Actuation.Descriptor` binds an actuator ref to a WorldPort-compatible shape:

- WorldSurface and optional TargetRef fingerprints
- optional dense `world_port_id`
- optional WorldPort and source effect-shape refs
- payload and response value refs or table ids
- allowed response statuses
- kind, class, value policy, label, and metadata

Descriptors are target-neutral enough for future imported module surfaces, but they never include the actual host implementation pointer.

## ActuationBinding

`Actuation.Binding` connects a residual import requirement to a descriptor:

- TargetRef and WorldSurface fingerprints
- ImportRequirement fingerprint
- dense `world_port_id`
- ActuatorRef and descriptor fingerprints
- optional PortAuthority and EnvironmentCertificate fingerprints
- binding mode policy

Bindings can be used by Environment preflight, Runspace dispatch, and Fabric adapter routes.

## ActuationPolicy

`Actuation.Policy` is fail-closed by default for fresh effects. It controls:

- fresh, replay, verify, pending, deferred, rejected, and failed responses
- allowed classes
- idempotency-key requirements
- mutation and irreversible approval requirements
- portable-value requirements and native-only rejection
- receipt and journal requirements
- retry permission
- call, pending, response-byte, and metadata limits

Presets include `strict_fresh`, `strict_replay`, `verify_replay`, `fixture_test`, `audit_only`, `capsule_restore`, `handoff_receiver`, `no_irreversible`, and `human_gate_required`.

## IdempotencyKey

`Actuation.IdempotencyKey` binds:

- TargetRef and WorldSurface fingerprints
- dense `world_port_id`
- request fingerprint
- optional replay key, run handle, pending port, capsule, and intent fingerprints
- ActuatorRef fingerprint
- attempt scope
- metadata bytes

It excludes wall-clock time, runtime pointers, handler pointers, credentials, and request tokens. Hosts may keep external idempotency mappings outside World.

## Intent

`Actuation.Intent` is the side-effect request before authorization or commit. Creating an intent performs no host effect.

It binds actuator, descriptor, optional binding, target, surface, port id, optional pending port, frame request, optional payload value image, idempotency key, optional permit/environment/fabric/capsule refs, class, requested mode, and metadata.

An uncommitted intent is safe to freeze in a capsule when policy allows.

## Envelope

`Actuation.Envelope` is the portable host-call envelope. It binds the intent, encoded frame request or ref, payload value image or ref, idempotency key, expected response value ref/table, supervision refs, and metadata.

It carries no credentials, host pointers, request tokens, handles, or transport state.

## Decision

`Actuation.Decision` records local policy approval before commit. Statuses are approved, denied, deferred, cancelled, replay required, and verify required.

Denied, deferred, and cancelled decisions do not call the fresh implementation.

## Commit

`Actuation.Commit` records the attempt to perform or replay the effect. Statuses are not started, committed, commit pending, commit failed, replayed, verified, rejected, and cancelled.

Fresh commit can happen only after an approved decision. Replay commit never calls a fresh implementation. In-flight fresh commit is non-quiescent for capsule freeze.

## Response

`Actuation.Response` is actuator output before parent resume. Statuses are responded, rejected, failed, pending, deferred, and cancelled.

Responses must match the expected port, response kind, value shape, descriptor, and policy. They do not resume the parent directly; Runspace mailbox validation owns parent routing.

## Receipt

`Actuation.Receipt` is the deterministic record of what happened. It binds intent, envelope, decision, commit, response, actuator ref, idempotency key, target, surface, port id, class, mode, attempt number, booleans for fresh/replay/verify/pending/deferred/rejected/failed/cancelled, optional permit/environment/run/capsule refs, blockers, warnings, and metadata.

Receipts are deterministic local evidence, not cryptographic proof. A receiver may preserve sender receipts as evidence, but receiver-local permits and receipts are authority.

## Journal

`Actuation.Journal` is an in-memory run-local record of intents, decisions, commits, responses, receipts, idempotency keys, and request fingerprints.

It supports append operations, lookup by idempotency key or request fingerprint, duplicate fresh-commit checks, and summary counts. It is not the Continuity Vault, but it is store-ready for a future vault.

## Membrane

`Actuation.Membrane` executes the protocol:

1. Runspace has a pending port.
2. Environment, Fabric, or Linker chooses an actuation binding.
3. The membrane builds an intent.
4. Supervision checks policy, permit, and budget.
5. The membrane emits a decision.
6. If approved, it emits an envelope.
7. The actuator implementation is invoked only when fresh commit is allowed.
8. The membrane emits a commit.
9. The membrane emits a response.
10. The membrane emits a receipt.
11. Runspace validates the resulting frame response.
12. The parent resumes only for terminal allowed responses.

Denial happens before a fresh call. Replay-only mode never calls a fresh implementation.

## Replay and Verify actuators

`ReplayActuator` satisfies intents from receipts, transcript images, or journals by idempotency key or replay key. It validates request, port, and response kind and never calls fresh implementation.

`VerifyActuator` compares expected and fresh receipts and emits `Actuation.VerifyReport` with match status or divergence kind.

## Pending and Deferred actuations

Pending and deferred responses keep the parent parked. They are useful for human-gated or external approval flows without implementing a workflow engine.

Capsules can carry pending intents and completed receipts when policy allows.

## Capsule freeze/thaw behavior

Completed receipts freeze as evidence. Pending, deferred, prepared-but-uncommitted, and committed-but-unresumed states freeze only when their evidence is sufficient and policy permits it.

In-flight fresh commits are non-quiescent. On thaw, the receiver may replay from sender receipts, reject sender receipts as authority, or issue a local permit and call a local actuator. Idempotency keys prevent duplicate local fresh commits under strict policy.

## Guest bridge

Guest execution remains frame-based. A guest parks on `Frame.Request`; the host may satisfy that request through `Actuation.Membrane`. The guest does not learn the host implementation. Conformance vectors can include actuation receipt summaries.

## Supervision

Supervision tracks actuation intents, commits, fresh calls, replay calls, verify calls, pending/deferred/failed/rejected counts, irreversible counts, idempotent mutation counts, bytes, per-actuator usage, and per-port usage.

Policy denial happens before fresh host invocation.

## Future real actuators

Future model, tool, file, browser, and human adapters should implement the same protocol: stable actuator refs, descriptors, bindings, intents, envelopes, decisions, commits, responses, receipts, journals, replay, verify, pending/deferred behavior, and capsule evidence.

## Non-goals

World Actuation does not implement real model integration, tool registries, filesystem effects, browser effects, human workflow, network transport, storage backends, scheduler threads, async runtime, provider lifecycle, service discovery, WASM host packages, Boundary loaded execution, TreatyResolver or ProviderHarness hot paths, package management, artifact registries, signing, encryption, cryptographic security, or exactly-once distributed transactions.
