# World 6 successor status

World 6.0.0-dev.0 executes stable-activation Programs through one evaluator, with
fresh and prepared/resident operation, portable checkpoints and a browser-neutral
embedding. The successor remains incomplete; all linked PRs remain drafts.
Contracts and commands are in [kernel-abi.md](kernel-abi.md) and
[verification.md](verification.md).

## Current construction and validation

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

The generic kernel is 463,045 bytes, SHA-256
`54d39b7cf8b881701bb58f590cc2cd2a6baf461d7f0cad01e647c888e379ccad`.

## Current measurements and limits

The fixed predecessor is Boundary 42a09b9 / World d075169, including compact BPC1.
The complete 45-case native refresh at Boundary 6c59436 / World dc7e81d established
large control/value gains: mixed256 about 8× faster, sequence4096 about 67×, and
1 MiB projections over 100×. Subsequent control-node and allocator comparisons
use the same Boundary images and independent trace/result oracles. They do not
replace final cumulative acceptance against BPC1.

Two native remap windows compare this implementation with World 58f2533 over all
30 control fixtures. Each side has three process observations per case per window,
with three warmups and nine samples. Clocks cover complete fresh invocations;
fixture replies and oracle checks are outside them. Latency changes are small and
mixed, so no broad speedup is claimed. These are not request-tail measurements.

| Installations | Native peak before remap | Native peak now | BPC1 peak |
| ---: | ---: | ---: | ---: |
| 1 | 10,995 | 10,995 | 8,700 |
| 8 | 26,703 | 24,199 | 15,564 |
| 64 | 141,786 | 135,051 | 121,956 |
| 128 | 227,570 | 227,570 | 435,558 |
| 256 | 388,069 | 365,015 | 1,324,938 |

Total allocation at 64 falls 432,129 → 374,049 bytes, and at 256 falls
1,459,837 → 1,310,861. Default images remain 2,241/4,559/9,551 bytes at 64/128/256,
below BPC1's 2,805/5,574/12,102. The 64-case peak gap remains unresolved.

Guest confirmation uses isolated Node processes: two windows, three observations
per side/case, nine batches of 64 full fresh calls after 32 warmups. Seven selected
initial-invocation fixtures preserve canonical outputs. Guest peaks are unchanged
and timing changes are mixed; no guest speedup is claimed. The final kernel is
byte-identical to the timed candidate.

Unrestricted in-place resize was rejected: it let standard arenas retain larger
slabs and raised installation256 peak to 420,861 bytes. The selected remap path
avoids that change. No rejected implementation or experiment archive is maintained.

Native cursor reclamation retains its 17,003-byte sequence64 peak and 20,845-byte
sequence256 peak; corresponding BPC1 peaks are 13,597 and 27,813 bytes. Some
projection timings incurred a 1–5% cost. Suspension reclamation retains the
independent live-alias checks and one-element-survivor result: 8,182 native working
bytes and an 86-byte checkpoint, independent of discarded backing size. Its earlier
1–5% control-time cost remains part of the cumulative comparison.

## Remaining acceptance work

Small scalar/deep, installation1/8, retained-loop1/8, tiny projection and empty
sequence latency gaps remain subject to final comparison. Installation64,
shallow, queens, cleanup, mixed/irregular8, retained loops and short sequences retain
peak-memory gaps; large projections were about 3.5 KiB higher at peak. Favorable
cases do not cancel those residuals. Final guest/Agent confirmation, serial
reviews and the requirement audit remain open.

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
