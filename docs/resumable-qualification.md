# Change-proportional resident execution

## Post-P0 repair in qualification

P0 was `1082c07945b0227e77c15bb275edfd77dc1b657d`, tree
`9518b875ae789f9a8ab499ebd2106f7b241a1cb1`. Its initial serial review wave found
one rollback defect: a mutable frame pointer acquired before transaction entry
could write without acquiring a saved entry. The driver reproduced that case and
two copied-descriptor cases; all three fail on P0 and pass on W0. P0 is invalidated,
and none of its initial review credit carries to the successor.

The repair keeps Frames as the transaction owner. Registered descriptors carry
their entry identity, so frame-writing operations acquire protection even when
the descriptor came from a read. Outstanding mutable map pointers are recorded
with one inline pointer and a set only for additional simultaneous borrows;
begin protects only those possibly writable entries. Their
borrows survive begin/commit and end at the existing map-mutation boundary.
Resident ends its internal borrows at its operation boundary because its private
Session cannot expose them. Independent construction and semantic forks remain
separate owning values; map insertion transfers their ownership as before.

The first repair passed the normal aggregate and primary/scalar timing but failed
the larger H/Q memory guardrails: two optional per-frame fields added too much
map storage. The compact successor adds eight bytes per frame, keeps the borrow
set proportional to actual simultaneous pointers, and releases that set at its
lifetime boundary. It passes 83 storage and 92 native tests and all ten H/Q working
memory comparisons. The scalar probe's earlier exact physical-memory equality
was also corrected to the specification's explicit allowance; canonical outcomes,
checkpoint sizes, step counts, and preparation comparisons remain exact.

Complete successor economics, evidence packaging, exact-head delivery and a fresh
review campaign remain pending. **The measurements and archive below describe P0 until
that requalification is complete; they are not successor qualification.**

## P0 implementation and measurements

World now journals frames on first mutation and keeps one canonical expected
request identity inside the controlled Resident owner. The ordinary low-level
Session API remains available and recomputes its expected identity. The old
all-frame rollback backup and the Resident's repeated expected-State reconstruction
are removed; there is no production selector between old and new implementations.

The unchanged [accepted specification](resumable-execution-spec.md) is authoritative.
This report records the implementation and local measurements. The PR proof block
records the exact final source, authenticated package delivery, P0/P1, and independent
review receipts; those closure facts cannot be embedded in their own Git commit.

## Fixed inputs and scope

| Input | Identity |
|---|---|
| W0 | `c61edfc8208c375d5188e476131ca8cff5aeeb8a`, tree `87edc03ebb7b8b56facfe7f2e60845c5931f1834` |
| D0 | `511fe388587b36ae37307d277e04c22b0bb6f6d9`; unchanged World package lock |
| A0 | `b1f9d2866b5717d16339e7022a3b4d08951f0770` |
| C0 | `65f46131f366bdd21aa98701f4110ecb801d2c8d`; separate test/compiler input |
| B0 | `93340dade30b7d27a1e139f107359f91fb66fad3`; historical harness source only |
| Specification SHA-256 | `d914b959e32d10b841e549cb27665689c419856e5b77ae632363fb71b22e92f3` |
| Runtime implementation commit | `424a36ca0921ff408394ba6e8556e89d3f224328` |
| Root run | `01a0fc7f-2d45-7520-a093-d28236999615`; original driver; serial reviews |
| Toolchain | Zig 0.16.0, Node 26.10.0; native ReleaseSafe; WASM ReleaseSmall |
| Host | macOS 27.2 (26B5091g), Apple M2 Pro, 32 GiB; 8176 KiB stack limit |

W0 and all upstream inputs have isolated immutable checkouts. No Boundary or Agent
production source, dependency lock, application policy, compiler policy, or runtime
binding was changed. Existing PRs and other candidates were excluded. Installed
skill source at entry was dotfiles `2a93e85047de678af845dd805dafac2f6b56d9e9`.

World's production import scan covers 35 Zig source/build files and 207 named or
relative imports. The D0 data closure covers 51 files and 377 imports, all within
`src/data` apart from standard-library imports. Both scans completed without an
unparsed or missing import. Compiler-dependent emitters remain test-only.

## Measurements

Every reported acceptance cell has five independently launched, alternating
baseline/candidate windows, with at least three warmups and nine measurements.
The ratio is the median of paired window-median ratios. A slowdown requires a
ratio above 1.05 and at least four of five windows above 1.05; a primary win uses
the symmetric below-0.95 rule. These are engineering rules, not confidence intervals.
No task build or other benchmark ran alongside acceptance timing; ordinary desktop
activity remained. Raw windows, variability, failures, and inconclusive cells are retained.

