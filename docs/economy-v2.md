# World 5 development economy measurements

These are development measurements from September 9, 2026 UTC. Release acceptance
must bind the final source and delivered kernel separately. The measured kernel
is `c372950bfc184f04e54f0e9ce8339c931634c616a69c4e07e82803980745b17d`.
Raw samples and allocation observations are in
[`test/v2/economy/results`](../test/v2/economy/results/).

The host was an Apple M2 Pro, 12 cores, 32 GiB memory, macOS 27.0, Node 26.8.1
and Zig 0.16.0. Timings ran serially without an active Agent measurement or
another successor build. Native profiling used ReleaseSafe; both WASM kernels
used ReleaseSmall and a 256 MiB maximum. No operational ceiling was increased.

| Gate | Observation |
|---|---|
| Warm execution, at most 2× v1 | All seven matched workloads passed; worst median ratio 0.8701. |
| Peak working allocation, at most 2× v1 | The seven matched workloads peaked at 78,703 bytes, below the 261,408-byte mandatory v1 validation workspace alone. |
| Cold compile and emission, at most 2× v1 | One effect: 1.3677×; 32 dependent additions: 1.3499×. |
| Serialized overhead, at most 1.5× plus 4 KiB | All twenty frozen images passed even when every v2 constant byte was conservatively counted as overhead. |

Warm measurements include input copying, admission, execution to the first
observable boundary, and output copying. They exclude module compilation and
instance creation. Each side uses a warmed module and a reusable, stateless
instance: five warmups, then 21 samples of 20 invocations. Version order
alternates. Legacy internal `Progressed` outcomes are drained by the benchmark
harness; World `run` performs these transitions internally. Values and residual
payloads were compared through the pure BPI1 value conversion before timing.

| Workload | v1 median ms | v2 median ms | v2/v1 |
|---|---:|---:|---:|
| Integer and Boolean operations | 0.06885 | 0.03492 | 0.5072 |
| Algebraic collections | 0.12151 | 0.05443 | 0.4480 |
| Portable values | 0.03553 | 0.01410 | 0.3969 |
| Recursion, initial zero | 0.32208 | 0.01383 | 0.0430 |
| Recursion, initial 32 | 10.61005 | 0.04543 | 0.0043 |
| Residual request | 0.04681 | 0.04073 | 0.8701 |
| Authored yield | 0.02351 | 0.01198 | 0.5093 |

The recursion ratios include v1's repeated admission and serialization of its
internal progress records. They are not measurements of scalar instruction
dispatch alone. The fixed public v1 kernel occupies 161,021,952 bytes of linear
memory on these workloads; v2 occupies 1,310,720 bytes. These reservations are
reported separately from live native working allocation. Kernel sizes are
682,943 and 393,407 bytes respectively.

Native working peaks include PKI decoding, image admission, execution, snapshot
production, and PKO encoding. They count simultaneously live allocator payload;
mandatory allocator metadata demand is a separate lower-bound observation.
The v1 comparison reports its mandatory native validation workspace and each
observed arena demand. Comparing v2 against the mandatory workspace alone is
conservative: v1 additionally needs its state, values, environments and scratch.
Unused backing reservations are not counted as live payload.

Cold compilation uses independently authored equivalent programs through each
version's public source interface. Every sample starts with empty Zig object
caches. Immutable dependency sources are acquired before timing. The OS file
cache is uncontrolled. Five samples per version and workload include the build
driver, Zig compilation and image emission. The frozen compiler is Boundary
1.8.2 commit `999e936c4a865cd31948b52b2af2baeacf84c9f1`.
All compiler and runtime measurement lanes were rerun against the current
compiler, loader and optimized data-admission kernel.

## Earlier borrow-analysis comparison

Profiling the 9,576-byte ownership/cleanup image found repeated fixed-point
settlement in Boundary's pure borrow admission. Successful settled queries now
reuse their results, and validation registers all function roots before one
settlement. New work and failed settlement keep the analysis dirty. Three
regression tests cover allocation-free reuse, retry after allocation failure,
and allocation growth across independent function roots.

In that comparison, 21 paired samples on the same image reduced native `run` from 89.4603 ms to
6.8710 ms, JavaScript WASM from 94.4505 ms to 5.6117 ms, and Wasmtime from
67.2617 ms to 5.1649 ms: 13.0–16.8× faster. `advance` improved by 13.1–17.0×.
All measured invocations preserved exact outcome bytes before/after and across
the three engines. The full 121-script conformance corpus also preserved all
546 record checks and its complete binary output. Raw samples, native statistics,
source identities and conformance hashes are in
[`borrow-analysis.json`](../test/v2/economy/results/borrow-analysis.json).

