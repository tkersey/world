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

## Consumer qualification

The qualified Actions bundle at World `a48d5fd` has the same runtime inventory as
the measured local build. Its source archive, Git tree, transport, manifest and
kernel were authenticated before consumer execution. [Run 36726709618](https://github.com/tkersey/world/actions/runs/36726709618)
passed the public producer's aggregate and delivered-byte checks.

The unchanged Agent corpus was freshly emitted with Boundary `65f4613` and Agent
`20362f1`: all 18 images match the previously qualified bytes. Native and WASM
each cover 18 admission cases and 30 named replay cases containing 491 recorded
commands. Every command preserves its original control, quantum and checkpoint;
expected outcome bytes match exactly. No external host effect is dispatched.
All 48 local cells in each engine pass the specified timing and memory gates.
The native replay sampler also rejects a deliberately incorrect expected digest.

The additional 48 WASM comparisons retain the actual original baseline. They
still show previously accepted cumulative costs: review-model admission is
15.0% slower than that baseline (previously 13.8%), and 21 cases exceed its
memory threshold. None is a newly excessive local change. Admission peaks are
unchanged from the previous qualified runtime; the affected document/consequence
replay peaks add 212 bytes, below their local allowances of 2798–3712 bytes.
These costs remain visible in the report and are not described as zero cost.

Against original World `c20695e`, the final native 1000-call witness has paired
ratios 0.816, 0.714 and 0.684 at widths 4, 4096 and 65536. This is a bounded
same-image runtime comparison, not an application-wide speed claim.

The 582-case Boundary platform check and the public package check pass against
the new runtime, including 79 malformed-input rejections, 79 restores and 74
wrong-image rejections. Agent's outside-tree authoring check passes. Its 259-step
emission preserves all 123 generated outputs, and all three actual archive
command tests pass without skips. The archive changes only its dependency lock
and checksum manifest; its receipt retains the precommit source observation.

Full Agent integration passes 411/411 build steps, 202/202 Zig tests and the
95-test Node integration suite with no skips. The dependency snapshot remains
unchanged after integration. Serial reviews remain pending.

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
node test/current/native_consumer_cost.mjs \
  BASELINE_NATIVE CANDIDATE_NATIVE AGENT_CORPUS REPORT_JSON \
  INQUIRY_REPLAY_MANIFEST ADDITIONAL_REPLAY_MANIFEST
```

Arguments are positional absolute paths. The harness emits its own six images
and fixed inputs, asserts exact outcomes, and records every timing window. The
resident sampler also reports peak allocation across preparation, session and
outcomes in a separate instrumented pass. Run benchmarks without concurrent
builds. Kernel, image and source digests in the measurement file bind the recorded
run; a later run must report its own identities and results.

For the original 36-cell run, use the scalar sampler from `a48d5fd` and the
resident timing sampler from `9e2956a`. The resident peak-memory pass was added
after those timings and measured separately using `a48d5fd`; its incidental
timing samples are excluded. The JSON records these sampler revisions.

The native consumer command uses `scalar_batch_memory.zig` in admission and
recorded replay modes. Each recorded command has its own measured process;
reported trace samples sum corresponding per-command samples. This measures
fresh runtime invocations and excludes whole-application and external host
latency. WASM consumer comparisons use the maintained Boundary
`test/consumer_runtime_admission.mjs` and `test/consumer_runtime_replay.mjs`
harnesses with explicit authenticated locks for both arms. The report records
the immutable timed lock separately from the integration lock; their executable
dependency objects are identical, while publication/limitation text was updated.
