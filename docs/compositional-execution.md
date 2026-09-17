# Compositional execution: World status

This is an incomplete part of the accepted Boundary 3 / World 6 / Agent successor.
The complete specification, including draft publication and serial review closeout,
remains the goal. No merge, release or application data operation has occurred.

World starts at `d075169a4805d999ceba4c37b3e1c925b78c3bf9` on the dedicated
`feat/compositional-execution` branch. Validation uses the separate Boundary
successor worktree at `5c7a38e1ad63445b633f30ba82eff60b0af0c697`, Zig 0.16.0,
and Node 26.8.2. The normal dependency pin remains the predecessor until cutover.

## Private activation slots

`src/interpreter_v2/activation_slots.zig` stores value descriptors in indexed
16-slot pages under a radix directory. Reads take a path bounded by machine word
width, not the number of earlier handlers. Existing unique paths update in place.
Shared paths copy only touched pages/directories; new storage is prepared before
the authoritative root changes. Directory growth never copies a whole slot array.

Forked views retain binding versions. They do not clone referents: an actually
outer mutable cell remains shared. Branch-local region/cell cloning must remain
the evaluator's separate semantic operation. Private reference counts, addresses,
generations and instance keys are not portable State or Program identity.

Handles check store instance, generation and active state. Iterators additionally
reject mutation after traversal starts and enumerate only initialized bindings in
slot order. Instance-counter exhaustion fails closed; its atomic uses the host word
size so the wasm32 baseline requires no 64-bit atomic support.

Tentative views can be discarded or committed without changing retained entry
views. Point updates and survivor compaction preserve the old root on allocation
failure. This is a component guarantee, not yet a complete Session transaction:
the evaluator's mutable object graph, control, pending response and output buffers
must participate in the final commit protocol as well.

`retainOnly` right-sizes a small survivor. It is not an implementation of ordinary
continuation capture or a per-boundary full-environment copy. The evaluator must
use changed liveness and required-disposition facts to clear dead slots; it must
not confuse memory reclamation with semantic finalization. Views and this store
have native owner lifetimes; all handles expire when their store is destroyed.

## Shared value evaluator

The existing aggregate/blob implementation reads either ordinary argument arrays
or stable slots through `operands.zig`. It now needs only schema records, not a
predecessor Program. Sparse slot tests execute real product, projection and blob
operations with independent expected bytes. No second value evaluator was added.
The current control interpreter still uses predecessor block interfaces.

## Evidence and limits

The growing 1/8/64/128/256/4096-binding tests establish each value without copying
earlier value descriptors. Retained loop versions and reentrant storage forks
remain isolated. A 4,096-slot population shrinks to one live page and at most two
directories for one surviving binding, with reserved storage under one eighth of
the original. Capacity accounting includes node bytes and reserved handle tables;
payload-graph storage and allocator overhead are separate.

Tests also cover stale/foreign handles, iterator invalidation, tentative commit
and rollback, ordered enumeration under different allocation histories, shared
outer cells, deterministic allocation-failure sweeps, and 600 mixed lifecycle
steps against an independent flat-array model. These are storage witnesses, not
proof of complete multi-shot or portable checkpoint execution.

```sh
zig build check-v2-native check-activation-storage-wasm \
  -Dboundary-source=/absolute/path/to/boundary-compositional-execution \
  --global-cache-dir .cache/activation-global --summary all
zig build check-v2-native -Doptimize=ReleaseSafe \
  -Dboundary-source=/absolute/path/to/boundary-compositional-execution \
  --global-cache-dir .cache/activation-global --summary all
zig build check-v2-source check-v2-wasm \
  -Dboundary-source=/absolute/path/to/boundary-compositional-execution \
  --global-cache-dir .cache/activation-global --summary all
```

The isolated storage probe executes in an import-free wasm32 module with unshared
memory and an explicit maximum. It is a test probe, not World kernel ABI 3. Existing
source agreement and native/WASM transfer regressions pass, including handlers,
regions, cleanup, compact collections and 10,000 tail calls. Those are predecessor
regression results and do not establish successor portability.

