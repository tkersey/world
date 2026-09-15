# Compact program images: implementation results

**Status: implementation and selection in progress.** Size and initial native
correspondence are established for the witnesses below. Performance retention,
the full cross-engine corpus, default dependency integration and draft PR
delivery are not yet complete.

## Reference and construction

The accepted September 14 Compact Program Images v1 specification governs this
successor. Both earlier performance PRs merged before implementation began.
The immutable optimized references are Boundary
`5084a0d487b886197863866e20ebe6d04de2a0a1` and World
`fd794b36fe7f429fcd62def4d87556cb5ace56f9`. Separate worktrees use
`perf/compact-program-images`; the previous performance branches are untouched.

Boundary owns the opt-in codec and exact logical projection. Typed literals,
repeats and ascending slot runs remove repeated wire descriptions. A small
schema-ID backing table shares profitable block parameter prefixes. Instruction
headers omit exact zero immediates and empty failure lists. World dispatches
recognized BPC1 images into those existing records and its existing evaluator.
All other public records, authoring APIs, BPI2 defaults, logical identity and
PST2/protocol behavior retain their contracts.

The installed skills were read at dotfiles
`490cffce0f9a53f99c66260ab8764c078dcb4c96`. After the user requested a reload at
`74b8e1c8e268385621de23f23a495b34c28adcae`, Tune also owned software-performance
experiments under its expanded scope. The required Metanoetic pass compared
local runs with whole-program prefix storage under the same size/performance
constraints. Universalist nominated the existing owned Program boundary;
Actuating selected it. `tune tune`, with inspect authority on Actuating, found
no supported skill defect and made no package changes. Tests do not establish
global compression optimality.

## Size and structural observations

These are complete selected images, including framing and dictionary bytes.
The unchanged installation programs preserve all live results and transitions.
The mixed witness is synthetic public-builder code with heterogeneous result
types, growing live interfaces, permutations and repeated copyable operands.

| Program | BPI2 | BPC1 | Reduction |
| --- | ---: | ---: | ---: |
| 64 installations | 8,971 B | 2,805 B | 68.7% |
| 128 installations | 30,141 B | 5,574 B | 81.5% |
| 256 installations | 118,205 B | 12,102 B | 89.8% |
| Mixed interface, 64 boundaries | 7,481 B | 1,836 B | 75.5% |
| Mixed interface, 128 boundaries | 27,111 B | 3,572 B | 86.8% |
| Retained queens search | 2,298 B | 2,094 B | 8.9% |

The 64/128/256 installation images have respectively 73/137/265 physical
parameter descriptions and 132/260/516 argument descriptions. This is linear
description growth while the logical interfaces remain quadratic. The current
64-installation breakdown is 20 framing bytes, 6 dictionary bytes, 2,410 block
bytes, 263 constant bytes and 106 bytes in the other catalogs. Eight-byte
constant payload abbreviations and suffix sharing are retained after attribution.

## Measured costs and unfavorable observations

Zig 0.16.0; native ReleaseSafe and repository-fixed guest ReleaseSmall; fresh
WASM instances on every public call. Development timing windows used five
warmup batches, nine rotating-order observations and 100 calls per batch.
Reported times are **batch averages**, not individual-request latency tails.
The final separated confirmation windows remain required.

The [whole-image preflight prototype](compact-images/runtime-whole-preflight.json)
was 5.5% slower on small compact calls, 6.1% on retained search and 6.2% on saved
search response. It is not selected. Full preflight duplicated the traversal of
ordinary fields. The successor validates each compressed descriptor immediately
before its allocation/expansion and removes that redundant whole-image pass.

The [sequence-local window](compact-images/runtime-sequence-preflight.json)
improved compact small and installation calls, but still showed approximately
2.7–2.8% slower search calls. Candidate BPI2 installation calls were 4–5% slower
than reference BPI2. Format-dispatch inlining is being tested as an attribution
hypothesis; these costs are unresolved selection obligations.

