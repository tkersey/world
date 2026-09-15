# Compact program images

BPC1 reduces complete program images while preserving canonical profile-1
records, legacy identities, PST2 and existing World invocation APIs. The codec
is opt-in; ordinary authoring and BPI2 production remain unchanged.

Paired drafts: [Boundary #151](https://github.com/tkersey/boundary/pull/151) and
[World #53](https://github.com/tkersey/world/pull/53). World pins published Boundary
`315c9b1e3c5ccacbb9cf6c2ecf22bb042c88eb6c` and its verified Zig package hash.
Default and source-override builds produce identical kernel bytes.

## Representation and correspondence

Boundary encodes typed literals, repeats and slot ranges. Economical immutable
backings share block parameter prefixes or suffixes; a full-length logical use
is required for every backing. This prevents a small view retaining otherwise
unused expanded storage. Instruction headers omit exact zero/empty fields;
eight-byte literal payloads can use shorter integer bit-pattern spellings.

The decoder reconstructs the same logical records in the existing `Decoded`
owner, then runs canonical admission. It validates the owned input snapshot,
checks compressed descriptors before expansion, and frees temporary admission
storage. World retains its existing generic evaluator, ownership transfers,
collection cadence/scratch and request preparation. The old identity algorithm
still visits the expanded canonical stream and remains quadratic in growing
interfaces. Numeric sizing and a one-byte reader fast path reduce overhead
without changing any legacy bytes or validation rules.

The [wire specification](https://github.com/tkersey/boundary/blob/perf/compact-program-images/docs/bpc1-wire.md)
and [public emission example](https://github.com/tkersey/boundary/blob/perf/compact-program-images/examples/compact_image.zig)
describe the precise format and adoption API. The encoder chooses exact BPI2
fallback when its complete compact candidate would not be smaller.

## Complete image sizes

| Program | BPI2 | Selected compact | Reduction |
| --- | ---: | ---: | ---: |
| 64 installations | 8,971 B | 2,805 B | 68.7% |
| 128 installations | 30,141 B | 5,574 B | 81.5% |
| 256 installations | 118,205 B | 12,102 B | 89.8% |
| Nonperiodic interface, 64 boundaries | 7,481 B | 1,836 B | 75.5% |
| Nonperiodic interface, 128 boundaries | 27,111 B | 3,572 B | 86.8% |
| Retained queens search | 2,298 B | 2,094 B | 8.9% |
| Stored 64 KiB constant | 65,652 B | 65,605 B | 47 B |

Installation parameter descriptions are 73/137/265 and argument descriptions
132/260/516 at 64/128/256 boundaries: linear physical descriptions, with all
logical occurrences preserved. A nonperiodic 64-boundary witness has 129 physical
parameter descriptions instead of 2,080 entries. The public-builder generator
varies schema pattern, operand order, declaration order and copies independently.

The 64-installation image contains 20 framing bytes, 6 dictionary bytes,
2,410 block bytes, 263 constant bytes and 106 other catalog bytes. Runs, shared
interfaces, instruction defaults and small constant payloads address the major
supported reductions. Remaining literals, distinct declarations, instructions
and intrinsically large payloads remain explicit. The large constant is stored
once and referenced twice; its payload is unchanged. No global minimum encoding
is claimed. An existing Agent-generated document image was inspected read-only
(8,717 to 8,212 bytes in the earlier prefix candidate); Agent was not modified.

## Runtime comparison and measurement controls

The optimized references are Boundary
`5084a0d487b886197863866e20ebe6d04de2a0a1` and World
`fd794b36fe7f429fcd62def4d87556cb5ace56f9`, containing merged #150/#52.
Zig 0.16.0, native ReleaseSafe, guest ReleaseSmall and Node 26.8.2 were used.

Each final window has five warmup batches and 21 rotating-order observations,
200 complete public calls per batch, with a fresh WASM instance on every call.
Three independent Node processes isolate the reference BPI2, candidate BPI2 and
candidate BPC1 hosts. IPC and initial module admission are outside call timers;
image/State admission, identity, execution and publication remain inside.
Numbers below are medians of batch averages, **not p99 latency**.

| Compact public call | Window 1 reference → compact, ms | Window 2 reference → compact, ms |
| --- | ---: | ---: |
| Small | 0.08329 → 0.08415 | 0.08489 → 0.08448 |
| 64 installations | 0.65286 → 0.59103 | 0.65213 → 0.59128 |
| Retained search | 0.63030 → 0.62223 | 0.62894 → 0.61845 |
| 128 installations | 1.79594 → 1.53978 | 1.79047 → 1.53198 |
| Stored constant | 0.54584 → 0.54665 | 0.54061 → 0.54068 |
| Saved response | 0.94857 → 0.93478 | 0.94451 → 0.93021 |

[Window 1](compact-images/runtime-final-window-1.json) and
[window 2](compact-images/runtime-final-window-2.json) retain all three
configurations and raw observations. Installation calls improve about 9–14%;
search/response are slightly faster, and small/large-constant calls stay near
parity with no reproducible material regression in these windows.

Earlier shared-process measurements showed small search/response penalties.
Identical-kernel controls also showed ordering-dependent displacement. Isolating
loaded hosts removed shared JIT/GC interaction while retaining the same public
calls and timed work. The [shared-process windows](compact-images/runtime-shared-process-window-1.json),
[second window](compact-images/runtime-shared-process-window-2.json) and
[control](compact-images/runtime-final-control.json) remain counterevidence;
they are not replaced or silently pooled with the final method.

[Secondary observations](compact-images/secondary-final.json) preserve complete
checkpoint hashes. Repeated portable advance improved 286.75 → 248.85 ms across
321 checkpoints. BFS, reentrant control, local/shared state, capture payloads,
generator, scheduler, owned cleanup and recursion are included. These secondary
results have one window and establish no universal speed or tail-latency claim.

## Memory and construction costs

[Memory results](compact-images/memory-final.json) use the existing 16 MiB native
invocation and 1 MiB decoder reservations. These are allocator-requested payload
bytes, not RSS or reduced reservations. Allocation counts and copying statistics
are retained in the same results.

| Complete invocation | Optimized reference peak | Compact peak |
| --- | ---: | ---: |
| Small | 9,042 B | 8,700 B |
| 64 installations | 140,036 B | 121,956 B |
| 128 installations | 660,850 B | 435,558 B |
| Retained search | 122,612 B | 121,160 B |
| Saved response | 142,450 B | 140,998 B |
| Nonperiodic, 64 boundaries | 172,906 B | 146,822 B |
| Stored constant | 493,193 B | 493,123 B |

[Sharing ablation](compact-images/parameter-sharing-ablation.json) compares eager
ordinary parameter arrays with shared backing under the same production kernel.
Shared backing lowers observed memory and [full-call time](compact-images/parameter-sharing-latency.json);
it also reduces the nonperiodic image from 3,785 to 1,836 bytes. Arena growth
thresholds influence peak sizes, so these are workload-specific observations.

The new codec has an emission cost. [Source-to-image profiling](compact-images/source-to-image.json)
measured 1.257 → 1.405 ms at 64 installations and 4.890 → 5.324 ms at 128
(nine paired processes, each summarizing 21 internal observations). These
instrumented whole pipelines include authoring, compilation, allocation and
encoding; they are separate from already-built encoder phases. Compact emission
is opt-in and this extra producer work is not hidden in invocation setup.

The kernel grows from 393,588 to 413,317 bytes, a fixed 19,729-byte cost shared
by unrelated programs. Its SHA-256 is
`d046dbe1e92e61bb3d8aeb52cac898ae90916fb388c289d87c0b304ff23e7380`.
[Fresh-process setup](compact-images/kernel-setup.json) measured medians of
1.8615 and 1.9319 ms across nine alternating pairs. The
[cold guard](compact-images/cold-guard.json), five fresh-cache pairs, measured
legacy-emitter build medians 16.809 → 17.063 s and kernel builds 9.567 → 9.999 s.
All emitted legacy examples agree and each kernel reproduces exactly. These
costs accompany the new codec; the historical 0.80-versus-1.8.2 target is excluded.

## Validation and reproducibility

Boundary's aggregate passes, including existing formal-core checks and native/
wasm32 writer agreement over 60 images. Codec tests cover canonical hand-built
and compiled records, field equality, legacy re-encoding, identity, integer
boundaries, alternative legal spellings, ownership, malformed input and allocator
failure. An allocator callback regression proves framing is checked on owned
bytes. Existing tests and oracles were retained.

World's **default pinned-dependency aggregate** passes. Native/JavaScript/Wasmtime
agree across 3,139 cross-format calls over 41 source images, including fresh
PST2 transfers, stale responses, cancellation and cleanup. All three capacity
arenas publish no successor on exhaustion and retry unchanged inputs. The old
native/WASM kernels reject BPC1 normally; old BPI2 behavior and all 33 historical
v1 compatibility cases remain checked.

[Authenticated package verification](compact-images/package-check.json) binds
published Boundary `315c9b1` and World `61d05e8`: inventories, compiler example,
bundled CLI, 563 runtime replay checks and 905 external records pass. New
consumers were authored after exact kernel freezes. Unknown kernels still reject.
Assets were generated locally; no release was published. Later report/benchmark
changes do not change the tested runtime, and these receipts do not authenticate
any future release.

Reproduce with repository build steps and the narrow tools in `test/v2`:
`compact_isolated.mjs` (two kernel paths, fixture directory, new JSON output),
`compact_secondary.mjs`, `compact_memory.mjs`, and Boundary's
`compact-image-report`/`compiler-phases`. Run benchmarks without overlapping
builds. Default `check-v2` additionally needs `boundary-v2-fixtures`, the frozen
v1.8.2 `legacy-v1-kernel`, and the separately built `bpi1-lift` paths. Packaging
uses the clean published Boundary Git checkout for source receipts; the default
package-pin build is separately proved byte-identical.

## Selection and limits

Whole-image double preflight was replaced by validation at each compressed
sequence. Forced inlining, outlining and hash buffering did not establish needed
end-to-end gains and were removed. A broad length fold added excessive kernel
code; the retained sizing-only sequence fast path has the same byte projection.
These unfavorable measurements remain alongside the final results.

The installed Actuating/Metanoetic/Tune packages were read; the initial inspect-only
Tune pass found no skill defect. The user's later reload expanded Tune to software
performance, and it governed the measured runtime experiments. No skill files,
Agent code, external pins or public record layouts changed. Draft delivery and
Actuating review closeout remain separate from the executable proof above.