No full-path latency improvement is claimed. The existing `NEG-000012` exclusion
still covers its exact old continuation-view/edge-projection implementation.
The definition-bound route check found no applicable exclusion for stable-slot
storage; no negative-evidence record was changed. The new mechanism still owes
the specification's measured complete-path comparison.

## Native stable-control slice

`stable_session.zig` now executes the direct Boundary `source.lower` records.
Function inputs populate stable slots; continuation nodes own private frame views
rather than predecessor argument vectors. Changed-only edge assignments use
simultaneous sources and omit dead copyable destinations. Reclamation uses set
differences, and the graph collector traces bindings in live control frames.
The same instruction implementation serves both layouts during migration.
The predecessor controller remains until the successor contract is complete;
unsupported successor features never dispatch to it.

The existing graph cloner now includes stable frames. Captured branch-local cells
are relocated, genuinely outer cells remain shared, and only changed references
cause slot-page copies. Native source checks pass for 1/8/64/128/256 real handler
installations with the final checked sum preserved, non-tail answer transformation,
typed external suspension and joins, two simultaneous one-shot owners, an escaping
owned suspension package, multi-shot choice, local/shared cells, cyclic reentry,
and 10,000 tail calls. A handwritten admitted loop additionally proves that
rebinding slots in one resumed branch does not change an older retained template.
These preserve independent existing expected values; no candidate-generated oracle
replaces those expectations.

The native driver retains prepared Program ownership after authoring storage is
released. Optional instruction/control quanta yield progress. Low-level errors
poison tentative execution; fresh invocation discards it and Resident rolls back
before returning an error. Malformed/stale replies reject against the current
pending binding. BPI3/PST3 admission has no predecessor fallback.
Borrowed/resource execution is now enabled through position-sensitive stable
borrow admission. Both private resource representations acquire, lend, reread and
release through their unchanged interfaces across external requests. Cancellation
while a loan is suspended releases its owning resource. The 24-case return-clause
matrix admits older references and rejects fresh ones, and an explicit same-slot
rebind cannot hide an earlier invalid store. Portable State provenance has separate
Program-relative admission and corruption tests; native execution alone does not establish that
restoration guarantee.

Shallow value/computation resumption now removes the old handler return clause;
successor resumption installs the replacement handler with its admitted state.
The shared resumption helper preserves explicit capability identities while
updating lexical-context links. All eight deep/shallow, linear/multi-shot and
value/injection combinations retain their independent expected answers.

The existing unwinder now also consumes stable frames. Slot-indexed custody links
record establishment order and lexical boundaries; normal exits splice surviving
inner owners ahead of the parent, and failure/cancellation visit scopes inside-out.
Retained frame versions share these links with copy-on-write isolation. Consuming
an owner removes its node, so repeated ownership cycles leave no historical chain.

Native cases cover ten existing cleanup-order scenarios, suspending and yielded
cleanup, cancellation before work/at yield/at request/after an answer, first-reason
retention, primary-failure precedence, accumulated cleanup failures, abandoned
captured cleanup, and generator cleanup with a private cell. The same unwinder
continues serving the predecessor while migration remains open. No source-visible
cleanup runs as a side effect of physical memory reclamation.

Run the separate compiler-dependent lane with:

```sh
zig build check-stable-source \
  -Dboundary-source=/absolute/path/to/boundary-compositional-execution \
  --global-cache-dir .cache/activation-global --summary all
```

The first implementation collects every 256 native transitions; this is a bounded
correctness cadence, not an accepted performance conclusion. The cyclic-reentry
witness additionally collects after every transition to challenge missing roots.
Slot movement is bounded in the installation test, but complete-path timing,
working-memory comparison and predecessor-gain acceptance remain unproved.

## Next required work

