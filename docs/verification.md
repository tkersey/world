# Current execution verification

Boundary's source oracle evaluates the staged AST independently of its compiler
and World. `zig build check-source` emits all 42 current source/BPI3 examples,
compares source-visible results, failures, payloads, yields and cleanup order,
and compares exact PKI3/PKO3 observations between native and WASM execution.
Fresh invocations alternate the actual producer of the next portable State.
The harness asserts the complete expected source/image name sets.

The migrated cases retain 42 borrow-operand inputs, scalar fault cases, deep and
shallow handling, answer transformation, forwarding, generators, retained and
reentrant multi-shot state, indexed effects, resources, DFS/BFS queens, and
cancellation before or during cleanup. The four cleanup-disposal expectations
retain the independent historical oracle correction, including finalizer order
`[3, 7, 99]`. Current fixtures are emitted by the selected compiler; no old-pin
exception or frozen BPI2 image is needed. PKI3 explicitly resumes an already
observed cleanup yield after cancellation records the first reason. Test horizons
count current instructions, not predecessor block transitions.

Unsupported forwarding constructors are absent from the current records.
Forwarding uses older-capability dispatch; the runtime control switch handles
every admitted terminator explicitly.

`check-native` exercises stable slots, retention, source execution, lifecycle,
allocation failure, rollback and PST3 admission. Capture bounds have valid and
invalid one-shot/multi-shot counterparts. Six return-path mutations reject
disposal markers; valid execution restores at every boundary, including captured
cleanup. `check-storage` retains lower-level storage, allocation, cloning and
collection regressions. The old native evaluator and its record-based execution
tests are removed after migration to current source and PST3. Current source
regressions also cover lexical shadowing, full-width zero-size collections,
same-family capability substitutions, forged region/token effects, duplicate
obligations and one-shot custody, and text and binary cancellation reasons.

`check-kernel` checks current native/fresh/resident agreement and handle custody.
`check-transfer` checks an independent Wasmtime embedding. `check-browser` moves
actual State through Chromium and Firefox Workers. These use one generic ABI 3
kernel; the source suite does not claim every host/fixture Cartesian combination.

`check-codecs` covers byte ownership, cross-realm views, intrinsic copying,
current value framing, exact ABI signatures, guest ranges and bounded regular-file
loading. `check-capacity` forces input, working and output budget failures and a
fixed physical-memory failure. It requires no published successor State, unchanged
input, successful retry and cleared output after malformed ABI calls. ABI 3 labels
allocator observations as lower bounds and final output demand as exact.

`check-package` executes the API and CLI from an extracted current npm artifact.
The old ABI 2 guest/host, v1 replay corpus, archive/release tools and old-format
drivers are removed. Current dependency archive authentication and safe extraction
are exercised by Agent's `test/agent4/setup.test.mjs` and
`test/agent4/consumer_build.test.mjs`. Agent's normal authenticated lock now selects
Boundary 1b00c8c and World a20a285; its recorded functional qualification includes
these paths. Remaining selected-tuple performance confirmation and serial reviews
are tracked in [current results](compositional-execution.md). Historical performance
samples remain in Git history, not in a maintained old-format production dependency.

The old ABI 1 Boundary locks, frozen vector bytes and repository-repair transcript
bundle are also removed from the source package. Their current counterparts are
the independent source-oracle suite, malformed PST3 tests, capacity checks and
Agent's qualified repair/approval/inquiry scenarios. The retired bundles are
available through immutable World 5.0.2 source
`d075169a4805d999ceba4c37b3e1c925b78c3bf9`; they are not current dependencies.

These checks do not prove host truthfulness, global exactly-once effects,
historical reachability of arbitrary State, full performance acceptance, or a
refinement theorem for the shipping implementation. Boundary's formal model is a
separately authored semantic model with its own independently runnable checks.

## Coordinated optimization qualification

