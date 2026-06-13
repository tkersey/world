<proposed_plan>
Iteration: 5

# World Actuation Kernel Execution Plan

## Summary
Add the World Actuation Kernel: a deterministic host-side side-effect protocol for residual WorldPort requests that reach the host boundary. Actuation introduces explicit actuator declarations, descriptors, bindings, policies, idempotency keys, intents, envelopes, decisions, commits, responses, receipts, journals, replay/verify sources, a membrane, Runspace dispatch, supervision accounting, environment preflight, Fabric/Linker/Guest/Capsule/Handoff/Admission integration, examples, docs, and proof lanes. This is a protocol kernel only: no real model/tool/file/human integrations, storage, network transport, scheduler, async runtime, crypto, or exactly-once claims.

## Non-Goals
No real OpenAI/model integration, real filesystem integration, real browser integration, real human workflow, network transport, storage backend, xitdb, production database, scheduler thread, async runtime, service discovery, provider lifecycle manager, WASM host package, Boundary LoadedModule execution, Boundary closure/normalization, TreatyResolver hot path, ProviderHarness hot path, package manager, artifact registry, signing/encryption, cryptographic security claims, exactly-once distributed transactions, handler pointer serialization, credentials, host handles, URLs, request tokens, runtime pointers, allocator pointers, or thread pointers.

## Governing Invariants
1. Boundary owns normalized semantics; World owns host actuation protocol and execution timelines.
2. Environment says what the host can provide; Actuation says how the host is allowed to commit an effect and what receipt proves what happened.
3. Runspace mailbox remains the owner of pending ports; ActuationResponse cannot resume a parent directly and must pass mailbox validation.
4. No fresh host effect happens without Intent, IdempotencyKey where policy requires it, approved Decision, Supervision allowance, Commit, Response, and Receipt.
5. Denial, defer, replay-required, verify-required, and cancellation happen before any fresh actuator implementation call.
6. Replay mode never calls fresh implementation; replay-only receipts must have `fresh_called = false`.
7. ActuatorRef, Descriptor, Binding, Intent, Envelope, Decision, Commit, Response, Receipt, Journal, and VerifyReport fingerprints exclude implementation identity, credentials, tokens, URLs, runtime/allocator/thread pointers, and host handles.
8. Capsule freeze admits completed receipts and policy-allowed prepared/pending/deferred intents; in-flight fresh commit is non-quiescent.
9. Receiver policy owns authority after handoff; sender actuation receipts remain evidence unless receiver-local replay/verify/fresh policy accepts them.
10. Actuation objects are continuity-ready deterministic records, but no storage backend is added.

## Implementation Brief
1. step=core_actuation_model; owner=implementation; success_criteria=`world.Actuation` namespace, public aliases, version constants, `Kind`, `Class`, `Ref`, `Descriptor`, `Binding`, `Policy`, `IdempotencyKey`, `Intent`, `Envelope`, `Decision`, `Commit`, `Response`, `Receipt`, `Journal`, `ReplaySource`, `VerifyReport`, deterministic fingerprints, validators, policy presets, object/dependency summaries, and focused core tests compile and pass.
2. step=actuator_interfaces_and_membrane; owner=implementation; success_criteria=Fixture, NativeFunction, Replay, Verify, ByteProtocol, Reject, Pending, and Deferred actuators execute through `Actuation.Membrane`; denial happens before fresh call; replay does not call fresh implementation; verify reports divergences; pending/deferred do not resume parent; receipts are emitted.
3. step=environment_runspace_supervision; owner=implementation; success_criteria=Environment exposes `world.actuator`, `world.bindActuator`, `Environment.bindActuator`, and `preflightActuation`; Runspace dispatch APIs route through mailbox validation and preserve pending/deferred mailbox state; Supervision policy/budget/ledger/run receipts track actuation counts, classes, bytes, per-actuator/per-port usage, and deny before invocation.
4. step=fabric_linker_guest; owner=implementation; success_criteria=Fabric adapter routes can target actuation and record `ActuationReceipt`; provider nested ports can use actuation; Linker catalogs explicit actuation external candidates without implicit discovery; Guest frame bridge is satisfied by ActuationMembrane and conformance vectors include receipt summaries.
5. step=capsule_handoff_admission; owner=implementation; success_criteria=Capsules freeze/thaw pending, deferred, and completed actuation states under policy; in-flight commits are non-quiescent; committed-but-unresumed requires response/receipt evidence; thaw can replay sender receipt or call receiver-local actuator with new permit; Admission/Handoff reports actuation metadata, required actuators, receipts, replay/verify feasibility, and receiver local remapping.
6. step=examples_docs_build; owner=implementation; success_criteria=required actuation examples and build steps are added; README and `docs/actuation.md` explain Actuation vs native handlers/Fabric/Environment, classes, refs, descriptors, bindings, policy, idempotency, intent/envelope/decision/commit/response/receipt, journal, membrane, replay/verify, pending/deferred Capsules, Guest bridge, Supervision, future integrations, and non-goals.
7. step=fixed_point_review; owner=verification; success_criteria=no duplicate truth owner, no unretired additive scaffold, no non-goal leak, no fresh-call bypass, no pointer/credential/token serialization, no mailbox bypass, no replay fresh-call path, no unsafe capsule in-flight freeze, and one-change challenge produces no further required code change.
8. step=proof_closeout_ship; owner=verification; success_criteria=all requested format, diff, build, check, wasm, actuation examples, existing example matrix, focused filters, full tests, lint commands pass; `$st` projection is clean; `$ship` opens or updates a PR with proof.

## Proof Commands
- `zig version`
- `zig fmt --check build.zig src examples test`
- `git diff --check`
- `zig build --summary all`
- `zig build check --summary all`
- `zig build world-wasm`
- `zig build check-world-wasm`
- `zig build run-world-actuation-fixture-tool`
- `zig build run-world-actuation-agent`
- `zig build run-world-actuation-replay-verify`
- `zig build run-world-actuation-pending-capsule`
- `zig build run-world-actuation-supervised-denial`
- `zig build run-world-actuation-guest-bridge`
- `zig build run-world-actuation-idempotent-retry`
- `zig build run-world-actuation-deferred-approval` if added
- existing Capsule/Linker/Fabric/Guest/Runspace/Admission/Supervision/Handoff/Timeline/Machine example matrix
- `zig build test --summary none -- --test-filter "actuation"`
- `zig build test --summary none -- --test-filter "actuator ref"`
- `zig build test --summary none -- --test-filter "actuation descriptor"`
- `zig build test --summary none -- --test-filter "actuation binding"`
- `zig build test --summary none -- --test-filter "actuation policy"`
- `zig build test --summary none -- --test-filter "idempotency"`
- `zig build test --summary none -- --test-filter "actuation intent"`
- `zig build test --summary none -- --test-filter "actuation envelope"`
- `zig build test --summary none -- --test-filter "actuation decision"`
- `zig build test --summary none -- --test-filter "actuation commit"`
- `zig build test --summary none -- --test-filter "actuation response"`
- `zig build test --summary none -- --test-filter "actuation receipt"`
- `zig build test --summary none -- --test-filter "actuation journal"`
- `zig build test --summary none -- --test-filter "actuation replay"`
- `zig build test --summary none -- --test-filter "actuation verify"`
- `zig build test --summary none -- --test-filter "actuation membrane"`
- `zig build test --summary none -- --test-filter "actuation capsule"`
- `zig build test --summary none -- --test-filter "actuation guest"`
- `zig build lint -- --max-warnings 0`

</proposed_plan>
