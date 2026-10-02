# Change-proportional resident execution

The current successor repairs native Frame/Slot/Store binding invalidation, direct
Slot rollback, and the lifetime of scoped callback borrows. Frames tracks active
callbacks with automatic stack nodes alongside escaping native borrows. Transaction
entry protects those live IDs; membership changes end their borrows. Session denies
binding reuse during a callback, and callback exit invalidates observation metadata
because a callback may publish and then directly change its frame.

Three scoped-lifetime comparisons fail on 99bb1a6 and pass on W0's equivalent
getMutable adapter: transaction entry inside a callback, entry after committing an
earlier transaction, and direct metadata mutation after publication. All pass on
the repair. Committed regressions cover nested callbacks, identifier reuse, denied
allocation during rollback, and stale replies both during and after a callback.
The obsolete scalar 64-byte supplementary wrapper is removed; original exact
scalar equality samplers remain canonical and pass.

Current qualification passes 94 native tests, 82 storage tests and all 39 normal
aggregate steps, including Node/native/WASM, 159 Wasmtime boundaries, actual Chromium
and Firefox Workers, 277 capacity cases and package/source checks. All seven
independent preservation lanes pass, including original scalar equality, 19 history
cases, 12 fresh-process transfers and all eight fixed Agent fixture families.
Current kernel: `4159328d1c881147292c0ad998a30280bfafb9167077dc8c30e260f47561f0dc`,
486492 bytes, normal ReleaseSmall profile and unchanged arena/stack/memory limits.

Current H1024 complete WASM lifecycle saves 5.483292 ms (9.05%); Q1024 saves 1.799582 ms
(5.42%). Both satisfy the five-window win rule. All 272 economic timing cells are complete. Twenty-three cells exceed the
original 5% detection rule: their added costs range from 0.024735 µs to 78.703125 µs,
and every affected measured workload is below 100 ms. The full raw cost table is
retained; no percentages or samples are hidden. All peak-memory gates pass,
including 1061 paired-window and independent preservation-peak comparisons. The user's direction is one
optimization attempt for operations below 100 ms, then code review; that attempt is
complete and no further threshold tuning is planned. New correctness fixes are
requalified rather than credited with the predecessor's timings.

