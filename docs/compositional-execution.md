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

The qualified kernel is 461,374 bytes with SHA-256
`353d8ca5ba0a94b09c4e6b83345adca5ae834236c7948ec7370ae6069b933e6e`.
It incorporates Boundary's temporary flow-storage release and bounded FIFO worklists.

Native control64 is about 362 microseconds and 219,987 working bytes, versus
about 238 microseconds and 121,956 bytes for optimized BPC1. That gap remains open.
Control128/256 peaks are 417,163 / 881,349 bytes: above the preceding successor's
415,111 / 788,285 but below BPC1's 435,558 / 1,324,938. The retained large variant-tag
improvement has not been remeasured for this change.

Across 13 unchanged Agent scenarios, native inquiry/ReAct peaks fall from
2,847,222 / 4,239,618 to 2,408,588 / 3,841,782 bytes. Native/Node outcomes and work
counts agree. Five paired guest windows overlap substantially; guest speed is
indeterminate. Working allocation is not RSS or reserved memory.

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
