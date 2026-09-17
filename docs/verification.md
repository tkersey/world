# Current execution verification

Boundary's source oracle evaluates the staged AST independently of its compiler
and World. `zig build check-source` emits all 41 current source/BPI3 examples,
compares source-visible results, failures, payloads, yields and cleanup order,
and compares exact PKI3/PKO3 observations between native and WASM execution.
Fresh invocations alternate the actual producer of the next portable State.
The harness asserts the complete expected source/image name sets.

The migrated cases retain 42 borrow-operand inputs, scalar fault cases, deep and
shallow handling, answer transformation, forwarding, generators, retained and
reentrant multi-shot state, indexed effects, resources, DFS/BFS queens, and
cancellation before or during cleanup. The four cleanup-disposal expectations
retain the independent historical oracle correction, including finalizer order
`[3, 7, 99]`. Current fixtures are emitted by the selected compiler; no old-pin
exception or frozen BPI2 image is needed. PKI3 explicitly resumes an already
observed cleanup yield after cancellation records the first reason. Test horizons
count current instructions, not predecessor block transitions.

`check-native` exercises stable slots, retention, source execution, lifecycle,
allocation failure, rollback and PST3 admission. Capture bounds have valid and
invalid one-shot/multi-shot counterparts. Six return-path mutations reject
disposal markers; valid execution restores at every boundary, including captured
cleanup. `check-storage` retains lower-level storage, allocation, cloning and
collection regressions. The old native evaluator and its record-based execution
tests are removed after migration to current source and PST3. Current source
regressions also cover lexical shadowing, full-width zero-size collections,
same-family capability substitutions, forged region/token effects, duplicate
obligations and one-shot custody, and text and binary cancellation reasons.

`check-kernel` checks current native/fresh/resident agreement and handle custody.
`check-transfer` checks an independent Wasmtime embedding. `check-browser` moves
actual State through Chromium and Firefox Workers. These use one generic ABI 3
kernel; the source suite does not claim every host/fixture Cartesian combination.

`check-codecs` covers byte ownership, cross-realm views, intrinsic copying,
current value framing, exact ABI signatures, guest ranges and bounded regular-file
loading. `check-capacity` forces input, working and output budget failures and a
fixed physical-memory failure. It requires no published successor State, unchanged
input, successful retry and cleared output after malformed ABI calls. ABI 3 labels
allocator observations as lower bounds and final output demand as exact.

`check-package` executes the API and CLI from an extracted current npm artifact.
The old ABI 2 guest/host, v1 replay corpus, archive/release tools and old-format
drivers are removed. Current dependency archive authentication and safe extraction
are exercised by Agent's `test/agent4/setup.test.mjs` and
`test/agent4/consumer_build.test.mjs`; final successor repinning and qualification
remain required. Historical performance samples remain available without creating
an old-format production dependency.

These checks do not prove host truthfulness, global exactly-once effects,
historical reachability of arbitrary State, full performance acceptance, or a
refinement theorem for the shipping implementation. Boundary's formal model is a
separately authored semantic model with its own independently runnable checks.