The six-lens99bb1a6 initial wave is terminal and folded. Four lenses independently
confirmed the obsolete scalar expectation; invariant review found the scoped entry
gap, and root comparisons confirmed the related publication gap. Soundness found
no additional defect. Reviewer blocked fresh-cache commands remain blocked in their
receipts; root qualification is reported separately. All invalidated-head review
credit is zero. Fresh clean-source delivery and complete serial review convergence
on the eventual committed successor remain required; completion is not claimed.
The only public subject remains [draft World #60](https://github.com/tkersey/world/pull/60).

The detailed results below are historical1850937 evidence, including its kernel
`a184db4e…`, old frame-association construction and measurements. They do not
qualify this current scoped-lifetime repair.

## Fixed inputs and product

- W0: `c61edfc8208c375d5188e476131ca8cff5aeeb8a`, tree `87edc03ebb7b8b56facfe7f2e60845c5931f1834`.
- D0: `511fe388587b36ae37307d277e04c22b0bb6f6d9`, package `boundary-3.0.0-dev.0-flclaGcPXAB8lBsvhVLPJFZmROkee3fHGfsloqpgeZSE`.
- A0: `b1f9d2866b5717d16339e7022a3b4d08951f0770`.
- C0: `65f46131f366bdd21aa98701f4110ecb801d2c8d`, package `boundary-3.0.0-dev.0-flclaEdzRQBpnNrUM2gj62qP_jA65zcVHZgFfmxIPqxe`.
- B0 harness: `93340dade30b7d27a1e139f107359f91fb66fad3`.
- Specification: SHA-256 `d914b959e32d10b841e549cb27665689c419856e5b77ae632363fb71b22e92f3`.
- Installed skill source: dotfiles `f7228a8d188f72be666f5e3db5bcce3e677580df`.
- Zig 0.16.0, Node 26.10.0; native ReleaseSafe, normal ReleaseSmall WASM.
- Apple M2 Pro, 12 CPUs, 32 GiB RAM; Darwin 27.2 arm64.
- W0 kernel: `9627eb1e66239119bccb4ddcd43b4f6c757180dab930a9feb276671262f735d1`, 470027 bytes.
- Repaired successor kernel: `a184db4ee2ecf1eb2dc7c4bec4abb93a35cbfa106be4999c9551e18c10437ec6`, 479028 bytes.
- ABI 3, import-free wasm32; existing 65536-byte stack, 256 MiB maximum,
  default input/working/output budgets 65536/1048576/65536 remain unchanged.

The compiler and runtime-data selections are separate immutable inputs. Agent's
source, policies, approvals and historical runtime lock were not repinned.
World alone contains production changes. Native CLI dependencies explicitly use
ReleaseSafe; the normal World owner builds the WASM product.

## Construction and coverage

Frames owns a first-touch journal. Begin protects only live mutable pointers acquired
before entry; an inline first ID and cold additional-ID set avoid scanning the
registered population. Protected mutable acquisition and membership changes save the
entry version once; commit releases only those saved entries. Rollback first removes
all touched successors, then restores originals using retained map capacity, without
allocation. Null entries preserve entry absence across creation/removal/ID reuse.
The original frame-map pointer is read before protection and exposed only afterward;
protection grows its own journal and slot/custody tables, never the frame map.
Interpreter instruction borrows end inside a synchronous callback and do not enter
the escaped-pointer set. The public getMutable API retains its original lifetime.
Mutable borrows remain protected across commit until membership changes; rollback
invalidates them. Copies survive map growth: the installed owner ID is only a lookup
hint, and the full backing-view handle must match before saving the registered entry.
Independent semantic forks retain distinct handles. Rollback snapshots exclude that
derived hint, reconstruct it from the journal key, and release slot/custody ownership
directly at commit. A present last-held ID certifies successful protection and resets with each attempt.
The rare protection path is separated from the common no-transaction/repeated-write
branch. No old/new selector or all-frame backup implementation remains.

The sanctioned controlled cut covers getMutable/getForMutation, put/update/remove,
copy/rebase, and their Session capture, clone/resume, tail restart, unwind and
collection callers. New unregistered frames are initialized before protected put;
restoration admits State before materializing views. Existing Slots COW, packed
insertion/removal, semantic forks, intentional shared graph mutation, custody and
Prepared-owned exact layout classes remain authoritative. The journal does not
replace them. Store's existing failure rollback rebuilds indices in linear time;
no claim makes that failure path change-proportional.

Session owns the last published canonical 32-byte request identity. Its supported
mutation entrypoints invalidate that identity, including native cancellation,
resumption, capture and execution. Read-only inspection preserves it. A public
transaction moves the entry identity into rollback custody before exposing
mutation; rollback restores it and commit awaits a new canonical publication.
During Resident's gated operation, that transaction lends its entry identity to
the shared response checker; standalone Session.answer recomputes canonically. Required
response parsing and schema/value admission remain shared. Canonical finish writes
Resident's operation-local publication slot; its low-level three-argument entry
has no slot. That lifecycle fact is selected at compile time, so fresh publication
carries no runtime metadata branch or larger Outcome. The prior value carrier and
ambient Session next-identity pointer were removed. These handoff changes retain
the canonical producer, publication law and failure falsifiers. Moving retained
identity ownership into Session closes the native mutation and replacement escape
without restricting the existing embedded Session API or adding a revision key.

Every successful publication replaces or clears the private identity only after
all fallible output construction/encoding. Failure restores entry State and leaves
the original identity usable. Checkpoint is read-only; transfer/close clear custody
and cache; restore starts without a private identity. The incoming borrow clears
before replacing its owner and on every failure exit. No full State graph, result,
approval or response is cached. Required low-level Session capabilities remain.
The existing owning/noncopyable Resident contract and stable-address gate govern
controlled operations; low-level Session.answer does not trust the retained identity.

The first P0 review found an unwind ownership failure: after positionOwned handed
its values buffer to Store, fallible frame removal could activate the old local
errdefer and then Store rollback, freeing the buffer twice. Local cleanup now ends
at the successful ownership transfer. A live Resident allocation-failure sweep
fails on P0, passes W0 and the repair, and verifies exact State and retry behavior.
The same WASM pressure case retains its entry allocation count and releases to
zero after retry; 277 owned-unwind capacity failures pass. Restoring a checkpoint
before injecting failures alone had missed the original private-capacity state.

WASM returns gather the value before returnTo can grow the frame map, avoiding a
frame copy and unused general-control scratch. Native retains ordinary control
handling. This uses the existing slot reader and return transition; no engine flag,
new evaluator, disabled check or resource expansion is shipped.

Falsifiers include a missed mutation path, an unprotected escaped mutable borrow,
failed protection altering entry ownership, allocation during rollback, a stale
pending identity, or publication failure changing retry State. New owner/alias
contracts, frame-map resizing within protection, changed layout/custody semantics,
codec changes or compiler/control changes invalidate the relevant proof.

## Structural and correctness observations

The C0 H/Q fixture retains usable non-tail continuation history; completion observes
every distinguishing depth separately. At depth 1024 it has 1025 registered frames.
W0 protects all 1025 at begin and spends 232376 allocated bytes on the first small
H drive. The current successor protects zero at begin and one per small drive;
the first costs 1920 bytes. Escaping mutable pointers are additionally protected
at begin, bounded by actual acquired borrows rather than retained frame count.
Interpreter pointers end inside their callback and do not add entry-time protection. All 64 drives avoid collection. Large retained-population unit
cases independently cover mutation sets 1, 7 and 31, repeated writes and untouched
reads. Saved entries, forks and commit work equal the changed set.

At Q=1024 three invalid responses perform zero checkpoint constructions and one
binding reuse each. Their temporary allocations are 215/64/484 bytes, versus W0's
883969/883818/884238. Diagnostics and the original valid retry agree. The largest
Q agreement also repeats rejection 128 times per arm, preserves exact State and
constant live allocation, and records reserved memory separately.

Executed on the current repaired product: 91 native and 76 storage tests, all 39 aggregate steps;
42 independent source fixtures / 8692 exact observations; 159 Wasmtime/native/Node
transfer boundaries; real Chromium 153.0.8010.12 and Firefox 155 Workers; codecs,
capacity, storage WASM and extracted standalone package checks. Additional proofs:
19 prescribed/neighbor H/Q cells with both transfer directions and late output
failure/retry; 12 fresh-process H/Q cells through Node/native/Wasmtime; six scalar
sizes / 158 exact logical observations and 18 native memory cells; ten frame cases / 6530
observations; 15 blob cases / 90 prefixes / ten capacity cases. Existing failure
sweeps cover record, encoded and caller-buffer publication, including primed and
unprimed reply/cancellation paths. Semantic forks and packed shifts are tested at
every fallible protection/successor allocation; commit and rollback deny allocation.

All eight immutable A0 fixture families pass: Inquiry application/cases, document,
consequence application/economy, recursive single/double parser and review. The
adapter preserves their assertions, fixtures, approvals and sandbox behavior while
supplying actual experimental kernel bytes/digests to the public API. Historical
binding verification remains independent and unchanged. Earlier restricted-sandbox
Inquiry failures were later executed successfully; the failed logs were not relabelled.

## Economics

Five alternating windows, three warmups and nine samples per process. Confirmed
wins require median ratio below 0.95 and at least four of five below 0.95; slowdowns
use the symmetric 1.05 rule. Peak increases are bounded by max(1024, ceil(1% of W0)).
No tradeoff exception was accepted. There are 272 completed timing cells with no
confirmed slowdown or excess peak. Smaller and inconclusive changes remain in raw
results. Timing ran without other task build/benchmark/qualification CPU work.

| Complete lifecycle, depth 1024 | Ratio | Reduction | Saved per lifecycle | Peak working bytes |
|---|---:|---:|---:|---:|
| wasm H | 0.903378 | 9.66% | 5.895 ms | 2331659 → 2220683 |
| wasm Q | 0.932342 | 6.77% | 2.266 ms | 2044517 → 1978597 |
| native H | 0.494100 | 50.59% | 3.746 ms | 2976143 → 2778959 |
| native Q | 0.736450 | 26.36% | 1.036 ms | 2636580 → 2521316 |

Both largest WASM primary cells satisfy the prospective five-window win rule.
Both largest native cells also qualify. All smaller and inconclusive cells remain
in the raw results; the fixed numerical gates are unchanged.

H includes preparation,
start/yield, resumption, 64 live-handle drives, checkpoint transfer, restore,
cancellation, close and release. Q includes initial request publication, three
invalid replies, the valid reply, cancellation, close and release. All smaller
prescribed dimensions are retained. Engine setup is recorded separately.

Guardrails include scalar 0/2/4/16/256/1024 admission/prepared/fresh; compatible and
fallback frames at 0/1/8/128/512; sparse widths 4/4096/65536 with admission/fresh/live
resident costs; blob lengths 0/65532/65533/65536/1048576 and direct/captured/retained
aliases; alias counts 1/4/16/64; fixed 18-image admission and 30-case / 491-command
fresh consumer replay, in both native and WASM. The replay is a separate guardrail,
not a substitute for live H/Q. Its path-independent schedule digest is
`5e46c9a03c488b6407bcc63d8a39ddb3e5f33c7d47992a3dd37c8bc3473cf781`.

Every WASM memory observation folds the peak immediately before another command
can reset it, including failure and cleanup. Memory passes are separate from
latency. Native peak covers one full retained preparation/session/outcome allocation
domain, with allocation traffic separate. Native Session/Resident/Outcome sizes are
1592/1608/112 bytes. Working/live allocation is distinct from reserved linear memory
and native workspace capacity; H/Q use common 2 MiB/32 MiB/2 MiB stress budgets,
and layout/blob guards their declared 256 MiB test allowances. Defaults are unchanged.

Native submicrosecond resident timing now uses 64 independent drives per sample
with setup/teardown outside that drive-only interval, as specification 10.3 requires.
Earlier single-drive readings quantized to 41–42 ns and receive no final latency
credit. The single-resident memory interval is unchanged. All old raw windows are
retained. W0 already reclaims dead large backing: the separate preservation wrapper
keeps the original P26 sampler and substitutes an independently justified existing
capability oracle, retaining alias/trace/capacity checks rather than demanding a new
improvement over an obsolete pre-reclamation baseline.

## Retained evidence and reproduction

W0's scalar samplers assert exact physical memory equality. Their original current-source
failures are retained and the samplers are unchanged. The association hint adds eight
bytes to each frame: independent native/wasm layout probes observe 104→112 and
96→104 bytes respectively, with eight reserved map entries in these scalar fixtures.
The supplementary preservation lane requires exactly 64 added fresh/cycle peak bytes,
exact admission and post-release retention, and every original logical/canonical
assertion. All six scalar sizes / 158 observations and 18 native memory cells pass;
64 bytes is below the unchanged specification §10.4 margin. This is separate from
latency qualification and does not grant a tradeoff exception.


[Machine-readable report](change-proportional-execution.json) binds source/product
hashes, exact scopes, cells and open work. [Raw evidence archive](performance/change-proportional-raw.tar.gz)
SHA-256: `0ddfb598c1cf52e98feeebae0250149e1d2da39adaf854525ec5a013095de9e9` (38117092 bytes), with historical and repaired-source
path/hash inventories. It contains passing and failed/inconclusive windows, current
verifier logs, frozen H/Q replies, 18 BPI3 inputs and the 491 exact input/output pairs.
These documents/archive are outside npm files and Zig source-package paths.

Extract the archive outside the checkout. Raw replay paths are locators; replace
the original task evidence prefix with the extraction root before replay, preserving
input/output hashes and the path-independent schedule digest. The checked-in
freeze_consumer_replay.mjs can reproduce the same 30 selected cases from a W0 run
of consumer_qualification.mjs. The fixed inputs can be acquired/emitted through
A0's existing setup and agent4-images/build-economy-probe routes; no replacement
verifier or runtime lock is used. Additional emitters/probes are uninstalled tests.

Build W0 and the candidate through `zig build check -Doptimize=ReleaseSafe`.
Native probes use the same test/current source with explicit `-O ReleaseSafe` on
root, world and boundary_data modules, selecting W0/candidate src/root.zig and D0
src/data/root.zig. Use resident_lifecycle.mjs compare for complete H/Q;
consumer_cost.mjs/native_consumer_cost.mjs for the frozen replay; the existing
scalar/frame/layout/blob samplers for their named cells. H/Q process portability
is independently exercised by retained_history_process_transfer.mjs. The archive's
raw report identities and file hashes bind actual replay inputs and outputs.

## Remaining delivery and review

World's normal producer completed all 11 checks at `60f1ff037ccbf7eaaa75b7854de981d7239cab31`
(tree `523e0dc0434c1279ee79d899d45d15a1f0fef575`). Acquisition and moved source-free
verification/smoke passed. The subsequent probe-only correction reused those identical production inputs.
The current borrow repair changes production and requires a new bundle; the previous
artifact retains its actual producer identity and receives no current-product credit. Manifest:
`5a7aa584f3b0758f9780e4c4848e0583754236fe8d4527cbf015c7ad8099f84b`; archive:
`258b5b03e371a23dab0ca5905bffadf514ce30f47f6f72145c61cef5859b8cb1`.
Then serial review requires native/default standard, the five installed auxiliary
lenses, and four further native/default standard confirmations on the same head.
The first P0 was `32f7c576da52c06dfb9d3dea893aa8d43f785fb1`, tree
`ead1e4b3818b1be57aff95ca48b4fc8038543fd3`. Its clean-source bundle was produced,
acquired and verified outside the source tree, but standard and recovered
soundness reviews found the unwind double-free. A root native comparison also
established the stale binding after embedded Session cancellation. Both defects
were current, entailed failures, and all old-head credit is zero.

The user directed immediate bug repair while the invalidated initial wave was
open. The footgun request was interrupted without a semantic verdict; the old
wave is superseded and is not claimed complete. After qualification, the repaired
head receives the full initial six-lens serial wave and four further standard
confirmations. The first repaired head, `60f1ff0`, then received a standard P2: the diagnostic
probe committed an inspection-only transaction, clearing the binding before Q
measurement. The probe now rolls that transaction back and requires zero checkpoint
constructions plus one binding reuse per invalid reply. Its corrected counters
restore W17 evidence; production behavior and all 272 timing windows are unchanged.
The corrected head `7dca3dd` received clean standard and soundness reviews, then a
footgun P2: a mutable frame pointer obtained before transaction entry could bypass
rollback. W0 restores that position; the old journal did not. The current repair
protects actual outstanding pointers at begin and copied backing views at mutation.
New tests cover position/slots, copies across map growth, independent forks, every
begin allocation failure, no-allocation commit/rollback, and pointers across commit.
All credit resets for this production repair; final P1 remains unselected.
Material findings or head changes reset all credit. The PR remains draft/unmerged.

Historical Review Fold/negative-evidence custody is unregistered. Current accepted
source/test evidence supports this bounded construction, but not a claim of first
observation, complete history or elimination of every historical failure family.
Available native-goal usage and CAS review usage will be recorded at their phase
boundaries; unavailable model/effort/provider billing is not inferred. Required
producer/review/publication obligations remain open, not waived by local green tests.