The stable controller now exports PST3 graph records
without advancing or collecting. Slot values and lexical owner order are attached
to their owning control node; private page handles and stale store entries do not
become checkpoint identities. Terminal exports retain the full result/exit.
The stable-source tests verify repeated export and graph re-encoding at drive
boundaries, including one-instruction quanta and cleanup. Reentrant-cycle tests
replace every private view handle and collect garbage without changing a byte of
the checkpoint. An export allocation-
failure sweep verifies unchanged resident bytes. `Session.restoreImage` now admits
the matching Program and complete State before adopting executable storage.
Each source drive also restores a separate native session, destroys the supplied
image/checkpoint bytes, and compares exact successor checkpoints after the same
quantum. Negative cases reject forged positions, missing slots, identity mismatch,
invalid cleanup status and aliased unique packages; restore allocation failures
release every partial owner.

The Store adopts the decoder's immutable owner and allocates replacement records
on mutation. Collection evacuates small surviving borrowed records when their
estimated bytes are at most one quarter of the imported arena backing, then frees
that backing. A fixed 128 KiB plus 5-byte payload witness compares the old physical
import's 131,077 copied payload bytes against zero on adoption, then 5 bytes to
evacuate the survivor. These counters exclude the decoder's initial owned-input
copy. End-to-end time/peak memory and the compaction threshold remain unmeasured;
this is a demonstrated copy/retention mechanism, not final performance acceptance.

`Session.initImage` now accepts Boundary's BPI3 bytes. The complete stable source
suite encodes the staged construction, loads it, overwrites and frees the image,
then drives the native session. This covers the existing generalized-control,
resource, cleanup, cancellation and reentrant witnesses through the image path.
The source tests include the 19 scalar/collection scenarios with the predecessor
suite's unchanged independent expectations. Core ABI 3 and cross-host checks are
described in [the current kernel contract](kernel-abi.md).

`Prepared.init` now owns an opaque admitted image, immutable analysis and cached
external schema descriptors. `Session.start` and `Session.restore` retain strong
references to it; releasing the outer Prepared handle does not invalidate active
Sessions. Explicit clones acquire additional ownership, and operations on a
released handle reject. Handles are native owning values with sequential access;
kernel instance/generation validation remains a separate required interface.

Code, schema facts and static liveness arrays are shared. Sessions allocate only
their own mutable map overlay over a single immutable base, alongside execution
storage. Restore still validates the entire incoming State but does not decode,
re-admit or re-hash the Program. Fresh invocation uses the same preparation path
and releases its outer handle after the Session retains it. The unused raw-record
Session constructor has been removed.

Tests cover sequential starts, prepared restore, shared code/liveness addresses,
distinct mutable pools, unchanged base-node counts, early outer-handle release,
and allocation failures while starting/restoring. Prepared storage accounting
includes owned arena capacities; this is structural reuse evidence, not an elapsed
time or end-to-end peak-memory acceptance claim.

`interpreter_v2/invocation.zig` now implements PKI3/PKO3 fresh invocation through
the same Session, with explicit reply, yield-resume and cancellation controls.
Session replies require ERS3 bound to the current canonical pending State;
raw typed values are no longer a public reply entry point. All source drives also
compare the fresh path's State/outcome to resident and restored execution at the
same quantum. Owned result buffers survive input/session destruction. Allocation
and output-capacity failures publish no successor and leave commands unchanged.

Dedicated cases cover equal visible requests with different retained values,
unchanged pending/yield polls, zero-quantum control application, and cancellation
rebinding the same pending cleanup operation. An already acquired result requires
explicit host re-encoding against the new challenge; no external work is repeated.
The default facade still awaits coordinated cutover.

## Resident transactions

`Resident.start`/`restore` create one owning native handle. An atomic gate rejects
concurrent or allocator-reentrant operations. `drive` commits after detached
outcome buffers exist; `driveInto` includes caller-buffer encoding and capacity
checks in that same transaction. Failure restores roots, pending control, exit
state, positions, slot values and lexical custody without allocating on rollback.

The Store retains the first version of each changed entry node/blob. Later writes
to that slot release intermediate versions; new nodes are reclaimed normally.
Frame backup copies one descriptor per live frame and retains COW view roots,
without copying their values. It does not clone semantic cells or serialize the
Session. Imported backing stays alive while the journal needs it. After commit,
optional compaction may retain that backing if its evacuation allocation fails.

