# API-preserving performance work (draft)

This implements the September 14, 2026 Boundary 2 / World 5 API-preserving
performance specification. The full milestone remains in progress. There is no
API, ABI, protocol, default memory limit, kernel trust or JavaScript lifecycle
change. No merge or release is part of this work.

The immutable comparator W0 is `87698f92ca7be4d5442e97ba27a2468aa3ff6a7c`, which
includes the approved running-cleanup disposal correction. Main remains the
released-line reference `5175e775005ee95e141b079936be163e1e75b803`. The correction
is included by ancestry in this branch and is not attributed as a performance
improvement. B0 is `55e8feedcae0b9ee1492da11f9fbd4a1ac7ff328`.

## Production changes

Store can take a completely initialized node's record allocations on success.
Callers retain ownership on failure. Continuation arguments, resumed controls,
jumps, calls, closure environments, initial arguments, captured-plus-explicit
arguments and direct-clause successors now construct their final buffer once.
Graph references retain their logical aliases. Borrowed `replace` still copies
before releasing the previous node; the owned operation does not accept borrowed
sub-slices. Remaining handler and cleanup construction sites still need review.

Collection marks and traversal storage remain private to Store, reset before
tracing and freed with Store. Collection cadence, exact roots and no-effects
reclamation are unchanged. This addition is provisional: its isolated timing
results did not establish an overall win. No allocation-pressure policy or
stable-activation experiment has yet been implemented.

Response admission shares request construction with publication. It calls the
existing protocol identity and validation functions without encoding and decoding
a temporary ERQ2. For snapshot input, `decodeGraph` has compared the full canonical
encoding to the input and State admission has checked the resulting logical
state. Those same bytes supply the pending-state digest before any authority is
consumed. Records input still emits canonical bytes. No digest from unvalidated
input, caller trust flag, cross-invocation cache or second validator is used.
The request payload borrows the admitted State; schema buffers live in operation
scratch until validation completes. The resumed value belongs to Store.

## Exploratory results

Zig 0.16.0, native ReleaseSafe tests, ordinary ReleaseSmall WASM kernel, default
memory settings, macOS arm64. The baseline and candidate builds finished before
timing. Every measured invocation goes through the public loaded host and creates
a fresh WASM instance. The harness includes input encoding, admission, execution,
publication and result decoding; module loading is reported separately.

These are dirty-candidate exploratory observations, not final acceptance windows.
Five warmup batches precede 21 paired AB/BA samples, with 20 fresh calls per batch.
No sample batch reuses a live process or guest instance. Initial unbatched runs
are also retained; they exposed substantial short-call noise.

| Combined candidate path | W0/B0 median ms | W1/B1 median ms | Ratio |
|---|---:|---:|---:|
| Short scalar (one installation) | 0.074927 | 0.067127 | 0.896 |
| 64 installations | 0.676019 | 0.598810 | 0.886 |
| Retained search to first boundary | 0.584000 | 0.568265 | 0.973 |
| Saved search response | 1.125546 | 0.853204 | 0.758 |

All measured outcomes match W0 byte-for-byte, including complete State and request
bytes. The search fixture first yields; setup follows those existing boundaries
to its first pending request before measuring the saved response. The initial
fixture expectation of an immediate request was corrected before timing.

[Latest raw measurements](performance/combined-state-reuse-batched.json) include
kernel and input hashes, output hashes and sizes, all sample values and environment.
Earlier runs remain alongside them: scratch alone, direct ownership plus initial
request sharing, and combined Boundary changes before canonical-byte reuse.
Small differences remain inconclusive; the scalar baseline-to-itself run was noisy.
No numerical non-regression, p99 or total peak-memory claim is made.

Run from this checkout after building both kernels, supplying absolute paths:

```sh
node test/v2/performance_compare.mjs "$W0_KERNEL" "$W1_KERNEL" \
  "$BOUNDARY_FIXTURES" "$RESULT_JSON"
```

## Proof and remaining work

`zig build check-v2-native` passed against both B0 and candidate Boundary during
implementation. It includes focused zero-copy ownership, overlapping borrowed
replacement, cyclic garbage, freed-slot reuse and allocation-failure tests.
Repeated same-payload requests reject stale results, and response failure sweeps
preserve input and exact successful request bytes. Records and snapshot response
paths have an explicit equality case. Source agreement passed against B0 before
the final canonical-input reuse refinement; that lane requires a fresh run.

Full native/WASM/source/Wasmtime crossing, release-consumer API fixtures, package
identity checks, constrained capacities, peak memory and descriptor-copy
attribution still need completion. Final measurements require committed inputs,
two separated confirmation windows, cold-build guards and fixed workload coverage.
The private stable-transfer and separate collection-cadence experiments remain
required, as do Boundary metadata/size experiments and review convergence. These
open requirements are not waived by the useful initial improvements.

The current combined candidate also passed `check-v2-native check-v2-wasm`:
exact native/WASM outcomes and fresh transfers for handlers, regions, cleanup,
full-width compact collections and 10,000 tail calls. The command used
`-Dboundary-v2-source` pointing at the candidate and `-Doptimize=ReleaseSafe`;
the guest remains built with the repository's standard ReleaseSmall setting.

## Completing direct ownership

Handler state, use-site capture vectors and cleanup discard positions now build
final Store-owned buffers. Application and handler-entry argument construction
fills captures and explicit arguments directly into one final call buffer.
Cleanup failure replacement takes both newly prepared value buffers and a
separately copied cancellation reason; borrowed replacement remains available
for records containing aliases into the previous owner.

An intermediate unpublished attempt omitted the nested cancellation text when
transferring an Exit. The existing `body failure wins over later cancellation and
both failing finalizers run` test crashed on the dangling text. The successor
owns that nested buffer before replacement. The test now sweeps all allocation
failures through both failing finalizers and checks primary failure, ordered
cleanup failures, first cancellation and unchanged input. A focused test covers
owned replacement of both value vectors and nested cancellation bytes. No claim
or passing result from the failed intermediate version is retained as proof.

The first 20-call-batch run showed a noisy scalar ratio of 1.094. GC diagnostic
output showed repeated incremental collections during these short batches,
including marking work of several milliseconds. The samples had two timing
bands, and medians changed substantially with their proportions. The deciding
harness now uses 200 fresh public calls per batch (still 21 AB/BA paired samples
and five warmup batches), including the actual collection overhead rather than
forcing collection outside the measured path. Workloads and public lifecycle
are unchanged. Earlier observations remain in the report directory.

The [longer-batch exploratory run](performance/complete-ownership-long-batches.json)
reported candidate/baseline medians of 0.966 for the short scalar, 0.854 for
64 installations, 0.973 for retained search and 0.746 for saved response. All
four complete outcome byte strings matched the reference. These dirty-source
results still need final committed-input confirmation and uncertainty estimates;
they do not waive the cold-build, memory, stable-storage or cadence experiments.
The [GC trace](performance/host-gc-diagnostic.txt) and its
[instrumented measurements](performance/host-gc-diagnostic.json) are diagnostic
only. They used the previous 20-call harness with `node --trace-gc`; the
uninstrumented 200-call run is the current exploratory timing comparison.

The completed ownership candidate passed `check-v2-native check-v2-wasmtime check-v2-capacity` with the candidate Boundary source and its emitted fixtures. Kernel `ac49497b5025fc72af20553811c43e29ce3dfc879d1d678e7ef67f092135be9c` matched all 41 source checkpoints, handwritten checkpoints and cancellation scenarios. Input, working and output exhaustion published no State; unchanged-input retries matched the unconstrained result.
