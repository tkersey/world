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

## Cumulative native comparison

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

| Workload | BPI2 µs | BPC1 µs | BPI3 µs | Peak bytes BPC1 → BPI3 |
| --- | ---: | ---: | ---: | ---: |
| scalar | 1.85 | 1.77 | 2.42 | 3,594 → 4,406 |
| deep | 9.79 | 9.83 | 11.25 | 10,784 → 13,889 |
| residual | 14.88 | 14.54 | 12.77 | 12,726 → 11,481 |
| reentrant | 155.27 | 154.58 | 93.63 | 127,125 → 102,931 |
| shallow | 319.81 | 320.48 | 208.10 | 145,914 → 149,898 |
| generator | 240.90 | 240.48 | 145.98 | 58,859 → 53,163 |
| scheduler | 417.31 | 422.73 | 221.06 | 88,240 → 87,857 |
| queens_dfs | 8206.79 | 8189.81 | 3072.63 | 142,727 → 161,300 |
| queens_bfs | 10953.75 | 11077.67 | 3146.94 | 153,579 → 213,208 |
| cleanup | 295.46 | 300.92 | 170.60 | 43,221 → 44,827 |
| install / 1 | 8.00 | 7.96 | 8.65 | 8,700 → 10,995 |
| install / 8 | 23.00 | 23.10 | 28.58 | 15,564 → 24,199 |
| install / 64 | 252.60 | 241.60 | 226.50 | 121,956 → 135,051 |
| install / 128 | 739.00 | 703.94 | 476.10 | 435,558 → 227,570 |
| install / 256 | 2526.75 | 2339.19 | 985.94 | 1,324,938 → 365,015 |
| mixed / 1 | 18.23 | 18.15 | 17.48 | 13,900 → 13,038 |
| mixed / 8 | 204.06 | 203.71 | 151.21 | 18,104 → 20,663 |
| mixed / 64 | 16122.46 | 15414.02 | 5038.83 | 157,992 → 75,234 |
| mixed / 128 | 104424.73 | 98535.05 | 20599.85 | 550,276 → 171,155 |
| mixed / 256 | 775457.90 | 728132.97 | 89877.17 | 1,951,618 → 320,644 |
| irregular / 1 | 18.27 | 18.25 | 17.65 | 13,898 → 13,026 |
| irregular / 8 | 204.67 | 203.04 | 150.79 | 18,104 → 20,663 |
| irregular / 64 | 16047.73 | 15471.44 | 5019.00 | 157,992 → 74,982 |
| irregular / 128 | 104261.08 | 98356.79 | 20380.15 | 550,276 → 170,697 |
| irregular / 256 | 777783.90 | 729663.00 | 90127.17 | 1,951,618 → 319,681 |
| retained_loop / 1 | 17.52 | 18.10 | 21.50 | 14,576 → 20,589 |
| retained_loop / 8 | 31.85 | 31.79 | 35.79 | 14,614 → 20,625 |
| retained_loop / 64 | 140.02 | 141.98 | 144.31 | 14,614 → 20,713 |
| retained_loop / 128 | 264.69 | 266.54 | 269.23 | 14,626 → 20,720 |
| retained_loop / 256 | 513.15 | 529.06 | 523.23 | 14,626 → 20,720 |
| variant / unit | 141.29 | 141.06 | 191.87 | 7,232 → 9,678 |
| variant / 0 | 153.04 | 152.73 | 189.25 | 7,232 → 9,680 |
| variant / 1024 | 191.56 | 193.81 | 187.35 | 8,105 → 11,731 |
| variant / 65536 | 2779.81 | 2761.29 | 206.88 | 137,131 → 140,758 |
| variant / 1048576 | 38790.06 | 38253.90 | 341.02 | 2,103,211 → 2,106,838 |
| product / 0 | 163.79 | 161.90 | 197.71 | 7,232 → 9,698 |
| product / 1024 | 205.46 | 204.10 | 196.62 | 8,202 → 11,749 |
| product / 65536 | 2759.63 | 2741.73 | 209.48 | 137,228 → 140,776 |
| product / 1048576 | 37390.90 | 37351.52 | 356.60 | 2,103,308 → 2,106,856 |
| sequence / 0 | 4.92 | 4.88 | 5.71 | 8,382 → 9,927 |
| sequence / 16 | 35.37 | 35.00 | 23.88 | 8,382 → 16,311 |
| sequence / 64 | 188.35 | 185.13 | 73.19 | 13,597 → 17,003 |
| sequence / 256 | 1541.29 | 1593.54 | 270.10 | 27,813 → 20,845 |
| sequence / 1024 | 19211.92 | 20170.29 | 1079.21 | 84,645 → 37,636 |
| sequence / 4096 | 286336.33 | 302179.58 | 4281.71 | 311,973 → 105,221 |

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

### Memory decisions still pending

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
- **Queens/search: DFS +18,573 bytes (+13.01%); BFS +59,629 (+38.83%).** Faster
  search alone does not justify these costs. Their precise allocation/retention
  cause is unresolved in the current report. **Recommendation: resolve that
  evidence gap before asking for acceptance**, using the unchanged search fixtures
  and a targeted lifetime observation, not another optimization campaign.
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
- **Deep, shallow, cleanup and mixed/irregular8:** the comparative peaks remain
  explicit, but this report does not yet isolate their additional storage by
  lifetime. **Recommendation: finish the focused attribution before disposition.**

These are recommendations, not user acceptance. Agent-specific peak/checkpoint
costs and its larger ReAct image are separately reported in
[Agent's results](https://github.com/tkersey/agent/blob/feat/compositional-execution/docs/compositional-execution.md).

## Remaining acceptance work

Cumulative guest/Agent confirmation on the selected production tuple, the targeted
memory-attribution gaps above, the requirement audit and serial reviews remain
open. The named native latency tradeoffs are accepted for this milestone;
installation64 memory and the other economic recommendations still require explicit
disposition. Optional representation/allocator/cache/compiler redesign is not a
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
