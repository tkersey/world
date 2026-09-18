# World 6 successor status

World 6.0.0-dev.0 executes Boundary's stable-activation Program through one evaluator,
with fresh and prepared/resident operation, portable checkpoints and a browser-neutral
embedding. The successor remains incomplete; all linked PRs remain drafts.

Current contracts and checks are described in [kernel-abi.md](kernel-abi.md) and
[verification.md](verification.md). The dependency manifest selects the current
Boundary source. Experimental evidence is excluded from the dependency package.

## Current validation

The current evaluator passes 75 native source tests, 42 storage tests, 14 activation
storage tests, 6,755 source-oracle observations, 257 native/Node boundaries and 23
transfers, 174 Wasmtime boundaries, real Chromium 153.0.8010.12 and Firefox 155.0
Worker transfers, capacity/retry checks, and extracted runtime/CLI checks.
Agent must also qualify this kernel through its normal dependency lock.
These checks establish their tested semantic/portability cases, not performance acceptance.

The kernel is 460,161 bytes with SHA-256
`dbb929681cb7675affaccefbfee9fd8fc5ee579e0d76276eedab882fd35642a8`.

## Frame storage and current results

Slot pages alone determine initialization. A frame retains a conservative pruning
bound, which may contain uninitialized slots and grants no read or ownership authority.
Batch transitions write selected values and reclaim slots outside the next admitted
liveness bound. This avoids maintaining an exact interned set after every write.
Small bounds remain inline; large bounds reuse analysis roots. Restore/unpack writes
extend the bound, reads and projection use actual slots, and retained views remain
copy-on-write. Failed private transitions are discarded/poisoned or restored from
Resident's backup. Tests cover both bound representations, unavailable live slots,
retained views, allocation failure, cleanup, restore, and reentrant execution.

Native 64-bit analysis pools now use 16-byte nodes when their declared member
limit fits in 32 bits, retaining 24-byte nodes for full-width domains. Public
members stay u64. Control64/128/256 working peaks are 201,927 / 320,429 /
608,169 bytes; tiny scalar and one-installation peaks rise by 38 / 66 bytes.
Current native control64 is about 320 microseconds. Tiny scalar invocations cost
roughly 40–80 ns more; other control differences are mixed. No broad latency claim
follows from this storage change.

Across 13 fixed Agent scenarios and 128 paired invocations, canonical outcomes
and transition/control/copy counters agree. Native Session inquiry/ReAct peaks
fall from 2,049,764 / 3,534,020 to 1,952,780 / 3,084,054 bytes. Whole-invocation
peaks (including framing) fall from 2,147,127 / 3,676,006 to 2,050,143 / 3,226,040.
The final native replay windows show no material latency regression.

The all-target tagged compact layout slowed sampled fresh wasm32 inquiry/ReAct
invocations by about 3% / 7%; that variant is rejected. wasm32 retains its prior
untagged storage, producing the byte-identical 460,161-byte kernel above. No guest
latency or memory gain is claimed. The workspace still preserves first-fit
allocation, and contract encoding releases scratch before retaining finished bytes.

## Current native control matrix

The execution probe now follows complete fresh-invocation traces, including
request payloads, replies, yields, terminal values and ordered cleanup failures.
The fixture code is shared with the established source examples; the expected
observations come from the independent source oracle. The retained benchmark
accepts explicit source pairs and does not install a legacy production dependency.

Two windows use three rotating process observations per format and case, each
with three warmups and nine samples. Each sample sums runtime invocation clocks
for the complete trace; fixture replies/oracle checks are outside those clocks.
Working peaks exclude the fixed host input/output buffers. These are native
ReleaseSafe results on Zig 0.16.0, Apple M2 Pro, macOS 27.2, not guest timings.
The confirmation window is below. Baseline: Boundary 42a09b9 / World d075169
(normal BPI2 and compact BPC1); successor: Boundary 3b8a69f / World 46811af.