That correction reduced its kernel by 71 bytes. The current kernel additionally
checks captured handler state, normal-return destinations and saved resumption
entries, validates attachment links before graph traversal, and saturates
unrepresentable allocation demand. Those changes add 1,077 bytes to the
optimized baseline without changing memory limits.

After the final freeze, a new public-API consent consumer composed a shallow
state-passing handler with an outer deep answer reversal and negation. All 16
Boolean input combinations, one yield and cross-engine transfer passed 432 exact
records without changing the kernel.

## Structural checks and phase costs

Actual public-source programs execute 1, 8 and 64 handler installations using
one handler definition and the same executable function count. Their proven
tail clauses capture no resumptions. A non-tail one-shot workload retains a
64 KiB input with exactly one blob allocation.

At 1, 8 and 64 branch creations, immutable blobs and unchanged environments
retain identity; local cells receive distinct identities and preserve repeated
aliases. Containers that reference a rebased local cell are copied. Backward
dependency propagation handles cycles and nested templates. The 64-branch
structural witness now allocates 384 cloned nodes instead of 448 and keeps one
65,539-byte encoded blob. A separate compiler check adds a 64 KiB constant and
finds one stored payload, with only the expected ULEB framing growth.

Snapshot discovery visits each reachable node once and each reference once.
Remapping, sizing and writing are separate flat passes. Blob hash input bytes
and comparisons are counted separately. Collection has one reachability walk
and a separately counted slot sweep. The output producer previously repeated
canonicalization; it now normalizes, sizes and writes through one codec call.

The phase profiler times the production transition implementation independently
from admission and serialization. It reports one-shot and multi-template
capture, branch creation with activation, ordinary execution, unwinding,
collection, snapshot validation/encoding, and final outcome encoding. It does
not resolve environmental effects. `phases.json` contains medians, counts,
output sizes and working peaks for seven feature workloads; the `phase-*.json`
files retain all 21 samples from each workload.
Small transition timings have clock and scheduling noise; no instruction-level
speedup is inferred from them.

A consolidation of clone metadata into larger map entries was rejected after
measuring roughly 25% higher small-capture allocation peaks without a material
latency benefit. The exact patch and observations are retained in
[`clone-map-regression.json`](../test/v2/economy/clone-map-regression.json).
The separate sparse indexes remain in use.

`compiler-phases.json` records eight public source workloads with exclusive
checking, lowering, canonicalization and pure codec timings, including every
sample and compiler input digest. The 64-installation workload has one shared
handler definition and an 8,971-byte image; its extra source sites and control
edges remain program data. Codec measurements use admitted initial logical
State and make no historical execution claim.

`setup.json` separates five cold kernel builds from module compilation and
instance creation in JavaScript and Wasmtime. Every build emitted the same
393,407-byte kernel. Each JavaScript compilation uses a fresh process; each
Wasmtime compilation uses a fresh engine without enabling its code cache.
Instance measurements have five warmups and 21 samples per module. Startup of
the process, Python binding and engine itself is excluded from those timers.
The report also records exact paired image deltas for additional installations,
alternate private resource representation and State/Choice nesting. These are
whole-program comparisons, not isolated per-feature kernel costs.

`cli-statistics.json` contains native Zig `lift-bench-stats` 0.2.7 summaries and
bootstrap intervals for the warm and cold pairs. Original samples retain higher
precision than the CLI's six-decimal JSON presentation. Source input digests and
binary digests identify what was measured; the Git fields record the development
checkout at measurement time and do not claim that the old base commit contains
the new implementation.

## Reproduction

Build Boundary's `check-v2-economy` fixtures and `build-bpi1-lift` first. World
requires explicit absolute Boundary source and fixture inputs. Build
`build-v2-kernel`, `build-v2-economy-probe`, and `build-v2-economy-phases` with
`-Doptimize=ReleaseSafe`; the guest's own mode remains ReleaseSmall.

Run these harnesses serially in an available measurement window:

```text
node test/v2/economy.mjs KERNEL FROZEN_V1_KERNEL LIFTER BOUNDARY_SOURCE OUTPUT
node test/v2/economy_cold.mjs BOUNDARY_SOURCE OUTPUT
node test/v2/economy_memory.mjs BOUNDARY_SOURCE V2_PROBE V1_PROBE LIFTER OUTPUT
node test/v2/economy_phases.mjs BOUNDARY_SOURCE V2_PHASE_PROFILER OUTPUT
node test/v2/economy_setup.mjs BOUNDARY_SOURCE KERNEL OUTPUT
```

The cold harness extracts the pinned compiler into its own temporary directory,
checks compiler inputs before and after timing, and builds the isolated v1
allocation probe outside the timed samples. Its report names that probe.
Warm and memory harnesses enforce their 2× gates; Boundary's economy tests
enforce the serialized bound and structural sharing. These measurement
executables are development tools; runtime package contents are checked
separately.