Resident drive omits portable checkpoints by default. Its PKO3 incomplete outcomes
carry an absent checkpoint; `.checkpoint = true` requests the same publication
service as fresh invocation. Bound external requests still hash canonical State,
currently through a temporary materialization. `checkpoint` exports without
advancing; `takeCheckpoint` releases the resident owner only after successful export.
`close` requires terminal state. Unfinished work must finish cancellation/cleanup
or transfer custody through a checkpoint; physical release runs no finalizers.

Failure sweeps cover acquired replies, cancellation during cleanup, and reentrant
captures, both with and without checkpoint publication. They witness failures after
mutation, compare the exact original checkpoint, and retry the same control to the
same outcome. Other tests cover output capacity, failed checkpoint transfer,
released handles, reentrant callbacks, ID reuse, imported backing, and a 10,000-call
drive whose journal is bounded by entry state rather than transition history.
These are correctness and storage-mechanism results; full transaction latency and
peak-memory acceptance measurements remain required.

The generic ABI 3 kernel and browser-neutral byte embedding now run the same
evaluator through fresh and resident operations. Node/native/Wasmtime checks agree
on exact checkpoints/outcomes; Chromium and Firefox Workers transfer a real
resource suspension through native execution and finish cleanup in a new Worker.
Input, working and final-output budgets are independent; output allocation remains
inside resident commit. See the kernel contract for signatures, limits and commands.

The same kernel now executes Boundary-linked BMO1 components. Two complete Programs
reuse an effectful callable, private state and owned suspended cleanup, returning
83 and 166 with one release each. A separately compiled even/odd pair exercises
mutually recursive imports. Native/fresh/resident checks pass 115 matching
boundaries, and the Wasmtime transfer lane passes 29 including linked components.
The source-independent linker remains owned by Boundary; no compiler or linker
enters the production World kernel.

World is now version `6.0.0-dev.0` and normally pins Boundary `3.0.0-dev.0`.
Stable execution now increments handler-capture and multi-shot activation
counters at the same successful operations as the predecessor. A source witness
checks one linear capture and a multi-shot capture resumed twice. These are work
counters, so later rollback does not erase already performed allocation work.
Its root JavaScript export and standalone runtime package use ABI 3; Node file
loading remains separate from browser-neutral byte execution. Extracted-package
API/CLI checks pass, including capacity/retry and input/identity rejection.

The source-agreement suite additionally compares an immediately applied lexical
call with a retained callable. Boundary emits a direct call for copyable captures;
World uses its existing call path. Both return 42, preserve arithmetic overflow,
and resume a captured value through yield/PST3 restoration. Store additions during
the non-yielding execution fall from five to one for the immediate form; the
retained form stays at five. The baseline is Boundary `adf3c7e` and World
`321199b`, using native ReleaseSafe and Zig 0.16.0. These counts exclude Session
initialization and are neither heap allocation counts nor elapsed-time claims.
Run `check-stable-source` with the normal dependency pin, which now selects
Boundary `7094aa5f228aa1478489e20bd9245f02eda764a2`.

Total branching handler clauses now use Boundary's independently admitted
`tail` strategy. World enters the selected function with state/payload and an
ordinary continuation; it creates no resumption token and uses no separate
instruction evaluator. The selected delimiter stays active. Both branches,
body/return arithmetic, and every instruction checkpoint agree with the general
form. Cancellation from several positions inside a protected clause restores and
runs its external cleanup exactly once. Non-tail, shallow, escaping and reentrant
examples continue through their general paths.

The native ReleaseSafe branching witness allocates 14 Store nodes in the general
form and 11 in the tail form, with one versus zero one-shot captures. Node/native
and Wasmtime include the plain and protected branching fixtures; the existing
Chromium/Firefox Worker transfer remains enabled. These are bounded semantic and
work-count results, not the full performance acceptance matrix.

