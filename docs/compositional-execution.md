# World 6 successor status

World 6.0.0-dev.0 executes stable-activation Programs through one evaluator, with
fresh and prepared/resident operation, portable checkpoints and a browser-neutral
embedding. The successor remains incomplete; all linked PRs remain drafts.
Contracts and commands are in [kernel-abi.md](kernel-abi.md) and
[verification.md](verification.md).

## Current construction and validation

Slot pages determine initialization. Conservative pruning bounds grant no read or
ownership authority; retained views remain copy-on-write. Same-function tail calls
can reuse an activation only under the existing custody checks. Suspensions and
terminal outcomes reclaim dead backing; checkpoint export remains read-only.
Resident failure sweeps preserve unchanged retry input and cleanup custody.

On 64-bit native storage, a final reusable, capture-free callable can enter its
immediate handler without allocating an environment or callable object. State and
argument aliases, later uses and every declared edge source preserve ordinary
construction. The existing handler-entry owner receives the genuine arguments.
Fusion charges both work units and requires enough remaining quantum. Explicit
single-step execution retains the intermediate boundary. WASM uses ordinary
execution with the same work accounting and logical boundaries.

Tests distinguish eligible, non-adjacent, retained, edge-aliased, linear and
state-aliased callables. Bounded and strict checkpoints agree; every allocation
failure preserves retry state. The current candidate passes 84 native source
tests, 42 source/native/WASM cases (6,434 observations), 239 native/Node boundaries,
23 transfers, 161 Wasmtime boundaries, Chromium/Firefox Worker transfers, capacity
checks and extracted runtime/CLI checks. These prove the tested cases, not final
performance acceptance.

The generic kernel is 462,400 bytes, SHA-256
`3beae29e2b4f74de5248c636319c3f31fbdd28fab632314b9b1dd7c83c066c49`.

Consuming a saved continuation now changes its owned node back into a control;
its activation keeps the same custody. Function entry replaces an exclusively
active control only after the new frame is fully constructed. A caller that must
survive is already a continuation and is preserved. Multi-shot captures are cloned
before activation. No argument, handler, final sum, work unit or cleanup is omitted.
The displaced frame-map move operation is removed. New regressions cover mutual
tail entry, checkpoint restoration, retained caller results and resident failures.
Baseline-native versus candidate-guest outputs also agree at all 239 checked
boundaries and 23 transfers, including retained and reentrant cases.

## Current measurements and limits

The 45-case native refresh compares Boundary 6c59436 / World dc7e81d with the fixed
Boundary 42a09b9 / World d075169 anchors. Identical standalone probes and independent
result/trace oracles ran for BPI2, compact BPC1 and BPI3 on Zig 0.16.0 ReleaseSafe,
Node 26.9.0 and M2 Pro/macOS 27.2. Two windows rotated format order; each process
used three warmups and nine fresh-invocation samples. Most cases had six processes
per format; mixed/irregular128/256 and sequence1024/4096 had two. These are medians,
not service p99 estimates. Control clocks exclude fixture replies and oracle work.

The refresh confirms large-case gains over BPC1: mixed256 is about 8× faster,
sequence4096 about 67×, and 1 MiB projections over 100×. Installation64/128/256
images are 2,241/4,559/9,551 versus 2,805/5,574/12,102 bytes. Scheduler and
sequence1024 peaks are below BPC1. Retained-loop64/128/256 timing ranges overlap
BPC1, while their peaks remain higher.

Native cursor reclamation runs after sequence-pop operations. Tracing
preserves live aliases; their count raises the next collection threshold. The
existing 256-work-unit and suspension collections remain. Resident rollback also
restores the threshold. A shared sequence fixture checks the complete sum, early
reclamation and every failing resident allocation, with and without checkpoints.

Two rotating native confirmation windows compare this policy with dc7e81d using
the same full-consumption fixtures. Each process has three warmups and nine
samples; six processes per side, except sizes1024/4096 with two. Size64 is about
9% faster and size256 about 8% faster. Some projection cases cost about 1–5% more;
that tradeoff remains part of the unresolved final acceptance.

| Sequence elements | Native peak before | Native peak now | BPC1 peak |
| ---: | ---: | ---: | ---: |
| 0 | 9,927 | 9,927 | 8,382 |
| 16 | 20,475 | 16,311 | 8,382 |
| 64 | 50,899 | 17,003 | 13,597 |
| 256 | 53,973 | 20,845 | 27,813 |
| 1024 | 66,261 | 37,636 | 84,645 |
| 4096 | 132,860 | 105,221 | 311,973 |

WASM retains the existing schedule: earlier cursor collection reduced memory but
slowed long sequence consumption by 3–5%. Final native-only confirmation preserves
guest peaks and removes that repeatable slowdown across two rotating windows.
A fixed 32-step interval and general
node-growth trigger were also rejected for control-workload slowdowns. No rejected
implementation or raw experiment archive is maintained.

Scalar, deep, installation1/8, retained-loop1/8, tiny projections and empty sequence
still have latency gaps versus BPC1. Installation64 has overlapping timing ranges
but a clear memory gap. Shallow, queens, cleanup, mixed/irregular8, retained loops
and short sequences retain higher peaks. Large projections remain about 3.5 KiB
higher at peak. Favorable cases do not cancel these remaining failures.

## Control-node reuse confirmation

Two native windows compare this implementation with World 9922062, holding Boundary
6c59436 and all 30 control fixtures fixed. Each side has three process observations
per case per window, each with three warmups and nine samples. Input and independent
trace/result digests agree. Installation64/128 time improves about 8–10%; unchanged
or small mixed timing differences are not claimed as gains.

| Installations | Native peak before | Native peak now | BPC1 peak |
| ---: | ---: | ---: | ---: |
| 1 | 12,315 | 10,995 | 8,700 |
| 8 | 30,623 | 26,703 | 15,564 |
| 64 | 179,228 | 141,786 | 121,956 |
| 128 | 265,012 | 227,570 | 435,558 |
| 256 | 391,624 | 388,069 | 1,324,938 |

The 64-case total allocation falls from 499,932 to 432,129 bytes. Its preparation
alone peaks at 121,438 bytes before invocation framing; the remaining complete-call
memory gap is not declared closed. Queens BFS peak falls 244,736 → 213,208 bytes.

Guest confirmation uses isolated Node processes after mixed-instance timing proved
noisy: three observations per side/case/window, nine batches of 64 full fresh calls
after 32 warmups. Ten initial-invocation fixtures retain identical canonical outputs.
Installation128/256 full fresh-call time improves about 4–5% in both windows; smaller
case ranges overlap. Installation64 guest peak falls 151,213 → 135,069 bytes and
128 falls 236,125 → 225,759 bytes. The final kernel is byte-identical to this timed
candidate. These results reduce existing gaps; they do not complete acceptance.

## Remaining acceptance work

The gaps identified above, final guest/Agent/build confirmation and serial reviews
remain required. These measurements supersede older native summaries; they do not establish full
performance acceptance.

Suspension reclamation retains the independent live-alias checks and its recorded
one-element-survivor result: 8,182 native working bytes with an 86-byte checkpoint,
independent of the discarded backing size. Its earlier 1–5% control-time cost must
remain accounted for in the final cumulative comparison.

Cold native build, warm no-change, client-edit and component-reuse observations
remain separate from runtime timings. The earlier source-only emitter comparison
was 16.50–16.56 s predecessor versus 15.45–15.50 s successor; the full compiler/
evaluator probe had no clear cold-build gain. Final build qualification,
coordinated consumer/package qualification and serial reviews remain required.

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
