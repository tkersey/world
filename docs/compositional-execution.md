# World 6 successor status

World 6.0.0-dev.0 executes Boundary's stable-activation Program through one evaluator,
with fresh and prepared/resident operation, portable checkpoints and a browser-neutral
embedding. The successor remains incomplete. Implementation has resumed after archive
cleanup; all linked PRs remain drafts.

Current contracts and checks are described in [kernel-abi.md](kernel-abi.md) and
[verification.md](verification.md). The dependency manifest selects the current
Boundary source. No experimental evidence directory belongs in the dependency package.

The last implementation qualification passed 32 build steps, 74 source tests,
39 storage tests, 30 host tests and 6,755 independent source-oracle observations,
including native, Node, Wasmtime, real Chromium/Firefox transfer and extracted-package
checks. Cleanup changes no evaluator code or semantic test expectation and does not
repeat the full matrix.

## Current results and unresolved work

The qualified kernel is 460,851 bytes with SHA-256
`b0cee0db452b46d9cf8f3f3067c52693383d566b9670a38da778793e29de66ee`.
Its bytes are unchanged by the retained native index-width optimization.

Native control64 measured 363/359 microseconds and 241,495 working bytes, versus
about 238 microseconds and 121,956 bytes for optimized BPC1. That gap remains open.
Control256 measured about 1.76 ms versus 2.33 ms for BPC1. The large variant-tag
workload retained its substantial full-invocation improvement; some small value
medians remain slightly higher. These observations are scoped to their workloads;
working allocation is not RSS or reserved memory.

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
