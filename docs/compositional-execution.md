# World 6 successor status

World 6.0.0-dev.0 executes stable-activation Programs through one evaluator, with
fresh and prepared/resident operation, portable checkpoints and a browser-neutral
embedding. The successor remains incomplete; all linked PRs remain drafts.
Contracts and commands are in [kernel-abi.md](kernel-abi.md) and
[verification.md](verification.md).

## Current construction and validation

Unsupported forwarding constructors and handler fields are retired upstream.
World no longer carries an unreachable forwarding rejection; its control switch
is exhaustive over current terminators. Older-capability dispatch remains covered
by the scoped-reader forwarding witness. All 42 emitted images retain their bytes.

Slot pages determine initialization. Conservative pruning bounds grant no read or
ownership authority; retained views remain copy-on-write. Consuming continuations
and replacing exclusively active controls reuse their owned nodes. Captured callers
remain continuations, and multi-shot captures are cloned before activation.
Resident failure sweeps preserve retry input, frame custody and cleanup.

Qualified 64-bit native execution elides an immediately consumed, reusable,
capture-free handler callable only when arguments, state and all declared edge
sources cannot retain it. Both work units remain charged; strict stepping keeps
the intermediate boundary. Native sequence consumption also reclaims dead cursors
early, preserving live aliases. WASM retains ordinary callable construction and
its existing collection schedule after those shortcuts regressed guest timing.

The workspace now supports in-place remap for growable arrays. It preserves the
pointer and retained prefix, consumes only physically adjacent free blocks, and
repairs the free-list hint after splitting/coalescing. Failed requests preserve
allocation contents and metadata; the required-capacity observation may increase.
Nonmoving resize remains unsupported, preserving arena-slab growth behavior.

The current candidate passes 84 native source tests, 65 storage tests, 42
source/native/WASM fixtures (6,434 observations), 239 native/Node boundaries,
23 transfers, 161 Wasmtime boundaries, Chromium/Firefox Worker transfers, capacity
checks and extracted runtime/CLI checks. Allocator regressions cover alignment,
failed growth, earlier holes, noncontiguous segments and 10,000 mixed operations
with independent content/accounting/partition checks. Baseline-native versus
candidate-guest canonical outputs also agree at the checked boundaries.

The generic kernel is 462,524 bytes, SHA-256
`8f7b6359ddf4d63b513d8d5c17400487fde357cb487831bb2b555a449f39ee0b`.

## Cumulative native and guest comparison

The current measured pair is Boundary 1b00c8c / World a20a285, taken from Agent's
authenticated inputs, against the fixed Boundary 42a09b9 / World d075169 anchors.
The same 45 standalone control/value fixtures and independent trace/result
oracles run under normal BPI2, compact BPC1 and BPI3. Source policy, handlers,
input/reply values, checked sums and physical capacities are unchanged.

Two windows rotate format order. Each process has three warmups and nine samples;
most cases have three processes per format/window. Mixed/irregular128/256 and
sequence1024/4096 have one per format/window. Tables report medians of process
medians across both windows, not request-tail statistics. Zig 0.16.0 ReleaseSafe,
Node 26.9.0 and M2 Pro/macOS 27.2 were held fixed, with no overlapping builds or
benchmarks. Clocks cover complete fresh invocations; control-fixture reply encoding
and oracle checks are outside the clock. Projections repeat 256 times; sequences
consume every element. Projection sizes are bytes, sequence sizes element counts.

