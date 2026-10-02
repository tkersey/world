# Change-proportional resident execution

Work in progress. The first transaction slice is implemented and locally checked;
complete-task and performance acceptance remain open.

The unchanged [user-supplied specification](resumable-execution-spec.md) is the
acceptance authority. Its digest below binds the original attachment; this report
does not replace its requirements.

## Inputs and execution

- Run suffix: `01a0fc7f`; root thread `01a0fc7f-2d45-7520-a093-d28236999615` (native Goal owner); independent driver; serial reviews.
- World W0: `c61edfc8208c375d5188e476131ca8cff5aeeb8a`, tree `87edc03ebb7b8b56facfe7f2e60845c5931f1834`.
- Runtime data D0: `511fe388587b36ae37307d277e04c22b0bb6f6d9`, unchanged `build.zig.zon` package lock.
- Agent A0: `b1f9d2866b5717d16339e7022a3b4d08951f0770`.
- Compiler C0: `65f46131f366bdd21aa98701f4110ecb801d2c8d`; separate from D0.
- Historical harness B0: `93340dade30b7d27a1e139f107359f91fb66fad3`; not a dependency replacement.
- Specification SHA-256: `d914b959e32d10b841e549cb27665689c419856e5b77ae632363fb71b22e92f3`.
- Zig `0.16.0`; Node `26.10.0`; native ReleaseSafe; wasm32 ReleaseSmall, existing ABI 3 and default budgets.
- macOS 27.2 (26B5091g), Apple M2 Pro, 32 GiB RAM; stack limit 8176 KiB; open-file limit 4096.
- Provider model/effort and token telemetry are not independently observable at entry; no model switching or helper implementation.

The isolated candidate is `codex/change-proportional-01a0fc7f`. W0 has a separate immutable source/build workspace. Fixed consumers and compiler have separate detached checkouts. Existing PRs and other candidates are excluded.

## Frozen primary lifecycles

H starts a compiled recursive computation with distinguishable dormant return continuations, reaches its bottom yield, executes 64 resident drives with quantum one, exports a checkpoint, then cancels and releases the resident and preparation. A separate correctness replay completes all depth observations in ascending order. Preparation is reported separately and included in the complete total.

Q starts the request variant with the same retained depth, publishes its bottom request, submits malformed, wrongly bound, and correctly bound ill-typed replies, then admits a valid reply at quantum zero, cancels and releases. A separate correctness replay completes all depth observations. Initial binding and publication are included.

Depth dimensions and baseline capacity choose the largest successful prescribed case before candidate production edits. Smaller cases remain guardrails. No production collection is disabled. Actual frame counts and collection crossings are observed independently of requested depth. Timings and allocation passes are separate; per-command WASM peaks are folded before subsequent commands reset them.

## Baseline verification

`zig build check-storage check-native -Doptimize=ReleaseSafe --summary all` at W0: 71 storage tests and 87 source/session tests passed. The test runner prints diagnostic `failed command` lines alongside warnings, but both build summaries and the process exit status report success.

## First implementation slice: transactional frames

The selected ordinary construction is a first-touch journal in `Frames`, composed with the existing Store transaction. The source-fixed obligation is entry-state restoration without allocation through publication failure; retaining a second complete frame map is incidental. A persistent map root could satisfy the same obligation but would replace the hash-map representation and all its mutation/iteration interfaces. The local journal reuses current Slots/Custody forks and leaves semantic retention with those owners.

`Session.begin` starts both owners. `Frames.getMutable` and `getForUpdate` save before exposing mutation. `put`, `update`, `remove`, `copyFrame`, and `rebaseFrame` cover membership and clone operations. Copied mutable descriptors in public continuation capture and resumption acquire protection before touching Slots or custody. All other control/instruction writes originate at the protected active borrow. Unwind and Store collection propagate removal failure. Frame protection precedes Store retirement and unwind ownership transfer, so those transitions have no newly fallible gap after transfer.

