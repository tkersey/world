# API-preserving performance work (draft)

## Committed-candidate measurements

Measured inputs are Boundary `b599e664c57ca455395038bd28b703837f870030` and World
`24867d20afd2076136c0cb14d64fee3a951d0f96`, versus B0/W0 below. Both candidate
trees were clean. Two separated windows used five warmup batches, 21 alternating
AB/BA pairs and 200 full loaded-host calls per batch, with a fresh WASM instance
for every invocation. No builds or other benchmarks overlapped runtime timing.
The intervening cold-build guard used five fresh-cache pairs per workload.
Native builds use ReleaseSafe. Both guest kernels retain the repository's fixed
ReleaseSmall setting; no optimization mode or memory default was changed.

| Public call | Window 1, B0/W0 → candidate (ms) | Ratio | Window 2 (ms) | Ratio |
|---|---:|---:|---:|---:|
| Small invocation | 0.1010 → 0.1005 | 0.995 | 0.0948 → 0.0912 | 0.963 |
| 64 installations, run | 0.7350 → 0.6320 | 0.860 | 0.7073 → 0.6011 | 0.850 |
| Retained search to first boundary | 0.6243 → 0.6047 | 0.969 | 0.5962 → 0.5721 | 0.960 |
| Saved search response | 1.2046 → 0.9086 | 0.754 | 1.1478 → 0.8615 | 0.751 |

The installation and saved-response improvements reproduce in both windows.
Small-call changes remain sensitive to host overhead; no uniform scalar speedup
is claimed. [Window 1](performance/final-window-1.json),
[window 2](performance/final-window-2.json), and
[paired bootstrap summaries](performance/final-runtime-summary.json) retain all
primary rows. Intervals describe these samples, not a p99 guarantee or universal
non-regression proof. Module-admission setup is recorded separately and is not
used as a statistically established startup improvement.

[Secondary measurements](performance/final-secondary.json) cover 8 installations,
64 KiB blob capture, lexical captures, local/shared state, shallow multishot,
generator, scheduler, owned cleanup, recursion and repeated advance. The complete
321-transition advance sequence measured 266.2 → 265.0 ms: effectively unchanged,
with every checkpoint hash equal. The 10,000-call recursive case measured
7.67 → 5.41 ms. These are one secondary window, not the two-window primary claim.
The initial secondary harness used an invalid empty blob argument; its
[aborted run](performance/secondary-aborted-run.json) receives no acceptance
credit. The corrected harness persists rows as it completes them.

[Larger fixtures](performance/final-large.json) cover 128 installations across
the ULEB slot-width boundary and a stored 64 KiB constant referenced twice.
B0/B1 emitted identical 30,141-byte and 65,652-byte images respectively.
The 128-installation call measured 1.922 → 1.660 ms; the constant call was
effectively unchanged at 0.499 → 0.497 ms. The constant remains one stored
payload. Fixture source and hashes are retained alongside the measurements.

| Complete native invocation peak, bytes | B0/W0 | Candidate |
|---|---:|---:|
| 1 installation | 19,153 | 9,042 |
| 8 installations | 27,333 | 16,590 |
| 64 installations | 218,915 | 140,036 |
| 128 installations | 1,422,367 | 660,850 |
| Local state | 56,851 | 25,906 |
| Stored 64 KiB constant | 493,193 | 493,193 |

[Full invocation counters](performance/final-invocation-memory.json) use the
existing 16 MiB native probe reservation and include PKI2 decoding, Program
preparation, execution and output encoding. They are allocator-requested working
payload, not RSS; the final output buffer has separate caller ownership.
[Decoder-only measurements](performance/final-decoder-memory.json) use the same
fixed 1 MiB Workspace on both sides. Baseline 128-installation decoding exhausts
that capacity; the candidate completes with a 660,850-byte peak. Large-constant
decoder peak rises by 1,384 bytes due to separated scratch, while its complete
invocation peak remains unchanged. No universal memory reduction is claimed.

The synthetic retained-search workload is the public four-queens composition:
retained search branches, local/shared cells, repeated typed acquire/use/release
interactions, owned resources, yielding and cleanup. It is not production Agent
evidence. All portable outcome sizes and hashes remain identical for the same
image. Review convergence is tracked on the draft PRs and in native review receipts.

[CLI checks](performance/cli-compatibility.json) preserve help, version, usage
errors and exact execution bytes. [External crossings](performance/external-crossing.json)
compare the complete 813-record sequence produced with B0 authoring/W0 native
execution to the candidate path; the sequence is identical. Its full synthetic
records are retained. [Large-fixture conformance](performance/large-conformance.json)
also checks the independently calculated sum and constant bytes against W0
native, candidate JavaScript and Wasmtime execution.