| Workload | Native BPI2 µs | Native BPC1 µs | Native BPI3 µs | Native peak bytes BPC1 → BPI3 | Guest BPI2 / BPC1 / BPI3 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| scalar | 1.85 | 1.77 | 2.42 | 3,594 → 4,406 | 1.282 / 1.262 / 0.447 |
| deep | 9.79 | 9.83 | 11.25 | 10,784 → 13,889 | 1.379 / 1.366 / 0.495 |
| residual | 14.88 | 14.54 | 12.77 | 12,726 → 11,481 | 2.758 / 2.849 / 0.798 |
| reentrant | 155.27 | 154.58 | 93.63 | 127,125 → 102,931 | 3.843 / 3.706 / 1.266 |
| shallow | 319.81 | 320.48 | 208.10 | 145,914 → 149,898 | 2.083 / 2.183 / 0.989 |
| generator | 240.90 | 240.48 | 145.98 | 58,859 → 53,163 | 4.331 / 4.311 / 1.577 |
| scheduler | 417.31 | 422.73 | 221.06 | 88,240 → 87,857 | 3.287 / 3.339 / 1.317 |
| queens_dfs | 8206.79 | 8189.81 | 3072.63 | 142,727 → 161,300 | 23.152 / 23.411 / 9.905 |
| queens_bfs | 10953.75 | 11077.67 | 3146.94 | 153,579 → 213,208 | 27.379 / 27.349 / 9.463 |
| cleanup | 295.46 | 300.92 | 170.60 | 43,221 → 44,827 | 6.932 / 6.479 / 2.100 |
| install / 1 | 8.00 | 7.96 | 8.65 | 8,700 → 10,995 | 1.220 / 1.170 / 0.327 |
| install / 8 | 23.00 | 23.10 | 28.58 | 15,564 → 24,199 | 1.247 / 1.197 / 0.416 |
| install / 64 | 252.60 | 241.60 | 226.50 | 121,956 → 135,051 | 1.743 / 1.683 / 0.953 |
| install / 128 | 739.00 | 703.94 | 476.10 | 435,558 → 227,570 | 2.857 / 2.564 / 1.482 |
| install / 256 | 2526.75 | 2339.19 | 985.94 | 1,324,938 → 365,015 | 6.707 / 5.910 / 2.686 |
| mixed / 1 | 18.23 | 18.15 | 17.48 | 13,900 → 13,038 | 2.512 / 2.352 / 0.700 |
| mixed / 8 | 204.06 | 203.71 | 151.21 | 18,104 → 20,663 | 11.699 / 11.382 / 3.282 |
| mixed / 64 | 16122.46 | 15414.02 | 5038.83 | 157,992 → 75,234 | 114.974 / 112.513 / 33.674 |
| mixed / 128 | 104424.73 | 98535.05 | 20599.85 | 550,276 → 171,155 | 402.003 / 380.822 / 95.485 |
| mixed / 256 | 775457.90 | 728132.97 | 89877.17 | 1,951,618 → 320,644 | 2191.478 / 2111.399 / 340.323 |
| irregular / 1 | 18.27 | 18.25 | 17.65 | 13,898 → 13,026 | 2.290 / 2.357 / 0.738 |
| irregular / 8 | 204.67 | 203.04 | 150.79 | 18,104 → 20,663 | 10.528 / 11.049 / 3.203 |
| irregular / 64 | 16047.73 | 15471.44 | 5019.00 | 157,992 → 74,982 | 119.856 / 111.593 / 33.112 |
| irregular / 128 | 104261.08 | 98356.79 | 20380.15 | 550,276 → 170,697 | 397.132 / 380.676 / 94.739 |
| irregular / 256 | 777783.90 | 729663.00 | 90127.17 | 1,951,618 → 319,681 | 2187.653 / 2012.172 / 335.885 |
| retained_loop / 1 | 17.52 | 18.10 | 21.50 | 14,576 → 20,589 | 1.197 / 1.196 / 0.372 |
| retained_loop / 8 | 31.85 | 31.79 | 35.79 | 14,614 → 20,625 | 1.195 / 1.196 / 0.400 |
| retained_loop / 64 | 140.02 | 141.98 | 144.31 | 14,614 → 20,713 | 1.386 / 1.386 / 0.692 |
| retained_loop / 128 | 264.69 | 266.54 | 269.23 | 14,626 → 20,720 | 1.677 / 1.631 / 0.933 |
| retained_loop / 256 | 513.15 | 529.06 | 523.23 | 14,626 → 20,720 | 2.118 / 2.073 / 1.483 |
| variant / unit | 141.29 | 141.06 | 191.87 | 7,232 → 9,678 | 1.415 / 1.349 / 0.724 |
| variant / 0 | 153.04 | 152.73 | 189.25 | 7,232 → 9,680 | 1.468 / 1.430 / 0.706 |
| variant / 1024 | 191.56 | 193.81 | 187.35 | 8,105 → 11,731 | 1.623 / 1.587 / 0.762 |
| variant / 65536 | 2779.81 | 2761.29 | 206.88 | 137,131 → 140,758 | 11.382 / 11.141 / 0.816 |
| variant / 1048576 | 38790.06 | 38253.90 | 341.02 | 2,103,211 → 2,106,838 | 155.811 / 153.921 / 1.825 |
| product / 0 | 163.79 | 161.90 | 197.71 | 7,232 → 9,698 | 1.508 / 1.454 / 0.731 |
| product / 1024 | 205.46 | 204.10 | 196.62 | 8,202 → 11,749 | 1.652 / 1.671 / 0.785 |
| product / 65536 | 2759.63 | 2741.73 | 209.48 | 137,228 → 140,776 | 11.414 / 11.282 / 0.832 |
| product / 1048576 | 37390.90 | 37351.52 | 356.60 | 2,103,308 → 2,106,856 | 155.670 / 153.920 / 1.709 |
| sequence / 0 | 4.92 | 4.88 | 5.71 | 8,382 → 9,927 | 1.182 / 1.178 / 0.334 |
| sequence / 16 | 35.37 | 35.00 | 23.88 | 8,382 → 16,311 | 1.254 / 1.232 / 0.372 |
| sequence / 64 | 188.35 | 185.13 | 73.19 | 13,597 → 17,003 | 1.504 / 1.486 / 0.550 |
| sequence / 256 | 1541.29 | 1593.54 | 270.10 | 27,813 → 20,845 | 4.003 / 3.890 / 0.936 |
| sequence / 1024 | 19211.92 | 20170.29 | 1079.21 | 84,645 → 37,636 | 34.278 / 33.815 / 2.698 |
| sequence / 4096 | 286336.33 | 302179.58 | 4281.71 | 311,973 → 105,221 | 483.311 / 476.262 / 9.564 |

