<proposed_plan>
Iteration: 5
# World Timeline Kernel Execution Plan

## Round Delta
- Converted the spec handoff into a dependency-aware implementation campaign with explicit phase gates: frame identity first, portable replay authority second, branch/checkpoint and examples after core adapters are proven.
- Added one accretive hardening decision: a frame conformance fixture suite that stores canonical request/response/value/transcript image bytes as test vectors to catch future ABI drift without declaring a WASM ABI.
- Closed the plan after two no-delta reassessment passes and one press pass across interfaces, traceability, and rollback controls.

## Summary
Implement the World Timeline Kernel by making portable `Frame.Request` / `Frame.Response` / `ValueImage` and `TranscriptImage` the authority for replay, verify, checkpoint, branch, and audit semantics while keeping native Zig handlers as an adapter. First execution wave builds frame/value/codec primitives and conformance vectors before Machine refactoring. Done means image replay and ByteAdapter run without native handlers or `StoredValue`, existing examples remain green, all new examples/tests/docs are wired into `zig build check`, and the full proof bundle passes on Zig 0.16.0.

Chosen path: additive but core-directed refactor in `src/world.zig`, keeping public compatibility for `world.Machine`, `world.port`, `world.portWithOptions`, `PortRequest`, `PortResponse`, `Mode`, `Transcript`, and `AuditReport`. New root-level surfaces are limited to `world.Frame`, `world.ValuePolicy`, `world.Timeline`, `world.TranscriptImage`, and `world.AuditImage`; adapter types live under `world.Frame`.

Campaign waves: Wave 1 frame/value protocol, Wave 2 timeline/transcript image, Wave 3 Machine frame-first refactor and adapters, Wave 4 checkpoint/branch/audit, Wave 5 examples/docs/build integration, Wave 6 full proof and PR-summary handoff.

## Iteration Change Log
- iteration=1; focus=1; round_decision=continue; delta_kind=material; evidence=spec-pipeline handoff plus repo inspection at HEAD b61ebcb32dc1c3698e8fb6adbde926ac78d03241; what_we_did=established execution spine and phase order; change=made frame/value primitives the first wave and deferred Machine refactor until codecs/fingerprints are proven; sections_touched=Summary,Implementation Brief,Decision Log
- iteration=2; focus=2; round_decision=continue; delta_kind=material; evidence=current `StoredValue` transcript authority in `src/world.zig` and spec invariant challenge; what_we_did=hardened interfaces and authority boundaries; change=locked `StoredValue` as native sidecar only and required image replay/ByteAdapter tests that avoid handlers and StoredValue; sections_touched=Interfaces/Types/APIs Impacted,Data Flow,Tests/Acceptance,Rollback/Abort Criteria
- iteration=3; focus=3; round_decision=continue; delta_kind=material; evidence=checkpoint/branch uncertainty around Boundary capsule refs and no storage/scheduler non-goals; what_we_did=resolved operability and failure handling; change=specified deterministic replay-to-checkpoint fallback and explicit abort triggers for capsule/storage/scheduler drift; sections_touched=Edge Cases/Failure Modes,Rollout/Monitoring,Assumptions/Defaults,Rollback/Abort Criteria
- iteration=4; focus=4; round_decision=continue; delta_kind=none; evidence=requirement-to-test table maps R1-R16 and proof commands include current and new examples plus focused filters; what_we_did=traceability reassessment; change=no material delta; sections_touched=Requirement-to-Test Traceability,Tests/Acceptance,Contract Signals
- iteration=5; focus=5; round_decision=close; delta_kind=none; evidence=press pass checked Interfaces/Types/APIs Impacted,Requirement-to-Test Traceability,Rollback/Abort Criteria,Implementation Brief; what_we_did=creativity plus adversarial closure pass; change=no material delta after adding conformance vector decision already integrated in Round Delta/Decision Log; sections_touched=Round Delta,Decision Log,Decision Impact Map,Convergence Evidence

## Non-Goals/Out of Scope
- No WASM ABI, linear-memory layout, storage backend, xitdb integration, network transport, scheduler, async runtime, provider lifecycle, service discovery, real model/tool/file/human integrations, security/signing/encryption, distributed execution, Boundary closure, Boundary normalization, TreatyResolver hot path, ProviderHarness hot path, provider catalog lookup, morphism catalog lookup, closure graph traversal, evidence graph traversal, or agent framework.
- No widening Boundary `ProgramValue` and no invented Boundary codecs. If Boundary lacks a needed target-neutral helper, add only the smallest public helper after proving World cannot derive the data from existing target metadata.
- No public tracker or PR side effect in this plan. PR text is prepared only when the user explicitly asks for publication.

## Scope Change Log
- scope_change=none; reason=`$plan` consumes the accepted `$spec-pipeline` scope without adding or removing milestone deliverables; approved_by=user-provided `$spec-pipeline` and `$plan` requests.

