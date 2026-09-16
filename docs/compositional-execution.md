# Compositional execution: World status

This is an incomplete part of the accepted Boundary 3 / World 6 / Agent successor.
The complete specification, including draft publication and serial review closeout,
remains the goal. No merge, release or application data operation has occurred.

World starts at `d075169a4805d999ceba4c37b3e1c925b78c3bf9` on the dedicated
`feat/compositional-execution` branch. Validation uses the separate Boundary
successor worktree at `b4a1785e0276a0e074245150187085d217c0e6de`, Zig 0.16.0,
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

The native driver owns its Program and analysis after authoring storage is released.
Optional instruction/control quanta yield progress. Allocation-failure sweeps cover
partial-owner cleanup. Full resident rollback is NOT implemented: an operational
failure after mutation poisons this internal driver, while malformed typed replies
reject before mutation. No portable checkpoint or old-format fallback is exposed.
Cleanup/protection, shallow handling, injected resumption and borrowed/resource
execution reject before starting. These are incomplete requirements, not supported
behavior removed from the final successor.

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

Complete shallow/injected control, authored cancellation and cleanup with lexical
custody ordering, and borrow/context admission. Prepared lifetime, whole-Session
transactions, BPI3/PST3/current protocols, ABI 3, browser/server transfer, Agent
migration, component linking, performance acceptance, legacy retirement and linked
draft PRs remain open. Native source agreement does not prove portable execution.
