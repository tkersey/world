# World/WASM — Change-Proportional Resumable Execution

**Complete implementation specification · Version 1.1 · September 30, 2026**

**Production repository:** `tkersey/world`  
**Task:** one independent implementation, qualification, and draft PR  
**Inputs:** fixed Boundary data/compiler dependencies and fixed Agent applications  
**Execution:** `$actuating serial-reviews`  
**Status:** post-merge implementation handoff, grounded in the landed Boundary #161, World #59, and Agent #39 sources. The next-task optimizations and their performance gains have not been implemented or measured by this document.

> Make ordinary progress pay for the state it changes and the observations it must produce—not repeatedly for all the possibilities the computation retains.

This is a complete specification. It contains the engineering requirements, bounded implementation sequence, acceptance cases, measurement protocol, delivery contract, and full launch prompt. No previous specification, experiment operator, launcher, private setup directory, or preparation record is required.

The same file is suitable for separate coding-agent sessions. The user selects each session's model and reasoning level. Each session implements only its own candidate and creates its own unique World branch and draft PR. The implementation does not depend on knowing that another candidate exists.

**Revision 1.1:** pins the actual landed inputs; retains the completed optimization programme rather than reopening it; protects the newly landed sparse-page packing and Prepared-owned layout index; incorporates the repaired WASM peak-observation discipline; and separates frozen consumer replay from the new resident-lifecycle measurements. The three required outcomes and W01–W40 remain. This file replaces version 1.0 in full, including its launch prompt.

## Contents

1. Decision, scope, and authority
2. Starting point and reproducible inputs
3. Source-grounded opportunity map
4. Preserved execution and ownership contracts
5. Required outcome A: change-proportional transactional retention
6. Required outcome B: reuse of unchanged pending-state observations
7. Required outcome C: complete-lifecycle efficiency and prompt reclamation
8. Workload and discriminator contract
9. Correctness qualification
10. Performance acceptance
11. Implementation order and mandatory ablation
12. Workflow, independent runs, and delivery
13. Complete launch prompt
14. Acceptance matrix
15. Source and skill provenance

---

## 1. Decision, scope, and authority

### 1.1 Required result

Implement three connected outcomes in World's existing runtime:

**A. Change-proportional rollback preparation.** A bounded resident drive that changes a small set of frames must not enumerate, duplicate, fork, or release every dormant frame solely to establish or discard transaction rollback state.

**B. Reuse of unchanged pending-state observations.** After an exact pending-request binding has been established, the controlled resident path must not reconstruct the entire unchanged parked computation solely to verify a subsequent response against that binding. Reuse must be justified by ownership and complete invalidation coverage, not by an unverified cache key.

**C. Complete-lifecycle improvement.** Deliver a reproducible WASM improvement on the prescribed resident workloads, while preserving prompt reclamation, required throughput, exact logical observations, failure-atomic publication, and portable checkpoints. Measure the complete bill, including preparation, maintenance, invalidation, rollback, export, cancellation, and release.

All three outcomes are required. They need not be implemented by three separate mechanisms. Existing code that already meets an outcome at the selected starting point should be retained and demonstrated, not replaced merely to manufacture a new contribution.

The core production changes must live in World. Boundary's accepted compiler and mandatory coalescing remain fixed inputs. Agent's authored policies and applications remain fixed consumers.

### 1.2 What is selected—and what is not

The selected architecture is **one existing evaluator, with better placement and lifetime of its physical bookkeeping**.

The following are hypotheses, not mandatory designs:

- First-touch frame journaling.
- A persistent frame-map root or another shared rollback representation.
- A bounded resident-owned expected-request identity.
- Reuse of immutable facts already owned by `Prepared`.
- Less intermediate outcome or checkpoint materialization.
- Bounded active-frame access or scalar execution improvements.

Choose the least elaborate construction that satisfies the required outcomes and evidence. Do not turn a suggested mechanism into an additional acceptance requirement. A well-justified alternative is welcome; weakening the outcome is not.

### 1.3 Canonical adoption and ablation

The selected successor becomes the canonical production implementation. Migrate its actual internal callers and remove the bookkeeping it supersedes as part of the same replacement slice.

Do not ship an old/new transaction selector, a public optimization bypass, a “safe but slow” predecessor alongside a new default, or duplicated request-validation pipelines. Temporary coexistence during development must not survive delivery.

Necessary semantic cases are not legacy alternatives. Fresh invocation and resident execution serve different public lifecycles. Shared and unique storage need different lawful operations. A general instruction path remains necessary where a specialization does not apply. Preserve these distinctions under one coherent implementation.

Historical executables, immutable source snapshots, and narrowly scoped uninstalled test references may remain as evidence. They must not become production fallback routes.

This task does **not** begin with a repository-wide cleanup campaign. Its ablation scope is the mechanisms actually displaced by these outcomes.

### 1.4 Hard exclusions

Do not introduce:

- SQLite, another database, filesystem persistence, a durable-session service, an inbox/outbox, or environmental-operation retry orchestration.
- A new interpreter, JIT, serialized microcode, portable image/State family, application-specific kernel, optimizer service, or general cache framework.
- A replacement collector campaign, concurrent collector, or distributed execution owner.
- A Boundary frontend migration, another optimization-package programme, or changes to Agent business logic.
- Skill-package edits, global configuration changes, restored retired workflow machinery, model switching, or a comparison-launcher system.
- Increased default memory, weakened validation, or disabled reclamation as a way to improve timing.

“Transaction” in this document means World's existing **in-memory unpublished-attempt rollback boundary**. It does not authorize persistent storage.

### 1.5 Authorized effects and limits

This handoff authorizes task-local code/test/documentation changes in World, isolated source/build workspaces, ordinary locked development-dependency acquisition through repository tooling, local verification, commits, pushes, and one new draft World PR assigned to `tkersey` for this independent execution.

Run deterministic Agent scenarios against isolated disposable fixtures. Existing local test tools may read/write only their task-owned fixtures. Paid model inference, production load, user-document modification, credentials export, releases, package publication, PR merging, and destructive cleanup of unrelated data are not authorized.

Use existing CI normally triggered by the authorized PR. Do not build a new delivery or CI infrastructure project. Do not manually launch paid or separately permissioned workflows merely to satisfy a report.

A genuine missing permission blocks the dependent operation, not unrelated authorized work. Never invent a successful build, qualification, artifact, review, or model identity.

---

## 2. Starting point and reproducible inputs

### 2.1 The preceding round has landed

The coordinated PRs were verified merged on September 30, 2026. Their actual landed commits, not their former draft heads, are:

| Repository / PR | Landed commit | Final reviewed PR head | Merge time (UTC) |
|---|---|---|---|
| Boundary #161 | `93340dade30b7d27a1e139f107359f91fb66fad3` | `705ddd0fa4517b844f1ae70d8df84b463fa113f4` | 21:34:21 |
| World #59 | `c61edfc8208c375d5188e476131ca8cff5aeeb8a` | `00624ed338aea8d1cb9a2b5437a5c414d8bb576a` | 21:35:07 |
| Agent #39 | `b1f9d2866b5717d16339e7022a3b4d08951f0770` | `5bf88f605ba5941d39c02e8ac4fb68c58104e244` | 21:35:32 |

The original version of this spec inspected World `e89b94ab32118efbad96cca5917f27ddb8510298` and an in-flight Boundary qualification account. Those are now historical investigation snapshots only. They are not this task's implementation base. [S01] [S12] [S14]

The closing PR accounts report the corrected cutover and bounded P01–P31 / T01–T42 / G01–G45 / L01–L20 programme complete, with final reviews closed. Do not reopen that programme, restart its reviews, finish its former authoring migration, or repair its historical evidence custody as a prerequisite. Preserve its accepted capabilities and tests. A newly demonstrated in-scope defect still needs an honest disposition under §2.6; merging is not a proof of universal correctness.

The prior SQLite/durable-session/recovery assignment remains cancelled. This is a new World-only runtime optimization task, not a correction of those merged PRs.

### 2.2 Fixed default starting tuple

Use the following immutable tuple unless the user explicitly selects a different complete immutable tuple. No merge-waiting, operator binding refresh, or moving-branch selection is required.

| Input | Fixed selection |
|---|---|
| World implementation base, **W0** | `c61edfc8208c375d5188e476131ca8cff5aeeb8a`; Git tree `87edc03ebb7b8b56facfe7f2e60845c5931f1834`. |
| World build-time Boundary data, **D0** | `511fe388587b36ae37307d277e04c22b0bb6f6d9`, as selected by W0's `build.zig.zon`; Zig package `boundary-3.0.0-dev.0-flclaGcPXAB8lBsvhVLPJFZmROkee3fHGfsloqpgeZSE`. |
| Agent consumer source, **A0** | `b1f9d2866b5717d16339e7022a3b4d08951f0770`. |
| Agent compiler dependency, **C0** | `65f46131f366bdd21aa98701f4110ecb801d2c8d`, selected by A0's `build.zig.zon` and `conformance/agent4/dependencies.lock.json`; Zig package `boundary-3.0.0-dev.0-flclaEdzRQBpnNrUM2gj62qP_jA65zcVHZgFfmxIPqxe`. |
| Boundary evidence/harness snapshot, **B0** | `93340dade30b7d27a1e139f107359f91fb66fad3`. This supplies the consolidated acceptance and existing comparison harness sources; it does not replace D0 or C0. |
| Toolchain/profile | Zig `0.16.0`, Node `26.10.0`, the locked Wasmtime/browser test dependencies, native ReleaseSafe qualification, and the normal ReleaseSmall wasm32 kernel build. Use identical versions/options within comparisons. Platform-specific executable digests in historical locks are provenance, not a demand that another platform have identical binaries. |

D0 and C0 are deliberately different. A newer merged Boundary revision is not permission to repin either, rebuild the kernel against the full current frontend, or alter the frozen application corpus. The sources record compatible execution of the selected compiler output on the selected data/runtime profile. Confirm baseline execution of this task's actual inputs rather than inferring universal compatibility. [S15] [S16] [S17]

A0's existing authenticated runtime binding names World source `a48d5fd0cb2d4fcbe79bc3188f354d7d036d29f5`, kernel SHA-256 `9627eb1e66239119bccb4ddcd43b4f6c757180dab930a9feb276671262f735d1` (470,027 bytes). The final qualification reports that later World changes through the reviewed head affect evidence/samplers, not the qualified product/build inputs. This delivery identity remains an independent historical reference; **W0 above is the implementation base**. New candidate kernels have their own identities. [S18]

