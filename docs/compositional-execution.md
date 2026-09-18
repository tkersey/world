# World 6 successor status

World 6.0.0-dev.0 executes Boundary's stable-activation Program through one evaluator,
with fresh and prepared/resident operation, portable checkpoints and a browser-neutral
embedding. The successor remains incomplete; all linked PRs remain drafts.

Current contracts and checks are described in [kernel-abi.md](kernel-abi.md) and
[verification.md](verification.md). The dependency manifest selects the current
Boundary source. Experimental evidence is excluded from the dependency package.

## Current validation

The current evaluator passes 75 native source tests, 42 storage tests, 14 activation
storage tests, 6,755 source-oracle observations, 257 native/Node boundaries and 23
transfers, 174 Wasmtime boundaries, real Chromium 153.0.8010.12 and Firefox 155.0
Worker transfers, capacity/retry checks, and extracted runtime/CLI checks.
Agent must also qualify this kernel through its normal dependency lock.
These checks establish their tested semantic/portability cases, not performance acceptance.

The kernel is 460,161 bytes with SHA-256
`dbb929681cb7675affaccefbfee9fd8fc5ee579e0d76276eedab882fd35642a8`.

## Frame storage and current results

Slot pages alone determine initialization. A frame retains a conservative pruning
bound, which may contain uninitialized slots and grants no read or ownership authority.
Batch transitions write selected values and reclaim slots outside the next admitted
liveness bound. This avoids maintaining an exact interned set after every write.
Small bounds remain inline; large bounds reuse analysis roots. Restore/unpack writes
extend the bound, reads and projection use actual slots, and retained views remain
copy-on-write. Failed private transitions are discarded/poisoned or restored from
Resident's backup. Tests cover both bound representations, unavailable live slots,
retained views, allocation failure, cleanup, restore, and reentrant execution.

Native 64-bit analysis pools now use 16-byte nodes when their declared member
limit fits in 32 bits, retaining 24-byte nodes for full-width domains. Public
members stay u64. Control64/128/256 working peaks are 201,927 / 320,429 /
608,169 bytes; tiny scalar and one-installation peaks rise by 38 / 66 bytes.
Current native control64 is about 320 microseconds. Tiny scalar invocations cost
roughly 40–80 ns more; other control differences are mixed. No broad latency claim
follows from this storage change.

Across 13 fixed Agent scenarios and 128 paired invocations, canonical outcomes
and transition/control/copy counters agree. Native Session inquiry/ReAct peaks
fall from 2,049,764 / 3,534,020 to 1,952,780 / 3,084,054 bytes. Whole-invocation
peaks (including framing) fall from 2,147,127 / 3,676,006 to 2,050,143 / 3,226,040.
The final native replay windows show no material latency regression.

The all-target tagged compact layout slowed sampled fresh wasm32 inquiry/ReAct
invocations by about 3% / 7%; that variant is rejected. wasm32 retains its prior
untagged storage, producing the byte-identical 460,161-byte kernel above. No guest
latency or memory gain is claimed. The workspace still preserves first-fit
allocation, and contract encoding releases scratch before retaining finished bytes.

## Unresolved acceptance

Optimized BPC1 control64 remains faster and smaller in working memory: about
238 microseconds / 121,956 bytes. Native Session inquiry/ReAct remain above BPC1's
1,853,961 / 2,061,220-byte working peaks, and ReAct guest latency remains open.
The remaining workload matrix, final coordinated qualification, and serial reviews
are still required. Working payload is not RSS or reserved memory. No full
performance-acceptance claim follows from these local improvements.

Standalone probes under `test/v2/` accept explicit source inputs:
`build_execution_bench.zig`, `build_value_bench.zig`, and `build_replay_bench.zig`.
Raw samples, profiles and historical experiment patches are not maintained.

Linked drafts: [Boundary #152](https://github.com/tkersey/boundary/pull/152),
[World #54](https://github.com/tkersey/world/pull/54),
[Agent #32](https://github.com/tkersey/agent/pull/32).
Future landing order is Boundary → World → Agent, only when separately authorized.
No merge, promotion or release is authorized. Current-tree deletion does not purge
historical Git objects.
