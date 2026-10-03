# Direct-slot rollback repair

This is the authorized post-comparison repair of PR #61. The original reports,
comparison endpoints and usage cutoff remain historical and unchanged. PR #61 is
the selected implementation; PR #60 was closed without merging or deleting its
branch or artifacts. The accepted specification remains
`d914b959e32d10b841e549cb27665689c419856e5b77ae632363fb71b22e92f3`.
The later user direction limits further optimization of sub-100-ms work and
accepts remaining tiny timing regressions after the prior bounded attempt. That
allowance does not waive correctness, memory, package or review obligations.

## Reproduction and source identities

| Source | Commit | Unprotected Session slot write, then rollback |
|---|---|---|
| W0 | `c61edfc8208c375d5188e476131ca8cff5aeeb8a` | Pass |
| Original and initial current #61 | `9f771c47701bf5cdfc2db0b3c0e0e71b8daba751` | Fail: changed value survives |
| Frozen #60 | `750f8ec74f909735c96992eb05bfe0c22904526e` | Pass |
| First repair | `eba184266c046559f8255cfde2b21caf3bdef016` | Pass; later removal witness fails |
| Corrected repair | `63990c45f2f39d34ea04dba4ee8194b8c5df470b` | Pass; removed-handle witness also passes |

[`direct_slot_rollback.zig`](../test/current/direct_slot_rollback.zig) runs the same
operation sequence against each implementation and the same frozen H image. It
obtains a registered descriptor, saves a canonical checkpoint, begins a Session
transaction, changes an existing scalar slot through `frames.slots.set`, rolls
back, and checks both the entry value and byte-identical checkpoint. It never
obtains a protected frame mutation in that transaction. The original and initial
current #61 heads were identical, so their reproduction is one bound result.

The same probe's `removed` mode then found an additional lifetime bypass in the
first repair: remove the registered frame, attempt a direct write through its
previous descriptor, and roll back. W0 and #60 reject that old handle and restore
the entry state. The first repair accepted the write and restored the changed
value. Its untouched-removal optimization had transferred the original handles
into the journal, leaving that saved owner accessible to old descriptors.

W0's `Session.begin` calls `Frames.backup`, which forks every registered frame's
slot and custody views. Its rollback restores those saved frames before Store
rollback. `Frames.get` returns a descriptor without a restriction against reading
or replacing its initialized slots; the exposed Slots mutation APIs replace
values without consuming the view, and the witness preserves the value's schema.
The executed W0 result therefore establishes the
relevant pre-existing rollback behavior. The repair does not invent a restriction
requiring callers to use `Frames.write` first.

The data dependency remains D0 `511fe388587b36ae37307d277e04c22b0bb6f6d9`.
The separate compiler input remains C0 `65f46131f366bdd21aa98701f4110ecb801d2c8d`.
Agent A0 `b1f9d2866b5717d16339e7022a3b4d08951f0770` and historical harness B0
`93340dade30b7d27a1e139f107359f91fb66fad3` retain their original roles. Neither
dependency nor Agent's historical runtime lock is changed.

## Ownership repair and coverage

Registered slot and custody views carry their containing frame ID. During an
active frame transaction, their destructive root operations call the existing
frame journal before mutation. A private callback derives the current containing
Frames address from the embedded store address; it retains no pointer to a prior
location of the owner. Protection can grow the view table, so mutation reacquires
its view pointer afterward.

The first call saves the complete transaction-entry frame through the existing
inline journal entry and semantic root forks. Later root or metadata mutations,
removal and replacement find that same saved entry. There is no second root
journal or later-version rollback owner. Commit releases each saved owner;
rollback restores saved frames before Store restores its heap journal. Both
paths clear the callbacks before releasing views. Semantic forks clear the
frame association and remain independent. The copied Frame's old `owner_id` was
deleted; frame-wrapper protection and direct-root protection now consult the
same root association.

Untouched removal now transfers each root under a fresh handle generation. Both
slot and custody generations are checked before either changes, and journal
capacity is reserved before the transfer. Renaming itself allocates nothing and
copies no root. Old descriptors, readers and iterators reject immediately. If a
generation is exhausted, the existing first-touch COW path retains the entry
version and permanently retires the exhausted view. This is per-entry protection,
not an all-frame backup mode. Tests cover exhaustion of either or both roots,
replacement, an independent semantic fork, and rollback.