The recorded existing delivery is Actions run `36726709618`, artifact `11103177889`, named `world-runtime-a48d5fd0cb2d4fcbe79bc3188f354d7d036d29f5`. A0's lock supplies its transport and manifest authentication values and records expiration on October 30, 2026. Verify actual availability when using it. A missing/expired artifact does not block rebuilding W0 or justify fabricating an old delivery receipt; use §2.4's source-based route. [S17]

Fetch exact commits through the existing repository tooling and record their trees/locks. Do not resolve “latest main” at either run's start or during later phases. Record a discrepancy without silently choosing another input. Both independently started sessions receive these same immutable selections; neither needs to inspect the other session.

If an exact source or required tool cannot be acquired, identify that specific blocked operation and continue independent authorized work. Do not ask for a custom launcher or restore an old comparison setup. A user-selected replacement tuple must be explicitly applied to both comparison runs to preserve a matched experiment.

### 2.3 One bounded input record, not a setup system

At entry, record W0, its tree, D0, A0/C0, the spec digest, relevant installed skill identities, tool versions, build modes, and observed resource limits in the existing task/report mechanism.

Create an isolated candidate workspace on a unique branch from W0. Keep a separate immutable W0 source/build for differential execution. Do not modify another session's worktree, stores, branches, outputs, or mutable caches.

Only input selection requires an immutable base. Legitimate candidate edits must not later fail a “still equal to W0” or “entry worktree still clean” gate. Candidate tests bind the actual candidate commit/tree; baseline tests remain bound to W0.

No custom binding schema, manifest-verification service, launcher, config export, scoped Codex-home generator, or shared preparation operator is part of this task.

### 2.4 Build the kernels that are actually being compared

Build the baseline native runner and WASM kernel from W0/D0, and each candidate's native runner and WASM kernel from that candidate with the same D0.

**Kernel bytes are outputs of this task and are expected to change.** Do not demand that a candidate reproduce the baseline kernel digest. Record separate source, executable, kernel, package, and measurement identities.

Use World's existing build and authenticated runtime prepare/acquire/verify routes where they apply. A missing historical cached kernel is not a prerequisite failure: reproduce the baseline from W0/D0 through the normal build. Build the candidate through that same owner. The former a48d5fd transport is not a mandatory shared kernel artifact, and its qualification must not be relabeled as candidate qualification.

The kernel profile remains ABI 3, import-free wasm32, with the existing 64 KiB stack and 256 MiB maximum memory. The recorded qualified kernel has 18 initial memory pages and default input/working/output budgets of 64 KiB / 1 MiB / 64 KiB. Verify the actual built profile; preserve the declared defaults and distinguish reserved memory from requested live allocation.

Do not create a second acquisition mechanism, blindly select an arbitrary cached kernel, relabel an old qualification record, or alter producer metadata to claim a different source. A self-computed hash identifies local bytes; it is not an external authenticity anchor. Preserve the existing trusted-delivery boundary.

Local experimental kernels are legitimate for development and paired measurements when accurately identified. Complete the repository-required package/delivery qualification on the final candidate. Do not perform full runtime production and browser qualification after every local edit.

### 2.5 Freeze the programme being executed

Emit the application corpus from A0/C0 once per independent run and freeze the exact BPI3 bytes, arguments, permitted reply values, and logical input schedules before candidate performance measurement. Preserve the selected compile policy and mandatory coalescing.

Additional test emitters may live under World's test surface and use the fixed compiler as a test-only dependency. Production World must continue importing Boundary's pure data module only.

Build or copy an existing deterministic test harness into World's test area when necessary to exercise A0 against candidate kernels. This may select runtime bytes through supported APIs; it must not rewrite Agent policies, approvals, sandbox behavior, or authored computations.

A0's existing dependency verifier correctly rejects a candidate kernel presented under the unchanged historical lock. Do not disable that verifier or replace digests in A0's tracked lock to make candidate integration pass. Keep ordinary A0 qualification against its own binding separate from candidate runtime execution of the frozen application images and responses. A narrow World test adapter may supply the actual baseline/candidate bytes and identities directly to the existing public Kernel API, or consume a legitimately produced candidate bundle through its real descriptor. This is test wiring, not another runtime acquisition system or a fabricated upstream qualification. Local build hashes identify controlled experimental bytes; they are not external authenticity claims.

Retain A0's final-link profile forwarding and selected compilation policy. The shipped compiler already validates supplied profiles at the closed compiled-tool/participant link; do not count restoring that behavior as a new World optimization. [S19]

D0 and C0 can be different legitimate versions only when the baseline admits and correctly executes the frozen corpus. Report a real incompatibility; do not update either dependency, vendor Boundary code, or “fix” Agent to conceal it.

### 2.6 Keep baseline changes honest

The merged-source inspection confirms that outcomes A and B remain live opportunities at the fixed W0 (§3). Reproduce their witnesses before mutation. If the user selects a different immutable tuple, check whether either outcome already holds there.

If an outcome already holds, retain it with evidence and work on the remaining outcomes. Do not restore an old defect to create an optimization win. Do not use this refresh to broaden scope into unrelated hotspots.

A baseline defect in a required scenario must be distinguished from a candidate regression. Preserve the original result, establish the intended contract from current sources, and isolate any necessary in-scope correction from performance attribution. An out-of-scope dependency defect is an exact obstruction, not authority for another cross-repository assignment.

### 2.7 Closed upstream obligations and evidence chronology

The consolidated acceptance records the user's acceptance of **all then-recorded costs**. Preserve those exact historical observations and their accepted disposition. They are neither unaccepted gates to reopen nor permission for arbitrary new regressions from W0. The current task's additional costs are governed by §10. [S11]

The final reported coverage includes 18 unchanged application images, 18 admission and 30 named replay cells per engine, and 491 recorded commands in each replay corpus. The 48 local native and 48 local WASM admission/replay cells pass their stated local gates. Cumulative comparisons still disclose accepted costs, including review-model admission around 15% above its older baseline and 21 WASM memory-threshold exceedances. These are different denominators and baselines; do not combine them into a net speedup or count them as new-task H/Q resident measurements. [S18]

Committed reports and A0's lock retain historical phrases such as “reviews remain open” and “candidate-integration.” The closing PR accounts subsequently report final review closure and the provider confirms the merges. Treat those texts according to their timestamps and source roles; do not edit historical receipts, require a cosmetic lock/status rewrite, or reopen review campaigns to reconcile narration. Numerical evidence still belongs to the exact source/binary/sampler that produced it.

The final World measurement repair explicitly invalidates twelve earlier layout WASM admission/resident peak fields while retaining their historical timing samples. Use the corrected peak fields and current samplers, not an earlier conveniently lower peak. §10.2.1 makes the required observation discipline explicit. Historical counterexample custody limitations do not establish absent current tests and do not authorize evidence-store repair in this task.

This specification's preparation reviewed merged source, relevant changes and qualification accounts. It did not rerun the repository suites, audit every CAS receipt, or independently reproduce the old measurements. The implementing session must execute the checks required for its own candidate.

---

## 3. Source-grounded opportunity map

The following mechanisms were checked against the landed W0. They establish concrete optimization or preservation surfaces, not that any one mechanism dominates application latency.

| Owner and path | Observed mechanism | Implication to investigate |
|---|---|---|
| `src/interpreter_v2/activation_slots.zig` | Reference-counted persistent views now also pack sparse COW successor pages by occupancy/rank, retaining ordinary dense unique growth and safe packed-to-dense growth. | Preserve the landed P22 storage gain; a logical slot no longer implies a fixed physical array offset. Dense/packed representations are valid cases of one owner, not legacy alternatives. |
| `activation_frames.zig::Frames.backup` and `stable_session.zig::Session.begin` | Every transaction constructs another frame map and forks every registered frame's slot and custody handles. Commit discards that complete backup. | Rollback setup/teardown can depend on all retained frames even when one frame changes. |
| `store.zig::holdNode/holdBlob` | Ordinary node/blob rollback already saves entries on first modification. | Extend existing ownership boundaries rather than add an independent transaction manager. |
| `stable_session.zig::pendingRequest/answer` and `invocation.zig::finish` | Pending identity construction serializes State; response admission reconstructs the expected request. Resident request output without exported State still constructs State internally for its binding. | Repeated validation of an unchanged parked computation may redo full-state work. |
| `stable_session.zig::checkpoint` | Stages node records across the Store table before canonical emission. | Distinguish required traversal/encoding from avoidable staging. |
| `value_projection.zig::project` | The encoded-sequence path derives schema facts and builds a projected graph. | Examine exact reuse of admitted immutable facts and intermediate allocation lifetimes. |
| `resident.zig::publish` | Owns input, starts a transaction, advances, prepares/encodes output, then commits. | Preserve the shared publication fence while reducing its administration. |
| `frame_layouts.zig`, `prepared.zig`, `activation_frames.zig::canRestart` | Exact slot-schema/custody-length classes are already derived once in immutable preparation; Frames borrows the index under its lease, and restart still checks dynamic custody. | Do not build a second layout index or restore per-call full-layout comparison. Preserve exact compatibility, dynamic authority and owner lifetime. |
| `test/current/frame_layout_qualification.mjs` and kernel `enter` | Kernel allocation peaks reset on commands; the corrected sampler folds each operation's observation before another command can erase it. | Reuse this discipline for new H/Q/retention measurements; last-command peak is not lifecycle peak. |
| `stable_session.zig::scalarBatch/finishRetention` | Physical batching preserves logical prefixes; liveness-informed reclamation occurs before certain public pauses. | Preserve the existing throughput and retention gains while measuring surrounding costs. |

Source links: [S02]–[S09], [S18], [S20]–[S22]. These are not mandates to retain current file names or call graphs. Changes must stay within World's existing responsibility and public contracts. The newly delivered layout index and packed pages do not remove the all-frame backup or `answer` → `pendingRequest` → `checkpoint` reconstruction targeted by A/B. Their semantics, ownership guarantees and measured benefits are protected; their exact structs, class-array encoding and physical page policy are not immutable architecture. A justified in-scope replacement may change those details if it preserves the required outcomes and passes the same guardrails, with the displaced implementation ablated rather than kept alongside it.

A source scan nominates a mechanism. Timing, counters, and controlled workloads establish whether it matters. A lower dispatch count, smaller descriptor, or fewer lines alone is not a speed claim.

---

## 4. Preserved execution and ownership contracts

### 4.1 Same-image simulation

For the same admitted image, valid starting State/arguments, corresponding controls and replies, and sufficient physical capacity:

```text
projection(candidate_state at logical cut q)
    = baseline logical state at cut q
```

Every allowed public cut must preserve the baseline's outcome kind, values, authored failures, effect identity/payload/order, logical work charge, pending binding, cancellation/unwind behavior, and canonical portable representation.

The relation covers intermediate states, not merely final results. If a physical optimization executes several logical instructions, it must stop at the requested prefix; executing a full batch and charging the quantum afterward is forbidden.