Untouched removals transfer their entry owner into the journal. Changed frames fork only once. Frame IDs belong to Store's node namespace: appended IDs at/above the entry node extent had no entry frame, so rollback can remove that appended interval; reused earlier IDs retain explicit absent entries. Rollback first removes successors, then restores saved entries using retained map capacity. Store's existing failure-only index rebuild remains; no claim of change-proportional total rollback is made.

The old `Frames.Backup`/`backup` map copy and all-frame commit discard are removed. Preparation layout ownership, sparse packed Slots, semantic forks, and ordinary collection are retained. This decision is invalidated by any new sanctioned mutable path that bypasses acquisition, by frame IDs outside Store's namespace, or by any shrinking of map capacity during a transaction. First falsifiers are late allocation failure with identical retry, removal/reuse, and mutation through a copied descriptor.

Baseline H retains 2/17/65/257/1025 actual frames for depth 1/16/64/256/1024. Its transaction entry retains every frame; the one-step allocated bytes are 1856/4568/15416/58808/232376. The first journal implementation allocates zero bytes at begin and 1920 bytes for the same one-frame step at all five sizes. These are allocation/structural observations, not latency claims.

The unchanged native qualification passes 71 storage and 87 source/session tests. Four added transaction tests pass, including all-allocation-failure injection, rollback with an allocator configured to reject any further allocation, repeated mutation, removal/recreation, semantic forks, packed sparse slots, and a 2048-commit bounded-live plateau. Final storage count is 75.

WASM H/Q lifecycle outputs match frozen W0 outputs at all five depths. Peak working allocation is no higher in these cells. At depth 1024, H's measured peak changes from 2,043,439 to 1,961,135 bytes and paused live bytes from 1,342,814 to 1,244,126. Q's peak changes from 2,113,373 to 2,031,069; binding reconstruction is still present at this slice. Each command's peak is sampled before the next command.

The test-only H/Q emitter uses C0, with mandatory compilation/coalescing intact. Frozen H image SHA-256 is `17d4acc725c4c5e27daee91f48a9ab4bd54d976a4a1d6c6d0fe71709c798ad12`; Q is `8c6beeb21dd9cf6277e6a521f023cb233fba6e14eb89f49e011c1782d40863a7`. Both run on W0/D0. The largest prescribed baseline case succeeds at the common 16 MiB input/output and 128 MiB working stress limits, so depth 1024 is the primary case. Normal product limits remain unchanged.

Installed skill source at entry is dotfiles `2a93e85047de678af845dd805dafac2f6b56d9e9`; current contracts were loaded without restoring older workflow machinery. Bulk raw measurements stay outside the production package.

## Acceptance still outstanding

Complete lifecycle measurements and guardrails, remaining adversarial/platform and consumer qualification, P0/P1, serial review closure, and W01–W40 final audit. Draft PR #61 contains the first slice and stays draft/unmerged.

## Second implementation slice: unchanged pending observations

`Resident` owns a single optional 32-byte expected request identity with its private inline Session representation. The inline storage has the exact size/alignment of the private State; it introduces no heap allocation, and the only typed interpretation is in `resident.zig`. Resident operations retain the existing stable-address, non-copyable owning-handle contract. Mutable Session references no longer escape that owner. The separately exported low-level `Session` and its mutation operations remain available; `Session.answer` always canonicalizes its current state.

`invocation.finishObserved` reports the identity already constructed by the existing canonical publication procedure. It retains no graph or checkpoint bytes. A restored resident derives its first binding from its admitted parked state. A rejected response preserves that unchanged fact. Reply progress and cancellation clear it; a newly published request replaces it. On any late publication failure, the transaction restores the computation and the saved applicable identity. Checkpoint and read-only diagnostics do not invalidate it; transfer/close relinquish both execution and private identity.

Both callers use one `response.zig` decoder, identity comparison, typed admission, and continuation application. This replaces the controlled Resident's redundant expected-request reconstruction; the general low-level path retains canonical recomputation for its distinct mutation contract. No production optimization selector is present. Native diagnostic tests now use gated snapshots/statistics rather than mutable Resident internals. The direct transaction assertion remains on the public low-level Session API; the shallow-capture failure sweep inspects the same canonical checkpoint it already exports. No tested semantic obligation was removed.