The guest confirmation uses the same 45 authored workloads and all 982 captured
fresh invocations per format/window, with three warmups and nine timed calls per
input in two rotating, isolated-process windows. Every captured control trace and
value result first passes the maintained independent native oracle; every guest
output must then equal that capture. All 982 BPI2/BPC1 outcomes also agree byte for
byte. Guest columns show second-window sums of per-input medians in milliseconds,
not whole-scenario or tail timing. Timers include kernel authentication/admission,
setup, input encoding, fresh execution and outcome decoding; file loading and input
reconstruction are outside them. The same authenticated release/current kernels
and their 256 MiB maximum-memory profiles are used. This is fresh execution, not
prepared/resident execution with a weaker checkpoint obligation.

All 45 guest workload totals are lower than compact BPC1 in both windows. Selected
BPI3/BPC1 ratios are installation64 0.566–0.576, installation256 0.454–0.469,
queens BFS about 0.346, mixed256 0.161–0.168, sequence4096 about 0.020, and 1 MiB
product projection 0.0111–0.0116. Small guest totals include substantial host/setup
cost; these observations are not inferred from the accepted native regressions.
They do not measure browser timing or guest peak memory.

Installation64 latency is now below BPC1 in both windows, with separated observed
process ranges; its peak-memory gap remains. Installation128/256 retain large
improvements, and their complete default images remain 2,241/4,559/9,551 bytes
at 64/128/256 versus BPC1's 2,805/5,574/12,102. Mixed/irregular256 are about 8×
faster, sequence4096 about 70×, and large product/variant projections about 100×.
These are workload-specific results, not a uniform speedup claim.

