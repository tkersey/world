# Change-proportional resident execution

The two defects found on the first P0 are repaired. Correctness checks and all
272 economic cells pass, and the repaired H lifecycle meets the primary win rule.
Clean-successor bundle production and independent
serial review convergence remain required. The only public
subject is [draft World #60](https://github.com/tkersey/world/pull/60), assigned to
tkersey and unmerged; its current public head precedes this qualified successor.
The [supplied specification](change-proportional-spec.md), including W01–W40,
remains the accepted task. This document does not narrow that scope.

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
- Repaired successor kernel: `f4c3c3db8c42ffeb085e273c82b775edde6b5b28274508c54e771c9031b9ff7a`, 475692 bytes.
- ABI 3, import-free wasm32; existing 65536-byte stack, 256 MiB maximum,
  default input/working/output budgets 65536/1048576/65536 remain unchanged.

The compiler and runtime-data selections are separate immutable inputs. Agent's
source, policies, approvals and historical runtime lock were not repinned.
World alone contains production changes. Native CLI dependencies explicitly use
ReleaseSafe; the normal World owner builds the WASM product.

## Construction and coverage

Frames owns a first-touch journal. Begin creates an empty journal without visiting
registered frames. Protected mutable acquisition and membership changes save the
entry version once; commit releases only those saved entries. Rollback first removes
all touched successors, then restores originals using retained map capacity, without
allocation. Null entries preserve entry absence across creation/removal/ID reuse.
The original frame-map pointer is read before protection and exposed only afterward;
protection grows its own journal and slot/custody tables, never the frame map.
A last-held shortcut is certified by the nonempty attempt journal and resets with it.
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
H drive. The successor protects zero at begin and one per small drive; the first
costs 1920 bytes. All 64 drives avoid collection. Large retained-population unit
cases independently cover mutation sets 1, 7 and 31, repeated writes and untouched
reads. Saved entries, forks and commit work equal the changed set.

At Q=1024 three invalid responses perform zero checkpoint constructions and one
binding reuse each. Their temporary allocations are 215/64/484 bytes, versus W0's
883969/883818/884238. Diagnostics and the original valid retry agree. The largest
Q agreement also repeats rejection 128 times per arm, preserves exact State and
constant live allocation, and records reserved memory separately.

Executed on this product: 89 native and 74 storage tests, all 39 aggregate steps;
42 independent source fixtures / 8692 exact observations; 159 Wasmtime/native/Node
transfer boundaries; real Chromium 153.0.8010.12 and Firefox 155 Workers; codecs,
capacity, storage WASM and extracted standalone package checks. Additional proofs:
19 prescribed/neighbor H/Q cells with both transfer directions and late output
failure/retry; 12 fresh-process H/Q cells through Node/native/Wasmtime; six scalar
sizes / 158 observations and exact native memory equality; ten frame cases / 6530
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
| wasm H | 0.909635 | 9.04% | 5.452 ms | 2331659 → 2204299 |
| wasm Q | 0.945528 | 5.45% | 1.791 ms | 2044517 → 1962213 |
| native H | 0.492884 | 50.71% | 3.630 ms | 2976143 → 2762575 |
| native Q | 0.719917 | 28.01% | 1.076 ms | 2636580 → 2504932 |

The repaired WASM H primary cell meets the prospective win rule in all five
windows. Q's largest median is lower, but only three windows cross 0.95, so that
cell is inconclusive under the fixed rule. Both native primary cells qualify.
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
1544/1560/112 bytes. Working/live allocation is distinct from reserved linear memory
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

[Machine-readable report](change-proportional-execution.json) binds source/product
hashes, exact scopes, cells and open work. [Raw evidence archive](performance/change-proportional-raw.tar.gz)
SHA-256: `6d73c78e9e6b917a2d2127aab77e9aa8401a03c186121838bd37ffd985871027` (20963559 bytes), with historical and repaired-source
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

Runtime prepare/acquire/verify must run on the clean committed successor through
World's existing producer, including source-free verification and smoke. Its actual
source/tree/kernel/profile/package/delivery identities will be recorded with P0.
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
confirmations. The repaired review head and P1 are not selected yet.
Material findings or head changes reset all credit. The PR remains draft/unmerged.

Historical Review Fold/negative-evidence custody is unregistered. Current accepted
source/test evidence supports this bounded construction, but not a claim of first
observation, complete history or elimination of every historical failure family.
Available native-goal usage and CAS review usage will be recorded at their phase
boundaries; unavailable model/effort/provider billing is not inferred. Required
producer/review/publication obligations remain open, not waived by local green tests.
