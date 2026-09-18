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

Against World d571cbb with Boundary c6d9cf4, two isolated rotating-order native
windows (seven pairs each, nine measured fresh invocations per process) improve
64/128/256 installations by about 8% / 10% / 11%. Confirmation medians are
325 / 713 / 1,562 microseconds. Input bytes and independent results match.
Tiny scalar, deep, and 1/8-installation timing changes remain indeterminate.
Working peaks are 214,595 / 349,093 / 715,953 bytes; only control128 falls
(from 353,313). The kernel grows 200 bytes. Agent latency is not claimed here.

The workspace retains first-fit allocation with a search hint; a 20,000-operation
differential trace preserves offsets, failures, contents and capacity accounting.
Set nodes use 24 bytes without narrowing members; schema exportability is reused.
Contract encoding releases scratch before retaining finished bytes. The preceding
qualified Agent inquiry/ReAct working peaks are 2,049,764 / 3,534,020 bytes;
these numbers require confirmation for the current kernel.

## Unresolved acceptance

Optimized BPC1 control64 remains faster and smaller in working memory: about
238 microseconds / 121,956 bytes. Inquiry/ReAct remain above BPC1's
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