Unfavorable observations remain: scalar, deep, installation1/8, retained-loop1/8,
tiny projections and empty sequence are slower than BPC1. Retained-loop64/256
ranges overlap; retained-loop128 is about 1% slower in this run. Variant1024 ranges
also overlap. Installation1/8/64, shallow, queens, cleanup, mixed/irregular8,
retained loops, short sequences and projections retain higher peaks. Favorable
cases do not cancel those residuals or establish full performance acceptance.

The existing suspension-reclamation witness remains separate: a tiny survivor of
large dead backing retains 8,182 native working bytes and an 86-byte checkpoint,
with independent live-alias checks. This cumulative run does not repeat that
unchanged witness or the host-transfer matrix.

Guest remap confirmation remains bound to its earlier exact candidate: peaks were
unchanged and timing differences were mixed. Unrestricted in-place resize was
rejected after raising installation256 peak to 420,861 bytes. The selected remap
path retains the arena-slab policy. No rejected implementation, raw samples or
experiment archives are maintained.

## Milestone performance disposition

The September 19 task amendment accepts these measured native latency tradeoffs
for this milestone on Boundary 1b00c8c / World a20a285. They are regressions accepted
by the user, not improvements, noise, or general percentage allowances. Projection
rows measure the complete workload of 256 operations.

| Workload | BPC1 → BPI3 µs |
| --- | ---: |
| scalar | 1.77 → 2.42 |
| deep | 9.83 → 11.25 |
| install / 1 | 7.96 → 8.65 |
| install / 8 | 23.10 → 28.58 |
| retained_loop / 1 | 18.10 → 21.50 |
| retained_loop / 8 | 31.79 → 35.79 |
| variant / unit | 141.06 → 191.87 |
| variant / 0 | 152.73 → 189.25 |
| product / 0 | 161.90 → 197.71 |
| sequence / 0 | 4.88 → 5.71 |

The amendment does not accept new or materially worsened regressions, memory or
capacity failures, unbounded growth, missing structural behavior, semantic failures,
WASM regressions, or material Agent-consumer regressions. Indeterminate observations
remain indeterminate. No native benchmark rerun is needed for this documentation
change. The unamended performance gate is not claimed to have passed.

### Accepted memory tradeoffs

The following complete-fresh-invocation peaks use the same native source tuple and
fixed optimized BPC1 predecessor as the cumulative table. They are working-allocation
peaks, not RSS, reserved capacity, checkpoint bytes, or post-completion retention.
The table preserves every higher peak; percentages use BPC1 as denominator.

| Workload | BPC1 → BPI3 bytes | Increase | Increase % |
| --- | ---: | ---: | ---: |
| scalar | 3,594 → 4,406 | +812 | +22.59% |
| deep | 10,784 → 13,889 | +3,105 | +28.79% |
| shallow | 145,914 → 149,898 | +3,984 | +2.73% |
| queens_dfs | 142,727 → 161,300 | +18,573 | +13.01% |
| queens_bfs | 153,579 → 213,208 | +59,629 | +38.83% |
| cleanup | 43,221 → 44,827 | +1,606 | +3.72% |
| install / 1 | 8,700 → 10,995 | +2,295 | +26.38% |
| install / 8 | 15,564 → 24,199 | +8,635 | +55.48% |
| install / 64 | 121,956 → 135,051 | +13,095 | +10.74% |
| mixed / 8 | 18,104 → 20,663 | +2,559 | +14.13% |
| irregular / 8 | 18,104 → 20,663 | +2,559 | +14.13% |
| retained_loop / 1 | 14,576 → 20,589 | +6,013 | +41.25% |
| retained_loop / 8 | 14,614 → 20,625 | +6,011 | +41.13% |
| retained_loop / 64 | 14,614 → 20,713 | +6,099 | +41.73% |
| retained_loop / 128 | 14,626 → 20,720 | +6,094 | +41.67% |
| retained_loop / 256 | 14,626 → 20,720 | +6,094 | +41.67% |
| variant / unit | 7,232 → 9,678 | +2,446 | +33.82% |
| variant / 0 | 7,232 → 9,680 | +2,448 | +33.85% |
| variant / 1024 | 8,105 → 11,731 | +3,626 | +44.74% |
| variant / 65536 | 137,131 → 140,758 | +3,627 | +2.64% |
| variant / 1048576 | 2,103,211 → 2,106,838 | +3,627 | +0.17% |
| product / 0 | 7,232 → 9,698 | +2,466 | +34.10% |
| product / 1024 | 8,202 → 11,749 | +3,547 | +43.25% |
| product / 65536 | 137,228 → 140,776 | +3,548 | +2.59% |
| product / 1048576 | 2,103,308 → 2,106,856 | +3,548 | +0.17% |
| sequence / 0 | 8,382 → 9,927 | +1,545 | +18.43% |
| sequence / 16 | 8,382 → 16,311 | +7,929 | +94.60% |
| sequence / 64 | 13,597 → 17,003 | +3,406 | +25.05% |