| Complete live-Resident workload | W0 median | Candidate median | Paired ratio | Win windows |
|---|---:|---:|---:|---:|
| H, depth 1024, WASM | 37.833 ms | 30.439 ms | 0.8046 | 5/5 |
| Q, depth 1024, WASM | 33.927 ms | 30.866 ms | 0.9094 | 5/5 |
| H with late publication failure and retry, WASM | — | — | 0.8126 | 5/5 |
| Q with late publication failure and retry, WASM | — | — | 0.8966 | 5/5 |
| H, depth 1024, native | — | — | 0.2615 | — |

H prepares and starts, reaches its bottom yield, performs 64 quantum-one drives,
exports the declared checkpoint, cancels, closes, and releases preparation. Q
prepares and starts, publishes its request, rejects three distinct invalid replies,
admits the valid reply at quantum zero, cancels, closes, and releases. Preparation
is included in each actual lifecycle total and also reported separately. Failure
profiles additionally include the failed attempt, unchanged-state observations,
original-input retry, and cleanup. These definitions were frozen on W0 before
production edits. The largest prescribed case succeeds on W0 at common 16 MiB
input/output and 128 MiB working stress limits; smaller cases remain guardrails.

| Required timing lane | Cells | Result |
|---|---:|---|
| H/Q WASM lifecycles | 10 | Both primary wins; no confirmed slowdown |
| Scalar native / WASM | 12 / 18 | No confirmed slowdown |
| Compatible/fallback frame reuse | 44 | No confirmed slowdown |
| Layout widths 4/4096/65536 | 36 | No confirmed slowdown |
| Blob fresh/pause/complete resident lifecycles | 72 | No confirmed slowdown |
| Direct aliases 1/4/16/64, drive and complete lifecycle | 8 | No confirmed slowdown |
| Native H/Q/R complete lifecycles | 38 | No confirmed slowdown |
| H/Q failure/retry lifecycles | 2 | No confirmed slowdown |
| Frozen consumers, native / WASM | 60 / 60 | No confirmed slowdown |

There are 360 timing cells. No required peak-memory comparison exceeds its allowance,
including the conservative inline-owner accounting below. Some isolated blob cells
remain inconclusive, with median ratios as high as 1.0934 but only three of five
windows above 1.05. They are not relabeled unchanged. The initial native zero-operation
prepared cell had a 1.1208 median ratio, including one 5.01 ratio window, but did not
meet the four-window rule; an independent same-binary follow-up measured 1.0267 with
one window above 1.05. Both sets are retained. No speedup is claimed from these cells.

Short WASM samplers initially straddled engine tier-up. Independent compilation
traces observed compilation during the measured batches on both kernels. Scalar,
frame, blob, and alias timing now use 64 fixed warmups and retain every warmup plus
the original 12-batch cold-ramp total; applicable samplers also report engine setup.
Acceptance timings use normal engine flags. Cold-ramp/setup observations do not
meet the confirmed-slowdown rule. The layout sampler uses a separate instrumented
lifecycle before its three warmups and nine latency samples. Independent reset-on-call
models verify H/Q, layout, blob, and alias peak collection, including failures and
late small cleanup observations.

## Memory and lifetime

| WASM depth-1024 observation | W0 | Candidate |
|---|---:|---:|
| H whole-lifecycle working peak | 2,043,439 B | 1,961,135 B |
| H paused working live | 1,342,814 B | 1,244,126 B |
| Q whole-lifecycle working peak | 2,113,373 B | 2,031,069 B |
| Q paused working live | 1,342,541 B | 1,243,853 B |
| H whole-lifecycle reserved linear memory | 2,752,512 B | 2,555,904 B |
| Q whole-lifecycle reserved linear memory | 2,752,512 B | 2,818,048 B |

Q therefore reserves one additional 64 KiB page in the complete lifecycle despite
its lower working peak. Reserved memory is not live allocation and cannot be
reported as a working-memory saving. During 1,024 unchanged invalid replies, live
and reserved bytes plateau: candidate 1,243,853 / 2,228,224; W0 1,342,541 / 2,752,512.
Both release working live allocation to zero. In 64 complete H/Q cycles on each
kernel, working peaks, paused live bytes, and reserved memory remain constant after
warm-up. Native tests also cover 2,048 repeated commits without retained rollback history.