Agent migration and its actual compiled-tool/file transfer, component contract completion,
selective execution, value/performance acceptance, complete consumer package cutover, legacy
retirement and linked draft-PR/serial-review delivery remain mandatory.

The retained scoped-interaction witness supplies an effectful body to an
operation, stores a computation across a yield, and executes it under a new
interpretation. Definition-site and scope-supplied capabilities remain distinct
(10 and 20), and the complete return transformations produce `[1121, 99]`.
Cleanup requests payload 77 exactly once on normal completion and cancellation.
The native test checks the retained closure graph and portable cleanup state;
selected and general resumption forms agree at every instruction boundary across
fresh, resident and restored execution. Node/native qualification now covers 257
boundaries and 23 transfers; independent Wasmtime covers 174 boundaries.
Chromium and Firefox each transfer both forms through native execution and a
fresh Worker. These additions leave the production kernel bytes unchanged.

## Targeted value access

`Values` now reads a variant's tag directly and materializes only the requested
product field. A wrong-variant projection fails before materializing its payload.
Structured internal aggregates keep their existing ownership semantics. Encoded
projections copy the selected nonscalar value into Store-owned storage; they do
not return a borrow into a possibly reclaimed parent blob. Preceding product
fields are still parsed to locate a later field, so this is not a constant-time
index or a claim that all repeated decoding has been eliminated.

The controlled probe loads only the whole aggregate, then measures Store copying
for first-field, last-field, tag, and wrong-variant access. This avoids an existing
child blob masking the baseline cost through interning. With Zig 0.16.0 native
ReleaseSafe and the same admitted values, every operation copied 1/1,026/1,048,579
bytes for sibling payloads of 0/1,024/1,048,576 bytes in `c677647`'s implementation.
Each now copies zero sibling-payload bytes. The selected scalar values and
wrong-variant error are unchanged. These are deterministic work counts, not
elapsed-time or full-path performance acceptance.

Tests also collect the containing product while retaining a projected blob, and
reject truncated or invalid-UTF-8 payloads at Session initialization even when
the requested field/tag would not inspect that payload. Full input and State
admission remain required. Native semantics and current native/Node/Wasmtime/
browser checks pass with the new accessors; consuming sequence traversal and
matched-baseline performance acceptance remain open.

### Native full-invocation variant comparison

The optional `test/v2/build_value_bench.zig` accepts explicit frozen Boundary and
World source paths. It does not fetch historical dependencies or enter normal CI.
The same authored loop inspects a supplied variant 256 times and accumulates its
tag. A tag-1 control must return 256; tag-0 byte payloads must return zero.

The two-window comparison uses the specified Boundary 2.0.2 / World 5.0.2 commits
with both BPI2 and BPC1, the published successor before projection changes, and
that same successor with only `values.zig` changed. All use Zig 0.16.0 native
ReleaseSafe, a 32 MiB working arena, three warmups and nine samples per process,
and three rotating processes per window. Timing includes arena initialization,
input decoding, admission, execution, outcome encoding and owner release. Process
startup, program production and caller result verification are outside timing.
Allocation diagnostics use a separate replay. Background desktop/security activity
was observed; these are diagnostic native results, not an uncontended-host claim.

| Workload | BPC1 window medians | Candidate window medians |
| --- | --- | --- |
| Tag 1, no payload | 0.141 / 0.141 ms | 0.588 / 0.582 ms |
| Tag 0, 1 KiB payload | 0.199 / 0.196 ms | 0.581 / 0.577 ms |
| Tag 0, 1 MiB payload | 38.038 / 38.020 ms | 0.724 / 0.739 ms |

For 1 MiB, the pre-change successor takes 20.924 / 20.955 ms. Candidate allocation
traffic is 3,860,552 bytes versus BPC1's 269,740,101 bytes, but candidate peak live
working allocation is **higher**: 3,691,844 versus 2,103,211 bytes. The tiny control
also remains roughly four times slower than BPC1. These costs remain open; the
large-value win does not discharge control-heavy, actual-Agent or complete-matrix
acceptance. Full BPI2 results, all raw samples, binary/source hashes and configuration
are in [the measurement record](measurements/variant-tag-native.json).