- **Installation64: +13,095 bytes (+10.74%).** A read-only admission probe on
  this production pair found 22,572 bytes of unused arena tail capacity (16,028
  decoded-record bytes and 6,544 analysis bytes). Total admitted live storage was
  100,170 bytes. This establishes retained allocation slack, not a proof that all
  of the comparative peak comes from slack. No completely unused slabs remained.
  The 1/8/64/128/256 peak curve is reported above; 128 and 256 use substantially
  less memory than BPC1, and the stable-slot structural checks retain the final
  sum and all genuinely live results without triangular boundary lists.
  **Recommendation: accept the named installation-family storage tradeoff** on
  this tuple, subject to the final requirement audit; no allocator redesign is
  proposed. The 1/8 costs are reported separately above, not inferred to be fixed.
- **Queens/search: DFS +18,573 bytes (+13.01%); BFS +59,629 (+38.83%).** An
  untimed current-tuple lifetime probe, using the unchanged full trace oracle,
  reproduces both peaks exactly. DFS first reaches 161,300 during checkpoint/request
  production, from 103,304 live bytes before that phase to 111,874 afterward. BFS
  reaches 213,208 in the same phase, from 120,256 live bytes to 130,108 afterward.
  Thus 49,426 / 83,100 bytes at those peaks are no longer retained when the phase
  returns. The immutable preparation owner accounts for 59,652 bytes in either
  search. The request boundaries retain at most 53 / 65 live nodes and 7 / 8
  activation pages; each final computation has one result node and no activation
  pages. Every fresh invocation returns to zero workspace allocations after its
  owners release. The required complete checkpoint temporarily coexists with
  session data and projection/admission scratch; this is not evidence of a leak.
  **Recommendation: accept these named transient checkpoint peaks** for the fixed
  qualified searches. This does not establish bounded memory for arbitrary larger
  searches or credit latency gains as memory evidence.
- **Retained loops: about 6 KB additional peak.** The candidate peak reaches
  20,720 bytes at 128 iterations and remains there at 256; checkpoints and retained
  old-view regressions exercise isolation and reclamation separately. This is
  evidence of bounded cost over the tested range, not a universal constant bound.
  **Recommendation: accept this named tested-range storage tradeoff.**
- **Variant/product projections:** the payload-bearing 1,024/65,536/1,048,576-byte
  cases have nearly constant additional peaks (variant 3,626–3,627 bytes;
  product 3,547–3,548). Tiny cases have smaller absolute increases. Large-payload
  selective access and live-alias/small-survivor tests remain required and passed
  in the recorded qualification. **Recommendation: accept the reported projection
  storage costs**, without generalizing the offset to unmeasured schemas.