The boundary comparison rejected an unguarded cache in public mutable Session storage: a later frame write could invalidate its canonical binding without touching a cache key. Heap-boxing Resident would add at least the native Session's 1536 bytes to the allocation domain; inline private storage avoids that cost. The selected cache law is scoped to sanctioned Resident operations, not arbitrary corruption of its private representation. Its falsifiers include a predecessor reply accepted after cancellation, or a legitimate retry rejected after failed publication. A new mutable escape from Resident or an unaccounted successful mutation invalidates this ownership argument.

At all five prescribed Q sizes, three distinct rejected replies allocate 762 native bytes, perform two decoded binding comparisons (the malformed reply rejects during decoding), and perform zero State projections or expected-request constructions after publication. Counters include failed attempts. Initial publication, caller-requested export, and new post-progress requests remain separately charged canonical observations. The native probe also discloses first-transaction Store index capacity allocation after restoration, which is distinct from recurrent frame rollback preparation.

Four new native tests cover published and restored binding reuse, malformed/wrong-image/ill-typed replies against the ordinary Session's error oracle, all three late output-failure routes with original-input retry, cancellation-created cleanup binding replacement, and direct low-level frame mutation followed by rejection of the old binding. Native qualification is now 91 tests; storage remains 75. The frozen WASM H/Q outputs still match at all five depths, with no higher measured working peak in those cells. Timing acceptance remains unclaimed.

## Preservation argument and verification domain

At transaction entry let `E` be the frame map, `C` the current map, and `J` the
saved partial map. For IDs below Store's entry extent, the entry value is `J[id]`
when recorded and otherwise `C[id]`; IDs in Store's appended interval were absent
at entry. Read access preserves this relation. First mutable acquisition forks
Slots/custody roots before exposing the descriptor; their existing copy-on-write
operations preserve the saved value. A removed untouched frame transfers its
owner to `J`. A reused old hole records absence. Repeated mutation or ID reuse
does not replace the original saved value. Commit releases only `J`; rollback
removes successors before reinstating saved owners, so unchanged map capacity
suffices. Store's corresponding journal and Session's control snapshot restore
the rest of the unpublished attempt. Statistics are explicitly outside this
semantic relation.

The pointer returned by mutable frame acquisition remains valid until a frame-map
mutation. Instruction/control paths that can grow the map already use copied
descriptors; their first acquisition now secures entry ownership. Packed slot
readers continue resolving logical positions through Slots, and argument lists
are gathered before simultaneous writes. No raw packed offset is retained across
insertion/removal. Preparation leases still outlive all frame roots and layout
borrows. Store values referenced only by rollback frames remain owned by the
Store journal until the shared commit fence.

Resident binding reuse has a separate, closed operation domain. `start`/`restore`
create private state without a binding. The exact canonical request establishes
one. Only gated publication advances the computation; it couples binding
invalidation/replacement and frame/Store/control rollback. The final record,
encoded allocation, or caller-buffer encoding must succeed before commit.
Checkpoint and diagnostics are read-only. Successful transfer/close ends the
owner's lifetime. The general low-level Session API cannot use this private fact
and therefore still reconstructs its expected binding. The shared response helper
always parses and performs typed admission; it memoizes no response or external
permission.

Returned outcomes own an arena, encoded outputs own their allocator allocation,
and checkpoints own the requested output allocation. The retained binding is a
value copy of 32 bytes and borrows no Pending storage. Decoded response bytes live
through typed admission and Store literal construction, exactly as before; Store
retains the resulting value under its existing ownership rules. Diagnostic
snapshots contain only counters/counts/booleans. No pointer to Resident's Session,
temporary projection, frame map, or mutable WASM view escapes those APIs.

These arguments concern admitted Programs/states, the actual exported APIs, and
their supported owning-handle discipline. They do not cover arbitrary writes to
private representation bytes or invalid allocator implementations. Tests are
bounded falsification evidence: they include independent W0 bytes, source oracles,
named valid and rejected cases, allocation/capacity failure, and cross-engine
transfer. They are not a universal proof over all Programs.

## Qualification progress after both slices