Reproduce by building the probe separately for each frozen source pair:
`zig build --build-file test/v2/build_value_bench.zig -Dboundary-source=ABSOLUTE
-Dworld-source=ABSOLUTE --cache-dir=ISOLATED --global-cache-dir=ISOLATED --prefix=OUTPUT`.
Invoke `OUTPUT/bin/value-bench FORMAT PAYLOAD_BYTES TAG` with BPI2/BPC1 on the
predecessor or BPI3 on the successor. Formats are lowercase. The preserved matrix
is `(0,1)`, `(0,0)`, `(1024,0)`, `(1048576,0)`; each process emits its nine samples
and separate allocation diagnostics as JSON. Program production uses the same
builder function for every source pair.

### Runtime initialization bookkeeping

Sampling the tiny-loop benchmark attributed substantial execution time to
interning and rebuilding runtime initialization sets. Batched pruning now computes
the surviving initialized set once, clears discarded values/custody, and publishes
that set after the private transition. Frames with at most 64 slots use a private
word-sized initialization mask; larger frames retain compact shared trees.
Liveness still comes from independently derived Program facts, and custody still
owns disposal order. Neither is inferred from the mask. Wire State and slot-view
copy-on-write behavior are unchanged.

The tests cover 3/64/65/256-slot frames with holes in initialization, preservation
of older views, instruction checkpoints, and the existing resident allocation-
failure/rollback and generalized-effect cases. Native/Node/Wasmtime/browser
qualification passes. The word-sized path has a fixed 64-slot bound; it does not
create a per-boundary prefix table or replace large layouts with flat bitsets.

In two rotating diagnostic windows, tiny-loop process medians are 0.572–0.617 ms
with the projection-only successor, 0.509–0.537 ms with batched pruning, and
0.268–0.289 ms with the small-frame mask. The 1 MiB value workload improves from
0.728–0.752 ms to 0.417–0.451 ms. This still does not match the predecessor's
approximately 0.141 ms tiny-loop result. That remaining cost and full performance
acceptance remain open. Raw samples and allocation diagnostics are preserved in
[the frame measurement record](measurements/frame-initialization-native.json).

### Encoding into the final value owner

Exportable aggregate, collection and blob construction now allocates its encoding
with the Store allocator and transfers that completed buffer into the Store.
`literalOwned` consumes an independent buffer only on success; failures retain
caller ownership. Interning consumes/frees a duplicate buffer, and scalar results
consume the buffer after copying into inline storage. Publication follows all
fallible capacity and journal preparation. Borrowed literals retain their existing
copying interface, so projections and input admission acquire no new borrowed
lifetimes.

The product-construction probe previously copied 9/1,034/1,048,587 encoded bytes
from scratch to Store for payloads of 0/1,024/1,048,576 bytes. That second copy is
now zero in each case. Payload bytes are still written once into the final
encoding; this is not a zero-data-movement or elapsed-time claim. Allocation-failure
sweeps cover transfer, interning, inline values, journal rollback and freed-ID reuse.
Native semantics, resident rollback, current host transfers and extracted-package
checks pass. Efficient consuming sequence traversal and full matched performance
acceptance remain separate open requirements.

The measurement directory preserves `projection-only.patch` and
`frame-mask.patch` against `c677647`. Both reconstructed sources match the SHA-256
values recorded during measurement, so later value-construction changes do not
silently change those candidates. Apply the projection patch plus the frame patch
with `git apply --unidiff-zero` to reproduce the final mask candidate. Raw prune-only observations remain, but
its source and binary hashes were not recorded; that intermediate has a weaker
reproduction record.

## Structured sequence views

Structured sequence slicing now creates a logical aggregate over immutable shared
field storage. The first slice of an ordinary/imported aggregate copies its live
fields into an owned backing; later slices share that backing. When a survivor
falls to a quarter of the backing, it receives a smaller allocation. A consuming
chain therefore copies a geometric series rather than every successive tail.
The physical backing is not a graph root: tracing and PST3 serialization inspect
only each aggregate's live field slice, so consumed prefixes cannot keep semantic
owners executable. Graph records and the public wire grammar are unchanged.