- **Short sequences:** peaks are higher at 0/16/64 elements and lower than BPC1
  at 256/1,024/4,096. The existing cursor reclamation and rollback tests protect
  consuming traversal; the long cases do not reintroduce repeated tail copying.
  **Recommendation: accept the named short-sequence tradeoff**, retaining those
  scaling and reclamation limits.
- **Scalar/deep:** the lifetime probe reaches the 4,406 / 13,889 peaks during
  execution. Preparation owns 2,080 / 8,802 bytes; terminal sessions retain one
  result node and no activation pages. Full release returns to zero allocations.
  **Recommendation: accept these named fixed-fixture working peaks**, not an
  inference that arbitrary small Programs have constant overhead.
- **Shallow:** the 149,898-byte peak occurs during preparation; live allocation
  falls to 49,461 after preparation/start, including a 45,592-byte prepared owner.
  The final computation has one result node and no activation pages, and full
  invocation release returns to zero. **Recommendation: accept this named transient
  preparation cost**; its +3,984 bytes (+2.73%) is not retained session growth.
- **Cleanup and mixed/irregular8:** peaks of 44,827 / 20,663 occur during output
  and checkpoint production, while preserving suspending cleanup and the original
  trace. They remain live until the exported outcome is encoded and released;
  every complete invocation then returns to zero allocations. Mixed/irregular
  64/128/256 have lower peaks than BPC1 in the existing scaling table.
  **Recommendation: accept these named output-production tradeoffs.**

The lifetime probe adds observations only to an isolated copy of the current
runtime and uses the maintained execution benchmark's independent expectations.
It does not change inputs, transitions, allocation calls, collection, or physical
capacities. All nine observed peaks exactly match the uninstrumented cumulative
measurements. It attributes current peaks by phase and release lifetime; it does
not claim a byte-for-byte decomposition of the predecessor-to-successor difference.
No instrumentation or generated trace is retained in the repository.

The user explicitly accepted these named memory tradeoffs on September 19 after
reviewing this disposition, including installation64 and both queens/search peaks.
The recommendations above preserve the supporting reasoning and limits; they are
now accepted milestone costs, not improvements or a general allowance.
Agent-specific peak/checkpoint
costs and its larger ReAct image are separately reported in
[Agent's results](https://github.com/tkersey/agent/blob/feat/compositional-execution/docs/compositional-execution.md).

## Remaining acceptance work

Standalone guest and inquiry/ReAct confirmation on the selected production tuple
are complete; Agent's document records its clarification confirmation separately.
The named native latency and memory tradeoffs are accepted for this milestone.
The requirement audit identified a narrow State-inspector gap; Agent now provides
and tests the required read-only Program/State inspection. Serial-review closeout
remains. Optional representation/allocator/cache/compiler redesign is not a
closeout requirement. No such experiment is retained.

The [current build confirmation](https://github.com/tkersey/agent/blob/b277743aa2a8f0609428accd267b8719b64285ed/docs/compositional-execution.md#component-build-costs)
separates native build, warm no-change, client edit, emission and component reuse.
The matched source-only build plus first emission is 16.45–17.38 s for BPC1 and
16.62–16.89 s for BPI3: overlapping ranges, with no consistent cold-build gain.
Already-built installation256 emission is about 29.4 ms versus 4.4 ms. Native
component tools still take 22.56–23.26 s to build and 15.01–15.02 s after a client
edit; unchanged components remain reusable. No all-application build gain is claimed.

Small standalone probes under `test/v2/` accept explicit source inputs:
`build_execution_bench.zig`, `build_value_bench.zig`, and `build_replay_bench.zig`.
Generated samples, profiles and experimental patches are not maintained.
The Agent adequacy obstruction and minimal reproducer remain intact.

Linked drafts: [Boundary #152](https://github.com/tkersey/boundary/pull/152),
[World #54](https://github.com/tkersey/world/pull/54),
[Agent #32](https://github.com/tkersey/agent/pull/32).
Future landing order is Boundary → World → Agent, only when separately authorized.
No merge, promotion or release is authorized. Current-tree deletion does not purge
historical Git objects.
