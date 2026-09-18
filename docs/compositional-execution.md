# Compositional execution: World status

World `6.0.0-dev.0` implements the runtime portion of the accepted Boundary 3 /
World 6 / Agent successor. The milestone remains incomplete: performance gaps,
remaining workload measurements, consumer retirement and serial review closeout
are still open. Delivery is limited to linked draft PRs; no merge or release is
authorized.

The branch is `feat/compositional-execution`, based on World 5.0.2 at
`d075169a4805d999ceba4c37b3e1c925b78c3bf9`. Its manifest now selects Boundary
`652a798e9f6646d2d3d71efe29b2bb7e07591a8a`. The analysis-index candidate passes
the full World aggregate through both an immutable source override and the normal
dependency pin. The linked drafts record coordinated Agent qualification.

Linked drafts: [Boundary #152](https://github.com/tkersey/boundary/pull/152),
[World #54](https://github.com/tkersey/world/pull/54), and
[Agent #32](https://github.com/tkersey/agent/pull/32).

## Current runtime

`stable_session.zig` is the sole production evaluator. It consumes Boundary's
stable-activation records directly. World imports Boundary's pure data module;
the compiler is an explicit test dependency, and linking remains Boundary-owned.
The public contracts are BPI3, PST3, PKI3/PKO3, ERQ3/ERS3 and kernel ABI 3.
Predecessor executable records, raw graph State, control argument vectors,
interpreters, codecs and frozen-kernel acceptance gates are retired.

Function inputs populate stable slots. Changed-only edge assignments read their
sources simultaneously and omit dead copyable destinations. Continuations own
private frame views. A singly-custodied control becomes its saved continuation
in place after outgoing operands are gathered: its node ID and frame handle are
retained. Multi-shot activation still clones a template. Departed controls release
their frames; saved continuations retain theirs.

`activation_slots.zig` uses 16-slot pages under a radix directory. Unique prefixes
are updated in place; shared or missing suffixes are prepared before publication.
Retained views isolate slot rebinding. They do not copy semantic referents:
branch-local cells are relocated by the graph cloner, while genuinely outer cells
remain shared. Private addresses, generations and reference counts never enter
portable identity. Handles reject foreign/stale owners and iterators reject
mutation. Graph cloning requires the frame owner, preventing omission of values
held only in activations.

Liveness differences reclaim dead bindings. Physical tracing follows only live
frame and aggregate fields. Lexical custody is separate: slot-indexed links track
establishment order, normal exits splice surviving owners into the parent, and
failure/cancellation dispose inside-out. Consuming an owner removes its link, so
repeated cycles do not retain an execution history. Physical collection runs no
source-visible finalizers.

Deep/shallow, linear/multi-shot, value/computation and successor-handler resumptions
share the evaluator. Explicit capabilities retain their identity while lexical
context links change. Admitted total tail clauses use ordinary continuations
without creating resumption tokens. The selected delimiter remains active for
checkpointing and cancellation. Non-tail, shallow, escaping and reentrant clauses
continue through their general paths.

## Ownership and efficient values

Prepared Programs own immutable admitted bytes, derived schema/effect facts and
analysis sets. Sessions retain leases; per-session set overlays cannot mutate the
shared base. Fresh invocation creates the same prepared/session owners and releases
them afterward. No caller-supplied analysis or mutable decoded record grants
admission. Initialization, availability, obligations and liveness remain separate.

Arguments are validated before publication and copied once into Store backing;
scalars remain inline. Typed views are derived internally, so callers cannot forge
borrowed storage. Exportable value construction writes its encoding into the final
owner and transfers it only on success. Interning releases duplicate buffers;
allocation failure leaves caller ownership intact.

Structured sequences use immutable shared field backing. Consuming slices copy a
geometric series instead of every remaining tail, and quarter-size compaction
bounds backing retention. Encoded sequences use private cursors into admitted
bytes, with the same compaction rule. Only live fields are graph roots; physical
sharing grants no permission to copy a linear value. Read-only checkpoint
projection emits ordinary canonical values and no private cursor tags.

Terminal outcomes live in a Store-owned exit, not cached borrowed fields. Terminal
collection traces the complete result and releases dead arguments. Resident
compaction prepares survivor copies inside its journal and retains old backing
until commit. `Session.observe()` and `terminalExit()` read the authoritative owner.

## Portable and resident execution

Fresh and resident execution use one evaluator and explicit instruction/control
quanta. PST3 projection does not advance execution or collect it. Restoration
checks the complete Program-relative graph, activation bindings, cleanup custody,
capabilities and pending interaction identity. Malformed and stale replies reject
against the current pending binding. Old formats have no fallback path.

Resident operations use an atomic gate against concurrent/reentrant calls. A drive
commits only after detached output allocation or caller-buffer encoding succeeds.
The Store journals first versions of changed entries; frame backup retains COW
roots without copying values. Failure restores roots, positions, pending control,
exit state, values and lexical custody without allocating during rollback. The
journal is bounded by entry state rather than transition history.

Resident drives omit portable checkpoints unless requested. External request
binding still hashes canonical State, currently through temporary materialization.
`checkpoint` exports without advancing; `takeCheckpoint` releases custody only
after successful export. `close` requires terminal state. Unfinished work must
complete cleanup or transfer through a checkpoint before physical release.

The generic kernel and browser-neutral byte embedding support fresh/resident
execution through native, Node, Wasmtime, Chromium and Firefox hosts. Node file
loading is separate. Kernel admission binds an owned byte copy, digest, engine
validation and static ABI inspection before instantiation. A weak cache may reuse
the last admitted module after a fresh digest check; instances, tokens and Sessions
remain fresh. Cache loss falls back to ordinary admission. Input, working and
output budgets are independent, and output failure participates in rollback.

See [kernel-abi.md](kernel-abi.md), [verification.md](verification.md), and the
current package API for exact signatures, safepoints, limits and commands.

## Verification and catalogue-pruning fixtures

The current immutable Boundary candidate passes:

```sh
zig build check -Dboundary-source=/absolute/immutable/boundary \
  -j4 --global-cache-dir .zig-global-cache --summary all
```

The result is 32/32 build steps, 74 source tests, 39 storage tests, 30 host tests,
6,755 independent source-oracle observations, native/Node/Wasmtime agreement,
Chromium/Firefox Worker transfer and extracted-package checks. Zig is 0.16.0 and
Node is 26.8.2. The kernel is 460,967 bytes with SHA-256
`2564f95ac3f3b8ba24242c21f80d651b7e8a339940336a357223c5393a7b20e0`.
These results do not establish full performance acceptance or qualify future pins.

Pruning exposed four fixtures that reused source catalogue IDs or unreferenced
declarations after closed compilation. General-handler and deliberate malformed-
State fixtures now obtain declaration-preserving component records, then still
encode/admit a closed Program. Normal selected-handler cases continue through
closed compilation. The expected results, capture counts, cleanup behavior,
InvalidState/InvalidOwnership errors and checkpoint assertions are unchanged.

Coverage includes:

- Real handler installations with the final checked sum preserved, typed joins,
  answer transformation, escaping suspension, recursive/reentrant multi-shot,
  branch-local/shared cells, retained loop versions and 10,000 tail calls.
- General versus total-tail handling at every instruction checkpoint, including
  cancellation inside protected clauses and exactly-once external cleanup.
- Retained scoped computations with distinct definition/use capabilities, expected
  result `[1121, 99]`, and cleanup payload 77 on normal and cancelled completion.
- Resource representation changes through stable interfaces, suspended loans,
  return-clause reference bounds and same-slot rebinding provenance.
- Cleanup order, yielded/suspending cleanup, first cancellation reason, primary
  failure precedence, accumulated cleanup failures and abandoned captures.
- FIFO unique suspension packages, encoded/structured sequence consumption,
  tiny survivors, graph aliases/cycles and allocation-failure sweeps.
- Resident rollback after mutation, retry from identical checkpoints, output
  capacity, failed checkpoint transfer, reentrancy, freed-ID reuse and imported
  backing. An independent flat-array model checks mixed slot lifecycles.
- Linked effectful components and recursive imports; actual Worker/native/Worker
  transfer with source-independent runtime packages.

## Bounded analysis indexes

The selected Boundary source uses checked 32-bit private set indexes while
retaining 64-bit member IDs. This shrinks native tree records, interning keys and
per-position facts. Existing roots remain reusable at index capacity; new-root
exhaustion fails before publication. wasm32 index/node widths are unchanged.

The [source-bound comparison](https://github.com/tkersey/boundary/blob/652a798e9f6646d2d3d71efe29b2bb7e07591a8a/docs/measurements/analysis-root-width.json)
reports native control64 medians of 359/361 microseconds versus 374/376 before,
and peak working allocation of 241,495 versus 282,999 bytes. Control128/256 peaks
fall to 415,111/788,285 bytes. All measured value peaks fall; small higher value
medians remain disclosed. These gains do not close the control64 BPC1 gap.

Native paired inquiry Session peak falls from 3,107,532 to 2,847,222 bytes and
ReAct from 5,201,096 to 4,239,618; both still exceed optimized BPC1. Every paired
scenario preserves its semantic/work counts. These native changes do not establish
WASM guest latency gains. The kernel grows by 116 bytes; authenticated guest
remeasurement is pending.

## Measurements and open performance failures

Measurements remain bound to the sources and methods in their records. Working
allocation is not RSS, total reserved capacity or total browser memory. Store
node/copy counters do not alone establish elapsed-time improvements.

The latest continuation-transfer comparison reports native control64 medians of
401.8/391.2 microseconds versus its preceding successor's 446.6/440.6. Allocation
calls fall from 1,165 to 830 and working peak from 284,973 to 284,448 bytes.
Optimized BPC1 still takes 237.9/239.2 microseconds and 121,956 bytes: this remains
an unresolved regression. Control256 improves to 1.892/1.870 ms versus BPC1's
2.300/2.293 ms. Small higher medians on two value guards remain indeterminate.

The 1 MiB variant-tag workload previously improved from roughly 38 ms under BPC1
to roughly 0.4 ms under the successor. Exact argument ownership reduced a prior
successor peak from 3,691,908 to 2,128,044 bytes; BPC1 still peaked at 2,103,211.
Later changes have their own guarded measurements below. Large-value speed does
not waive small-control or peak-memory failures.

Agent's actual inquiry/repeated/ReAct and producer/build comparisons are recorded
in its linked draft. Inquiry improves, while ReAct latency and inquiry/ReAct
working peaks remain open. Catalogue pruning has reduced emitted image sizes;
the completed matched comparison in Agent #32 shows lower ReAct medians and
about 3% lower inquiry/ReAct working peaks, but the BPC1 regressions remain.
No performance failure is waived by semantic qualification.

| Evidence | Scope |
|---|---|
| [Continuation transfer](measurements/continuation-transfer.json) | Latest control/frame change, isolated candidates, rejected routes and value guards |
| [Solver facts](measurements/solver-facts.json) | Worklist position recording, interner changes and paired windows |
| [Admission buffers](measurements/admission-buffer-ownership.json) | Fact reuse and release of replaced Pool buffers |
| [Control matrix](measurements/control-native.json) | BPI2/BPC1/successor control comparisons and source parity |
| [Preparation profile](measurements/control-preparation-profile.txt) | Sampled attribution for the earlier control regression |
| [Argument backing](measurements/argument-backing-native.json) | Separate exact-buffer/Store ownership levers, retention fix and contended/final samples |
| [Kernel admission](measurements/kernel-admission.json) | Validation/module reuse and first-call limits |
| [Variant access](measurements/variant-tag-native.json) | Targeted value access and complete-invocation comparisons |
| [Frame initialization](measurements/frame-initialization-native.json) | Bounded initialization bookkeeping |
| [Low-word projection](measurements/low-word-native.json) | Earlier liveness projection experiment and limits |

Native probes are `test/v2/build_execution_bench.zig` and
`test/v2/build_value_bench.zig`, with explicit immutable Boundary/World inputs.
The records retain raw observations, reconstruction material, rejected candidates
and attribution limits. Earlier prose milestones are available in Git history.

Remaining work includes the full declared workload matrix and resource
corroboration, resolution of primary-workload regressions, normal dependency and
Agent package qualification on the final candidate, remaining legacy retirement,
serial reviews and a requirement-by-requirement completion audit.