Store owns the backing reference counts, including journal-held versions. Commit
releases saved ownership; rollback removes successor owners before restoring saved
ones, using retained map capacity and no allocation. This physical sharing does
not grant permission to copy a linear sequence. Existing type/use admission and
value consumption continue to enforce one logical owner.

The controlled resource-queue probe preserves FIFO order. Stored descriptor
copies for 16/64/256 elements fall from 184/2,272/33,664 to 82/337/1,360. Tests bound
the count by six copies per input element and retained backing after collection
by four times the live remainder. Allocation-failure sweeps cover sharing,
compaction, collection, freed-ID reuse, commit and rollback. The authored FIFO
scheduler retains its two unique suspension packages and returns the independently
expected result/log through instruction-by-instruction fresh/resident/checkpoint
agreement. Existing native, Wasmtime, browser and package checks pass.

Exportable encoded sequences now retain immutable cursors into their admitted
backing bytes. Consuming a tail parses the skipped prefix and reuses the suffix;
quarter-size compaction bounds retained backing. Product/sum wrappers can retain
these private values until observation instead of immediately encoding the tail.
The 16/64/256/1,024-element consuming probe constructs 180/584/2,140/8,307 bytes,
respectively, including compaction. These are construction counters, not timings.

Checkpoints use a read-only projection to ordinary canonical values; no private
cursor or new tag crosses the wire. Restoring a checkpoint needs no cursor
metadata. Repeated exports are byte-identical and do not change Store node/blob
counts. Allocation-failure sweeps cover cursor backing, collection, ID reuse,
rollback and resident execution/checkpointing. The source witness agrees across
fresh, resident and restored execution and returns the independently expected
remaining sequence.

Repeated append/update costs, full sequence performance measurements and broader
performance acceptance remain open. These changes do not establish completion
of the full specification.

## Component borrow-contract integration

The normal Boundary pin now carries checked BMO1 import assumptions and derived
export guarantees. World still consumes only closed BPI3, through its data-only
dependency. Native/storage, stable source, Node, Wasmtime, real browser transfer
and extracted-package checks pass on this pair: 34 build steps and 94 native/storage
tests. The default kernel is 459,817 bytes with SHA-256
`f2e1ddd54b65fe822e586f77fc63f97c114128c98d2c936e9e8919ae59ca8204`. These checks do not establish performance acceptance.

## Public compiler and data namespace

The normal dependency uses Boundary's public BPI3 compiler and the
`boundary_data` module. Current source fixtures call the ordinary public
compiler; the source override is now `-Dboundary-source`. Native/storage, source,
Node, Wasmtime, browser and package checks pass with the normal pin: 34 build
steps and 94 native/storage tests. The kernel is 459,884 bytes, SHA-256
`f436937401e3eb8c1dbd8d8dd6b3c54ac59bc6c60f1dc0a710adfbee1a3a8f67`. Remaining legacy runtime/data surfaces still need retirement.

## Host and build retirement checkpoint

The default build graph now exposes current native, storage, kernel, codec,
transfer, browser and package checks. The old ABI 2 build/release graph and public
`process_v2` export are removed. Shared runtime errors and statistics no longer
import the old evaluator. Its private implementation remains pending the rest of
the migration. Capture and return-path regressions now use current source/PST3.
The old ABI 2 JavaScript API and guest, v1 replay runtime, release/acquisition
drivers and frozen cleanup images are now physically removed. Current fixtures
come from Boundary's ordinary BPI3 emitter without historical pin exceptions.

Current host tests preserve independent byte ownership, value framing, ABI and
file-input expectations. They exposed two corrections: `encodeResult` snapshots
the reply before awaiting request hashing, and the CLI enforces the 64 MiB kernel
limit before reading or allocating file contents. `zig build check-storage
check-codecs --global-cache-dir .zig-global-cache --summary all` passes 80 native
tests and 24 JavaScript tests; formatting and diff checks pass.

