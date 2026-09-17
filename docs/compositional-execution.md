# Compositional execution: World status

This is an incomplete part of the accepted Boundary 3 / World 6 / Agent successor.
The complete specification, including draft publication and serial review closeout,
remains the goal. No merge, release or application data operation has occurred.

World develops on `feat/compositional-execution` from the 5.0.2 reference
`d075169a4805d999ceba4c37b3e1c925b78c3bf9`. The normal manifest selects Boundary
`711325d3453f9fbb4d43f3ca9438c038fb7c14d7`; normal-pin aggregate validation uses
Zig 0.16.0 and Node 26.8.2. Measurements below retain their individual source
bindings and do not automatically qualify later code.

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
The predecessor controller and control/continuation argument vectors are retired.
Control values exist only in the activation owner. The graph cloner requires that
owner, so there is no clone entry point that silently omits frame values.
The obsolete raw graph State and Store import/export helpers are also removed;
portable projection and restoration use `process_state.State` with activations.

The graph cloner includes stable frames. Captured branch-local cells
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
import the old evaluator. Its private implementation has now been removed after
migrating the remaining source, capture, return-path and admission regressions.
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

The subsequent native retirement removes `process.zig`, `machine.zig`, their
old record fixtures and execution wrappers, and the block-argument/PKO2 fallbacks
in cleanup and shallow reattachment. One current evaluator remains. Fifteen
current regression groups preserve the additional lexical-shadowing combinations,
full-width zero-size cardinalities, same-family capability substitutions,
successor return borrowing, region/token effect substitutions, duplicate custody,
malformed pending/blob records, capture aliases, cleanup obligations, and binary
as well as text cancellation. Each rejection has an admissible counterpart;
canonical malformed bytes reach public restore unless structural encoding itself
rejects a dangling reference. Finite source cases retain independent results.

The source-oracle suite covers the replaced ordinary handler, resource, search,
scheduler and cleanup executions. Boundary's active stable admission tests retain
linear-use/ordinary-discard rejection; current World tests additionally reject
forged empty obligation bounds. Private storage, clone and collection tests remain.
The old snapshot-counter wrapper is removed with its evaluator; the graph
collection/canonicalization visit assertions and Boundary's PST3 cycle/renumbering
tests remain. Historical measurement files are unchanged. Legacy data definitions
and codecs still require retirement in Boundary and remaining shared data helpers.

The migrated tests share the root test module: a dependency-module import does
not collect their test declarations. The final native selection explicitly
reports 69/69 passing tests, including all 15 migrated groups. The independent
storage selection now contains 35 tests; the ordinary execution and admission
obligations moved to the current source/PST3 suite rather than disappearing with
the old record-based interpreter.

The final expanded `check` run passes all 32 steps on this native retirement:
69 current source tests, 35 private-storage tests, 24 host tests, 6,755 independent
source-oracle/native/WASM observations, arena and physical-memory failures,
native/Node/Wasmtime transfer, both browser families and the extracted package.
The generic kernel is 459,863 bytes with SHA-256
`a824bc4404a6dfd9e579a96bd88f72694483c85bd557ec322ba7f69070606104`.
The exact Boundary source input remains `ff8a1b277392984681e9710224313adbbb396f4c`.

## Single current executable data contract

The current-record transition selected Boundary
`a918da81be930754ecb6d6b62c09df6b80b69cf1`, which removes the predecessor codecs
and executable record definitions. World graph utilities use `data.graph_order`
and cancellation reasons use `data.invocation`. Instruction dispatch receives
the current instruction directly with its result schema resolved from the
function layout; it no longer constructs the old block-argument instruction.
Private value/blob operations retain their independent tests with explicit
result schemas. Shared graph record/helper cleanup and consumer/performance
qualification remain separate open work.

The full current aggregate also passes through the normal Boundary pin, without
a source override: 32 build steps, 69 source tests, 35 storage tests, 24 host tests,
6,755 source-oracle observations, capacity and all current host/package lanes.
Kernel SHA-256 is
`89f8eb82abe322cda762fd6207b1a9374f0f1d45a48804f5b807f8018eff94c6`.

## Low-word liveness projection experiment

A refreshed 256-iteration variant-tag comparison reproduces the unresolved tiny
control cost: roughly 0.28 ms for the current successor versus 0.14–0.15 ms for
optimized BPC1. A separate five-second CPU sample attributes 803 of 4,139 samples
inclusively to frame pruning. Small frames rebuilt their liveness mask by
enumerating every member of an already compact immutable set.