The aggregate passes 75 storage tests, 91 native tests, 41 JavaScript tests,
42 source fixtures with 8692 observations, 237 native/Node boundaries and 23
transfers, 159 independent Wasmtime boundaries, input/working/output/physical
capacity checks, and extracted package operation. Chromium 153.0.8010.12 and
Firefox 155.0 execute real Workers. Additional H/Q transfer checks cover both
source directions after original process/Worker exit: 12 native/Node/Wasmtime
cases and four 1024-history transfers in each browser (15 Workers destroyed per
browser including the retained existing cases).

Two further storage tests (77 total) force first-protection growth of both slot
and custody view tables, untouched-removal allocation failure, and exhaustion of
a physical slot-handle generation. The added independent fake-kernel sampler test
makes each H/Q phase, including thrown rejection, cancellation, close, and release,
the sole large observation and proves the maximum is captured before reset.

Unseen retained-depth neighbors 7/31/63/65/257 preserve canonical lifecycle output
and each individually distinguished continuation. At 1025 retained frames,
bounded cancellation drives removing 0/1/4/8 frames save and commit exactly those
counts without tracing. Across 1024 wrong-binding commands, candidate live bytes
remain 1,243,853 and linear memory remains 2,228,224 bytes after warm-up; W0 reaches
a stable 1,342,541 live / 2,752,512 reserved bytes. Both release to zero.

The exact A0/C0 images reproduce the 18-image upstream corpus. Unchanged fixture
assertions on the authenticated reconstructed W0 runtime produce the original
30-case / 491-command replay, plus 12 parser cases / 171 commands. The candidate
is evaluated against those frozen inputs and expected outputs directly through
World's public APIs; A0's historical runtime lock is never rewritten.

The historical blob sampler's relative-improvement assertion fails even for
W0 versus itself, because W0 already includes the accepted reclamation change.
That failed result is retained. The corrected oracle checks each arm against its
own pre-pause live bytes and independently requires dead large backing below
8192 paused bytes while retaining live aliases. Threshold neighbors include
payloads 65532/65533/65534 whose encoded extents straddle 64 KiB. All 18 cases,
108 prefixes, and ten failure/retry cells pass. No old defect was restored to
manufacture a gain.

At head `5c940d0`, both primary WASM lifecycles meet the five-window win rule:
H1024 ratio 0.8125 and Q1024 ratio 0.9088. Complete failure/retry lifecycle ratios
are 0.8143 and 0.8901. The remaining guardrail run identifies material long-tail
dispatch regressions, so this head is **not economically accepted** and is not P0.
All initial raw windows are preserved for comparison with the correction.

Historical Review Fold projection reports `InvalidStoreBinding`. This task does
not repair predecessor evidence custody and makes no first-occurrence, historical
absence, or recurrence claim from that unavailable source. Current test evidence
retains its original subjects; the obsolete relative-reclamation expectation is
not admitted as a production correctness defect.

## Dispatch cost correction

The first full cost pass at `5c940d0` passes all 60 native and all 60 WASM consumer
cells (18 admissions plus 42 exact replay cases), but reports 6–21% regressions in
long tail-call probes. That measurement is retained rather than relabeled.
The hot mutable borrow performed both `contains` and `getPtr` on the frame map,
then checked the same journal key on every instruction. The correction retains
the Frames-owned journal and its rollback law: acquire the pointer once, protect
before returning it, and remember one proven journal-membership key. Membership
only grows during an attempt, including after logical ID removal/reuse; it is
reset by commit/rollback. This caches no frame pointer or mutable frame contents.
The general map lookup remains for another key. A future mid-attempt journal-key
deletion would invalidate this shortcut.

The corrected construction passes 77 storage and 91 native tests. A preselected
five-window discriminator covers compatible/incompatible 512-call fresh and
1000-call resident paths on native/WASM, the flagged four-operation fresh case,
and the captured-blob pause. None meets the defined confirmed-slowdown rule.
The four-operation cell remains variable (median ratio 1.0776 with fewer than
four windows over 1.05), so it is disclosed as inconclusive pending the cumulative
run rather than described as a speedup. Full final cost and package qualification
remain required before P0.