WASM's optional Resident is static storage outside `working_budget`: it grows from
944 to 1,048 bytes. Native caller-owned Resident storage grows from 1,472 to 1,592
bytes; the native Transaction value shrinks from 144 to 120 bytes. The WASM Transaction
value shrinks from 112 to 104 bytes. Conservatively adding the complete +104/+120-byte
owner growth to every applicable working-peak comparison, without credit for smaller
transaction values, still passes all allowances. Native Workspace peaks include
preparation/session/outcome allocations; WASM working peaks keep input/output budgets
separate. These are not process-RSS or maximum-stack-depth measurements.

## Construction and preservation

### Frame rollback ownership

At entry let `E` be the frame map, `C` the current map, and `J` the saved partial map.
For IDs below Store's entry extent, the entry value is `J[id]` when recorded and
otherwise `C[id]`; appended IDs were absent at entry. First mutable acquisition
forks Slots/custody roots before exposing a pointer or copied mutable descriptor.
Removing an untouched frame moves its owner into `J`. Reusing an old hole records
absence. Repeated mutation or identifier reuse never replaces the original entry.
Commit releases only saved entries. Rollback removes successors before reinstalling
saved owners using retained map capacity, without allocation.

The remembered acquisition key is initially the entry extent, which already denotes
an absent-at-entry identity; later keys have established journal protection. It resets
on every begin, and failed preparation cannot install a key. This avoids an unnecessary
optional tag and repeated journal lookup. Fast checks are inline; fallible first-touch
preparation is separate. Neither changes ownership or creates a fallback evaluator.

`Session.begin`, frame get/update/put/remove/copy/rebase, continuation capture and
resumption, clone, unwind, and collection all cross the protected mutation boundary.
Protection precedes Store retirement and unwind ownership transfer. Mutable map borrows
end before operations that can grow the map. New unpublished frames retain their own
construction cleanup. Slots still resolve logical positions after packed shifts;
argument values are collected before simultaneous writes. Prepared layout leases and
existing semantic sharing remain with their original owners.

The structural H probe has 2/17/65/257/1025 actual frames. One changed-frame drive
allocates 1,920 bytes at every size, saves/commits one entry, copies one value and zero
directories, and traces zero nodes. W0 allocates 1,856 through 232,376 bytes and its
backup visits every retained frame. The smallest case adds 64 bytes. At fixed 1,025
frames, changed sets 0/1/4/8 save and commit exactly those counts. Untouched reads save
nothing. Counters include failed attempts.

The frame journal itself needs no allocation at begin. The separate first Store
transaction after restoration still reserves an index proportional to its node extent
(152 through 12,424 bytes in this probe). Store's existing failure-only index rebuild
also remains. Neither is represented as change-proportional whole rollback.

### Pending observation ownership

Resident privately owns Session plus one optional 32-byte identity in inline storage.
`finishObserved` supplies the identity from the existing canonical request construction;
it retains no serialized State or response. Start/restore begin without that fact.
A restored resident derives it from its admitted parked State on first use. Rejected
responses preserve it. Successful reply progress and cancellation invalidate it;
publication installs a successor fact. Every record, allocated encoding, and caller-buffer
route shares the same commit fence; late failure restores computation and an applicable
original identity. Checkpoint and diagnostics are read-only; transfer/close end ownership.

The controlled owner exposes no mutable Session reference. The separately exported
Session and its low-level mutation capabilities remain available; `Session.answer`
reconstructs its current canonical binding. Both paths share response decoding, identity
comparison, typed value admission, literal construction, and resumption. Recreating the
same saved State may legitimately recreate the same binding; no external exactly-once
or approval memoization guarantee is introduced.

At every Q size, three distinct rejected replies allocate 762 native bytes, perform two
decoded identity comparisons, and perform zero further State projections solely for
expected-binding checking after publication. The malformed reply rejects before comparison.
W0 allocates 14,196 through 2,800,047 bytes for the same three cases. Initial publication,
restoration, requested exports, and new requests retain their necessary canonical work.

Outcomes, encoded output, and checkpoints retain their existing owning/detached-buffer
contracts. Private identity is a value copy, not a borrow from Pending. Response bytes
remain alive through admission and Store literal construction. Diagnostics expose only
snapshots/counters. These arguments assume admitted Programs/States, valid allocators,
and supported owning-handle discipline; arbitrary representation corruption is outside
that contract. Tests are bounded falsification evidence, not a universal theorem.

## Executed semantic coverage

