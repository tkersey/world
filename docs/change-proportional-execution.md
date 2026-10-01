# Change-proportional resident execution

This independent execution is in progress. No performance acceptance or review
closure is claimed yet.

## Fixed inputs

- Driver thread: `01a0f465-f4a1-73a3-9eaa-99bd6e6b2a6c`.
- World W0: `c61edfc8208c375d5188e476131ca8cff5aeeb8a`, tree
  `87edc03ebb7b8b56facfe7f2e60845c5931f1834`.
- Runtime data D0: `511fe388587b36ae37307d277e04c22b0bb6f6d9`, package
  `boundary-3.0.0-dev.0-flclaGcPXAB8lBsvhVLPJFZmROkee3fHGfsloqpgeZSE`.
- Agent A0: `b1f9d2866b5717d16339e7022a3b4d08951f0770`.
- Compiler C0: `65f46131f366bdd21aa98701f4110ecb801d2c8d`, package
  `boundary-3.0.0-dev.0-flclaEdzRQBpnNrUM2gj62qP_jA65zcVHZgFfmxIPqxe`.
- Boundary harness B0: `93340dade30b7d27a1e139f107359f91fb66fad3`.
- Specification SHA-256:
  `d914b959e32d10b841e549cb27665689c419856e5b77ae632363fb71b22e92f3`.
- Installed skill source: dotfiles `f7228a8d188f72be666f5e3db5bcce3e677580df`.
- Zig `0.16.0`; Node `26.10.0`; native ReleaseSafe, WASM ReleaseSmall.
- Machine: Apple M2 Pro, 12 CPUs, 32 GiB RAM; Darwin 27.2.0 arm64.
- Candidate branch: `codex/change-proportional-01a0f465` in an isolated clone.
  A separate detached W0 clone supplies the immutable differential reference.
- Root model/effort and consumption are limited to observable session metadata;
  provider billing and unavailable telemetry will not be inferred.

## Frozen primary lifecycles

The H/Q compiler emitter retains a non-tail recursive continuation at every
depth. On completion each continuation emits its distinguishing depth in order.
The bottom frame executes 128 additions, with an initial yield (H) or request
(Q). Both arms execute the same C0-emitted bytes with mandatory coalescing.

H: prepare/start, reach the bottom yield, resume, run 64 one-work-unit drives,
transfer the checkpoint, restore, cancel through cleanup, close/release.
Q: prepare/start, publish the bottom request, submit three invalid responses
(wrong binding, malformed result, correctly bound ill-typed value), submit the
valid u64 response, cancel through cleanup, close/release.

Select the largest specified dimension that W0 supports under common documented
stress limits; smaller dimensions and individually observed completion traces
remain guardrails. Time whole lifecycles including preparation; fold every
command's peak immediately in a separate memory pass. Primary wins require five
alternating windows, three warmups and nine samples per process, median ratio
below 0.95 with at least four of five below 0.95. Timing and memory limits are
those of specification sections 10.3–10.4.

## Baseline verification

`zig build check-storage check-native build-kernel build-runtime
-Doptimize=ReleaseSafe --summary all`: 71 storage and 87 native tests passed;
the normal WASM kernel and standalone runtime built successfully.

The W0 source unconditionally forks all registered frames at transaction entry
and releases all backup entries at commit. `Session.answer` calls
`pendingRequest`, which calls `checkpoint`, before checking every reply.

The frozen C0 H/Q images have SHA-256
`d59f1de88b58452e647853e9aa81ed91ca13cec600a5898028d29352b2c85ce8`
and `6a31366751bd89c246591c0996395e9380489590769e56676ba4a79685038209`.
W0 reproduces kernel
`9627eb1e66239119bccb4ddcd43b4f6c757180dab930a9feb276671262f735d1`.
Actual native and WASM Residents execute every prescribed H/Q size through
1024. At H=1024 the native runtime retains 1025 frames, protects all 1025
at begin, and allocates 232376 bytes on the first small drive. All 64 measured
drives avoid collection; completing observes depths 1 through 1024 separately.

## Frame transaction construction

The required law is preservation of transaction-entry state until successful
output publication, including semantic histories, custody and graph ownership.
The flat frame map is a contingent representation; the prepared lease, canonical
observations and allocation-free rollback are binding constraints. Ordinary reads
need no saved version. Mutable acquisition and membership changes must retain
entry ownership before mutation can escape.

The selected construction is a first-touch journal in Frames, composed with the
existing Store transaction under Session. A persistent frame-map root would
require replacing the flat map and its caller/borrow contract; journaling retains
those contracts and makes begin constant work and commit proportional to touched
entries. Saved null entries distinguish newly created frames from entry occupants
at reused IDs. Rollback removes touched successors before restoring entry versions
with retained map capacity. Necessary Store index rebuilding on failure remains
linear and receives no change-proportional rollback claim.