`zig build build-runtime check-package --global-cache-dir .zig-global-cache
--summary all` also passes all 20 steps, including execution from the extracted
package and its CLI. This checkpoint's rebuilt kernel SHA-256 is
`19d8fda6a667e1e2a278713f683e20eedb476c24e03ee589faf3cfa830953daf`.
The earlier complete portable-host results above belong to `f36994b`; they were
not repeated for this checkpoint.

The captured-handler test failed with `TypeMismatch` at checkpoint `014e207`:
the multishot fixture inserted a handler accepting the final list rather than
the captured body's boolean pair. The corrected identity handler uses the source
handler's input type. One-shot and multi-shot cases now admit and execute when
their capture bound includes the added state, reject specifically with
`InvalidOwnership` otherwise, and reject every incorrect handler node kind.

The current return-path test constructs states through the public compiler and
actual execution. It inserts disposal markers into all six independently required
paths: active, yielded, saved continuation, protection, normal exit and capture.
Each canonical mutant rejects with `InvalidState` through public restore. A
separate marker signature preserves effect admissibility so that an unrelated
effect rejection cannot mask this check. Valid execution restores from PST3 at
every boundary, including a captured continuation during cleanup, and preserves
the independent results 67, 60 and failure 9. All six paths must be visited.

The two superseded old-record test modules and their old rejection-emitter cases
are removed after this migration. `zig build check-native check-storage
-Dboundary-source=BOUNDARY_CHECKOUT --global-cache-dir .zig-global-cache
--summary all` passes with Boundary `ff8a1b277392984681e9710224313adbbb396f4c`:
the current source suite contains 53 tests and the remaining native/storage suite
passes 76 tests. Focused Debug capture/return tests, formatting and diff checks
pass. This does not establish full `check` or performance acceptance.

`check-source` now retains the old host conformance assertions on the current
protocol: all 41 source examples, 42 borrow-operand inputs, the four independently
specified cleanup-disposal cases, cancellation and fresh native/WASM transfers.
The migration run passed 6,755 byte-identical observations. Cancellation during
an existing failure preserves an already-observed yield until explicit PKI3
resumption. The operand test horizon now counts up to 1,024 current instructions
rather than 128 predecessor block transitions; terminal and trace assertions are
unchanged. The harness checks the exact expected fixture name set.

`check-capacity` covers each arena limit and a kernel whose maximum physical
memory equals its initial memory. A request larger than the initial 1 MiB backing
forces actual growth failure. Rejections publish no State; identical input retries
match the successful native/WASM observation. Final output demand remains exact;
allocator demands use ABI 3's conservative lower-bound provenance. Historical
measurements remain intact. Current coverage and the remaining native migration
boundaries are summarized in [verification.md](verification.md).

After removal, the expanded `zig build check -Dboundary-source=BOUNDARY_CHECKOUT
-j4 --global-cache-dir .zig-global-cache --summary all` passes 32/32 build steps
with Boundary `ff8a1b277392984681e9710224313adbbb396f4c`: 76 native/storage tests,
the 53-test source suite, 24 JavaScript host tests, the 6,755 source-oracle
observations, all capacity checks, 257 native/Node boundaries with 23 transfers,
174 Wasmtime boundaries, Chromium 153.0.8010.12 and Firefox 155.0 Worker transfers,
and the extracted 14-file package/CLI. Kernel SHA-256 remains
`19d8fda6a667e1e2a278713f683e20eedb476c24e03ee589faf3cfa830953daf`.

The normal Boundary pin is still `7094aa5f228aa1478489e20bd9245f02eda764a2`.
Agent still selects World `f36994b26b6506bfc2b80ee1db8a9dfdbdef5b77`; its previous
integration results do not validate this checkpoint. Repinning and full triad
qualification, remaining retirement, performance acceptance and serial reviews
remain required. Linked drafts stay incomplete, with eventual landing order
Boundary, World, Agent only after complete acceptance and separate authorization.