Zero quantum is meaningful. Control application before a zero-quantum run follows the existing API; do not treat every zero-quantum command as a no-op.

### 4.2 Semantic retention is not transaction rollback retention

**Semantic retention** preserves an activation version for a valid continuation, resumption, branch, handler, or cleanup observer.

**Transaction retention** preserves enough entry-state ownership to undo an unpublished attempt.

Reducing the second must not weaken the first. A retained branch must continue observing its own valid historical state. Deliberately shared mutable state must remain deliberately shared. Copyable descriptors do not establish dynamic uniqueness.

The relevant state includes frame membership, function, position, slot view, initialized values, custody, liveness bookkeeping, roots, status, terminal state, Store objects, imported backing, and private control needed for correct retry. Do not journal only the field visible in a simple benchmark.

### 4.3 Publication and rollback

All current public resident output routes must retain one effective commit boundary. Every fallible operation needed to publish a successful outcome—including encoding and final output allocation—must complete before authoritative advancement becomes irrevocable.

On physical failure, preserve the previous authoritative checkpoint, live handle, pending expected response binding, ownership, and retry behavior. Rollback must not allocate. Capacity failures may occur at different thresholds when allocation changes; safety and retry remain mandatory.

Returned data must own or safely retain its backing under the existing API. No pointer into temporary scratch, a moved frame map, released preparation, or invalidated WASM memory view may escape.

After successful checkpoint transfer, custody is relinquished exactly as the current API specifies. Failed transfer retains it. Closing unfinished execution must not bypass cancellation and cleanup.

### 4.4 Wire and public API compatibility

Keep the selected current BPI3/PST3/PKI3/PKO3/ERQ3/ERS3 contracts, canonical encodings, identity algorithms, ABI export signatures, and public native/JavaScript behavior unchanged.

Private native representation and non-contractual diagnostic fields may change. This is not a promise to preserve native struct size, pointer identity, or the ordinal of an allocation failure. Preserve supported source/API behavior and published ABI contracts; do not require new caller arguments, application migrations, or a weaker validation mode.

For the same logical state, require exact canonical checkpoint/request/outcome bytes where the existing contract makes them deterministic. Private handles, metadata, hashes, journals, and storage addresses must not enter portable identity.

A checkpoint created by the baseline must restore correctly in the candidate and vice versa for the same compatible image. Also exercise native/WASM and fresh-process transfer.

Do not patch Boundary's encoder, weaken canonical admission, add private serialized fields, or invent automatic State migration. Do not promise a new public low-level mutation restriction to justify caching without explicit source-contract support.

### 4.5 No new external-authority semantics

This task does not create exactly-once external execution, approval reuse, global replay prevention, or a new notion of delivery occurrence.

A saved valid checkpoint and a corresponding reply retain the baseline's restoration behavior. A stale-reply test must actually have a different expected binding according to the existing protocol. Do not demand distinct request identities where baseline semantics legitimately produce the same canonical binding.

Request-binding reuse is not response memoization. Every new valid reply still undergoes the required parsing, schema/value admission, and control transition.

### 4.6 Resource, platform, and trust invariants

Preserve native/wasm32 behavior, the import-free generic kernel, bounded memory/stack behavior, actual kernel identity verification, owned-input rules, reentrancy/handle rejection, and browser-neutral imports.

Do not change the declared capacities, engine feature baseline, compiler safety mode, host permissions, or default resource limits to make a candidate appear faster. Explicitly larger **test** capacities are permitted only when required by a stress fixture and identical for baseline/candidate.

Diagnostic counters are not semantic state. State whether counters include failed attempts; do not silently use statistics rollback as a substitute for semantic rollback.


## 5. Required outcome A: change-proportional transactional retention

### 5.1 The required cost property

Define:

- `F`: registered frames retained at transaction entry.
- `ΔF`: frames created, removed, changed, or conservatively acquired for mutation during that transaction.
- `L`: logical work actually executed.
- `R`: required reclamation work.
- `B`: required output bytes.

For a successful drive with a fixed small `ΔF`, no required global collection, no newly required full-state binding, and no checkpoint export, **transaction-specific setup and commit must not contain an unconditional linear traversal of F**.

Constant-root retention, first-touch work, or logarithmic map/path work are acceptable. A small conservative mutation set is acceptable when measured and explained. Reporting every frame as “possibly changed” simply renames the original problem and does not satisfy the requirement.

Count frame visits, versions retained/released, map entries copied, page/directory copies, and transaction temporary allocation. Demonstrate the property with §8's retained-history fixture and the actual mutation paths. Do not infer an asymptotic law from timing points alone.

This is not a claim that all runtime work is change-proportional. Full export, terminal destruction, necessary tracing, and actual user computation may legitimately touch retained state. Ordinary occasional data-structure growth must be accounted for rather than hidden or confused with an unconditional per-drive scan.

### 5.2 Representation obligations

Select a construction that preserves the transaction-entry state until successful publication:

| Event | Required disposition |
|---|---|
| Read-only access to an untouched frame | No eager rollback copy of unrelated frames. |
| First possible mutation of an entry frame | Secure sufficient rollback ownership before exposing a mutable reference or changing any field. |
| Further mutation of the same entry frame | Preserve the original entry version, not a later intermediate version. |
| Creation of a new frame | Record that no corresponding entry frame existed. |
| Removal of an entry frame | Keep enough entry ownership to restore it; do not destroy the sole required saved version. |
| Removal and reuse of a logical/physical slot | Distinguish entry identity from new occupants; rollback restores the entry state. |
| Successful commit | Retain the selected successor and release transaction-only ownership once. |
| Failed attempt | Restore entry membership, contents, custody, and related control without allocating. |

A first-touch journal is a plausible implementation, not a prescribed one. A persistent frame-map root is another possible implementation. Compare their actual setup, mutation, release, memory, and failure costs before selecting.

Reuse the existing Store, Slots, custody, and Resident ownership mechanisms. There must be one coherent transaction spanning them, not separately committed subtransactions that can expose mismatched state.

Frames now borrows immutable `Layouts` from `Prepared` rather than retaining a standalone Program copy. Transaction entry versions and restored frames must remain tied to the same admitted preparation lease. Do not journal or rederive the immutable compatibility classes per frame or per drive. Preserve dynamic custody checks even when two functions belong to the same static layout class.

### 5.3 Mutation coverage is part of implementation

Find the sanctioned mutation surface in the actual selected source, including mutable frame borrows, create/put/update/remove, write/clear/apply/prune, restart, custody/scope movement, copy/rebase, clone/resume, unwind, collection, and restoration where affected.

This is a finite source-level coverage check tied to the replacement—not a repository-wide migration project.

Do not trust a list declared by the new journal alone. Inspect the callers and public entrypoints independently. All relevant paths must either cross the first-mutation boundary or be proved not to require transaction protection in their actual lifecycle.

Protect mutable-reference lifetime. Journaling after returning a mutable pointer is too late. Growing a map, allocating a view, or invoking a helper must not invalidate a pointer still used by the caller.

At W0, packed slot insertion/removal can shift physical values even without changing the page address, and packed growth can replace the page. A borrowed raw value pointer or cached physical index must not outlive any such operation merely because the logical slot or page handle is unchanged. Keep logical slot availability, initialized occupancy, iterator invalidation and retained-version ownership authoritative. Include this interaction in any journal or active-page optimization; do not regress to a fixed-width-page assumption.

### 5.4 Failure and ownership details

Cover at least:

- Failure while establishing the first saved version, before any mutation escapes.
- Failure after slot changes but before corresponding custody/control publication.
- Multiple writes to one frame, followed by failure.
- Creation, mutation, deletion, and reuse within one transaction.
- Removal of an entry frame followed by recreation at a reused identifier.
- A semantic fork created before the transaction and one created during it.
- Collection retiring an object still needed for rollback.
- Imported backing or shared fields whose physical owner moves into rollback storage.
- Output allocation or encoding failure after successful logical progress.
- A succeeding retry with the original response after that failure.

Preserve rollback-only objects until they are no longer needed, but do not turn them into permanent semantic roots or retain them beyond successful commit.

Failure-path reconstruction of private indexes may legitimately require more work than successful commit. Document and measure it. Do not claim change-proportional rollback when an existing failure path still rebuilds a whole index. This task's hard structural gate concerns the ordinary successful drive; failure safety and complete failure/retry costs remain required.

### 5.5 Bounded lifetime

Repeated small drives must not accumulate journals, handle generations with unreclaimed backing, per-frame histories, scratch arenas, or dormant references proportional to the number of completed transactions.

Generation overflow and capacity exhaustion must fail safely. Physical identifier reuse must not resurrect released handles. Preserve the selected API's handle-lifetime contract.

At steady retained state and workload, live allocation must reach a justified bounded plateau. Reserved allocator capacity and actual live bytes must be reported separately.

---

## 6. Required outcome B: reuse of unchanged pending-state observations

### 6.1 Required behavior

On the controlled resident path, establish the expected request identity from the exact admitted parked computation. While that computation remains unchanged, reuse the established expected binding rather than reconstructing its entire canonical State on each response check.

The minimum witness must:

1. Publish a request from a parked computation with substantial retained history.
2. Submit several bounded invalid responses without changing that computation.
3. Submit a valid response.
4. Show no repeated full-state serialization/projection **solely for expected-binding verification** after the binding was established.
5. Preserve the exact baseline acceptance/rejection and successor behavior.

Measure expected-binding verification separately from required response decoding/value admission and from construction of a **new** request or checkpoint after progress.

Initial binding creation, rebuilding after restoration, and actual checkpoint output may still require full canonical work.

### 6.2 Authority of the reused observation

A reused binding must be established by the existing canonical identity procedure and owned by the exact state/lifetime it describes.

Its validity must follow from a controlled mutation boundary or an equivalently justified invariant. A hash of mutable memory, a convenient pointer, a function name, an external request payload, or an incrementing number without complete mutation coverage is insufficient.

The implementation must account for:

- Initial publication of a pending request.
- Invalid replies that leave state unchanged.
- Successful reply admission and resumption.
- Explicit yield resumption and subsequent progress.
- Cancellation, including cancellation of pending cleanup and rebinding.
- Restoration into a new Session/Resident.
- Checkpoint transfer, close, replacement, and released instances.
- A failed attempt after tentative invalidation or creation of a successor binding.
- Relevant public or internal low-level mutation and inspection paths.

Do not silently remove a supported low-level Session capability to make the cache sound. Where the contract permits mutation outside a controlled boundary, do not trust cached metadata through that route. Shared logic may conservatively recompute there; this is a contract distinction, not a second optional product. The public resident route must satisfy the required outcome.

### 6.3 Selected observation and rollback