The current source passes 78 storage tests and 91 native source/session tests in
ReleaseSafe. These include all-allocation-failure sweeps, both first-protection view-table
growth failures, allocation-free rollback, remove/recreate/hole reuse, semantic forks,
slot-generation exhaustion, and all three late publication destinations with retry.
A new identity-boundary witness rolls back the first appended frame, then protects that
same ID as an ordinary entry in the next transaction.

H and Q each complete all 1,024 individually distinguished continuation effects on W0
and the candidate, returning 273. Neighbor depths 7/31/63/65/257 also preserve expected
outputs. Current checks cover 158 scalar observations, nine checked-failure cuts and
16 capacity cases, 6,530 frame observations, 342 layout observations, and 162 blob
prefixes across 24 size/family cases, plus ten blob failure/retry cases. Retained blobs
remain live after the first reusable branch returns and are reclaimed at the public
pause after their last read.

Twelve extended H/Q transfers cover both source directions, native/Node/Wasmtime, and
restoration after the producer process exits. Chromium 153.0.8010.12 and Firefox 155.0
each destroy 15 real Workers, including four bidirectional depth-1024 H/Q transfers.
Existing wrong-image, released/cross-instance handle, reentry, ownership, suspended
cleanup, source-oracle, and package tests remain in the aggregate owner.

A0/C0 emits the exact 18-image historical corpus. Original A0 fixture assertions run
against its independently authenticated reconstructed W0 runtime, producing the original
30 scenarios / 491 commands plus 12 parser scenarios / 171 commands. World replays all
662 exact fresh commands and expected outputs through each candidate engine. This is
fresh-runtime replay, not one live Resident, live model latency, or an application-wide
gain. A0's lock was never rewritten to impersonate a delivered candidate.

## Kernel, package, and evidence

| Artifact property | W0 | Candidate |
|---|---:|---:|
| Kernel bytes | 470,027 | 475,612 (+1.188%) |
| WASM code-section bytes | 455,962 | 461,099 (+1.127%) |
| Code functions | 646 | 654 |
| Initial / maximum pages | 18 / 4096 | 18 / 4096 |
| Imports / exports | 0 / 23 | 0 / 23 |
| Single cold kernel + runtime-package build | 10.902 s | 10.673 s |

The build times are individual cold-cache disclosures, not repeated performance claims.
ABI 3, wasm32, 64 KiB stack, 256 MiB maximum, and default 64 KiB / 1 MiB / 64 KiB
input/working/output limits are unchanged. No threads, shared memory, memory64, or new
feature profile is required. Source/build flags remain the normal repository profile.

Baseline kernel SHA-256:
`9627eb1e66239119bccb4ddcd43b4f6c757180dab930a9feb276671262f735d1`.
Candidate kernel SHA-256:
`40c3d4c4dcfb5e06fc0dfaa93506b10c4a9740dea6c06e0a2413195e1814e9b9`.

The [evidence archive](resumable-evidence.tar.gz) retains raw paired windows, previous
failed/incomplete runs, frozen images and arguments, both measured kernels, all 662
command/output pairs, portable replay indexing, source-import enumeration, and relevant
logs. Its inventory preserves byte identities. Original report paths are provenance;
the portable manifest resolves locally. The archive is excluded from Zig's explicit
`.paths`, npm's file list, and the runtime build's copy list, so it is not in the consumer
package closure. Native executables are reproducible from the fixed inputs and recorded
commands; the task also retains the original binaries and full logs locally.

The final delivery uses the existing `runtime prepare`, authenticated `runtime acquire`,
and source-independent `runtime verify --smoke` owners. Their exact source/delivery
receipts and the final serial review result belong in the PR proof block. No release,
package publication, promotion, merge, or separately triggered paid CI workflow is part
of this task.

## Reproduction

Use the fixed tuple above and the locked test dependencies. The repository's normal
aggregate is `zig build check -Doptimize=ReleaseSafe --summary all`. A local D0 override
may point at its exact checkout; production remains bound to the unchanged package lock.

Build the uninstalled comparison tools from this checkout's
`test/current/build_resumable.zig`, supplying `-Dcompiler-source=<C0>`,
`-Ddata-source=<D0>`, `-Dworld-source=<W0-or-candidate>`, optional
`-Dagent-source=<A0>`, `-Doptimize=ReleaseSafe`, and a distinct `--prefix`.
C0 emission for A0 uses a plain exact source archive accepted by A0's existing verifier.