The source-derived root-writing surface is `Slots.change` (set/clear), `commit`
and `retainOnly`; each crosses this cut after argument validation and before
destructive publication. Custody uses the same generic Slots implementation.
Create/fork construct independent roots, and frame registration associates them
at put/update/restoration. `get`, readers and iterators do not manufacture saved
versions. Raw frame-pointer mutation keeps the existing getMutable/pre-entry
borrow protection. Consuming a view still requires owning it: releasing a root
while a registered Frame continues to own that handle leaves a dangling owner
even in W0. Arbitrary frame-map/representation corruption is outside this claim.

Tests retain PR #60 commit/test provenance for:

- direct root mutation followed by late frame protection, metadata mutation,
  removal and replacement;
- allocation-disabled rollback and both iterator versions;
- copied descriptors surviving frame-map and view-table growth;
- live-owned unwind, failure at each allocation and unchanged-state retry.

The iterator oracle preserves #61/W0's existing handle semantics: rollback
replaces the tentative frame with the saved frame, so the retired handle returns
`InvalidHandle`. #60 restores the root in its original handle and returns
`StaleIterator`. Both reject obsolete iterators before accessing freed nodes.

Additional tests exercise descriptor acquisition before/after begin, direct
clear/retainOnly/commit, custody mutation before later slot/metadata mutation,
semantic forks retained before/during a transaction, first-touch failure and
retry at widths 1/65/1024, allocation-disabled rollback, generation exhaustion,
and repeated commit/rollback without retained transaction-only history.

#60's pre-entry borrow witnesses are covered by the existing multiple-borrow,
begin-failure/retry and copied-descriptor tests. Its stale-binding/scoped-callback
cases depend on obtaining `resident.session` or `Frames.withMutable`; #61 exposes
neither. Resident's private State owns the Session and one expected identity, and
its observation methods return values rather than mutable engine borrows. The
separate low-level `Session.answer` always derives its current pending request
before shared response admission. The existing cancellation-rebinding test
rejects the predecessor response after a lawful Session mutation. No distributed
observation flags or scoped-callback API were imported.

## Current qualification

At implementation commit `63990c45f2f39d34ea04dba4ee8194b8c5df470b`, the repair
passed both same-image discriminators, 90 storage tests, 26 activation tests and
93 native semantic tests, including allocation-failure sweeps. Normal
clean-source runtime preparation passed the aggregate platform/package checks; authenticated
acquisition and moved, source-independent `runtime verify --smoke` also passed.
The extended fixed harness passed H/Q completion, failure/retry, scalar/tail/blob
preservation, native/WASM agreement, fresh-process transfers and browser Workers.

Successful H mutation still saves/commits one entry and allocates 928 bytes at
both depth 1 and depth 1024. Q's three invalid replies allocate 762 bytes and
perform no repeated State projection. These are actual Resident measurements;
the separate first low-level Session transaction retains Store's existing
extent-dependent scratch allocation and is not claimed to allocate constant
bytes. No all-frame frame-journal traversal was added.