Treat the expected binding as derived private state coupled to the authoritative computation.

If a reply advances execution but publication fails, restore a binding applicable to the original parked state along with the original computation. A stale successor identity must not survive rollback.

If a command validly changes the parked state, an old expected identity must not be accepted merely because the request's effect and payload are unchanged.

A valid response's identity is only one check. Keep all current typed response/value admission and instruction semantics. Never cache a result as permission to skip another operation or reuse consumed authority.

A failure to allocate derived metadata must either fail the unpublished attempt safely or use an equally correct recomputation path. It must not publish partial metadata or fall back to trusting an unchecked identity. Record the cost of such a path; do not make it a permanent production selector.

### 6.4 Retain the binding, not a hidden duplicate checkpoint

The retained observation should be bounded independently of the size of the mutable retained computation—for example, a compact identity plus necessary owner metadata.

Do not satisfy this outcome by keeping another serialized copy of every full checkpoint or duplicating the entire transitive state graph. Immutable effect/schema metadata may remain in its existing preparation owner.

Caller-requested exported bytes remain caller-owned under the existing API. Repeated exports must retain their original ownership and detachment behavior. Reusing an internal identity does not authorize lending out mutable shared output buffers.

### 6.5 Exact semantics and useful negative cases

Require tests for wrong image, wrong pending binding, wrong instance/handle, malformed reply, correctly bound but ill-typed value, cancellation-created replacement requests, failed publication, and restored checkpoints.

For a replay or “stale reply” discriminator, demonstrate that the baseline expects a **different** binding. Reconstructing the same saved state can legitimately recreate the same binding; this task must not invent an external exactly-once guarantee.

Where a diagnostic or checkpoint call leaves the computation unchanged, it must not gratuitously invalidate an otherwise sound expected binding. Nor may updating a private cache advance execution, alter custody, or change portable State.

---

## 7. Required outcome C: complete-lifecycle efficiency and prompt reclamation

### 7.1 Optimize existing boundaries, not the benchmark denominator

Outcomes A and B must be integrated into the existing native and WASM paths. Measure their effects on complete resident workloads as well as isolated operations.

Investigate remaining costs in the changed execution/publication path. Permitted candidates include eliminating repeated derivation of exact immutable facts, reducing temporary outcome copies, shortening scratch lifetimes, and avoiding repeated active-frame/slot resolution.

These are opportunities, not a requirement to implement every technique. Once A/B, the lifecycle performance requirements, and all preservation gates hold, do not add an unrelated optimizer merely to enlarge the task.

At least one prescribed complete WASM resident lifecycle must improve under §10's repeated-window criterion. Merely adding statistics, a proof sketch, an unused optimized helper, or a benchmark-only path is insufficient.

### 7.2 Necessary whole-state work remains necessary

A full checkpoint has to produce its output bytes. Canonical emission, graph validation, and a new full-state request digest may require traversal. This task promises neither constant-time snapshots nor change-proportional garbage collection.

Preserve Boundary's authoritative codecs and admission. World may improve how it supplies/uses their inputs through existing supported interfaces; it must not copy those algorithms into a private weaker encoder or change the frozen dependency.

If a desirable checkpoint optimization requires changing a Boundary-owned interface, record the exact boundary and continue independent World work. That interface expansion is not automatically part of this task.

Do not stage multiple identical full graphs merely because earlier code did so, but do not claim redundant validation without identifying its actual distinct obligation. Reusing admitted immutable schema facts requires exact program and lifetime identity.

### 7.3 Exact stepping with cheaper physical administration

A physical fast path may reduce lookup, allocation, or dispatch overhead while preserving every logical instruction and permitted prefix.

Before retaining such a change, account for all observers: public checkpoints/inspection, semantic capture or fork, another instruction reading frame contents, collection, unwind, exception/failure boundaries, cancellation, and output publication.

A stack-local value or borrowed page can remain unmaterialized only while its lifetime, aliasing, failure, and observation obligations are satisfied. Prepared metadata must remain tied to the admitted Program owner. Do not add per-program machine code, a JIT, or serialized execution plans.

The scalar fast path is not allowed to skip custody or liveness handling merely because the positive fixture uses unsigned scalars. General/ineligible execution must retain its behavior and reasonable overhead.

### 7.4 Prompt reclamation is protected

Preserve W0's large-blob, consumed-frame, shared-field, imported-backing, sparse activation-page and prepared-layout improvements. In particular, changing rollback ownership must not make every live activation dense again or accumulate a second full layout catalogue per Session. A smaller journal is not a gain if persistent-page or shared-preparation memory grows without an accepted disposition.

When the existing contract requires dead large backing to be reclaimed before returning a public pause, do not defer it to a later drive, checkpoint, terminal result, idle callback, or close. Old semantic aliases must survive; rollback-only ownership must disappear when the transaction commits.

Do not replace accurate tracing with “one slot disappeared, therefore unique.” A liveness hint is not proof that a value has no direct, captured, indirect, resumption, or cleanup observer.

Measure direct-alias scaling and captured-alias cases. A cache that avoids serialization but retains a dead megabyte is not acceptable.

### 7.5 Complete cost accounting

Measure the applicable sequence:

```text
prepare and start, or restore
  -> bounded resident drives
  -> pending-request publication and reply checking
  -> requested checkpoint/transfer
  -> completion or cancellation with cleanup
  -> close/release
```

Report the sum of each actual observed lifecycle, not the sum of separately selected best medians. Keep isolated phase medians as diagnostics.

Include the first binding creation, transaction commit/discard, deferred cleanup, physical release, and failure followed by retry. A faster `drive` bought by an equal or larger unreported bill elsewhere is not a lifecycle gain.

Preserve the existing fresh, prepared, and resident API distinctions. Do not replace the fresh workload with a warmed preparation and call it the same test.

---

## 8. Workload and discriminator contract

### 8.1 Fixed primary families

The following definitions are normative test requirements, not additional public product features. Use actual current-format admitted Programs and existing execution APIs.

| Family | Required construction and dimensions | Deciding observations |
|---|---|---|
| **H — Retained history, small active change** | A valid computation retains individually usable dormant continuations/alternatives while one active frame executes a fixed small scalar fragment. Nominal retained-population dimensions: 1, 16, 64, 256, 1024. Also exercise a bounded changed-frame set at a fixed larger retained population. | Successful transaction frame work, temporary allocation, copy counts, drive time; old branches remain usable. |
| **Q — Unchanged pending observation** | Park with retained history at 1, 64, 256, 1024; publish a request, present three bounded invalid replies and then a valid one. Keep payload/response size fixed while history varies. Include inspection/export and cancellation variants. | Initial binding construction versus expected-binding checks; projection/serialization counts; exact rejection and successor behavior. |
| **R — Reclamation and aliases** | Blobs below/at/above the actual large-backing threshold and at 1 MiB, with unique, direct-alias, captured-alias, and retained-branch cases. Direct-alias counts 1, 4, 16, 64. | Live and peak working bytes at the required pause, tracer/retirement work, pause and full-lifecycle time, failures/retry. |
| **S — Scalar and ordinary dispatch** | Existing 0/2/4/16/256/1024-operation witnesses, mixed eligible/ineligible instructions, checked-failure neighbors, every cut in short sequences and collection-boundary cuts in long ones. | Logical versus physical work, canonical prefixes, tiny/fresh overhead and sustained throughput. |
| **F — Frame reuse and argument transfer** | Existing compatible/incompatible tail-call witnesses at 0/1/8/128/512 calls; argument swaps/repetition; shared old frame versions; recorded sparse layouts at widths 4/4096/65536 with four used slots; dense/packed occupancy and growth neighbors. Use focused combinations, not a full Cartesian product. | Reuse/fallback, exact schema/custody class checks, bounds, preparation lease, retained versions, simultaneous arguments, page bytes, allocation and timing. |
| **X — Effects, ownership, and transfer** | Existing one-/multi-shot, deep/shallow, branch-local/shared mutation, borrowed/owned values, cleanup that suspends, authored failure, and cancellation fixtures. | Exact traces, obligations, old-version observations, native/WASM/fresh-process portability. |
| **A — Real consumers** | Frozen Inquiry, document-assistant, and recursive-parser application scenarios from A0, using their existing deterministic prescribed-response/tool fixtures. | Existing application assertions, full runtime cost, checkpoint/working-memory changes; no live model latency. |

These dimensions are structural/test selections, not promises that every case fits the default arena. Use the same documented, explicitly selected stress capacity on both binaries. Record actual retained-frame counts; a requested fixture size is not evidence that the compiler or runtime retained that many frames.

If canonical optimization lawfully eliminates a synthetic retained structure, revise the **fixture** to make its dormant alternatives genuinely and individually observable. Do not disable coalescing, weaken a compiler pass, fabricate arbitrary internal states, or count dead frames as semantic history.

The complete cross-product is not required. Use the focused dimensions above, justified pairwise interactions, and the specific acceptance cases in §14. Share fixtures and harness code where possible.

### 8.2 H: isolating transaction overhead without hiding collection

For the structural test, select valid program prefixes whose measured drive changes one active frame, exports no checkpoint, creates no new request binding, and does not cross a scheduled or liveness-triggered collection boundary.

Establish those conditions through execution and counters. Do not disable production collection or manipulate semantic state to make the timing favorable.

Measure transaction begin, first-touch preparation, successful commit, and release of rollback-only ownership. Keep the active fragment and output size fixed as dormant population grows. Count any map enumeration even when it is described as validation, cleanup, or cache maintenance.

Separately run the same family across collection boundaries and through a complete lifecycle with requested checkpoint and terminal cleanup. These costs remain visible even though the structural claim excludes them.

After many active writes, resume selected old branches and check their individually distinguishing values and effects. A final commutative checksum alone is insufficient to detect swapped or duplicated histories.

### 8.3 Q: separating identity reuse from subsequent progress

First publish the baseline-equivalent request and record its binding. The invalid replies must exercise different existing rejection obligations, not merely repeat one malformed byte.

The expected-binding subphase after establishment must perform zero additional full-state reconstruction attributable solely to checking that unchanged binding. A valid reply may then legitimately produce a new state, new request, or checkpoint; charge that work to the new observation rather than hiding it.

Repeat with cancellation that genuinely changes the expected binding, with failed output publication, and after a fresh-process restore. The restored computation must establish its own valid private metadata; no hidden in-memory cache may be required for portable execution.

### 8.4 Primary complete-lifecycle measurements

Freeze these two primary lifecycle definitions before production edits:

**H-lifecycle:** start a valid retained-history workload, execute 64 small resident drives, produce the declared checkpoint/transfer, then complete or cancel and finish cleanup/release. Use the largest prescribed H case that succeeds on the baseline under the documented common stress capacity. Include all phases from start through release; report preparation separately and also included.

