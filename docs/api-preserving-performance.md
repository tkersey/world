# API-preserving performance results

The retained World implementation removes temporary buffer copies and redundant
request serialization while preserving World 5.0's public API, ABI, ownership,
errors, capacity behavior, protocols and fresh-instance lifecycle. Combined
Boundary/World measurements show improvements in installation and saved-response
workloads. No uniform speedup or universal non-regression claim is made.

[Boundary's report](https://github.com/tkersey/boundary/blob/perf/api-preserving-data-path/docs/api-preserving-performance.md)
owns the shared baseline selection, Boundary mechanisms, binary-size conclusion,
cold-build reproduction and compiler experiments. The shared
[validation summary](https://github.com/tkersey/boundary/blob/perf/api-preserving-data-path/docs/performance/validation.md)
provides exact checked inputs, commands, outcomes and accessible logs for both
repositories. Delivery remains draft [World #52](https://github.com/tkersey/world/pull/52)
and [Boundary #150](https://github.com/tkersey/boundary/pull/150).

## Retained production mechanisms

Store takes fully initialized node allocations only on success; callers retain
ownership on failure. Continuation arguments, resumed controls, jumps, calls,
closure environments, initial and captured-plus-explicit arguments, handler
state, use-site captures and cleanup discard positions construct their final
buffers once. Borrowed replacement still copies before releasing the old node,
including overlapping input; owned replacement does not accept borrowed slices.
Nested cancellation text is separately owned before replacing an Exit.

Store reuses private collection marks and traversal storage, resets it before
tracing and frees it with Store. Roots and per-transition collection cadence
are unchanged. Its isolated timing was inconclusive; combined results follow.

Response admission and publication use one request-construction path and the
existing protocol identity/validation functions, avoiding temporary ERQ2 encode
and decode. Admitted canonical snapshot bytes supply the pending-state digest;
records input still emits canonical bytes. The request borrows admitted State,
schema buffers live through validation, and resumed values belong to Store.
No caller trust flag, cross-invocation cache or second interpreter was introduced.

## Runtime results

The clean measured candidates were Boundary
`b599e664c57ca455395038bd28b703837f870030` and World
`24867d20afd2076136c0cb14d64fee3a951d0f96`, against Boundary
`55e8feedcae0b9ee1492da11f9fbd4a1ac7ff328` and approved World correctness
successor `87698f92ca7be4d5442e97ba27a2468aa3ff6a7c`.
Zig 0.16.0, native ReleaseSafe and repository-fixed guest ReleaseSmall were used.
The retained paired kernel is 393,588 bytes, SHA-256
`9545076f16482ccb346ab7792ae87f4d9a262c3fe08b4086b3c376ed2b218c06`;
the baseline is 395,094 bytes. This kernel-size difference is separate from BPI2
program size, which is unchanged.

Two separated confirmation windows used five warmup batches and 21 alternating
AB/BA pairs, each batch containing 200 full loaded-host calls with a fresh WASM
instance per invocation. No builds or other benchmarks overlapped these windows.
The table reports **medians of batch-average full-call times**, in milliseconds.
Each ratio is **candidate median divided by baseline median**.

| Public call | Window 1 baseline → candidate | Ratio of medians | Window 2 baseline → candidate | Ratio of medians |
|---|---:|---:|---:|---:|
| Small invocation | 0.1010 → 0.1005 | 0.995 | 0.0948 → 0.0912 | 0.963 |
| 64 installations, run | 0.7350 → 0.6320 | 0.860 | 0.7073 → 0.6011 | 0.850 |
| Retained search to first boundary | 0.6243 → 0.6047 | 0.969 | 0.5962 → 0.5721 | 0.960 |
| Saved search response | 1.2046 → 0.9086 | 0.754 | 1.1478 → 0.8615 | 0.751 |

[Window 1](performance/final-window-1.json), [window 2](performance/final-window-2.json)
and [paired summaries](performance/final-runtime-summary.json) retain raw rows
and uncertainty. The summaries' **median paired ratios** take the median of each
candidate/baseline pair's ratio; they are distinct from the table's ratios of
medians. These are not distributions of individual request latency and establish
no p99 behavior. Module-admission setup is recorded separately, without a
statistically established startup-improvement claim. Small-call results remain
sensitive to host overhead.

These gains belong to the paired B1/W1 implementation. They do not establish the
full gain from Boundary codec changes alone. The synthetic retained-search
workload is the public four-queens composition, combining retained branches,
local/shared cells, repeated acquire/use/release interactions, owned resources,
yielding and cleanup. It is not production Agent evidence.

[Secondary observations](performance/final-secondary.json) cover eight
installations, 64 KiB blob capture, lexical captures, local/shared state, shallow
multishot, generator, scheduler, owned cleanup and recursion. The complete
321-call repeated-advance sequence measured 266.2 → 265.0 ms, effectively
unchanged; every checkpoint hash matched. The 10,000-call recursive case measured
7.67 → 5.41 ms. These have one secondary window, not two-window confirmation.
[Larger fixtures](performance/final-large.json) measured 128 installations at
1.922 → 1.660 ms and the stored 64 KiB constant at 0.499 → 0.497 ms, effectively
unchanged. Their BPI2 sizes remain 30,141 and 65,652 bytes; the constant remains
one stored payload referenced twice.

## Memory

| Complete native invocation working peak, bytes | B0/W0 | B1/W1 |
|---|---:|---:|
| 1 installation | 19,153 | 9,042 |
| 8 installations | 27,333 | 16,590 |
| 64 installations | 218,915 | 140,036 |
| 128 installations | 1,422,367 | 660,850 |
| Local state | 56,851 | 25,906 |
| Stored 64 KiB constant | 493,193 | 493,193 |

[Invocation counters](performance/final-invocation-memory.json) include PKI2
decode, Program preparation, execution and output encoding. These are
allocator-requested working payload bytes within a fixed 16 MiB native
reservation, not RSS or a reduction in reserved capacity. The final output buffer
has separate caller ownership.
[Decoder measurements](performance/final-decoder-memory.json) instead use a
fixed 1 MiB Workspace; Boundary's report owns the 64-installation retention
comparison. Baseline decoding of 128 installations exhausts
that workspace; the candidate retains 511,086 bytes with a 660,850-byte peak.
Large-constant decoder retention is 98,540 bytes on both sides; scratch raises
peak by 1,384 bytes, while the complete invocation peak is unchanged.
No universal memory reduction or elimination of quadratic interfaces is claimed.

## Compatibility and packaging

The production ownership, aliasing, cyclic-GC, freed-slot, allocation-failure,
stale-response and records/snapshot equality regressions remain intact.
Source-oracle/native/JavaScript/Wasmtime comparisons include fresh transfers,
cancellation and no-successor-on-exhaustion with unchanged-input retries.
The validation summary binds aggregate, cross-version and package evidence.
[CLI observations](performance/cli-compatibility.json),
[external crossings](performance/external-crossing.json) and
[large-fixture conformance](performance/large-conformance.json) retain earlier
byte comparisons and independently calculated fixture expectations.

World owns four supplemental cleanup vectors and their independent expectations,
so its unchanged Boundary pin can run the same cleanup regressions. Two defects
in the exact pinned source oracle are explicitly recognized; kernel expectations
keep corrected failure/finalizer semantics. Other compiler-supplied cases remain
unchanged. The post-freeze checker admits only two frozen supported kernels:
the paired kernel above and pinned-source kernel
`0da1f478fa1de495c2354724a8b90d7279fd7219c4dcde7f9f79dff85c1e06b6`.
All three consumers pass 833 exact records with each; unknown kernels reject.
Archive source inventory, kernel authentication and public pins remain unchanged.

## Rejected experiments and historical failures

| Experiment | Disposition and evidence |
|---|---|
| Exact-array handoff | Removed: primary control/response ratios 0.998/0.999/0.999 did not establish a useful gain over direct ownership. [Timing](performance/exact-handoff-performance.json), [conformance](performance/exact-handoff-conformance.json), [patch](performance/exact-handoff-prototype.patch.txt). |
| Continuation views | Removed: 245 actual unmaterialized views across 321 transitions, unchanged 140,036-byte peak, 11.5% installation slowdown. [Timing](performance/continuation-view-performance.json), [memory](performance/continuation-view-memory.json), [advance equality](performance/continuation-view-advance.json), [patch](performance/continuation-view-prototype.patch.txt), `NEG-000012`. This rejects this representation, not every stable-storage design. |
| Allocation-pressure GC | Removed: traced nodes 832 → 448, unchanged installation peak, 4.6% installation slowdown; search peak 122,612 → 122,686 B. [Timing](performance/collection-cadence-performance.json), [counters](performance/collection-cadence-memory.json), [patch](performance/collection-cadence-prototype.patch.txt), `NEG-000013`. Existing cadence retained. |
| Intermediate Exit ownership | Fixed before acceptance: missing nested cancellation ownership caused a dangling read. The existing primary-failure/finalizer regression and added failure sweep cover the corrected path. |
| Short-batch exploration | Earlier 20-call batches produced noisy scalar results. [GC diagnostics](performance/host-gc-diagnostic.txt) and [instrumented rows](performance/host-gc-diagnostic.json) remain historical. The two final 200-call windows supersede the dirty [long-batch exploration](performance/complete-ownership-long-batches.json). |
| Invalid secondary input | [Aborted run](performance/secondary-aborted-run.json) used an invalid empty blob argument. It receives no acceptance credit; the corrected full observation remains separately available. |

Archived patches are reproduction material, absent from production and active
tests. All raw observations and unfavorable results remain. Boundary's rejected
compiler pass achieved no retained smaller-BPI2 result. Neither these results nor
the cold guard establish the separate historical 0.80 compilation target.
