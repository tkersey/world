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
  -Dboundary-v2-source=/absolute/path/to/boundary-compositional-execution \
  --global-cache-dir .cache/activation-global --summary all
zig build check-v2-native -Doptimize=ReleaseSafe \
  -Dboundary-v2-source=/absolute/path/to/boundary-compositional-execution \
  --global-cache-dir .cache/activation-global --summary all
zig build check-v2-source check-v2-wasm \
  -Dboundary-v2-source=/absolute/path/to/boundary-compositional-execution \
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

`stable_session.zig` now executes the direct Boundary `source.construct` records.
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
  -Dboundary-v2-source=/absolute/path/to/boundary-compositional-execution \
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

Agent migration and its actual compiled-tool/file transfer, component contract completion,
selective execution, value/performance acceptance, normal package cutover, legacy
retirement and linked draft-PR/serial-review delivery remain mandatory.