**Q-lifecycle:** start the retained-history request workload, reach and publish its request, submit the three prescribed invalid responses, submit the valid response, then complete or cancel through existing cleanup and release. Use the largest prescribed Q case supported under the same documented baseline/candidate limits. Include initial binding and publication work.

Selection depends on baseline validity/capacity, not on the candidate's preferred result. Keep the smaller cases as guardrails. When a baseline cannot run the selected nominal case, report it and use the next smaller specified case; do not add larger memory only for the candidate or remove the failed observation.

The fixed production application scenarios remain separate real-consumer evidence. A synthetic lifecycle gain must not be called an application-wide gain.

The prior qualified consumer replay executes each recorded PKI3 as a **fresh invocation**, including its image admission and checkpoint restoration. Those 491-command replays are valuable fixed regression inputs but do not exercise one live Resident across the trace. Preserve that lane and label it accurately. Implement H/Q through actual persistent-in-process Resident handles; do not substitute fresh replay totals for these primary lifecycle measurements, and do not claim a resident gain from unchanged fresh replay alone. [S18] [S23]

### 8.5 Public-path and private-mechanism evidence

Run H/Q through the actual native Resident and WASM resident APIs. Tests of a private map or journal supplement but do not replace this requirement.

Use small private unit witnesses for lifecycle corner cases that are difficult to select from an application, then connect the mutation path to a real public invocation. All benchmarked production inputs must be admitted through the normal boundary.

Do not add benchmark-specific code that recognizes input hashes, fixture names, dimensions, or expected outputs.

### 8.6 Unseen-neighbor validation

After selecting a construction, validate neighboring sizes and layouts not used to choose it—for example 7, 31, 63, 65, and 257 retained elements where admissible, plus the actual page/liveness threshold neighbors.

Also vary effect payload values, alias placement, and reply/cancellation order within valid contracts. These are generalization checks, not independent model trials or proof over all programs.

A separate assessor may later run the same specification-derived checks against both candidates. Neither implementation needs to build or operate that comparison.


## 9. Correctness qualification

### 9.1 Independent evidence

Use the frozen W0 executable/kernel as the primary differential reference for same-image behavior. Retain existing independent source semantics and explicit expected-result fixtures where available.

Repeated `step()` execution is a useful prefix discriminator but is not independent if both paths share a newly broken helper. Combine it with W0 execution and targeted invariant/ownership tests.

A transform or representation name, equal candidate-generated digests, a round trip through the same new code, or a clean review does not establish correctness.

### 9.2 Required failure tests

Exercise allocation failure at every newly introduced fallible preparation or publication point reachable by the focused fixtures. Also cover failures in the existing Store/custody/output operations reached through the new path.

For native tests, use the repository's allocation-failure mechanism and prove that rollback itself performs no allocation. For WASM, exercise working/input/output capacity boundaries and unchanged-input retry through the public ABI; use an existing test-only failpoint route where supported rather than adding a production debug API.

The failure matrix must reach failures after real frame mutation, after creation/removal, after a semantic fork, after reclamation bookkeeping, and after logical progress but before output publication. A suite that fails only before execution is insufficient.

For each failure, compare the authoritative checkpoint and expected response behavior with entry state; then repeat the original valid operation with sufficient capacity and compare its result to the reference. Balance physical ownership over repeated failure/retry cycles.

### 9.3 Cross-engine and fresh-process checks

Required final qualification includes:

- Native and Node/WASM execution of the primary and relevant adversarial fixtures.
- Existing independent Wasmtime agreement/transfer checks, extended for changed boundaries.
- Actual browser Worker execution using the repository's supported browser matrix.
- Fresh-process/Worker restoration after the original process exits.
- Baseline-to-candidate and candidate-to-baseline State transfer for matching images.
- Wrong-image, stale/released/cross-instance handle, malformed input, and invalid response rejection.
- Unchanged reentry and prepared/resident ownership constraints.

Use the normal kernel profile. Do not require WasmGC, tail-call extensions, threads, memory64, SIMD, or relaxed validation if they are not already part of the selected profile.

A passing local native suite is not WASM evidence. A local kernel measurement is not authenticated delivered-package qualification. Distinguish each executed lane and its inputs.

### 9.4 Existing verification entrypoints

The investigation identified the following current owners; confirm their exact supported syntax at W0 before invoking them:

```text
zig build check-storage check-native -Doptimize=ReleaseSafe --summary all
zig build check --summary all
zig build build-kernel build-runtime --summary all
zig build check-package check-source check-capacity check-transfer check-browser check-codecs --summary all
```

These are a map to existing verification, not instructions to duplicate every lane already executed by an aggregate. Reuse exact-input coverage when valid. Re-run affected checks after changes; run full required final qualification on the coherent final candidate.

Existing targeted owners include `test/current/frame_layout_qualification.mjs`, `resident_cost.zig`, `native_consumer_cost.mjs`, scalar/frame/blob platform and failure probes, and the packed-page tests in `activation_slots.zig`/`activation_slots_tests.zig`. B0 retains `test/consumer_runtime_admission.mjs` and `test/consumer_runtime_replay.mjs` for frozen consumer comparisons. Inspect their phase boundaries and input requirements before reusing them. Their historical sampler invocations, local absolute paths, and output files are not prerequisite artifacts.

Keep the layout classifier's exact-equality/forced-collision, zero/one/two-function, allocation-failure and dynamic-custody tests. Keep the packed storage occupancy, alignment/zero-sized-value, old-view and growth-failure tests. These are preserved substrate checks, not newly requested compiler or storage features.

Resolve source overrides, fixture locations, locked test dependencies, and environment-specific commands from the selected repository. Do not hardcode paths from older BPI2 or comparison reports.

### 9.5 Tests and oracles cannot be weakened to obtain success

Inspect the base-to-candidate diff for removed tests, changed assertions, skipped dimensions, narrowed domains, and altered failure denominators.

Preserve the obligation or replace the test with stronger source-grounded evidence. An oracle correction requires independent support, original failing evidence, and separation from a performance claim. Do not adopt candidate behavior simply because it passes the new suite.

No new formal-proof repository or universal evaluator proof is required. Provide a precise local representation/simulation argument, complete changed-boundary coverage, executed witnesses, and honest residual limits.

---

## 10. Performance acceptance

### 10.1 Separate structural, measured, and economic claims

The final account must distinguish:

| Claim | Required evidence |
|---|---|
| No all-frame transaction scan on the selected path | Actual code/call-path argument and counter scaling. |
| Reused expected binding avoids unchanged full-state reconstruction | Phase-specific serialization/projection counters and exact-response tests. |
| Runtime is faster | Repeated matched timings of the actual kernels and complete lifecycle. |
| Memory improves or remains acceptable | Peak/live/retained allocation measured at declared boundaries, with owner scope. |
| Application benefit | Measurements on the unchanged named A0 application scenario. |
| General applicability | Supported domain, valid neighboring cases, and limitations; not a universal claim from samples. |

Neither more aggressive compiler optimization nor a different image may be credited as a World improvement in the primary comparison.

### 10.2 Build and runtime controls

Use identical toolchain, target, safety/optimization mode, capacities, fixture bytes, reply values, schedules, and engine options within each baseline/candidate pair.

Retain World's normal WASM build profile and native ReleaseSafe qualification. Measure any additional profile separately; changing build mode is not the primary intervention.

Record CPU/OS, engine versions, allocator, compilation/instantiation treatment, warm-up policy, background load, and measurement unit. Keep expensive counters/profilers out of final timing builds or demonstrate their negligible equal effect. Profile and time in separate runs where practical.

Do not run acceptance timing while another build or benchmark is competing materially for the same machine. Use existing task facilities to obtain an uncontended measurement window; do not create a scheduler or change system settings. Preserve an exact unqualified result when uncontended timing cannot be obtained.

Prepare fixed inputs before the timed region when that phase intentionally excludes preparation; include them when measuring a complete lifecycle. Always label which is which.

### 10.2.1 Measure reset-on-command peaks correctly

The landed kernel resets input/working/output budget observations at command entry. A later `close`, release, start, drive or other command can replace a larger earlier peak. Reading `workingPeak` once after cleanup is therefore invalid as a lifecycle maximum. The final upstream repair corrected precisely this error. [S18] [S21] [S22]

In a separate instrumented pass over the same baseline/candidate input schedule:

- Observe each relevant command's peak **immediately after that command and before any subsequent command can reset it**, including preparation, start/restore, each drive, checkpoint/transfer, cancellation, close and release. Observe failed commands before performing a retry or cleanup; a `finally`-style sample is appropriate when the public call throws and usage remains readable.
- Fold the maximum for the declared interval. Record phase peaks and the whole-sequence maximum separately. Do not sum phase maxima and call that a simultaneous live peak; do not subtract preparation that overlaps execution unless separately reporting a clearly labeled incremental quantity.
- Read paused live bytes at the actual required pause, before export/cleanup changes retention. Record immutable preparation retention, transaction/cache overhead, execution storage and allocator reservation under their actual scopes. Input/output budgets remain distinct.
- Preserve the existing reset-on-call sampler regression and verify any new sampler against an independently specified sequence where a later small observation would conceal an earlier large one. A fake sampler discriminator complements, and does not replace, actual-kernel observations.
- Keep instrumentation and incidental memory-pass timings separate from latency qualification. Use the corrected current sampler sources; the twelve invalidated historical fields receive no qualification credit.

These requirements extend the existing measurement owner; do not add production telemetry, new kernel exports, or another benchmark framework. They apply equally to the fixed baseline and candidate. A lower recorded peak is not accepted until its interval and reset behavior are correct.

### 10.3 Repeated-window rule

Reuse the earlier programme's engineering detection protocol:

- At least three independently launched alternating baseline/candidate windows per timing cell.
- At least three warmups and nine measurements per process unless the existing qualified harness is stronger.
- For suspected regressions and each claimed primary win, complete five windows.
- Let `r_i` be the candidate/baseline ratio of corresponding window medians.

A reproducible greater-than-5% regression under this protocol has:

```text
median(r_i across five windows) > 1.05
and at least four of five r_i > 1.05
```

For this task, a claimed material primary win requires the symmetric engineering condition:

```text
median(r_i across five windows) < 0.95
and at least four of five r_i < 0.95
```

The 5% win rule is a prospective acceptance discriminator selected for this task, not a predicted gain. These rules are not statistical confidence intervals and must not be reported as such.

For extremely short operations, use an equal, predeclared number of repetitions per sample to make timer overhead negligible; preserve per-operation semantics and include required maintenance. Show absolute time deltas and variability. Do not claim a meaningful speedup from unresolved timer noise.