Unpack the evidence archive. `consumer_replay.mjs` accepts the embedding module, both
kernel paths, `corpus/economy-corpus`, `replay/manifest.json`, and an output path.
`native_consumer_cost.mjs` accepts the two native runners, that corpus, an output path,
and the same portable manifest. Other `test/current` probes consume their corresponding
included corpus directories. H/Q sample, memory, complete, and plateau modes share the
same frozen manifest; the raw reports retain the exact controls and windows.

## Acceptance coverage

| Requirement | Deciding evidence / owner |
|---|---|
| W01 | Fixed tuple, spec digest, independent run identity, unchanged locks |
| W02 | Build-input hashes, identical images and modes, separate actual kernels |
| W03 | Existing persistent-view, sparse/dense, sharing, occupancy and alignment tests |
| W04 | H scaling, changed sets, first-touch journal path and commit iterator |
| W05 | Read-only acquisition test; one protected entry per selected H drive |
| W06 | Every allocation failure, full view tables, protection before mutable escape |
| W07 | Repeated writes restore the transaction-entry version |
| W08 | Create/remove/recreate/hole/append rollback and commit witnesses |
| W09 | Reused IDs, first-append boundary, exhausted slot generation |
| W10 | Before/during semantic forks and existing deep/shallow/shared fixtures |
| W11 | Custody/control rollback, packed shifts, argument gather-before-write |
| W12 | Store journal plus frame ownership, blob collection and imported backing |
| W13 | Allocation-rejecting rollback and repeated failure/retry sweeps |
| W14 | Record, allocated encoding, caller buffer and public capacity retries |
| W15 | 2,048 native commits, 1,024 invalid replies, repeated lifecycle plateaus |
| W16 | Canonical W0 request bytes and publication-derived identity |
| W17 | Q counters: zero repeated expected-binding State projections |
| W18 | Malformed, wrong image/binding, ill-typed and ordinary Session oracle cases |
| W19 | Cancellation-created replacement binding and predecessor rejection |
| W20 | Late publication failure restores original binding; original reply retries |
| W21 | Fresh native/Node/Wasmtime process and browser Worker restoration |
| W22 | Preserved public Session mutation, canonical answer, private Resident owner |
| W23 | Single bounded identity; no checkpoint graph or external-response cache |
| W24 | Detached exports, checkpoint observation, transfer success/failure contracts |
| W25 | Scalar prefixes, zero quantum, checked faults, collection-boundary cuts |
| W26 | Actual threshold neighbors and required dead-backing public pauses |
| W27 | Direct/captured/retained aliases, resumption/cleanup fixtures, alias scaling |
| W28 | Compatible/fallback calls, wide layouts, exact classes, custody and leases |
| W29 | Bidirectional matching-image transfer and suspended cleanup |
| W30 | Node, Wasmtime, real browsers, handles, reentry and capacities |
| W31 | A0 assertions plus exact 18-image / 662-command candidate replay |
| W32 | Both frozen primary live-Resident WASM wins, five windows each |
| W33 | Timing rule, raw inconclusive cells, working/static-owner memory accounting |
| W34 | Complete preparation-to-release totals; rejected and failure/retry paths |
| W35 | Backup/reconstruction ablation; one canonical implementation |
| W36 | Independent W0 bytes, source oracles, preserved assertions and corrected samplers |
| W37 | Exact-head producer, authenticated acquisition and offline smoke receipts |
| W38 | One early unique draft PR #61 assigned to tkersey, unmerged |
| W39 | P0/P1 and native CAS owner receipts in the PR closure record |
| W40 | Separate construction, semantic, economic and evidence-limit claims |

## Failed routes and limits

The archived `5c940d0` run has real tail-dispatch regressions. The `36b7fa5` correction
has native fresh-replay regressions. `9e96722` still fails three smaller gates. These
heads are not accepted candidates. Bounded lookup/cache/inlining ablations led to the
current smaller key check without an optional tag; only the final runtime earns current credit.
No claim that every possible program becomes faster is made.

The historical blob relative-improvement assertion fails even for W0 versus itself.
The corrected oracle checks each arm's own pre-pause live bytes, independently requires
dead large backing below 8192 paused bytes, and preserves live aliases. The original
failure and source-grounded correction are retained separately from speedup claims.

Historical Review Fold projection returned `InvalidStoreBinding`; no predecessor custody
was repaired. Its horizon is incomplete, so this task makes no historical absence,
first-occurrence, or recurrence claim. Current witnesses retain their original subjects.
Root model/reasoning identity is not independently observable; available native usage
snapshots and CAS receipts are reported without invented totals or model attribution.
