# World 6 successor status

World 6.0.0-dev.0 executes stable-activation Programs through one evaluator, with
fresh and prepared/resident operation, portable checkpoints and a browser-neutral
embedding. The successor remains incomplete; all linked PRs remain drafts.
Contracts and commands are in [kernel-abi.md](kernel-abi.md) and
[verification.md](verification.md).

## Current construction and validation

Slot pages determine initialization. Conservative pruning bounds grant no read or
ownership authority; retained views remain copy-on-write. Same-function tail calls
can reuse an activation only under the existing custody checks. Suspensions and
terminal outcomes reclaim dead backing; checkpoint export remains read-only.
Resident failure sweeps preserve unchanged retry input and cleanup custody.

On 64-bit native storage, a final reusable, capture-free callable can enter its
immediate handler without allocating an environment or callable object. State and
argument aliases, later uses and every declared edge source preserve ordinary
construction. The existing handler-entry owner receives the genuine arguments.
Fusion charges both work units and requires enough remaining quantum. Explicit
single-step execution retains the intermediate boundary. WASM uses ordinary
execution with the same work accounting and logical boundaries.

Tests distinguish eligible, non-adjacent, retained, edge-aliased, linear and
state-aliased callables. Bounded and strict checkpoints agree; every allocation
failure preserves retry state. The current candidate passes 81 native source
tests, 42 source/native/WASM cases (6,434 observations), 239 native/Node boundaries,
23 transfers, 161 Wasmtime boundaries, Chromium/Firefox Worker transfers, capacity
checks and extracted runtime/CLI checks. These prove the tested cases, not final
performance acceptance.

The generic kernel is 462,270 bytes, SHA-256
`03fe2d95e8a3ebb91115639f406ffcf72bbe3ec98be9a922a2af3ceae90a6307`.

## Current measurements and limits

The native comparison uses Boundary b3d3e76 / World fbc11c9 as its prior-successor
control, three warmups and nine samples per process, and two alternating windows.
These are complete fresh invocations on M2 Pro/macOS 27.2, Zig 0.16.0 ReleaseSafe.

| Installations | Before → candidate µs, confirmation range | Peak bytes before → candidate |
| --- | --- | --- |
| 8 | 31–33 → 29–30 | 40,222 → 30,623 |
| 64 | 272–291 → 252–266 | 179,719 → 179,228 |
| 128 | 556–577 → 509–512 | 274,031 → 265,012 |
| 256 | 1,126–1,136 → 1,034–1,065 | 400,643 → 391,624 |

Retained-loop peak falls 21,584 → 20,746 bytes, with a small observed timing cost.
All 128 Agent invocation outputs remain byte-identical. Agent timing differences
are small and mixed; consumer working peaks are unchanged. The kernel grows
237 bytes. WASM allocation fusion is excluded after a repeatable installation128
regression; the retained ordinary path removes that regression in the targeted
check. Final matched BPC1 acceptance remains open.

Boundary's dense accumulation slots remain in place. Full installation64/128/256
images stay below the compact BPC1 limits, and real handler results remain live
until the final checked sum. The maintained execution probe's --emit-input option
supports comparisons through a fixed runtime binary.

## Remaining acceptance work

The final matrix must recheck scalar, deep, small installations and retained-loop
costs against Boundary 42a09b9 / World d075169, including their working-memory gaps.
Earlier matched runs also exposed higher peaks for shallow, scheduler, queens,
cleanup, short sequences and small aggregate projections. These are unresolved
until final measurements establish their disposition; no failure is waived.

The implemented value representation retains the earlier large-value gains:
1 MiB product/variant projection avoided repeated payload materialization, and
consuming a 4,096-element sequence avoided repeated tail copies. The preceding
matched matrix measured roughly 96–100× / 55× improvements respectively; tiny
projections and the empty sequence were slower. Those timings are attributed to
the preceding candidate, not promoted to final acceptance.

Suspension reclamation retains the independent live-alias checks and its recorded
one-element-survivor result: 8,182 native working bytes with an 86-byte checkpoint,
independent of the discarded backing size. Its earlier 1–5% control-time cost must
remain accounted for in the final cumulative comparison.

Cold native build, warm no-change, client-edit and component-reuse observations
remain separate from runtime timings. The earlier source-only emitter comparison
was 16.50–16.56 s predecessor versus 15.45–15.50 s successor; the full compiler/
evaluator probe had no clear cold-build gain. Final build qualification,
coordinated consumer/package qualification and serial reviews remain required.

Small standalone probes under `test/v2/` accept explicit source inputs:
`build_execution_bench.zig`, `build_value_bench.zig`, and `build_replay_bench.zig`.
Generated samples, profiles and experimental patches are not maintained.
The Agent adequacy obstruction and minimal reproducer remain intact.

Linked drafts: [Boundary #152](https://github.com/tkersey/boundary/pull/152),
[World #54](https://github.com/tkersey/world/pull/54),
[Agent #32](https://github.com/tkersey/agent/pull/32).
Future landing order is Boundary → World → Agent, only when separately authorized.
No merge, promotion or release is authorized. Current-tree deletion does not purge
historical Git objects.