Keep raw paired windows, failures, unchanged and inconclusive cells. Do not select the fastest sample, average away a regression, or treat dozens of workload cells as independent coding-agent trials.

### 10.4 Required economic gates

| Dimension | Requirement |
|---|---|
| Structural outcomes A/B | Both must be demonstrated in production paths, or already satisfied in W0 with exact evidence. |
| Complete WASM lifecycle | At least one of the preselected H-lifecycle or Q-lifecycle must satisfy the primary win rule. Both remain required measurements. |
| Required runtime/admission cells | No reproducible greater-than-5% new slowdown without explicit user acceptance of the specific measured tradeoff. |
| Peak live working allocation | No increase above `max(1024 bytes, ceil(1% of baseline peak))` in a required cell without separately accepted tradeoff. Count preparation, transaction scratch, cached metadata, and execution under their actual owners. |
| Paused retention | Preserve the required prompt-reclamation behavior. Report any added bytes and explain bounded metadata. Indefinitely retaining dead large backing is a failure regardless of percentage. |
| Checkpoints and request identity | Exact same-image canonical behavior; the older compiler programme's percentage allowance is not permission to change these bytes. |
| Kernel/package economics | Report binary/code size, initial/reserved/max linear memory, build and engine setup costs. No expanded default arenas, stack, or feature profile as a shortcut. |
| Lifetime/scaling | No leak, accumulating per-drive history, pathological rescanning, unbounded cache, or hidden recurring all-frame cost. |
| Semantics/security/authority | Hard requirements, never percentage tradeoffs. |

The 5% timing and peak-memory guardrails are retained from the supplied optimization programme's §9.4–9.5, without retaining its obsolete optional-production-path clauses. This document contains the applicable rules in full.

Report smaller regressions too. Do not turn being under a threshold into permission for needless machinery.

The user accepted more Boundary construction cost, not arbitrary World regressions. World preparation/admission, checkpointing, invalidation, and code emitted into the kernel are runtime-side costs even when a helper is defined in a Boundary dependency. No such code may be changed here by silently expanding scope.

A material new regression remains an open acceptance item until corrected or explicitly accepted. Do not mark the candidate economically complete, hide it behind a flag, reset the baseline, or revive the predecessor. Continue independent authorized work and report the exact tradeoff when acceptance is required.

### 10.5 Historical regression diagnosis

Keep historical compiler-induced and runtime-induced regressions distinct.

Where exact compatible prior images/runtimes are available, a bounded old/new image × old/new runtime comparison can diagnose interaction. Preserve those historical identities and assumptions. Do not assemble every old experiment or make historical reconstruction a prerequisite for outcomes A/B.

Primary acceptance always compares **the same current frozen images on W0 and the candidate**. A published P19 slowdown between different compiler outputs is not, by itself, evidence of a World implementation regression. Likewise, a gain on a newer image must not be credited to the runtime if the baseline used a different image.

The preceding programme's then-recorded costs have an explicit accepted disposition in the closing accounts. Preserve that history without reopening it or interpreting “all costs accepted” as prospective acceptance of this task's changes. For this task, compare new costs to W0 and retain any bounded historical comparison as a separate diagnosis. Old inconclusive timing cells stay inconclusive; a new paired measurement must earn its own disposition.

### 10.6 No cost concealment or packaging bloat

Include successful, rejected, failed/retried, and cleanup lifecycles as specified. Do not move costs into preparation or release and omit them.

Retain concise source-adjacent results, reproducible harnesses, small fixtures, and semantic regression tests. Keep bulk raw measurements/logs/build outputs outside the production package using existing evidence/artifact practices. Do not add thousands of historical observations to a consumer's normal source-package closure.

A compact consolidated qualification document may link raw evidence. Retained evidence must remain obtainable and identify exact inputs; an expired cache path alone is not a reproducible result.

---

## 11. Implementation order and mandatory ablation

### Slice 1 — Establish the discriminator and deliver outcome A

Resolve the starting tuple, inspect the actual transaction owners, run the relevant baseline smoke, and realize H's valid retained-history discriminator.

Then implement change-proportional transaction ownership with its first-touch/removal/reuse/failure witnesses. Migrate every affected production caller and remove the all-frame rollback backup path that it replaces.

Open the unique draft PR after the first substantive, validated implementation slice. Do not wait for the entire project. A PR consisting only of this specification or an evidence inventory is not the intended early implementation witness.

Keep this slice focused on the changed transaction boundary. Do not require frontend uniformity, a new collector, or every historical benchmark to finish before publishing it.

### Slice 2 — Deliver outcome B

Add ownership-sound unchanged-binding reuse through the canonical resident path, with invalidation and rollback tests.

Use the existing identity/schema/response machinery. Remove superseded redundant reconstruction within that controlled path. Preserve the shared general machinery required by restoration or genuinely uncontrolled low-level access.

Expose the phase-specific counters and Q witness early enough to show that the repeated whole-state work was actually removed.

### Slice 3 — Integrate and improve the complete lifecycle

Run H/Q/R and the scalar/tail/general-effect guardrails through both native and WASM paths. Profile the remaining complete-lifecycle cost.

Make additional bounded World changes only when needed to satisfy the selected outcomes and cost gates. Prefer eliminating repeated work or intermediate materialization to another subsystem. Preserve already useful P25/P26 behavior and the selected upstream slot/custody contracts.

Re-run the complete cumulative candidate against W0, not only against the immediately preceding slice.

### Slice 4 — Qualify, review, and hand off

Run required package, browser, transfer, capacity, source-agreement, and real-consumer validation on the final coherent inputs.

Freeze P0 before independent review, execute the installed serial-review workflow, repair with the original implementation driver, and qualify the final P1. Preserve both identities and the corresponding results.

Finish the task's actual predecessor deletion and package closure before claiming completion. Do not end with “optimized implementation available” while production still chooses the predecessor.

### Scope admission rule throughout

An additional change belongs only when it realizes a required outcome, closes an actual affected caller/ownership dependency, fixes an in-scope correctness defect, or supplies the deciding qualification.

A family name, cleanup preference, unrelated old style, or opportunity discovered in another repository is not a prerequisite. Track the concrete causal dependency rather than expanding the programme.

Failed experiments may be removed from production while retaining their findings and minimal reproductions. This is not permission to remove an accepted predecessor before its required capability has a correct successor.

---

## 12. Workflow, independent runs, and delivery

### 12.1 Current skills, not inherited orchestration

Use the currently available definitions of:

| Capability | Skill reference | Boundary |
|---|---|---|
| Implementation and review-bearing closure | `$actuating serial-reviews` | Owns execution and review closure. Do not copy its internal review inventory or reset logic into another controller. |
| Measured performance work | `$tune` | Use its software-performance route and preserved-contract requirements. No skill-package editing campaign. |
| Durable deliverable/prerequisite tracking | `$ergon` | Maintain a small graph for this multi-session task using its current storage/transaction owner. Task readiness is not execution or merge authority. |
| Reconsidering unnecessary mechanisms and false constraints | `$metanoetic` | Use within the accepted runtime scope and receiving workflow; do not duplicate its activation or add another mandatory review campaign. |

Read the applicable repository instructions and selected current skill contracts before their governed actions. Use current installed definitions and relevant metadata/references, not this document's prose as a replacement for a skill.

The consulted dotfiles revision is recorded in §15 as provenance, not an installation pin. A compatible newer definition should not trigger downgrades, configuration repair, or recreation of retired skills.

If a named owner is unavailable or materially incompatible, state the precise affected action and continue independent authorized work. Do not invent modes/commands, restore old skills, hand-edit canonical evidence, or silently build a replacement tracker.

Use existing evidence/task custody and source-owner selectors. Do not hardcode their paths in this task, migrate existing records implicitly, or maintain a second authoritative graph. Track deliverables and real prerequisites, not a new task for every acceptance row or sample.

### 12.2 One execution owns one candidate

Each independent execution must:

- Start from the same immutable baseline-selection rule or the same explicitly supplied tuple.
- Create a unique World branch and isolated workspace; preserve the exact run identity on resumption.
- Create a new draft World PR, assigned to `tkersey`, and update it after substantive slices.
- Keep implementation, planning, and repairs in the original driver session; do not delegate candidate construction to helper models.
- Use the normal independent reviewers required by the installed selected workflow.
- Preserve the user's externally selected model/reasoning; do not switch or launch another implementation session.
- Avoid reading or incorporating another candidate's code, PR, findings, transcripts, benchmark outputs, or newly produced memories.
- Leave the PR draft and unmerged.

Resuming an interrupted execution continues its existing candidate; it does not create a duplicate PR. Another fresh independent execution creates its own new branch/PR and must not adopt the first candidate.

Use an isolated clone or existing supported isolation facilities when shared worktree evidence/build state would contaminate the run. Source-directory separation alone is not proof of task/evidence isolation. Use supported task/run selectors; do not alter global configuration or construct another isolation framework.

Do not require a second candidate to exist in order to complete this candidate.

### 12.3 P0 and P1

**P0** is the first candidate the original driver considers locally complete against this specification, after its own required checks and measurements and before its first independent review.

**P1** is the final candidate after the installed review/repair workflow and affected final requalification.

Record exact commits/trees, local completion claims, measured results, and limitations for both. Preserve P0's identity and evidence through any rebasing or repair. Do not retroactively relabel an earlier partial slice as P0.

Opening and updating a draft PR early does not itself start review credit. Follow the installed workflow's frozen-head review rules; do not repair the reviewed head mid-epoch.

No additional comparison-review wave or fresh-client model campaign is required by this specification. A later common independent assessment can evaluate both outputs without becoming an implementation prerequisite.

### 12.4 Comparison evidence without comparison orchestration

Retain the root session identifier, requested and actually observable model/effort, selected client/skill versions, and available usage from the beginning.

Separate implementation, independent reviews, review-driven repairs, and report generation where the tools support it. Preserve actual review identifiers, verdicts, accepted defects, duplicate findings, and repaired heads through their owning tools.

Do not:

- Infer a provider model from a prompt's self-description.
- Treat missing reviewer usage as zero.
- Sum repeated cumulative token snapshots.
- Add cached-input tokens to an input total that already includes them.
- Add reasoning-output tokens again to total output.
- Convert token totals into subscription consumption or dollars without a supported pricing/accounting basis.
- Count overlapping build/reviewer/driver intervals as disjoint time.

Missing telemetry is a disclosed comparison limitation, not a reason to create an instrumentation project or delay otherwise complete engineering work.

The eventual comparison should run frozen candidates serially through one common harness on one machine. Candidate-authored timing reports are useful evidence, not a substitute for that independent reproduction. Each candidate supplies replayable commands and fixed artifacts; it does not inspect or operate the other run.