The corrected measured kernel is
`66c2b9fcf12cd97b07945053c0204e21c0e27a5aef2959d6ccdd7471fdf7d10c`, 478,000 bytes
(816 bytes above original #61). Fixed owner storage increases by eight bytes
relative to original #61: native Resident 1,792 bytes; WASM optional Resident
1,224 bytes. Working peaks, live retention and reserved pages are measured
separately rather than substituted for those fixed values.

## Comparable H/Q measurements

All four kernels use the same frozen images, inputs, limits, controls, 3 warmups,
9 samples and 5 alternating windows. H includes checkpoint export without a
restore in the timed interval, consistently for every arm. Separate transfer
checks retain restoration coverage. These measurements do not compare #60's
historical 9.05% and #61's historical 18% headlines as identical workloads.

| Complete lifecycle | W0 | Original #61 | Frozen #60 | Corrected #61 |
|---|---:|---:|---:|---:|
| H, depth 1 | 0.945 ms | 0.929 ms | 0.940 ms | 0.933 ms |
| H, depth 1, failure/retry | 0.980 ms | 0.972 ms | 0.992 ms | 0.983 ms |
| H, depth 1024 | 37.047 ms | 30.383 ms | 31.823 ms | 30.271 ms |
| H, depth 1024, failure/retry | 38.301 ms | 31.707 ms | 33.289 ms | 31.340 ms |
| Q, depth 1 | 0.571 ms | 0.566 ms | 0.569 ms | 0.567 ms |
| Q, depth 1, failure/retry | 0.616 ms | 0.616 ms | 0.613 ms | 0.613 ms |
| Q, depth 1024 | 32.892 ms | 30.329 ms | 30.977 ms | 30.112 ms |
| Q, depth 1024, failure/retry | 34.871 ms | 30.964 ms | 31.946 ms | 31.706 ms |

The corrected normal H/Q depth-1024 paired ratios versus W0 are 0.8171 and
0.9143; both win in all five windows. The acceptance reference remains W0.
All four arms also have separate per-command memory observations in the same
common-HQ report.

The extended economics, conservative owner-memory account, bounded attribution
and lifetime/transfer checks below all completed on that implementation. The
final documentation commit’s package identity and serial-review disposition are
recorded in PR #61’s current proof block, rather than predicted by this report.

## Obligation cross-check

The accepted W01–W40 obligations remain the review scope. The follow-up user
instruction extends W38 only to authorize reading #60 and adapting applicable
witnesses; it does not authorize merging either PR or changing upstream inputs.

| Obligations | Current deciding evidence |
|---|---|
| W01–W02 | Fixed input identities above; normal runtime build manifest; four-arm same-image harness hashes. |
| W03 | Native storage suites and semantic fork tests preserve packed semantic roots and deliberate shared state. |
| W04–W05 | Actual retained-history counters at depths 1/16/64/256/1024; read-descriptor and pre-entry borrow tests. |
| W06–W07 | Direct first-touch failure/retry at widths 1/65/1024; late protection restores the first entry version. |
| W08–W09 | Membership/reuse tests; removed descriptors, readers and iterators reject; either/both root generation exhaustion tests. |
| W10–W11 | Independent forks before/during a transaction; slot/custody and metadata tests; copied descriptors survive map/view-table growth. |
| W12–W13 | Store transaction and failure-injection tests; allocation-disabled rollback; repeated commit/rollback releases saved roots. |
| W14 | Resident publication failure/retry suite and extended H/Q failure schedules. |
| W15 | Working/live/reserved observations plus repeated-lifecycle plateau qualification. |
| W16–W18 | Exact canonical requests and Q invalid-reply schedule; shared response admission tests. |
| W19–W20 | Cancellation-rebinding and failed-response-publication retry tests; private Resident expected identity. |
| W21–W22 | Fresh-process transfers; low-level Session computes current request; direct Session regressions remain lawful. |
| W23–W24 | Source shows one expected identity, no duplicate State graph; checkpoint ownership/transfer/capacity suites. |
| W25 | Exact scalar prefixes, zero quantum and checked-failure/platform probes. |
| W26–W27 | Blob platform reclamation, captured/indirect/cleanup aliases and alias scaling checks. |
| W28 | Frame and sparse/wide layout semantic and cost matrices; Prepared-owned compatibility remains unchanged. |
| W29–W30 | Native/Node/Wasmtime transfer, fresh process and browser Worker checks; normal aggregate runtime package tests. |
| W31 | Frozen Agent consumer assertions and exact 662-command replay manifest, native and WASM qualification. |
| W32 | H and Q complete Resident lifecycles meet the five-window win rule against W0. |
| W33–W34 | Full economic summary, per-command memory, fixed owner account and separately reported setup/teardown costs. |
| W35 | One existing frame journal now receives direct root mutations; redundant Frame owner field removed; fresh-generation ownership transfer. |
| W36 | Native tests and W0 exact outcome/checkpoint oracles preserved; historical sampler memory-reset issue is kept separate. |
| W37 | Normal clean-source preparation, authenticated acquisition and moved source-independent smoke; final documentation head binding below. |
| W38 | #61 remains the selected draft assigned to tkersey; #60 closed without merge, branch or artifact deletion. |
| W39 | Original comparison endpoints/cutoffs preserved; follow-up driver/review usage separately reported with unavailable values marked unknown. |
| W40 | This report separates source, semantic evidence, economics, delivery and remaining limitations. |

This matrix maps the completed implementation qualification. W37’s final
documentation-commit delivery and W39’s fresh serial-review disposition are
recorded in the current PR proof block. A review receipt is not a substitute
for any of the semantic or economic evidence above.

## Retained evidence and reproduction

Raw follow-up evidence is retained at
`/Users/tk/workspace/tk/world-evidence-01a0fc7f/followup/`; the corrected extended
reports are under `rekey-qualification/`. The original portable frozen-image and
consumer corpus remains in `docs/resumable-evidence.tar.gz` and the original
qualification report remains historical. No second bulk archive is added.

The reproduction below uses the same D0 checkout for all source revisions. Set
`world_task_source` to an exact W0, original #61, #60 or corrected source checkout,
and `world_task_data` to D0. `world_task_probe` is this checkout’s
`test/current/direct_slot_rollback.zig`; `world_task_image` is frozen `H.bpi3`.

```sh
zig run -O ReleaseSafe --dep runtime -Mroot="$world_task_probe" \
  --dep boundary_data -Mruntime="$world_task_source/src/interpreter_v2/stable_session.zig" \
  -Mboundary_data="$world_task_data/src/data/root.zig" -- "$world_task_image" direct
```

Run the same command with final mode `removed` for the removed-descriptor
discriminator. Both modes assert the transaction-entry value and exact canonical
checkpoint; `removed` also requires rejection of the old handle.

The original report’s build instructions reproduce the fixed native comparison
tools. The corrected source uses the same existing `test/current` probes:

```sh
node test/current/retained_history_wasm.mjs sample "$world_task_embedding" \
  "$world_task_kernel" "$world_task_image" H 1024 "$world_task_record" normal
node test/current/retained_history_wasm.mjs memory "$world_task_embedding" \
  "$world_task_kernel" "$world_task_image" H 1024 "$world_task_record" normal
node test/current/retained_history_wasm.mjs plateau "$world_task_embedding" \
  "$world_task_kernel" "$world_task_image" H 1024 "$world_task_record" normal
```

Use Q’s image/record and mode Q for its cases; failure cases use the frozen
failure manifest and final profile `failure`. The common report records all
eight case inputs, actual kernel hashes, five windows and separate memory phases.
`bounded-attribution.json` retains each scalar/tail/blob sampler and its exact
arguments. Native/WASM consumer reports bind the same original 662-command
manifest and command hashes. These are runtime replays, excluding external model
and host-service latency; they do not claim a new end-to-end Agent model trial.

## Memory and lifecycle phases

These depth-1024 normal-case observations sample every command before the next
command can reset its peak. All arms finish with zero working-live bytes.

| Mode / source | Working peak bytes | Paused live bytes | Reserved WASM bytes |
|---|---:|---:|---:|
| H / W0 | 2043439 | 1342814 | 2752512 |
| H / original61 | 1993903 | 1260510 | 2818048 |
| H / control60 | 1961135 | 1244126 | 2949120 |
| H / repaired61 | 1980927 | 1263918 | 2621440 |
| Q / W0 | 2113373 | 1342541 | 2752512 |
| Q / original61 | 2063837 | 1260237 | 2818048 |
| Q / control60 | 2031069 | 1243853 | 2949120 |
| Q / repaired61 | 2050861 | 1263645 | 2883584 |

The corrected pause retains 3,408 more bytes than original #61 in these cases,
while remaining below W0. Reserved Q memory is 131,072 bytes above W0; this is
reported separately from the accepted live-working allocation guard. The
corresponding H reservation is 131,072 bytes below W0. No default arena, stack
or maximum-page setting was enlarged.

The raw memory rows also preserve cold instrumented phase times for preparation,
start, initial observation, export, cancellation, close and release. These are
single diagnostic runs with measurement overhead, not paired latency claims.
For corrected H their values are 4.361, 0.832, 33.256, 1.927, 2.476, 0.103 and
0.055 ms respectively. Corrected Q preparation/start/initial observation are
4.366/0.827/35.691 ms; cancellation/close/release are 2.354/0.116/0.059 ms.
The five-window latency measurements include cancellation, close and release in
the total; their work is not deferred outside the denominator. Kernel creation
and cold-ramp observations are separately retained by the scalar/tail/blob
samplers and are not presented as warmed execution costs.

## Full economic guard results

All 360 required timing cells completed, including 60 WASM and 60 native consumer
cells over the frozen manifest. Neither consumer matrix has a confirmed slowdown
or memory flag. Blob/alias and complete native H/Q/blob lifecycle matrices also
have no confirmed slowdown or memory flag. The raw summary retains smaller and
inconclusive changes; they are not rounded into zero.

16 cells exceed the original 5% repeated-window timing guard. All are
sub-100-ms operations and fall under the later bounded-optimization direction;
no new tuning attempt budget was started after either correctness fix. The
following costs remain visible rather than being classified as performance wins.
Ratios are medians of paired-window ratios; times are medians of window medians.

| Cell | W0 µs | Corrected µs | Paired ratio | Added µs |
|---|---:|---:|---:|---:|
| scalar-native-timing / 4 ops / prepared | 1.432 | 1.537 | 1.0699 | 0.105 |
| scalar-wasm-timing / 256 ops / prepared | 46.302 | 50.974 | 1.1013 | 4.672 |
| scalar-wasm-timing / 1024 ops / prepared | 157.523 | 174.120 | 1.1013 | 16.596 |
| frame-timing / wasm / compatible / n 128 / fresh | 134.633 | 146.897 | 1.0949 | 12.264 |
| frame-timing / wasm / compatible / n 512 / fresh | 477.248 | 527.079 | 1.1098 | 49.831 |
| frame-timing / wasm / fallback / n 128 / fresh | 151.589 | 164.048 | 1.0837 | 12.460 |
| frame-timing / wasm / fallback / n 512 / fresh | 543.261 | 588.973 | 1.0835 | 45.712 |
| layout-timing / wasm / compatible / width 4 / n 8 / fresh | 31.215 | 36.777 | 1.1606 | 5.562 |
| layout-timing / native / compatible / width 4 / n 1000 / resident | 435.125 | 465.292 | 1.0725 | 30.167 |
| layout-timing / wasm / compatible / width 4 / n 1000 / resident | 996.583 | 1120.541 | 1.1249 | 123.958 |
| layout-timing / wasm / fallback / width 4 / n 1000 / resident | 1158.625 | 1270.583 | 1.0961 | 111.958 |
| layout-timing / native / compatible / width 4096 / n 1000 / resident | 540.583 | 568.125 | 1.0585 | 27.542 |
| layout-timing / wasm / compatible / width 4096 / n 1000 / resident | 1180.458 | 1320.167 | 1.1252 | 139.709 |
| layout-timing / wasm / fallback / width 4096 / n 1000 / resident | 1499.042 | 1616.209 | 1.0767 | 117.167 |
| layout-timing / wasm / compatible / width 65536 / n 1000 / resident | 1221.500 | 1377.583 | 1.1320 | 156.083 |
| layout-timing / wasm / fallback / width 65536 / n 1000 / resident | 1661.625 | 1809.375 | 1.0856 | 147.750 |

Six associated cold-ramp totals also exceed 5%; these sums retain repeated
operations during engine tier-up. They are not single-operation latency:

| Sampler cell | W0 ramp ms | Corrected ramp ms | Paired ratio |
|---|---:|---:|---:|
| scalar-wasm-timing / 256 / prepared | 15.340 | 16.332 | 1.0649 |
| scalar-wasm-timing / 1024 / prepared | 37.428 | 40.582 | 1.0872 |
| frame-timing / compatible / 128 / fresh | 125.546 | 134.786 | 1.0705 |
| frame-timing / compatible / 512 / fresh | 383.401 | 419.960 | 1.0977 |
| frame-timing / fallback / 128 / fresh | 138.231 | 147.218 | 1.0666 |
| frame-timing / fallback / 512 / fresh | 434.963 | 471.421 | 1.0835 |

The scalar cold totals cover 192 invocations (12 batches of 16); the fresh-tail
totals cover 768 invocations (12 batches of 64). No engine-setup observation has
a confirmed greater-than-5% increase under the same paired-window rule.

The conservative fixed-owner memory account passes all 1,054 observations. It
adds the complete extra native Resident footprint of 320 bytes, or WASM optional
Resident footprint of 280 bytes, to every observed W0 working-peak delta before
applying `max(1024, ceil(1% of W0 peak))`. This overcounts cases without a live
Resident and takes no credit for the smaller transaction value. It is not a
process-RSS or maximum-stack-depth claim. No memory tradeoff waiver is used.

## Attributing the repair

The following bounded check uses W0, original #61 and corrected #61 in the
same existing sampler, with 64 warmups, nine samples and five alternating
windows. These are separate attribution windows, not replacements for the
360-cell qualification. Setup and cold-ramp values remain in the raw report.

| WASM cell | W0 µs | Original #61 µs | Corrected #61 µs | Corrected / original paired ratio |
|---|---:|---:|---:|---:|
| scalar-prepared-256 | 46.388 | 46.872 | 50.820 | 1.0817 |
| scalar-prepared-1024 | 157.661 | 158.550 | 173.182 | 1.0904 |
| tail-compatible-512-fresh | 476.120 | 482.294 | 529.933 | 1.0988 |
| tail-fallback-512-fresh | 543.953 | 554.268 | 588.682 | 1.0621 |
| blob-unique-65536 | 42.474 | 42.417 | 42.359 | 1.0031 |
| blob-captured-65536 | 45.922 | 46.365 | 46.859 | 1.0107 |
| blob-alias-1048576 | 648.229 | 646.141 | 645.817 | 0.9972 |

The direct-root protection adds observable scalar and fresh-tail cost; the
selected blob lifecycle changes are small. All three arms’ blob working peaks
and reserved memory are separately captured after each command.

Eight corrected H/Q cases (depth 1 and 1024, normal and failure/retry) each pass
64 complete lifecycles, with identical peak/live/reserved tuples from cycle 16
onward and zero working-live bytes after each release. The source suite also
retains its repeated native commit/rollback checks.

The bounded #60 transfer cross-check passes 12 fresh-process cases against
original #61 and another 12 against corrected #61, at depths 1/64/1024 in both
directions for H/Q. Node and Wasmtime restore and continue the exported State,
reject invalid replies, cancel and release with matching canonical outcomes.
W0 is the independent native reference in these two checks; no native #60
qualification is claimed. The separate full W0/corrected pipeline also passes
browser Worker transfers and native↔WASM equivalence.

## Delivery, review and evidence limits

The normal implementation package at `63990c4` was authenticated and moved to
a path containing spaces; `runtime verify --smoke` passed from `/tmp`. Its
kernel is the qualified 478,000-byte image above. W0, original #61 and #60
kernels are respectively 470,027, 477,184 and 486,492 bytes. The corrected
profile remains import-free wasm32, 23 exports, no start function, 18 initial
pages, 4,096 maximum pages, unshared 32-bit memory and a 65,536-byte stack.
Default input/working/output limits remain 65,536/1,048,576/65,536 bytes.
The build uses Zig 0.16.0, ReleaseSmall kernel and ReleaseSafe host; Node
measurements use 26.10.0 on Darwin arm64.

The final documentation commit receives its own normal clean-source runtime
preparation, acquisition and moved smoke check. Byte equality to this qualified
kernel is required before reusing its measurements. The resulting exact
head/archive/manifest identities, build duration and serial-review disposition
belong to PR #61’s current proof block. No predecessor bundle is substituted
under Agent’s historical lock.

Current source witnesses and executed checks support the scoped rollback and
lifetime claims. Canonical Review Fold history projection was unavailable
(`InvalidStoreBinding`), so this report makes no first-observed or complete
historical-family claim. Canonical learning capture was likewise unavailable
under the existing custody binding; no store was bypassed or replaced. This
does not relabel either unavailable projection as a successful check.

The original model comparison and usage cutoff are unchanged. Follow-up driver
totals are unknown: the available goal counter is a stale partial observation
(97,297 tokens and 369 seconds, last updated before most follow-up execution),
not a completed accounting interval. Fresh reviewer usage and elapsed time are
reported separately from the current CAS receipts in the PR proof block. No
missing telemetry is treated as zero.
