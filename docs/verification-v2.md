# Portable effects verification

The source oracle, target execution, serialization laws and formal model answer
different questions. Boundary's source oracle evaluates the staged source AST
with higher-order host closures. It does not execute BPI2. World executes the
emitted BPI2 through its native interpreter and the same interpreter compiled
to WASM. JavaScript and Wasmtime make independent ABI calls.

Source agreement compares observable values, residual payloads, yields and
exit information. Target agreement compares exact canonical PKI2/PKO2 bytes at
matching boundaries. A saved State is replayed by a fresh instance; transfer
tests alternate the actual producer. Pure snapshot tests cover canonical byte
round-trip and alpha-renaming. None of these checks establishes truthful host
results, global exactly-once I/O or historical reachability of arbitrary State.

## Semantic witnesses

Boundary emits the named `source-*.bpi2` programs and independent source scripts.
`test/v2/source_agreement.zig`, `source_transfer.mjs` and `transfer.mjs` exercise
them. Release conformance consumes the separately emitted fixture assets and
records exact target inputs/outputs in `world-v2-conformance.json` and `.bin`.

| Required witness | Source program and observation |
|---|---|
| H01 | `deep`: non-tail resumption returns the handled answer to clause postprocessing. |
| H02 | `answers`: the same authored body produces optional and state-paired answers. |
| H03–H04 | `choices-all`, `choices-first`: ordered two-choice enumeration and first solution. |
| H05 | `state-local`, `state-shared`: lexical placement produces `[1,1]` and `[1,2]`. |
| H06 | `nested`: both non-tail postprocessors and delimiters survive transfer. |
| H07 | `shallow`: typed successor handling changes phase; the invalid phase fails. |
| H08–H09 | `injection`, `nested`: distinct attachments and clause/use-site failure handlers remain distinct. |
| H10 | `scoped-reader`: logging forwards both the inside computation and outside continuation. |
| H11 | `generator`: an authored caller retains, transfers, resumes and closes an owned package. |
| H12 | `reentrant`, `cloned`: nested template activation preserves local cells, aliases and active callers. |
| H13 | Boundary source ownership negatives; `ownership` is the valid two-token counterpart for forged duplicate custody. |
| H14 | `queens-dfs`, `queens-bfs` acquire only after branching; Boundary's latent multi/capture tests reject an exclusive live caller capture. |
| H15–H16 | `unwind`, `clause-abort`, `abort-custody`: parked cleanup, ordered failures, primary-exit priority and cancellation rebinding. |
| H17–H18 | `indexed`: row-polymorphic composition and result-index preservation; a mismatched result rejects before valid retry. |
| H19 | `resource-scalar`, `resource-pair`: one client observes equivalent private representations; unauthorized introduction/elimination and escaping borrows reject. |
| H20 | `reentrant`: a live template/cell cycle transfers and is collected after its final owner exits. |
| H21 | `scheduler`: authored FIFO interleaving, retained packages and a blocked typed join transfer. |
| H22 | Native `tests.zig` and transfer harnesses compare `advance` and `run` at the same observable boundary. |
| H23 | Native failure-injection tests plus `capacity.mjs`: admission, capture/branch creation, unwinding, image emission and output encoding retain unchanged retry inputs. |
| H24 | Recursive/yielding source and native workloads reach externally selected lengths; dead control slots are reused without semantic fuel. |
| H25 / O03 | `test/v2/external/checksum` was authored after `external/freeze.json`: its new byte-mixing operation and handler passed 120 exact records under the recorded kernel digest. |
| H26 | `bpi1_agreement.mjs`: pure lifted data agrees with the frozen public v1 interpreter; no v1 evaluator is in the v2 package. |

The integrated solver explores columns 1–4, reports `[2,4,1,3]` then
`[3,1,4,2]`, and counts 60 attempted placements. It transfers with alternatives
retained and while cleanup is waiting; each selected solution has one acquire
and release pair. BFS changes authored interpretation under the same kernel.

## Admission and operational failures

Boundary data tests independently construct bytes and mutate valid images for
framing, directories, minimal integers, overflow, UTF-8, schema recursion,
catalog references, registers and captures. Source tests cover hidden effects,
answers, representations, use/capture bounds and borrowed-region escape.
Program-relative State admission checks the complete ownership graph, region
topology, blobs, cleanup status, pending contracts and control attachments.
Compiler regressions also distinguish fresh capabilities from older values of
the same family through helpers, product fields, sequence lookups and writes to
handler state. Saved-State substitutions reject before an outward return;
selecting an older field from a helper's temporary product remains valid.
Owned package tests distinguish private captured regions from the implicit
handler and region context borrowed by a nested installation.

`emit_rejections.zig` starts from valid source-derived states before changing
pending contracts, identities, blob types, delimiters, local aliases or token
custody. Native, JavaScript WASM and Wasmtime reject the same serialized inputs.
`wasm.test.mjs` constructs ABI variants independently; `capacity.mjs` forces
each actual guest arena to exhaust, checks that no State is published, and
retries identical bytes with adequate physical capacity. Harness deadlines and
malformed-input bounds are not evaluator fuel.

The physical installation test copies only the permitted components into
independent directories before building public consumers. Forbidden compiler,
oracle, proof, application and legacy execution sources are absent when their
permitted counterparts build. It records actual Zig module arguments and the
public package import closure. The JavaScript source scan is a bounded
observation; executable installation tests and archive inventories provide
the additional evidence. Native logical-record/serialized equality supplies
O05; the protected inventory and anonymous public-asset checks supply O06.

## Retired execution and formal scope

Boundary's old Machine/Process facades, generated evaluator, driver, Agent
compatibility layer and WASM build targets are removed. Their applicable
contracts now have v2 source, data and runtime tests at their respective owners.
Historical records retain their original bytes and identities. Pure BPI1
decoding/lifting remains in Boundary; frozen runtime comparison tooling is
under World's `test/v2/legacy/` and excluded from its public package.

Boundary's `semantics/v2/README.md` names the Lean 4.33.1 theorems and modeled
subset. The checked effectful core includes return/bind, deep/shallow handling,
non-tail resumption, regions and linear/multi disposition, with type/scope/
ownership preservation, progress and simulation to first-order expression
blocks. It does not certify the Zig implementation. Scoped forwarding,
cleanup/cancellation, graph serialization and compiler optimizations have
executable differential evidence and owner-local arguments instead.

Selective tail lowering requires checked effect, answer and usage evidence;
it preserves evaluation order and retains one code body across installations.
Snapshot emission normalizes once before program-relative admission. Cloning
uses a complete remapping relation for local mutable regions while immutable
blobs and unchanged outer references remain shared. Collection traces ownership
roots and never executes a finalizer. These claims are exercised by the
structural checks and phase/allocation measurements in `docs/economy-v2.md`.