[Native memory observations](compact-images/memory-sequence-preflight.json)
use the existing 16 MiB invocation and 1 MiB decoder reservations. They count
allocator-requested payload bytes, not RSS or reserved memory savings.

| Complete invocation | Reference peak | Compact peak |
| --- | ---: | ---: |
| Small | 9,042 B | 8,788 B |
| 64 installations | 140,036 B | 126,750 B |
| 128 installations | 660,850 B | 447,804 B |
| Retained search | 122,612 B | 121,332 B |
| Saved search response | 142,450 B | 141,170 B |
| Mixed, 64 boundaries | 172,906 B | 147,376 B |

The reference kernel is 393,588 B, SHA-256
`9545076f16482ccb346ab7792ae87f4d9a262c3fe08b4086b3c376ed2b218c06`.
The sequence-local prototype is 412,365 B, SHA-256
`9e6cfa954af0225b0e6df4dd347bb5fa05c806d714594be85aa27b93ef0c4180`.
The kernel-size increase is separate from per-program savings and remains in
the cost account. These development observations bind uncommitted prototypes,
their named executable hashes and the retained input/output hashes; they are
not final-head acceptance or release authentication.

## Checks so far

Boundary's `check-v2-data` and `check-v2-compact` pass in ReleaseSafe. They cover
hand-authored/compiler-generated records, every-field equality, legacy bytes,
identity, independent backing lifetime, allocation failures, exact/short/overlap
buffers, malformed framing/counts/ranges, alternate legal spellings, mixed
interfaces and a byte-identical BPI2 fallback witness.

World's `check-v2-native` and `check-v2-source` passed with the compact source
override before the latest inlining experiment. Added tests compare every
64-installation advance outcome, alternate BPI2/BPC1 across fresh invocations,
and resume saved search with unchanged PST2 and request/response identities.
Existing tests and independent expected outcomes remain intact.

Reproduction uses the existing build steps and the new narrow tools:

```sh
# Boundary checkout
zig build check-v2-data check-v2-compact emit-v2-compact-fixtures \
  build-compact-image build-compact-image-report -Doptimize=ReleaseSafe
zig-out/bin/compact-image-report < zig-out/install-128.bpi2

# World checkout, with absolute source and artifact paths
zig build build-v2-kernel build-v2-economy-probe build-v2-decode-probe \
  -Doptimize=ReleaseSafe -Dboundary-v2-source="$BOUNDARY_CANDIDATE"
node test/v2/compact_performance.mjs "$REFERENCE_KERNEL" "$CANDIDATE_KERNEL" \
  "$FIXTURES" "$NEW_OUTPUT_JSON" 21 200
node test/v2/compact_memory.mjs "$REFERENCE_ZIG_OUT" "$CANDIDATE_ZIG_OUT" \
  "$FIXTURES" "$NEW_MEMORY_JSON"
```

The benchmark fixture directory contains both encodings of each named input;
the pure `compact-image` converter supplies compact forms of existing source
fixtures. Output paths must be new so prior observations are preserved.

## Remaining delivery obligations

Resolve all protected per-workload timing regressions; complete additional byte
attribution and representation ablation; verify the large constant, repeated
advance, full generalized-effect native/JavaScript/Wasmtime corpus, cross-format
cancellation/cleanup and capacity retries; finish encoder/construction/identity
costs and the cold-build guard; run required aggregate and packaging checks;
publish the Boundary commit, update only the successor World's dependency and
package hash, regenerate exact kernel authentication, and deliver paired draft
PRs through Ship and Actuating review-closeout. No merge, ready transition,
release or external consumer-pin update is authorized.

## Published integration checkpoint

[Boundary draft #151](https://github.com/tkersey/boundary/pull/151) supplies immutable
commit `315c9b1e3c5ccacbb9cf6c2ecf22bb042c88eb6c`. This successor pins that
commit and its verified Zig package hash. A default build, without a source
override, passed native checks and reproduces the candidate kernel. The retained
one-byte natural reader fast path preserves the longer-integer validation rules.
Final paired performance acceptance, package checks, cold guard and review
convergence remain pending; this is a draft checkpoint, not full closure.
