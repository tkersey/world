# Prepared frame-layout classes

Preparation derives exact compatibility classes from immutable slot-schema IDs
and custody lengths. Sessions borrow this index under their existing preparation
lease. Restart still checks dynamic custody initialization and both function
bounds. Hash collisions require exact equality; no hash is a compatibility proof.

The two-function case needs one exact comparison and no temporary hash table.
Larger catalogues use the same exact hash-table classification. Retained storage
is one class ID per function (none for zero or one function). Preparation is
measured separately; the index does not make preprocessing free.

## Local evidence

[Measurements](frame-layout-qualification.json) retain all five alternating
windows, with three warmups and nine samples per process. The baseline is the
previous World implementation, using the identical BPI3 image on both sides.
Widths are 4, 4096 and 65536 slots; fallback differs in length at width 4 and in
the last schema ID at larger widths. Only four slots participate in computation.

All 342 per-prefix comparisons and sampled cancellation cuts match. The aggregate
World check passes. No cell meets the specified confirmed-slowdown condition.
Two medians exceed 5% without four-of-five confirmation and remain inconclusive.
Native resident peak memory increases by 64 bytes in all six instrumented cases.
Consumer qualification and serial reviews are separate outstanding obligations.

## Reproduction

Use Zig 0.16.0 and Node 26.10.0. Export the recorded baseline source from Git;
build both native arms with `-OReleaseSafe` and the same locked `boundary_data`
module. Use `test/current/scalar_batch_memory.zig` for admission/fresh invocation
and `test/current/resident_cost.zig` for resident execution. Build the emitter
from `test/current/frame_reuse_fixture.zig`, with `frame_fixture` bound to
`src/interpreter_v2/frame_reuse_tests.zig` and the same `boundary_data` module.
World's `zig build build-runtime` builds the ReleaseSmall WASM kernel for each
source revision. Keep the two kernels and native binaries in separate locations.

```sh
zig build check -Doptimize=ReleaseSafe --summary all
node test/current/frame_layout_qualification.mjs \
  EMBEDDING_MODULE BASELINE_KERNEL CANDIDATE_KERNEL EMITTER \
  BASELINE_NATIVE CANDIDATE_NATIVE BASELINE_RESIDENT CANDIDATE_RESIDENT \
  CORPUS_DIRECTORY REPORT_JSON
```

Arguments are positional absolute paths. The harness emits its own six images
and fixed inputs, asserts exact outcomes, and records every timing window. The
resident sampler also reports peak allocation across preparation, session and
outcomes in a separate instrumented pass. Run benchmarks without concurrent
builds. Kernel, image and source digests in the measurement file bind the recorded
run; a later run must report its own identities and results.
