# World 6 successor status

World 6.0.0-dev.0 executes Boundary's stable-activation Program through one evaluator,
with fresh and prepared/resident operation, portable checkpoints and a browser-neutral
embedding. The successor remains incomplete. Implementation has resumed after archive
cleanup; all linked PRs remain drafts.

Current contracts and checks are described in [kernel-abi.md](kernel-abi.md) and
[verification.md](verification.md). The dependency manifest selects the current
Boundary source. No experimental evidence directory belongs in the dependency package.

Current checks pass: 75 native source tests, 41 storage tests, 6,755
source-oracle observations, 257 native/Node boundaries, 174 Wasmtime transfer
boundaries, real Chromium 153.0.8010.12 and Firefox 155.0 Worker transfers, and
extracted runtime/CLI checks. Agent's compiled-tool transfer must be requalified
after its normal dependency lock selects the new kernel. These are semantic/portability
checks; they do not establish performance acceptance.

## Current results and unresolved work

The kernel is 459,961 bytes with SHA-256
`a32c2a807f5b8c10cec4f44d235c2dae938e72b78c7d654843cf968fb4a6cf7c`.
Canonical set nodes now use 24 bytes instead of 32 without narrowing members or
roots. Cardinality is derived from ranges, words and children. Compact predecessor
storage remains specific to 64-bit hosts; smaller set nodes apply on both targets.
Type validation reuses its existing schema exportability table for borrow checking.
This removes one duplicate derivation; working peaks are unchanged and no speedup
is claimed from the local reuse.

The workspace now skips a known allocated prefix while preserving first-fit
selection. Frees update the hint only when segment address order proves list
order; other growth orders fall back to scanning. A 20,000-operation differential
trace preserves offsets, failures, live bytes and capacity accounting. In
control256, inspected blocks fall from 139,600 to 71,306 for the same 3,071
allocations. Block metadata, allocation counts and working peaks are unchanged.

Two rotating native timing windows support roughly 3–5% improvements on
control8/64/256. The confirmation medians for control64/256 are about 350 / 1,714
microseconds; control128 and tiny-program changes remain indeterminate. Across
128 prescribed Agent invocation replays, per-scenario differences remain below
1%, so no Agent latency gain is claimed from the hint.

Native control64 is about 350 microseconds and 214,595 working bytes, versus
about 238 microseconds and 121,956 bytes for optimized BPC1. That gap remains open.
Control128/256 peaks are 353,313 / 715,953 bytes, below both the preceding
successor and BPC1's 435,558 / 1,324,938. The retained large variant-tag
improvement has not been remeasured for this change.

Contract encoding now releases canonicalization scratch before retaining its
finished bytes. Inquiry/repeated/ReAct preparation retains 1,265,868 / 1,275,378 /
2,812,770 bytes instead of 1,583,444 / 1,692,696 / 3,057,524. Across 13 unchanged
Agent scenarios and 128 paired native invocations, inquiry/ReAct working peaks
fall from 2,367,460 / 3,656,504 to 2,049,764 / 3,534,020 bytes. Outcomes and
transition/copy counters match the preceding native runtime and pinned Node/Wasmtime
runtime. ReAct now peaks during admission rather than contract retention.

Five rotating native timing windows and a second eight-window control comparison
show overlapping timing variability; no latency improvement is claimed. Scalar,
deep and 1/8/64/128/256 installation working peaks are unchanged. Working allocation
is not RSS or reserved memory. This comparison isolates the current change, not
final acceptance against BPC1: inquiry/ReAct remain above its 1,853,961 / 2,061,220
byte peaks.

Agent inquiry/ReAct working peaks and ReAct guest latency remain unresolved against
BPC1. The remaining workload matrix, final coordinated
qualification and serial reviews are still required. Passing semantic checks do
not establish full performance acceptance.

Standalone native probes remain under `test/v2/`: `build_execution_bench.zig`,
`build_value_bench.zig`, and `build_replay_bench.zig`. They accept explicit source
inputs. Historical raw samples, profiles and experiment patches have been removed.
Defect records retain historical provenance at their recorded Git revisions.

Linked drafts: [Boundary #152](https://github.com/tkersey/boundary/pull/152),
[World #54](https://github.com/tkersey/world/pull/54),
[Agent #32](https://github.com/tkersey/agent/pull/32).
No merge, promotion or release is authorized. Current-tree deletion does not purge
historical Git objects.