The initially unbound Review Fold corpora were validated and bound without
rewriting their event bytes. Current review witnesses were captured through the
owner definition. Historical absence is not used to claim first occurrence or
complete coverage; native review convergence is a separate delivery requirement.

## Conformance dependency repairs

The first review wave identified that the companion-only kernel freeze and four
new cleanup files could not be reproduced from World's unchanged Boundary pin.
World now owns the four immutable supplemental vectors and their independent
source expectations. The supplied oracle still runs, with the pinned oracle's
two known defects checked explicitly; kernel expectations always retain the
correct failure and finalizer semantics. Existing compiler-supplied cases remain
unchanged.

The post-freeze checker admits the two explicitly frozen supported kernels:
`0da1f478fa1de495c2354724a8b90d7279fd7219c4dcde7f9f79dff85c1e06b6`
from the declared Boundary pin, and the companion-derived `9545076f...` kernel.
A new byte-length/yield consumer was authored after both freezes. All three
consumers passed 833 exact records with each kernel; an unlisted kernel still
rejects. The pinned 37-fixture bundle plus the four owned regression vectors
passed native/JavaScript/Wasmtime source-transfer checks. No dependency pin or
runtime source changed in these repairs.

This implements the September 14, 2026 Boundary 2 / World 5 API-preserving
performance specification. Review closure is recorded separately on the PRs. There is no
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
sub-slices. Handler and cleanup construction use the same completed ownership path.

Collection marks and traversal storage remain private to Store, reset before
tracing and freed with Store. Collection cadence, exact roots and no-effects
reclamation are unchanged. Its isolated timing was inconclusive; the combined
implementation is measured above. The separate pressure-collection and stable
storage experiments below were tested and rejected.

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

[Earlier raw measurements](performance/combined-state-reuse-batched.json) include
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

## Proof

`zig build check-v2-native` passed against both B0 and candidate Boundary during
implementation. It includes focused zero-copy ownership, overlapping borrowed
replacement, cyclic garbage, freed-slot reuse and allocation-failure tests.
Repeated same-payload requests reject stale results, and response failure sweeps
preserve input and exact successful request bytes. Records and snapshot response
paths have an explicit equality case. The later full aggregate check and external
consumer crossings are recorded below. Final paired measurements and experiment
dispositions are now available; PR review records supply the separate closure
evidence.

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

## Cross-version compatibility continuation

At W1 `2a1599afb4166f59bbc067c4e4d6129d5c844868` and B1
`c914de195a6003076629e650ba0b6496d5fcdb75`, the native test matrix passes
W0/B0, W1/B0, W0/B1 and W1/B1. The cross-version source-transfer run also passed
all 41 fixtures and cancellation scenarios using the unmodified W0 native
embedding built against B0 and the W1/B1 guest kernel. The harness alternates
the actual native and JavaScript producers of the next State, with complete
PKO2 equality at each compared checkpoint. Standard three-engine runs now also
include the native producer alongside JavaScript and Wasmtime.

The baseline native embedding was built directly from the immutable W0 checkout's
`test/v2/native_records.zig`, W0's public `world` module and B0's
`boundary_data_v2`, with explicit `-O ReleaseSafe` on each module and Zig 0.16.0.
This is cross-version restoration evidence, separate from performance timing.
The later aggregate includes physical package installations. Both external
consumers also passed with B0 authoring, W0 native execution and the candidate
guest, including all 813 complete records.

## Private transfer experiment, first variant

An exact-array handoff prototype moved the evaluated slot buffer into the next
control node when every slot was forwarded in order. Other mappings used the
existing materializing path. A native allocation guard confirmed elimination
of the second buffer allocation; an independently admitted two-block image
passed public WASM run/advance and cross-restoration with identical complete
outcomes. No logical node was merged or public transition fused.

Against the committed direct-ownership comparator, the 21-pair, 200-call
comparison produced ratios 0.981 / 0.998 / 0.999 / 0.999 for scalar / installs /
search / saved response. This did not establish a useful gain on the primary
control and response paths. The dominant installation transfer is a suspended
continuation with a result hole, which this exact-array rule does not address.
The [prototype](performance/exact-handoff-prototype.patch.txt) was removed;
[measurements](performance/exact-handoff-performance.json) and
[public-path conformance](performance/exact-handoff-conformance.json) remain.
This narrow variant alone did not settle the storage question; the fuller
continuation-view experiment below supplies its final measured disposition.

## Private continuation-view experiment: rejected