The [coordinated acceptance report](https://github.com/tkersey/boundary/blob/codex/canonical-durable-3183/docs/optimization-acceptance.md) retains exact P22/P25/P26
source/kernel identities, local and cumulative measurements, accepted costs and
remaining review status. World has no redundant generated delivery reports in
this change set. Its distinct native/WASM, retained-view, quantum, alias, failure
and source-agreement harnesses remain substantive qualification inputs. Cleanup
of documentation does not rebuild or relabel the authenticated cb52f4f kernel.

## Zig 0.17 migration qualification in progress

Maintained source, compiler selection, and CI support exact Zig 0.17.0 only.
The 0.16 predecessor is frozen comparison evidence. The migration retains ABI 3,
22 function exports plus memory, import-free unshared wasm32, the `small` kernel,
65,536-byte stack, 268,435,456-byte maximum memory, and existing runtime budgets.
The explicit linker export list prevents Zig 0.17's `-rdynamic` from adding the
linker's `__stack_pointer` export. `check-kernel` independently checks the ABI.

The current local migration passed `check check-zig17 -Doptimize=safe` (47 steps)
on macOS arm64 with the official 0.17.0 distribution. Node/native canonical
agreement covered 235 boundaries and 23 transfers; Node/Wasmtime/native transfer
covered 158 boundaries. This is local correctness evidence, not a complete
cross-platform delivery or performance result. The coordinated upgrade's
experiments and final delivered-artifact qualification remain open.

### Retained borrow intervals

| Owner and borrow | Creation and last use | Potential invalidation and disposition |
|---|---|---|
| Activation view table: `lookupView` pointers | `release`, protected `commit`, `change`, and `retainOnly`, through their last view access | Page allocation and drop callbacks occur inside these intervals. Lock `views`, with deferred unlock on every return/error. Run `protect` before locking because frame journaling may legitimately fork/add a view; reacquire afterwards. |
| Activation views: immediate reads, registration, transfer | Lookup through immediate field read/write; `fork` copies the view before allocation | No retained pointer crosses table growth. Generation/instance checks remain authoritative even when an address is unchanged. |
| Session frame map: `getMutable` result | `stepInternal` before instruction execution through the last frame write | Lock `frames.entries` for ordinary instruction paths. Copy the descriptor and unlock before control, known-handler installation, or clone paths that may grow/move the map. Deferred unlock covers errors. |
| Store mark arrays: `marks` and `blob_marks` slices | `collectWith` after capacity reservation through tracing and reclamation | Slices survive frame-owner callbacks and journal allocation. Lock both containers and defer both unlocks. Other store arrays are accessed by index or copied value. |
| Store free-blob suffix | Deferred sorting after retirement | Capacity is reserved before retirement. The suffix is acquired only at sorting time; no append/growth occurs while it is borrowed. |
| Store/journal hash-map iterators | Rollback/collection loop, ending before table clear/rebuild | Journal iteration does not mutate its own map. Intern-table retirement removes only the current entry with `removeByPtr`; it does not grow/rehash the table. Pointer locks must not forbid this supported removal. |
| Activation page arrays and slot iterators | Stable separately allocated page; iterator carries the logical handle/revision | View-table relocation does not relocate pages. Logical retirement, mutation, and ownership transfer remain checked separately; a container lock cannot replace those checks. |

`check-zig17` injects view growth and shifting removal through the allocator at a
real `change` borrow. The parent requires the injection marker and a pointer-lock
stack, rejecting unrelated crashes. The fault child uses `debug` so diagnostic
frames remain identifiable. Valid neighbors cover ordinary post-borrow growth,
allocation-failure retry, stale-generation rejection at a stable address, and
moving an unlocked owner, all with explicit SafeAllocator leak checks. These are
bounded diagnostics, not concurrency protection or hostile-process isolation.

Native failure sweeps force resize failure before the standard allocation-failure
sweep. SafeAllocator's successful remaps otherwise make allocation ordinals vary
between identical runs. Ordinary native tests retain the real allocator and resize
paths; production storage and rollback policy are unchanged. Allocation ordinals
and native metadata bytes are not asserted equal to the predecessor.