Independently authored H/Q emitters need not produce identical images merely because their dimensions match. Freeze each emitter before its production experiment and feed its exact bytes to both W0 and that candidate. Such results are within-candidate mechanism evidence, not directly comparable cross-model timing scores. For the later common assessment, use the fixed A0 corpus and a common validated set of the public-API H/Q inputs, chosen without selecting only either candidate's favorable measurements. Execute both kernels on every common input with one harness. Do not have either implementation inspect the other's fixture construction to synchronize itself.

One implementation per configuration is a matched engineering trial, not a general statistical model ranking.

### 12.5 Required handoff

Return one compact final report with:

1. Draft PR, W0/P0/P1 identities, dependency/corpus/build identities, and executed platform lanes.
2. Exact retired production mechanisms and the retained distinct responsibilities.
3. Structural A/B evidence, preserved invariants, required-valid cases, and independent rejection/failure evidence.
4. Primary lifecycle results, all required guardrail cells, memory scopes, kernel/package deltas, and cumulative tradeoffs.
5. Review findings/repairs and available phase-separated consumption.
6. Reproduction commands and retained artifact locations.
7. Unresolved requirements, explicit accepted tradeoffs, and unexecuted checks.

No model winner, merge, release, live service deployment, or new product roadmap is required.

### 12.6 Definition of done

Completion requires the actual production A/B outcomes, the complete-lifecycle win and guardrails, exact semantic/ownership/identity preservation, mandatory affected-path ablation, source-independent package operation, the installed review contract, and an honest final handoff.

A useful partial result remains useful, but must be called partial. A blocker does not authorize a weaker claim. Conversely, do not keep adding independent optimizations after this defined objective is satisfied.


## 13. Complete launch prompt

The short invocation below is sufficient when the file is available to the session:

```text
$actuating serial-reviews @world-change-proportional-execution-spec.md
```

For a full pasted instruction, use the following. It delegates commands to the coding agent; it does not ask the user to operate scripts.

```text
$actuating serial-reviews @world-change-proportional-execution-spec.md

Implement this complete World/WASM Change-Proportional Resumable Execution
specification as one independent candidate.

Read the whole file and the applicable current repository/skill instructions.
Use the selected current $tune software-performance guidance, $ergon for the
small durable deliverable/dependency graph, and $metanoetic within the accepted
scope and receiving workflow. Do not copy their internals into a new workflow,
edit skills/global configuration, or restore retired machinery.

Use the exact landed tuple in section 2: World W0 c61edfc8208c375d5188e476131ca8cff5aeeb8a,
Agent A0 b1f9d2866b5717d16339e7022a3b4d08951f0770, World's locked Boundary
D0 511fe388587b36ae37307d277e04c22b0bb6f6d9, and Agent's locked compiler
C0 65f46131f366bdd21aa98701f4110ecb801d2c8d. B0 is the fixed evidence/harness source,
not a replacement compiler or runtime dependency. A user-selected complete
immutable replacement tuple takes precedence; otherwise do not retarget anything.
The preceding PRs and bounded programme have landed and closed. Do not wait for
another merge, follow moving main, repin for cosmetic SHA alignment, downgrade
to investigation snapshots, take over the old PRs, or reopen their reviews.
Treat historical pending-status prose and accepted costs according to section 2.7.

Create your own isolated workspace, unique World branch, and early draft PR
assigned to tkersey. Preserve unrelated and concurrent work. Continue that same
candidate when resuming. Do not merge, release, promote, or modify Boundary or
Agent production code.

Deliver all three outcomes:
A. Transaction setup/commit for a small changed frame set must not enumerate
   every dormant frame merely to preserve or discard rollback state.
B. An unchanged parked resident must safely reuse its established expected
   request binding instead of rebuilding full canonical State for each reply
   check, without weakening parsing, value admission, invalidation, or rollback.
C. Demonstrate the specified complete-lifecycle WASM gain and guardrails while
   preserving exact same-image execution, prompt reclamation, and publication
   atomicity.

Choose the simplest correct representation. First-touch journaling, a persistent
frame-map root, and compact observation metadata are candidates, not commands
to build three mechanisms. Preserve semantic histories and required general
paths. Remove actual superseded production bookkeeping in the same slices;
do not ship old/new selectors.

Build baseline and candidate native/WASM artifacts yourself through existing
World tooling. Both execute the same fixed programme corpus and controls.
Different candidate kernel hashes are expected. A missing old cached kernel
does not justify inventing a setup system: reproduce the selected baseline
source through the normal build and retain its actual identity.

Start with the retained-history discriminator and a real transaction-path change.
Then deliver unchanged-observation reuse and cumulative lifecycle qualification.
Keep original-program semantics, all required input/ownership checks, scalar and
tail-reuse benefits, cleanup, and reclamation. Do not improve timing by disabling
features, increasing default capacity, retaining dead backing, changing images,
or moving work into an unmeasured phase. Preserve the semantics and benefits of
the landed sparse COW pages and Prepared-owned exact layout classes; do not
claim those as new work. An equally correct in-scope replacement is permitted,
not a competing production path. Packed insertion/removal can move physical
values even when a page address remains the same.

Use the corrected reset-on-command memory-observation discipline: sample each
operation before the next can erase its peak, including failures, cancellation
and cleanup, and retain the whole-sequence maximum. Keep memory-pass timings
separate. Existing fresh-invocation Agent replay is a guardrail, not the required
H/Q live-Resident lifecycle. Never present a candidate under A0's old runtime lock;
use the bounded test integration route with the candidate's actual identity.

Run focused checks while editing and the complete required final package,
capacity, native/WASM/Wasmtime/browser, transfer, and real-consumer validation
on coherent candidate inputs. Preserve independent baseline/oracle evidence.
Do not weaken tests or infer performance from counters alone.

Keep construction, planning, and repairs in this driver session. Do not launch
another implementation driver, switch model/reasoning, inspect another
candidate, or build comparison orchestration. Normal independent reviewers
remain governed by the currently installed serial-review workflow.

Record P0 before independent review and P1 after review/repairs, with actual
executed evidence and available phase-separated usage. Report missing telemetry
honestly. Keep the PR draft and update it throughout the work.

Execute the task rather than returning another plan or commands for me to run.
An acquisition failure for a pinned input, missing permission/tool, or a required
new-tradeoff decision blocks only its dependent work/claim. Name the exact
obstruction and preserved progress; never invent a successful qualification
or silently widen scope.
Finish at the specification's definition of done.
```

---

## 14. Acceptance matrix

These are obligations, not forty new processes or one required task per row. A shared fixture or verifier can satisfy multiple rows when its actual observations establish each claim.

| ID | Required acceptance observation |
|---|---|
| **W01** | The fixed landed W0/A0/D0/C0 selections, B0 evidence role and spec identity are recorded. Compiler, runtime-data and historical delivered-kernel identities are not conflated or repinned. Historical pending narration does not reopen completed upstream work. |
| **W02** | Baseline/candidate builds use the same fixed data dependency, toolchain/profile, programme bytes, and applicable controls. New candidate kernels have their own identities. |
| **W03** | Existing semantic persistent views, sparse/dense COW-page behavior and deliberately shared mutable state survive the replacement; no redundant “new COW subsystem” is credited. Packing savings and logical/physical slot distinctions remain protected. |
| **W04** | H demonstrates no unconditional all-retained-frame enumeration/fork/discard in successful transaction setup/commit for a fixed small mutation set. Counter evidence and the actual path argument agree. |
| **W05** | Untouched frame reads do not manufacture rollback versions; conservative write-acquisition is bounded and reported rather than expanded to all F. |
| **W06** | Failure establishing first-mutation protection leaves the entry state and ownership intact. No unprotected mutable pointer is exposed first. |
| **W07** | Repeated mutation followed by failure restores the transaction-entry version, not an intermediate saved value. |
| **W08** | Frame create/remove sequences preserve correct entry membership and physical ownership on both commit and rollback. |
| **W09** | Deletion/recreation and identifier or slot reuse cannot confuse an old entry with a new occupant or revive a stale handle. |
| **W10** | Semantic forks retained before and created during a drive remain correct after commit or rollback; branch-local and intentional sharing are independently distinguished. |
| **W11** | Custody, initialized slots, liveness, function/position, borrows, scope movement, and cleanup order remain consistent with the logical frame. Packed shifts/growth cannot leave a stale physical pointer or index, including failure/rollback cases. |
| **W12** | Collection and imported/shared backing retain rollback-needed objects until resolution, without preserving transaction-only roots indefinitely after commit. |
| **W13** | Rollback performs no allocation, including after late failures. Repeated failure/retry does not leak or exhaust a growing private history. |
| **W14** | Every supported resident output route preserves prior authoritative State and pending binding on output/encoding/capacity failure; unchanged-input retry succeeds. |
| **W15** | Repeated drives at stable retained state have bounded live journals/views/cache/scratch; live and reserved memory are not conflated. |
| **W16** | Initial request identity is produced through the existing canonical contract and matches W0 for the same parked state. |
| **W17** | Q's unchanged expected-binding checks perform no repeated full-state projection/serialization solely for that check, including the prescribed invalid replies. |
| **W18** | A correctly bound response still receives required parsing/value admission; malformed, ill-typed, wrong-image and genuinely wrongly bound replies reject as before. |
| **W19** | A successful state change or cancellation-created replacement request invalidates/replaces the old private binding exactly where required. |
| **W20** | A reply that advances privately and then fails publication restores the original computation and an applicable expected binding; retry uses the original valid response. |
| **W21** | Restored execution works in a fresh process without inherited private metadata; new metadata is derived from the admitted restored state. |
| **W22** | Reuse is sound across the actual sanctioned mutation surface. Permitted low-level Session access is preserved, not silently forbidden to justify a cache. |
| **W23** | Observation reuse does not retain a duplicate full checkpoint/state graph or create external-response/approval memoization. |
| **W24** | Checkpoint/inspection remain semantically read-only; output owns its backing; successful transfer and failed transfer preserve their respective custody rules. |
| **W25** | All short scalar prefixes, zero quantum, checked-failure boundaries, and selected collection cuts match exact baseline logical outcomes and canonical State. |
| **W26** | Dead large backing is reclaimed at the required public boundary without postponement to another command or teardown. |
| **W27** | Direct, captured, indirect and resumption/cleanup aliases remain valid; alias scaling does not introduce another uncontrolled repeated full trace. |
| **W28** | Existing compatible/incompatible tail behavior, simultaneous/repeated arguments, packed-page boundaries and wide sparse layouts remain correct with measured costs. Prepared-owned exact compatibility, dynamic custody, bounds and lease lifetime stay enforced without repeated full-layout classification. |
| **W29** | Baseline↔candidate and native↔WASM matching-image checkpoint transfer succeeds, including fresh-process restoration and suspended cleanup. |
| **W30** | Actual Node/WASM, Wasmtime, browser Workers, stale/cross-instance handles, reentry and capacity controls retain the selected public contract. |
| **W31** | The fixed Inquiry, document and recursive-parser scenarios preserve their existing assertions, approvals, tool restrictions and deterministic outcomes. |
| **W32** | At least one prescribed complete H/Q WASM lifecycle satisfies the primary repeated-window win rule; both remain in the results and use live Resident handles. Qualified fresh-invocation consumer replay is retained separately and cannot substitute for this observation. |
| **W33** | Required timing/memory guardrails have no unaccepted material new regression from W0; smaller/inconclusive changes and accepted historical costs remain visible. Peak evidence uses corrected per-command sampling over the complete interval, not a cleanup-reset field. |
| **W34** | Initial observation, preparation, commit/discard, export, failure/retry, cancellation and release costs are reported, without hidden deferred work or denominator changes. |
| **W35** | The affected successor is canonical; superseded production rollback/reconstruction paths and selectors are gone. Necessary semantic/general cases remain. |
| **W36** | Independent reference and existing tests retain their obligations. Any oracle correction has source-grounded independent evidence and separate attribution. |
| **W37** | The packaged runtime operates outside source/build caches through existing delivery tooling; candidate bytes use their actual provenance rather than A0's historical lock. Bulk experiment evidence is not shipped as production baggage. |
| **W38** | This execution owns one unique early draft World PR assigned to tkersey; neither upstream nor another candidate's work was overwritten or adopted. |
| **W39** | P0/P1, actual review/repair evidence and available usage are distinguishable; no model switching, hidden helper implementation, or fabricated consumption is present. |
| **W40** | The final report separates implementation, correctness, economics, and limitations. No unresolved requirement is erased to claim completion. |

