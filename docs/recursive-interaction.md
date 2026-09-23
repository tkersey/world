# Tail application in recursive interaction

This follow-on to the merged compositional-execution foundation changes one generic
operation: indirect application now uses the existing direct-call tail predicate.
When the successor is an empty block returning exactly the application result,
World passes the current parent to the callee instead of capturing a redundant
return control. Computation/argument values are read first. The callee still uses
its actual captured environment, evidence and region; non-tail application retains
its original continuation. No opcode, format, package budget or scheduler is added.

The motivating Boundary witness is `examples/hyper_tail.zig`: two public `ana`
participants count down runtime input and only delegate to the peer. The same
783-byte BPI3 image runs on both kernels. At work quantum 97, the baseline kernel
`7a27d64295431c960046439353a158e378f14d4686fac47b61b1406cf1753663`
grows its sampled checkpoint from 599 bytes at count 7 to 73,672 bytes at count
1,024. The candidate kernel
`df7fe1ae0ed0de7b2976c98b1534d1d55f4c341b7148837ce32f42ed8d011084`
has a 125-byte sampled checkpoint from counts 31 through 1,024. Peak World working
memory at count 1,024 falls from 3,009,769 to 111,688 bytes. The direct recursive-call
comparator remains at 93 checkpoint bytes and 8,490 peak working bytes. All outputs
are 42 and completed executions release working ownership to zero.

These are structural/high-water observations, not throughput or tail-latency
measurements. The source/runtime structure explains the bound: the pure tail apply
creates no new return parent. The observed working plateau also includes bounded
transient storage and collection overhead. Non-tail/history-retaining programs do
not acquire this bound. The sampling series is finite (0/1/7/31/127/512/1,024).

The native regression in `test/v2/source_regressions.zig` uses a first-class recursive
callable with a captured seed. Across counts 7/127/1,024, tail application keeps the
checkpoint graph within sixteen nodes and survives actual fresh restore. Its
non-tail neighbor performs a distinct addition after each return; those additions
must remain present. Existing source, protected-scope, cleanup, resumption, borrow,
allocation, kernel and package tests remain separate checks.

Executed with Zig 0.16.0: check-native passes 87 tests; check-storage and
check-activation-storage pass 49 and 16 tests. check-source compares 42 fixtures over
6,433 observations; check-kernel compares 237 boundaries and 23 native/Node transfers;
check-package passes the extracted runtime/CLI check. World hardcodes ReleaseSmall
for WASM; `-Doptimize=ReleaseSafe` selects the host build. This corrects earlier
Boundary prose that mislabeled the same baseline kernel as ReleaseSafe.

Base: World 374ed712c2a2ab5041c28befa38bb3c3a859bd26. The normal pinned Boundary
package remains 1b00c8c159f0cb490a1223fac8d3d208cef41cb1. The new higher-order witness
is compiled by Boundary's recursive-interaction branch using the unchanged BPI3
contract. Broader Agent integration, browser/Wasmtime transfer, matched economic
measurements, exact final dependency integration and serial reviews remain open.

Additional checks on the same executable inputs pass: check-transfer covers 159
Node/Wasmtime/native boundaries; check-browser covers actual Chromium 153.0.8010.12
and Firefox 155.0 Workers; check-capacity and check-package pass. Candidate kernel
size is 462,730 bytes versus 462,629 baseline (+101 bytes).

Agent a134f624b430d05cc73a6cedd2406dea851a7e01 was exercised with this explicitly
supplied runtime and native peer. Its local-abandonment/cleanup/sibling case agrees
across Chromium/native/Wasmtime/Node, and its separate global-cancellation case
agrees with Firefox. Each uses six actual State transfers and seven destroyed
Workers. Complete parser repair, independent acceptance, exact approval and
conditional fixture application also pass: 539 candidate executions plus two
qualification executions, two synthetic model calls, one approval and one write,
twenty transfers and twenty-one Chromium Workers. No paid inference or real user
target was used. Agent's normal dependency lock has not yet been updated; these
executions establish compatibility, not completed final package integration.

The report-only update reuses code/tests and the exact kernel hash from the first
World commit. Remaining work includes normal dependency integration, matched
latency/setup and unchanged-consumer economic comparisons, and serial reviews.

## Matched timing follow-on

Boundary's `docs/recursive-interaction-timings.csv` now records 73 native/WASM
cells against the immutable foundation World 374ed712 and this runtime's unchanged
executable code. Identical BPI3/PKI3 inputs and independent numerical/event oracles
are checked before accepting measurements. Native tail-hyper count 512 improves
from 9.970 to 4.542 ms initial and 9.974 to 4.490 ms initial-State recovery; the
direct control remains about 0.270 ms. Six unchanged foundation controls range
from 0.968x to 1.013x, without a supported material regression from these samples.

WASM measurements include generic-kernel setup and matched per-quantum checkpoint
obligations for resident/fresh modes. Tail-hyper 512 resident/fresh medians improve
from 191.85/612.32 to 17.65/104.25 ms; the candidate direct loop remains much faster.
Wide overlapping setup/direct-control ranges are inconclusive. This report does
not assign their apparent improvements to the interpreter change. All cells,
ranges, exact input identities, commands and limitations are in Boundary's report.
No runtime code or default capacity was changed for these measurements. Native
emitter build and compiler attribution remain separate from execution timing.