`analysis_sets.Pool.lowWord` projects IDs 0–63 directly from canonical runs/tree
nodes. It allocates nothing and changes no set. World uses it only for its
existing small-frame mask; large-layout handling, custody and slot storage remain
unchanged. Tests compare ranges and sparse sets with independent membership,
including high IDs and immutable-base overlays under an exhausted allocator.

Two rotating native windows reduce median tiny-control invocation time from
276,125 to 245,916 ns and from 287,166 to 251,500 ns (10.9% and 12.4%). Process
median ranges do not overlap in either window. Allocation traffic and peak
working bytes are unchanged. The 1 MiB value case also improves, while its peak
working allocation remains above the predecessor. These are diagnostic results
with observed background load, not full performance acceptance.

The follow-up CPU sample reduces inclusive pruning attribution from 19.4% to
14.5%. Scalar decoding, slot mutation and runtime bookkeeping remain visible
costs. The command decoder already borrows its fields from an owned buffer;
large-input memory work should instead examine the additional argument snapshot
in `Session.start` and the Store's value copy, preserving caller-buffer isolation.

[Raw samples and configuration](measurements/low-word-native.json) retain the
optimized predecessor and the before/candidate results. Reconstruct the candidate
from the recorded source revisions using the adjacent Boundary/World patches,
then use the existing `test/v2/build_value_bench.zig` and `value-bench` commands
described above. The low-word checkpoint selected Boundary
`fb5e287037da86d27110e731a7e08b0cb4009a3d`, including this projection and the
current source-package cleanup. The remaining tiny-control gap, peak memory,
actual Agent improvements and complete workload matrix still require work.

The normal-pin aggregate passes 32/32 steps: 69 source tests, 35 storage tests,
24 host tests, 6,755 source-oracle observations and all current native, Node,
Wasmtime, browser, capacity and extracted-package checks. The generic kernel is
458,465 bytes, SHA-256
`1767d27d6b5a15913f7fa72ea321278c6334756de76337054445d1badb54abd7`.

## Argument ownership and terminal retention

The memory-ownership candidate removes two sources of large-input memory overhead.
Boundary's invocation decoder owns an exact-sized byte buffer instead of a
geometrically grown arena. Every decoded slice remains backed by that owner.
World copies the complete argument buffer once into its Store, validates every
argument before publishing values, and derives typed blob views internally.
Scalars remain inline. Callers cannot introduce arbitrary borrowed slices, and
caller overwrite/free does not alter execution.

The first Store-backed candidate exposed a terminal-retention defect: a short
computation could finish before the periodic collector ran and keep a large dead
argument indefinitely. Session now stores a handle to a Store-owned terminal exit
rather than caching borrowed outcome and cleanup fields. Observation and snapshot
projection read that owner, and terminal collection traces its complete result.
Resident compaction prepares survivor copies inside the journal, retains old
backing for rollback, and releases it after commit without further allocation.
Use `Session.observe()` and `terminalExit()` for terminal data; the former
`Session.exit` field and observation-valued `terminal` field are removed.

For the unchanged 256-iteration variant-tag invocation with a 1 MiB payload,
peak working allocation falls from 3,691,908 to 2,128,044 bytes (42.4%); allocation
traffic falls from 3,858,832 to 2,285,570 bytes (40.8%). Optimized predecessor
BPC1 still peaks at 2,103,211 bytes, 24,833 bytes lower. The exact-buffer lever
alone removes 524,435 peak bytes; Store argument ownership alone removes
1,039,429 bytes and misses its original 1 MiB target by 9,147 bytes. Their
combination exceeds that target; neither isolated result is relabeled.

In two final rotating windows after task-owned builds exited, large-invocation
process medians were 0.400–0.443 ms and 0.398–0.405 ms for the candidate, versus
0.400–0.428 ms and 0.395–0.402 ms for the prior successor. These ranges overlap;
no latency improvement is claimed. Optimized BPC1 remained approximately
38 ms for this value-heavy case. Tiny-control medians remain around 0.25 ms,
versus approximately 0.14 ms for BPC1; that gap is unresolved. Earlier contended
observations are retained separately, not discarded.

Boundary passes 216 steps and 210 Zig tests. World passes its full 32-step
aggregate with the explicit local Boundary source: 73 source tests, 35 storage
tests, 24 host tests, 6,755 independent source-oracle observations, native/Node/
Wasmtime agreement, real Chromium/Firefox transfer, capacity and extracted-package
checks. New tests cover every envelope family's caller release, exact-sized large
command ownership, duplicate arguments, tiny survivors, allocation-failure sweeps
for argument construction and compaction, journal collection/ID reuse, and resident
terminal commit/rollback. The kernel is 457,997 bytes with SHA-256
`bbd75266aa43fdb25985093bb154d7935cd0ded91a83c7ef24cbd8a21b6b9acf`.

