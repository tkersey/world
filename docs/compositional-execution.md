# World 6 successor status

World 6.0.0-dev.0 executes Boundary's stable-activation Program through one evaluator,
with fresh and prepared/resident operation, portable checkpoints and a browser-neutral
embedding. The successor remains incomplete. Implementation has resumed after archive
cleanup; all linked PRs remain drafts.

Current contracts and checks are described in [kernel-abi.md](kernel-abi.md) and
[verification.md](verification.md). The dependency manifest selects the current
Boundary source. No experimental evidence directory belongs in the dependency package.

The latest flow-storage candidate passes 74 source tests, 52 storage tests,
257 native/Node boundaries, 23 transfers and extracted runtime/CLI checks. Prior
qualification also covered 6,755 source-oracle observations, Wasmtime and real
Chromium/Firefox transfer. Those broader host lanes still need final requalification.

## Current results and unresolved work

The qualified kernel is 459,875 bytes with SHA-256
`39320df71108e646a68183f4fd4394401c30933d238f01dee4abbaa52ae7adaa`.
Canonical set nodes now use 24 bytes instead of 32 without narrowing members or
roots. Cardinality is derived from ranges, words and children. Compact predecessor
storage remains specific to 64-bit hosts; smaller set nodes apply on both targets.

Native control64 is about 360 microseconds and 214,595 working bytes, versus
about 238 microseconds and 121,956 bytes for optimized BPC1. That gap remains open.
Control128/256 peaks are 353,313 / 715,953 bytes, below both the preceding
successor and BPC1's 435,558 / 1,324,938. The retained large variant-tag
improvement has not been remeasured for this change.

Across 13 unchanged Agent scenarios, native inquiry/ReAct peaks fall from
2,847,222 / 4,239,618 to 2,367,460 / 3,656,504 bytes. Native/Node outcomes and work
counts agree. Five paired guest windows show mixed medians within the observed variability;
no general guest speedup is claimed. Working allocation is not RSS or reserved memory.

Agent inquiry/ReAct working peaks and ReAct guest latency remain unresolved against
BPC1. The remaining workload matrix, consumer retirement, final coordinated
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