---

## 15. Source and skill provenance

### 15.1 Engineering source anchors

These immutable sources ground the post-merge revision. The specification states the required behavior in full; linked historical records are provenance, not instructions to reproduce the old assignment. Source inspection, reported execution and independently observed provider status are distinct evidence.

| Ref | Source | Relevance |
|---|---|---|
| S01 | [World PR #59](https://github.com/tkersey/world/pull/59) and [landed W0](https://github.com/tkersey/world/commit/c61edfc8208c375d5188e476131ca8cff5aeeb8a) | Merge identity and final closure account; supersedes earlier pending-review narration for status only. |
| S02 | [Activation slots](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/src/interpreter_v2/activation_slots.zig) | Existing COW views, sparse packed successors, dense growth and lifetime/failure tests. |
| S03 | [Activation frames](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/src/interpreter_v2/activation_frames.zig) | All-frame backup remains; mutable frame surface and Prepared-owned layout reference. |
| S04 | [Stable Session](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/src/interpreter_v2/stable_session.zig) | Transaction state, repeated pending reconstruction, checkpoints and exact execution. |
| S05 | [Store](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/src/interpreter_v2/store.zig) | Existing first-touch node/blob journaling, collection and ownership. |
| S06 | [Resident](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/src/interpreter_v2/resident.zig) | Shared output publication, rollback, close and transfer. |
| S07 | [Invocation](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/src/interpreter_v2/invocation.zig) | Fresh lifecycle and request/checkpoint output construction. |
| S08 | [Prepared](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/src/interpreter_v2/prepared.zig) | Immutable admitted Program lease, external contracts and exact frame-layout classes. |
| S09 | [Value projection](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/src/interpreter_v2/value_projection.zig) | Existing encoded-sequence projection and schema-fact derivation. |
| S10 | [Kernel ABI](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/docs/kernel-abi.md) | Capacities, handles, outputs, public semantics and portability. |
| S11 | [Consolidated acceptance](https://github.com/tkersey/boundary/blob/93340dade30b7d27a1e139f107359f91fb66fad3/docs/optimization-acceptance.md) and [measurement/archive index](https://github.com/tkersey/boundary/blob/93340dade30b7d27a1e139f107359f91fb66fad3/docs/performance/optimization-acceptance.json) | Bounded delivered packages, accepted historical costs and exact archived evidence. Initial status prose is historical relative to final PR closure. |
| S12 | [Agent PR #39](https://github.com/tkersey/agent/pull/39) and [landed A0](https://github.com/tkersey/agent/commit/b1f9d2866b5717d16339e7022a3b4d08951f0770) | Fixed consumer source and final profile/integration closure. |
| S13 | User-supplied **Boundary Optimization Program, Version 2.0, September 25, 2026**, especially §§2.1, 9.4–9.5, P22/P25/P26 | Same-image boundary and inherited numerical guardrails, restated here. Its retired selectors, broader programme and historical setup are not imported. |
| S14 | [Boundary PR #161](https://github.com/tkersey/boundary/pull/161) and [landed B0](https://github.com/tkersey/boundary/commit/93340dade30b7d27a1e139f107359f91fb66fad3) | Completed canonical compilation and optimization programme. |
| S15 | [World dependency selection](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/build.zig.zon) | Exact D0 and pure-data production build boundary. |
| S16 | [Agent compiler selection](https://github.com/tkersey/agent/blob/b1f9d2866b5717d16339e7022a3b4d08951f0770/build.zig.zon) | Exact C0, distinct from D0. |
| S17 | [Agent authenticated dependency lock](https://github.com/tkersey/agent/blob/b1f9d2866b5717d16339e7022a3b4d08951f0770/conformance/agent4/dependencies.lock.json) | Compiler/runtime/source/package/profile/delivery identities; historical publication prose is not a current merge gate. |
| S18 | [World frame-layout qualification](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/docs/frame-layout-qualification.md) and [raw record](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/docs/frame-layout-qualification.json) | Local versus cumulative costs, corrected peak fields, consumer replay scope and exact source identities. |
| S19 | [Agent final-link repair](https://github.com/tkersey/agent/blob/b1f9d2866b5717d16339e7022a3b4d08951f0770/conformance/agent4/evidence.md#final-link-profile-repair) and [compiled-tool implementation](https://github.com/tkersey/agent/blob/b1f9d2866b5717d16339e7022a3b4d08951f0770/src/compiled_tool.zig) | Profiles reach final closed linking; 123 emitted files preserved; corrected runtime subdirectory guidance. |
| S20 | [Frame layouts](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/src/interpreter_v2/frame_layouts.zig) | Exact-equality partition with collision, arity and allocation tests; not a second admission checker. |
| S21 | [Current layout sampler](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/test/current/frame_layout_qualification.mjs) | Per-command peak folding and separated timing scopes. |
| S22 | [Kernel command entry](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/src/kernel/main.zig) | Budget observation resets; baseline physical profile and publication. |
| S23 | [Existing WASM consumer replay](https://github.com/tkersey/boundary/blob/93340dade30b7d27a1e139f107359f91fb66fad3/test/consumer_runtime_replay.mjs) and [native consumer comparison](https://github.com/tkersey/world/blob/c61edfc8208c375d5188e476131ca8cff5aeeb8a/test/current/native_consumer_cost.mjs) | Fresh-invocation replay of exact commands, not an already implemented H/Q Resident benchmark. |

No new optimization, benchmark or paired model trial was executed in preparing this revision. The merged sources and targeted changes were inspected, provider merge status and the named successful producer job were read, and qualification accounts were reviewed. Their measurements remain reported evidence rather than independently rerun results. This is a scoped review for the next runtime handoff, not an exhaustive audit of all 31 compiler packages or all historical review receipts.

### 15.2 Skill references checked

The consulted dotfiles snapshot was:

```text
f7228a8d188f72be666f5e3db5bcce3e677580df
```

Main was re-resolved during the September 30 post-merge update and remains this exact snapshot. The inventory, applicable AGENTS guidance, four selected skill definitions, invocation metadata and relevant performance references from this snapshot were already read in this conversation. Their unchanged contracts are reused—not names or procedures inferred from older remembered workflows. No skill dependency, mode, tracker, review quota or model-selection mechanism is added by this revision.

| Source | Role in this handoff |
|---|---|
| [codex/AGENTS.md](https://github.com/tkersey/dotfiles/blob/f7228a8d188f72be666f5e3db5bcce3e677580df/codex/AGENTS.md) | Applicable capability, scope, tooling and evidence-owner guidance. |
| [Actuating SKILL.md](https://github.com/tkersey/dotfiles/blob/f7228a8d188f72be666f5e3db5bcce3e677580df/codex/skills/actuating/SKILL.md) and [invocation metadata](https://github.com/tkersey/dotfiles/blob/f7228a8d188f72be666f5e3db5bcce3e677580df/codex/skills/actuating/agents/openai.yaml) | Existing implementation and serial-review route; current owner loads its required guidance. |
| [Tune SKILL.md](https://github.com/tkersey/dotfiles/blob/f7228a8d188f72be666f5e3db5bcce3e677580df/codex/skills/tune/SKILL.md), [metadata](https://github.com/tkersey/dotfiles/blob/f7228a8d188f72be666f5e3db5bcce3e677580df/codex/skills/tune/agents/openai.yaml), [performance](https://github.com/tkersey/dotfiles/blob/f7228a8d188f72be666f5e3db5bcce3e677580df/codex/skills/tune/performance.md), and [software performance](https://github.com/tkersey/dotfiles/blob/f7228a8d188f72be666f5e3db5bcce3e677580df/codex/skills/tune/references/software-performance.md) | Measured software optimization, preservation and reporting. |
| [Ergon SKILL.md](https://github.com/tkersey/dotfiles/blob/f7228a8d188f72be666f5e3db5bcce3e677580df/codex/skills/ergon/SKILL.md) and [metadata](https://github.com/tkersey/dotfiles/blob/f7228a8d188f72be666f5e3db5bcce3e677580df/codex/skills/ergon/agents/openai.yaml) | Small durable dependency-aware task graph; storage and transactions remain with its current owner. |
| [Metanoetic SKILL.md](https://github.com/tkersey/dotfiles/blob/f7228a8d188f72be666f5e3db5bcce3e677580df/codex/skills/metanoetic/SKILL.md) and [metadata](https://github.com/tkersey/dotfiles/blob/f7228a8d188f72be666f5e3db5bcce3e677580df/codex/skills/metanoetic/agents/openai.yaml) | Scope-preserving reconsideration of unnecessary costs and mechanisms. |

Repository availability does not establish local installed availability. Resolve actual available definitions at execution entry; record meaningful drift without changing global configuration or reconstructing a historical workflow.

---

**Completion means that large retained possibility spaces no longer impose unnecessary whole-state administration on small steps, exact pending observations are reused soundly, and the improvement survives the full native/WASM lifecycle—not merely that a faster alternative exists behind another flag.**