The mutable cut covers getMutable/getForMutation, put/update/remove, copying and
rebasing; local frame copies come from protected acquisitions or new frames.
Session capture/resume, tail restart, clone, unwind and collection route through
these operations. Raw slot/custody mutation is permitted by the low-level native
surface, so callers there still own acquisition discipline; controlled Resident
operations use the complete audited cut. No new restriction on Session is added.
First-touch allocation failure, mutable-reference escape, a missed mutation path,
or a rollback allocation falsifies this construction. The frame-map/layout/custody
representation or sanctioned mutation changes require rechecking this argument.

The first slice passes 73 storage tests (including exhaustive allocation-failure
selection for the changed frame operations) and all 87 existing native tests.
Native H=1024 protects zero frames at begin and one on each of the 64 small
drives; the first drive allocates 1920 bytes. All 1024 later effects retain their
distinguishing values. Actual Node/WASM H/Q completion passes every specified size.
Paused live bytes are unchanged in this instrumented pass. These are structural
and correctness observations, not timing acceptance.

## Current handoff within this execution

The early draft is [World #60](https://github.com/tkersey/world/pull/60), assigned
to tkersey, at `ad4cf8ea7f842dc9201a0affbc04e4e00c38dfe0` (tree
`4df3e7c8afa9b3b0bb4d73b060c56e659ed6a0a1`). It remains draft and unmerged.
This is a partial slice, not P0. No independent review epoch has opened.

The Q baseline now exercises wrong binding, truncated response and correctly
bound ill-typed value, preserving the exact entry checkpoint on every rejection
before accepting the original valid response. At Q=1024 the three rejected
calls allocate 883969, 883818 and 884238 temporary bytes respectively, with
diagnostics InvalidResult, Truncated and InvalidValue. The baseline builds,
frozen images and raw observations remain in this execution's isolated sibling
evidence directory. The checked-in emitters/probes supply reproduction sources.

Pending-binding implementation, complete lifecycle timing/economic acceptance,
fixed consumer emission/replay, final platform/package qualification, P0/P1,
serial review closure and the final consolidated report remain required.

## Pending observation construction

The selected boundary retains only the canonical request identity in Resident,
derived from the actual published Outcome. It lends that identity to the shared
response checker during a gated drive. Standalone low-level Session.answer keeps
canonical recomputation, preserving its independently mutable lifecycle. No
response value, authority decision, checkpoint graph or serialized State is cached.

Every successful drive replaces the identity with the new published pending
identity or null for a nonpending observation. The replacement occurs after all
fallible output construction and encoding, at the existing transaction commit
fence. Failed drives leave the previous identity untouched and rollback the
computation. Checkpoint inspection does not change it; transfer and close clear
it; restoration starts with no private identity. A stale identity after successful
progress/cancellation or a failed-publication retry mismatch falsifies this design.
The ownership premise is the existing exclusive, noncopyable Resident contract;
the separate low-level Session route does not acquire that premise or trust a cache.

The candidate's Q=1024 wrong-binding, truncated and ill-typed response checks
each perform zero checkpoint constructions and one expected-binding reuse.
Their temporary allocation is respectively 215, 64 and 484 bytes, versus
883969, 883818 and 884238 in W0. The exact rejection diagnostics, entry State
and succeeding original reply agree. The native failure sweep also runs reply
and cancellation allocations after establishing the private binding, retaining
every original unprimed failure case.

The cumulative World suite passes 89 native and 73 storage tests, 42 source
fixtures / 8692 exact observations, 159 Wasmtime/native/Node transfer boundaries,
the real Chromium 153.0.8010.12 and Firefox 155.0 Worker checks, capacity and
standalone package checks. The additional H/Q agreement contains 19 prescribed
and neighbor cells, both W0↔candidate transfer directions and late output-failure
retry. Scalar preservation covers six sizes / 158 observations; frame preservation
covers ten cases / 6530 observations; blob preservation covers 15 cases / 90
prefixes and ten capacity cases. W0 already reclaims dead large backing, so this
run asserts that existing absolute reclamation and alias behavior; it does not
reuse the old sampler's demand for another gain over a pre-reclamation baseline.

The initial five-window WASM comparison at H=1024 has median ratio 0.914626
(5.45 ms less per lifecycle) and satisfies the prospective 5% win criterion.
Q=1024 is 0.952547 and does not satisfy that criterion. All nine primary cells
remain below the timing/memory regression gates in that initial measurement.
Final guardrail and cumulative timing qualification remains open.

All 18 A0/C0 economy images reproduce the previously accepted hashes. The fixed
fresh-invocation regression lane contains exactly 30 named cells / 491 commands,
with expected bytes captured from W0 under the original deterministic assertions.
Candidate document, consequence and reciprocal recursive-participant assertions
pass against actual candidate kernel bytes. The adapted World test wiring leaves
Agent's runtime verifier and historical installation unchanged; that authenticated
bridge remains independent reference evidence.

After the workspace permission profile changed, the live Inquiry host test stops
before kernel execution: its existing nested sandbox-exec profile probe returns
`sandbox_apply: Operation not permitted`. No sandbox, assertion or approval policy
was bypassed. Frozen Inquiry replay remains independently executable. This limits
the live-host rerun claim and is not a candidate runtime defect.
