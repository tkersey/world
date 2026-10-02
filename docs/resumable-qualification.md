# Change-proportional resident execution

Work in progress. The first transaction slice is implemented and locally checked;
complete-task and performance acceptance remain open.

## Inputs and execution

- Run: `01a0fc7f-2d47-7a50-b1be-68c8f42f82fc`; independent driver; serial reviews.
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

Production A/B, H/Q structural observations, complete lifecycle measurements and guardrails, allocation failure and ownership coverage, frozen Agent corpus, final native/WASM/Wasmtime/browser/package qualification, early draft PR, P0/P1, serial review closure, and W01–W40 final audit.