[Raw observations and source reconstruction](measurements/argument-backing-native.json)
include separate lever measurements and both contended and final windows. Apply
the adjacent argument-backing Boundary/World patches to the named published
heads to reconstruct the candidate. This checkpoint is superseded by the control-set candidate below. The full required matrix,
control-heavy and actual Agent gains, remaining cleanup and serial reviews are
still open; this diagnostic does not establish milestone acceptance.

## Matched control measurements and canonical word sets

The normal dependency selects Boundary
`58bf6fb133e7d5bba1210c6ad64cd59f51755620`. The generic kernel is
459,416 bytes, SHA-256
`9e9b789ddb72c67d728de2eabedb74a22f3042a9399545110e517fd0a29de63a`. The normal-pin World aggregate passes without source overrides.

The public installations and deep-handler builders are byte-identical across
the optimized predecessor and successor. The native control probe checks the
complete u64 result (42, 67, or n(n+1)/2), includes decoding, fresh preparation,
execution and output encoding, and records BPI2 and BPC1 separately. Three
warmups precede nine samples in each process; three rotating processes per
format/case are repeated in two windows. The workspace is 128 MiB for every
control case. Reported peaks count tracked working allocation, not process RSS
or that fixed reservation. Compilation/emission occurs before timing and is
recorded separately. No image-size result substitutes for runtime measurements.

The first complete control comparison exposed a regression: 64 installations
needed about 0.92 ms and 1,589,165 peak bytes versus optimized BPC1's 0.24 ms and
121,956 bytes. A five-second CPU sample attributed 2,128 of 3,714 thread samples
inclusively to preparation. A separate allocation replay retained 1,478,042
bytes in the prepared owner. This is recorded as CEX-4711e1b9b63d4c219e0f1eb5;
the performance requirement remains open.

Analysis sets now use canonical bitmap leaves for sparse subsets of an aligned
64-ID word, retain single-node intervals, and share larger binary subtrees.
Their interner stores immutable node IDs and derives comparison from the owning
array, avoiding a second full node copy. Canonical bounds and cardinality select
the payload representation; constructors normalize intervals before publication.
The explicit private layout keeps nodes at 40 bytes on native 64-bit targets.
Tests exhaust all pairs of eight-member subsets across word boundaries and high
IDs, check insertion-order identity and immutable overlays, and preserve prior
allocation-failure, large-ID and monotonic-prefix bounds.

The selected combination improves the prior successor but still loses to BPC1.
Each timing cell below reports the two window medians, in milliseconds:

| Installations | BPC1 ms | Before ms | Selected ms | Selected peak bytes |
|---|---:|---:|---:|---:|
| 1 | 0.008 / 0.008 | 0.015 / 0.015 | 0.014 / 0.014 | 19709 |
| 8 | 0.023 / 0.023 | 0.073 / 0.072 | 0.058 / 0.057 | 89951 |
| 64 | 0.238 / 0.248 | 0.911 / 0.920 | 0.652 / 0.651 | 530351 |
| 128 | 0.697 / 0.705 | 1.989 / 1.960 | 1.462 / 1.477 | 1435037 |
| 256 | 2.302 / 2.303 | 4.288 / 4.348 | 3.287 / 3.344 | 2268977 |

The 64-case peak drops to 530,351 bytes (66.6% lower); its latency drops about
29%. The 256-case remains around 3.3 ms versus BPC1's 2.3 ms. Small-case memory
and the prior value witness do not regress in the selected combination. The
1 MiB value witness peaks at 2,127,750 bytes, still above BPC1's 2,103,211 bytes.
Ordinary bitmap and union-layout attempts, plus the index-only variant's slower
timings, remain in the raw observations rather than being discarded.

Boundary passes 216 steps and 212 Zig tests. World passes all 32 current steps,
including 73 source tests, 35 storage tests, 24 host tests, independent source
agreement, capacity, native/Node/Wasmtime, browser transfer and extracted-package
checks. The package test now requests a one-byte working budget explicitly:
its old assumption that install64 must exceed the default budget was invalidated
by the memory improvement. Failure and unchanged-input retry remain asserted.

[Raw paired measurements and reconstruction](measurements/control-native.json)
and [the preparation sample](measurements/control-preparation-profile.txt) retain
the method, source/body parity, input identities, all observed windows and
allocation counts. Build `test/v2/build_execution_bench.zig` with explicit
`-Dboundary-source` and `-Dworld-source` paths; the frozen predecessor also uses
`-Dlegacy-names=true`. Run `execution-bench FORMAT scalar 0`, `deep 0`, or
`install COUNT`. The remaining workload matrix, consumer measurements, build/
edit/link costs and serial review closeout are still required.