## Interfaces/Types/APIs Impacted
- `world.Frame`: add nested `Request`, `Response`, `ValueImage`, `Status`, `Codec`, `Error`, `NativeAdapter`, `ReplayAdapter`, `VerifyAdapter`, and ByteAdapter test helper. These own canonical byte encode/decode, deterministic fingerprints, validation, and adapter-level frame semantics.
- `world.ValuePolicy`: add presets `portable`, `native_compatible`, and `audit_only` with fields `require_portable_values`, `allow_native_only_values`, `require_response_images_for_replay`, `allow_diagnostic_type_labels`, and optional `max_value_image_bytes`.
- `world.Timeline`: add ordered events plus nested `Checkpoint` and `Branch`; event kinds include run, frame request/response/replay/verify/reject/fail, checkpoint, branch start, optional branch join, completion, and failure.
- `world.TranscriptImage`: add portable image encode/decode and `Transcript.toImage(allocator, options)` / `Transcript.fromImage(allocator, image)` or equivalent methods. Images must serialize frames/events/replay keys/counts/status, never `StoredValue`, `*anyopaque`, allocator/runtime/thread/request token, or host pointer identity.
- `world.Machine.Run`: add `nextFrame()` and `resumeFrame(response_frame)`; keep existing `start`, `run`, `next`, and native dispatch helpers source-compatible by layering them over frames.
- `world.AuditImage` / `AuditReport`: add frame/image/checkpoint/branch/portable/native-only counts and optional transcript image fingerprint while preserving existing audit count semantics.
- `build.zig`: add examples and expected stdout/run steps for `run-world-frame-ports`, `run-world-transcript-image-replay`, `run-world-byte-adapter`, `run-world-agent-timeline`, and `run-world-agent-branch`; extend `check` and `lint` hot-path guards.

## Data Flow
1. Boundary Certified Target exposes `Program`, `WorldSurface`, `WorldPortTable`, `WorldValueTable`, `WorldDispatchTable`, `SourceMap`/`TraceMap`/`EvidenceMap` when available, and `Target.Certificate`.
2. `Machine.start` initializes the residual `Program.Session`, validates expected surface/certificate options, prepares audit/timeline state, and records `run_started` as a timeline event when transcripting is enabled.
3. `Run.nextFrame()` calls `session.next()`. On `.request`, it reads the residual trace, uses `WorldDispatchTable.lookup(site_index)`, validates dense `world_port_id` and residual site fingerprint, creates `Frame.Request`, records `frame_requested`, and returns it without calling a handler.
4. Adapter choice handles the request: `NativeAdapter` calls typed handler and builds `Frame.Response`; `ReplayAdapter` looks up image/transcript response frame and never calls handlers; `VerifyAdapter` compares fresh NativeAdapter response against expected ReplayAdapter response; ByteAdapter encodes/decodes canonical bytes through a fake host.
5. `Run.resumeFrame(response_frame)` validates target/surface/certificate/port/request/replay key/status/value image, decodes or projects response value under `ValuePolicy`, records frame response/replay/verify/fail event, and resumes the Boundary session.
6. `Transcript` retains timeline/frame data plus optional native `StoredValue` sidecars for `native_compatible` mode only. `TranscriptImage` is derived only from portable frame/timeline data.
7. Checkpoint creation records event index, turn index, prefix fingerprint, branch id, optional current request/last response fingerprints, and optional Boundary capsule ref. Branch execution uses capsule ref when publicly available; otherwise it deterministically replays from start to checkpoint before injecting alternate response frames.
8. Audit image summarizes counts, per-port data, image blockers, branch/checkpoint counts, and optional transcript image fingerprint.

## Edge Cases/Failure Modes
- Unsupported value image: return `UnsupportedValueImage` when the type/metadata cannot be safely imaged; return `NativeOnlyValue` when native-compatible sidecar exists but portable policy requires an image; return `MissingValueImage` when replay requires a response image that is absent.
- Rejected/failed/pending responses: `responded` path is fully executable; rejected and failed frames are encoded, decoded, recorded, and tested; pending is structural only and must not introduce scheduler/async semantics.
- Decode hazards: reject invalid format versions, invalid enum tags, trailing junk, impossible lengths, over-policy byte lengths, missing required fields, mismatched request fingerprints, and mismatched surface/certificate/port ids.
- Verify divergence: use precise errors `VerifyDivergence`, `VerifyMissingExpected`, `VerifyResponseKindMismatch`, `VerifyResponseFingerprintMismatch`, and `VerifyValueImageMismatch`; record `frame_verified` only on successful comparison.
- Branch immutability: branch timeline/image owns new events; parent transcript/timeline is never mutated by branch creation or branch execution.
- Capsule absence: branch/checkpoint remains valid metadata; execution rehydrates from transcript prefix instead of requiring a Boundary capsule image.
- Handler ownership: `response_deinit` remains called after NativeAdapter clones/retains handler response; replay/image/byte paths never call handler deinit.
- Hot-path contamination: fail lint if core frame/replay path references TreatyResolver, ProviderHarness, catalogs, closure/evidence graph traversal, Boundary normalization, operation-name dispatch, direct native handler function pointer dispatch, or `StoredValue` in TranscriptImage replay.