| Fixture | BPI2 µs | BPC1 µs | BPI3 µs | Working bytes BPC1 → BPI3 |
|---|---:|---:|---:|---:|
| scalar | 1.83 | 1.75 | 2.54 | 3,594 → 4,662 |
| deep | 9.92 | 9.79 | 12.71 | 10,784 → 17,071 |
| residual | 14.83 | 14.75 | 12.88 | 12,726 → 11,439 |
| install 1 | 7.92 | 8.00 | 9.75 | 8,700 → 14,628 |
| install 8 | 23.92 | 23.00 | 34.04 | 15,564 → 42,820 |
| install 64 | 247.08 | 245.92 | 317.54 | 121,956 → 201,927 |
| install 128 | 743.54 | 696.63 | 695.96 | 435,558 → 320,429 |
| install 256 | 2523.46 | 2334.46 | 1526.00 | 1,324,938 → 608,169 |
| mixed 8 | 205.08 | 205.58 | 172.59 | 18,104 → 24,222 |
| mixed 64 | 16002.54 | 15504.92 | 6987.12 | 157,992 → 141,922 |
| mixed 128 | 104786.30 | 98635.83 | 31708.17 | 550,276 → 279,276 |
| mixed 256 | 779337.96 | 731503.08 | 152264.74 | 1,951,618 → 568,536 |
| irregular 8 | 213.67 | 203.67 | 177.96 | 18,104 → 24,222 |
| irregular 64 | 16138.42 | 15505.04 | 6959.30 | 157,992 → 141,929 |
| irregular 128 | 104951.17 | 99186.59 | 31741.16 | 550,276 → 279,272 |
| irregular 256 | 781855.04 | 733218.25 | 154063.96 | 1,951,618 → 568,543 |
| reentrant | 154.83 | 157.79 | 107.13 | 127,125 → 101,302 |
| shallow | 323.79 | 328.88 | 250.63 | 145,914 → 168,350 |
| generator | 243.50 | 244.42 | 163.00 | 58,859 → 58,534 |
| scheduler | 416.79 | 418.71 | 275.46 | 88,240 → 97,911 |
| queens_dfs | 8125.13 | 8206.17 | 3541.92 | 142,727 → 194,005 |
| queens_bfs | 11103.88 | 11138.75 | 3617.38 | 153,579 → 236,580 |
| cleanup | 294.92 | 305.46 | 173.17 | 43,221 → 46,518 |

The second window confirms the large mixed/irregular gains (about 4.8× at 256),
queens DFS/BFS (about 2.3× / 3.1×), and faster reentrant, shallow, generator,
scheduler and suspending-cleanup execution. Mixed/irregular 256 also reduce
allocated bytes from about 913 MB to 266 MB per complete 257-call trace, although
allocation call counts rise. Some portable State peaks grow: mixed 256 is
2,890 → 3,085 bytes, and queens BFS is 1,000 → 1,098 bytes.

The full 64/128/256 installation images remain below compact BPC1:
2,629 / 5,451 / 11,339 bytes versus 2,805 / 5,574 / 12,102. Their normal BPI2
comparators are 8,971 / 30,141 / 118,205 bytes. Compiler-execution time for
installation256 is about 2.74 ms versus BPC1's 25.33 ms; this excludes native
tool compilation and does not measure native cold-build costs.

## Unresolved acceptance

Scalar, deep and 1/8/64 installations remain slower and use more working memory
than BPC1. Shallow, scheduler, queens and cleanup gain time but have higher
working peaks; those tradeoffs remain visible and unresolved. Installation128
latency is approximately unchanged, with lower working memory. Native Session
inquiry/ReAct peaks remain above BPC1's 1,853,961 / 2,061,220 bytes, and ReAct guest
latency remains open. No performance failure has been waived.

The retained-loop benchmark, remaining value/projection/sequence and tiny-live-view
measurements, final Agent comparison, native build/client-edit decomposition,
final coordinated qualification and serial reviews remain required.

Standalone probes under `test/v2/` accept explicit source inputs:
`build_execution_bench.zig`, `build_value_bench.zig`, and `build_replay_bench.zig`.
Raw samples, profiles and historical experiment patches are not maintained.

Linked drafts: [Boundary #152](https://github.com/tkersey/boundary/pull/152),
[World #54](https://github.com/tkersey/world/pull/54),
[Agent #32](https://github.com/tkersey/agent/pull/32).
Future landing order is Boundary → World → Agent, only when separately authorized.
No merge, promotion or release is authorized. Current-tree deletion does not purge
historical Git objects.