## Earlier portable-host checkpoint
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

## Admission-buffer ownership

Initialization, availability, obligations and liveness remain separate facts.
When input roots coincide, the analyzer reuses the same pure set-operation
result. This preserves every fact while avoiding duplicate work, improving
control64 by 5–8% in the two measured windows without changing allocations.

Set node/index buffers now belong directly to their Pool through the parent
allocator, so growth releases replaced buffers instead of retaining them in
the analysis arena. Facts still owns both the arena and the Pool and releases
both through one deinit/error-cleanup path. Held-buffer accounting includes
resize, remap and free; prepared-storage reporting includes these buffers.
No set or Program identity changes.

Control64 peak tracked allocation falls from 530,351 to 291,133 bytes; control256
falls from 2,268,977 to 1,126,229 bytes. Latency remains around 0.60 ms and 3.0 ms,
respectively, so the BPC1 latency gap is unresolved. The value probe's tiny peak
falls to 23,402 bytes and its 1 MiB peak to 2,120,562 bytes. Captured Agent
clarify-first start/terminal peaks fall from 1,500,229/1,721,174 to
940,863/1,161,816 bytes. These are native diagnostics, not an updated Agent
public-host performance result.

Boundary passes 216 steps / 213 tests and World passes its full current
32-step aggregate with this local source, including 73 source tests, 35 storage
tests, 24 host tests and all portable/package lanes.
[Raw comparisons and source patch](measurements/admission-buffer-ownership.json)
retain both the small fact-reuse lever and the buffer-ownership change. The normal dependency now selects Boundary
`d8edcf14d23fcd3664d8a868595150518cd40e51`; the normal-pin aggregate passes.
Agent requalification and the remaining performance/review requirements follow.

The buffer-ownership kernel is 459,817 bytes, SHA-256
`d76bfe2c7949903f53e3d5b2b6b6d229887422483d383524d655f087b8609931`.

## Kernel module admission and reuse

The host factory binds its byte copy, expected digest, engine compilation and
static ABI inspection in one helper. Compilation supplies full WASM validation;
the standalone inspector retains its own validation path. ABI checks still
complete before instantiation, so rejected imports, start functions or exports
never execute. Caller mutation cannot alter the private snapshot between awaits.

The last admitted module is held through one weak cache entry. Every lookup
follows a fresh digest check of owned caller bytes. Each Kernel creates a fresh
instance, identity and token table, and retains the module only for its own
lifetime. Cache collection, replacement or unavailable WeakRef falls back to
ordinary admission. Program and Session state are not cached here.

Targeted repeated Agent-command calls improve by roughly 7–9% from removing
duplicate validation, then another 10–13% with weak module reuse. Separate
first-call observations remain around 20 ms and do not establish a cold-start
speedup. [All stages and paired samples](measurements/kernel-admission.json)
retain the no-effect compile/instantiate split experiment and the resource/
identity preservation conditions. Full consumer remeasurement remains required.

## Solver-position and interner update

The analyzer records positions during its existing fixed-point worklist.
Final read/overwrite and successor checks remain in their original order.
Liveness refreshes internal positions on every visit, even when a successor
change leaves the entry root unchanged. All facts remain analysis-owned and
come from the same immutable Program; no supplied summary becomes authority.

The interner uses one computed hash and, when capacity permits, one lookup/
insertion probe. Every fallible reservation precedes publication. Hash keys
omit redundant derived metadata but equality still checks complete nodes.
The accessor is inlined, and direct insertion preserves the same canonical
run/word/tree structure without creating unnecessary singleton nodes.

The final paired control64 medians are 447/444 microseconds versus the preceding
implementation's 619/622 microseconds. Control256 takes 2.146/2.148 ms versus
BPC1's 2.295/2.272 ms. Control64 still trails BPC1's 239/237 microseconds.
The value guard shows no repeatable slowdown and no increase in allocations.
The kernel grows from 459,817 to 463,084 bytes; this size tradeoff is separate
from invocation time and working allocation.

Boundary passes 216 steps / 217 tests. World passes its full 32-step aggregate
with normal Boundary pin `50df22c1ef83c2d84550e19ccabf807dfe2dedf5`: 73 source tests, 35 storage tests, 30 host tests,
6,755 source-oracle observations and all portable/package lanes. A 1024-case
CFG differential comparison preserves every observed error and fact set.
[All candidates, targets and paired windows](measurements/solver-facts.json)
include the under-target attempts rather than discarding them. The normal dependency pin now selects the published Boundary source. Agent
qualification follows this World source; the full goal is incomplete.