## Tests/Acceptance
- Unit tests cover frame request/response/value image fingerprints, canonical encoding, invalid decode rejection, policy behavior, adapter success/failure, transcript image replay, timeline ordering, checkpoints, branches, audit images, and hot-path independence.
- Examples prove user-visible paths: frame ports, transcript-image replay without handlers, byte adapter bytes, agent timeline handler-free replay, and agent branch alternate outcome.
- Regression tests keep existing examples green: `run-world-strict`, `run-world-ports`, `run-world-replay-ports`, `run-world-agent-loop`.

## Requirement-to-Test Traceability
| requirement | acceptance |
| --- | --- |
| R1 constants/fingerprint versions | `request frame`, `response frame`, `value image`, `transcript image`, `timeline event`, `checkpoint`, `branch`, and `world audit` tests assert version constants and fingerprint domains. |
| R2 `Frame.Request` | `request frame` tests assert stable fingerprint, surface/certificate/port/request binding, no token/pointer fields, and canonical encode/decode. |
| R3 `Frame.Response` | `response frame` tests assert request binding, response kind/status, rejected/failed representation, replay key binding, and canonical encode/decode. |
| R4 `ValueImage` | `value image` tests assert scalar/string/product/sum round trips, stable image fingerprint, byte limit rejection, and fail-closed unsupported/native-only cases. |
| R5 `ValuePolicy` | policy tests assert `portable`, `native_compatible`, and `audit_only` behavior for missing/native-only images and audit blockers. |
| R6 adapters | `native adapter`, `replay adapter`, and `verify adapter` filters assert typed handler frame lowering, handler errors to failed/rejected frames, replay validation, and verify divergence errors. |
| R7 ByteAdapter | `run-world-byte-adapter` and `byte adapter` tests assert request/response bytes length, decode/encode round trip, final result, and native handler calls remain zero in byte path. |
| R8 timeline/checkpoint/branch | `world timeline`, `timeline event`, `checkpoint`, `branch`, and `agent branch` tests assert event order, prefix fingerprints, branch immutability, alternate branch result, and audit summary. |
| R9-R10 TranscriptImage replay | `run-world-transcript-image-replay`, `transcript image`, and `world replay` tests assert image round trip, no native pointers, handler-free replay, and all response events consumed. |
| R11 step/resume frame API | `step frame` tests assert `nextFrame`, `resumeFrame`, failed response cleanup, replay step path, and parity with full-run helpers. |
| R12 audit image | `world audit` tests assert request/response/replayed/verified/failed/rejected/checkpoint/branch/per-port counts, native-only/missing-image counts, and transcript image fingerprint. |
| R13 hot-path guard | `zig build lint -- --max-warnings 0` plus targeted tests assert no forbidden Boundary surfaces and no `StoredValue` dependency in TranscriptImage replay. |
| R14-R15 examples/docs | `zig build --summary all`, all new run steps, README review, `docs/timeline.md` review, and `zig fmt --check build.zig src examples test`. |
| R16 PR summary | manual acceptance before public side effect; PR body must list all kernel pieces and explicit non-goals. |

## Implementation Brief
- step=Wave 1 frame/value foundation; owner=implementation lead; success_criteria=version constants, frame/value structs, codec helpers, fingerprints, conformance vectors, and value-policy tests pass without Machine refactor.
- step=Wave 2 timeline/transcript image; owner=implementation lead; success_criteria=Timeline events, TranscriptImage encode/decode, replay cursor, pointer-exclusion tests, and image round-trip tests pass while existing Transcript tests remain green.
- step=Wave 3 Machine frame-first refactor; owner=implementation lead; success_criteria=`nextFrame()`/`resumeFrame()` exist, existing `Machine.run`/`Run.next` behavior is source-compatible, NativeAdapter owns all handler calls, ReplayAdapter and VerifyAdapter pass focused tests.
- step=Wave 4 image replay, checkpoint, branch, audit; owner=implementation lead; success_criteria=image-backed replay runs without `.ctx`/handlers/StoredValue, checkpoint prefix fingerprints are stable, branch transcript does not mutate parent, branch alternate response changes outcome, and AuditImage counts match tests.
- step=Wave 5 examples/docs/build; owner=implementation lead; success_criteria=five new examples and run steps are wired into `build.zig`, README and `docs/timeline.md` document frame-first semantics and non-goals, hot-path guard is strengthened.
- step=Wave 6 proof and handoff; owner=implementation lead; success_criteria=full proof command bundle passes, final diff review confirms no scope drift, PR summary draft includes required kernel/adapters/image/branch/non-goal details if publication is requested.

Iteration: 5
</proposed_plan>