The fuller prototype targeted the growing installation family's suspended
continuations. Store owned an immutable evaluated-slot buffer plus the admitted
edge's argument mapping, avoiding construction of the optional-value argument
array. A shared projection preserved result holes, permutations and repeated
arguments. Generic reads and publication materialized ordinary continuation
records; resume could read the view directly. Collection traced only mapped
values, and a failure-swept regression showed that an unused 64 KiB blob was
reclaimed. Each dynamic evaluated buffer had one owner; small or sparse captures
used the ordinary path. The prior small-capture map regression was inspected
before adding this private index.

The [prototype patch](performance/continuation-view-prototype.patch.txt) is
historical only; it has been removed from production and from active tests.
The [native profile](performance/continuation-view-memory.json) observed 245
unmaterialized views across 321 installation transitions, confirming that the
intended path ran. Complete working peak was 140,036 bytes both before and after.
The [public comparison](performance/continuation-view-performance.json), using
the same flattened-admission Boundary revision on both sides, produced ratios
1.041 / 1.115 / 1.013 / 0.999 for scalar / installations / search / response.
All outcome bytes matched. The
[advance comparison](performance/continuation-view-advance.json) matched all 320
progressed checkpoints and final output with actual producer alternation.

This implementation did not repay its indexing, projection and materialization
costs. It is a non-winning disposition of the required focused private-storage
experiment, not a claim that every stable-storage representation is impossible.
The direct-ownership implementation remains the comparator. Collection cadence
is evaluated separately; a materially different tracing policy would require
fresh evidence before reconsidering this view representation.

## Allocation-pressure collection experiment: rejected

A separate prototype accounted for newly owned record buffers and blobs, live
payload, spare node capacity and retained traversal scratch. It forced
collection before publication and on every `advance`, without a semantic step
budget. Its history-free control test ran 10,000 transitions with at most three
stored control slots, avoiding capacity-feedback growth. Native checks passed.

The [prototype](performance/collection-cadence-prototype.patch.txt) has been
removed. [Timing](performance/collection-cadence-performance.json) ratios were
1.007 / 1.046 / 1.000 / 1.012 for scalar / installations / search / response.
[Memory and work counters](performance/collection-cadence-memory.json) show
installation traced nodes falling from 832 to 448, but unchanged 140,036-byte
full peak; the short and eight-installation peaks were also unchanged. Search
peak rose from 122,612 to 122,686 bytes. Complete output hashes matched.
The accounting and scheduling costs did not repay the avoided traces. Existing
per-transition collection remains the production policy. This completes the
separate cadence experiment without claiming that every pressure policy loses.

## Refreshed external-consumer freeze

The retained kernel has SHA-256
`9545076f16482ccb346ab7792ae87f4d9a262c3fe08b4086b3c376ed2b218c06`.
The existing external-consumer check correctly rejected it against the previous
frozen digest. The September 9 freeze is preserved in
`test/v2/external/freeze-2026-09-09.json`; the new freeze records the actual
candidate before authoring `sum_squares.zig`. The original consent program and
all its checks remain intact.

The new separate public-compiler consumer yields and then recursively computes
a sum of squares. Independent closed-form expectations cover inputs 0 through
16 and authored overflow at 2^32. Together with the original consent program,
813 complete records matched native, JavaScript and Wasmtime while alternating
the producer at every advance checkpoint; run matched those boundary records.
`zig build check-v2-external -Doptimize=ReleaseSafe` passed with explicit Boundary
source and isolated cache. [Evidence summary](performance/post-freeze-external.json)
records image/source/kernel identities and the full output-log digest.

Boundary's retained data tree is committed as
`b599e664c57ca455395038bd28b703837f870030`; its full `check-v2` passed. The first
World aggregate attempt also required explicit historical-kernel/lifter paths.
The v1.8.2 release kernel was downloaded and verified against its published
SHA-256 `4da38268f12e8a2749a266480748da5460b5030dadfc10804f79ba3a3bb8013e`.
The aggregate rerun supplied that kernel and a separately built current BPI1
lifter and passed (exit 0). It includes 33 legacy cases with 38 native/JS/Wasmtime
checkpoints, 41 source fixtures, full portable transfers, native ownership/failure
checks, capacity checks, separate physical package installations, and both
external consumers. The exact command was:

```sh
zig build check-v2 -Doptimize=ReleaseSafe \
  -Dboundary-v2-source=/Users/tk/.codex/worktrees/e38a/boundary \
  -Dboundary-v2-fixtures=/Users/tk/.codex/worktrees/e38a/boundary/zig-out \
  -Dlegacy-v1-kernel=/Users/tk/.codex/worktrees/perf-reference/results/legacy-release/boundary-process-kernel-v1.wasm \
  -Dbpi1-lift=/Users/tk/.codex/worktrees/perf-reference/results/legacy-lifter/bin/bpi1-lift \
  --global-cache-dir /Users/tk/.codex/worktrees/e38a/world-global
```
