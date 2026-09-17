# World 6

World executes complete Boundary programs through one Zig interpreter, built
natively and as an import-free wasm32 kernel. Computations, handlers, policies,
retained control and cleanup are program data. The environment supplies typed
external results.

World `6.0.0-dev.0` uses Zig `0.16.0`. This successor branch is completing the
coordinated Boundary 3 / Agent migration. See [current status](docs/compositional-execution.md)
and the [ABI 3 contract](docs/kernel-abi.md).

## JavaScript and browser Workers

The package root is an environment-neutral byte API:

```js
import { Kernel, encodeInput, decodeOutcome, decodeRequest, encodeResult } from "@tkersey/world";
const kernel = await Kernel.create({ bytes: kernelBytes, expectedSha256 });
const outcome = decodeOutcome(kernel.invoke(encodeInput({ image, initialArgs })));
if (outcome.kind === "requested") {
  const request = await decodeRequest(outcome.request);
  // Resolve the declared operation using the environment's permitted adapter.
  const value = await encodeResult(outcome.request, typedReplyBytes);
  const next = decodeOutcome(kernel.invoke(encodeInput({ image, state: outcome.state, control: "reply", value })));
}
```

Supply expected kernel identity from the consuming application's trusted binding.
The same entry point loads directly in a real browser Worker without Node imports
or a bundler. Inputs and returned buffers have explicit ownership; old image,
checkpoint and envelope families reject.

`prepare`, `start`/`restore`, `drive`, `checkpoint`, `close`, and
`releasePrepared` expose prepared/resident execution through the same evaluator.
Resident checkpoints are explicit; `checkpoint(session, { transfer: true })`
exports and releases only after successful output publication. `close` requires
terminal control. Cancellation and cleanup are executable operations, not physical
handle destruction. Use `setLimits` to select input, working and output budgets.

Native consumers import `world.Session`, `world.Prepared`, `world.Resident`, and
`world.invocation`. Production builds import only Boundary's pure data module.

## Build, package and command line

```sh
zig build build-kernel build-runtime
node zig-out/runtime/bin/world.mjs --help
node zig-out/runtime/bin/world.mjs invoke --kernel zig-out/runtime/world-kernel.wasm --sha256 EXPECTED_SHA256 --input command.pki3 > outcome.pko3
```

The CLI reads regular files, rejects observed changes, and writes canonical PKO3
bytes to stdout. The input is a complete PKI3 command, including image, initial
arguments or checkpoint, reply/cancellation/yield control, and optional quantum.
`build-runtime` creates a standalone package under `zig-out/runtime` without
constructing Boundary's authoring compiler. It does not publish a package.

```sh
zig build check-native check-storage check-kernel check-codecs check-transfer check-browser check-package
```

During coordinated development, `-Dboundary-source=/absolute/boundary-source`
selects the matching source explicitly. `check-native` runs current source and
Session regressions in a separate compiler-dependent build. `check-storage`
also retains native regressions still being migrated from the old evaluator.
Wasmtime uses the locked Python environment through uv; browser checks run
real Chromium and Firefox Workers.

## State and effects

BPI3 contains the closed executable Program; PST3 contains complete portable
execution. Fresh and resident operations publish only after admission and output
encoding succeed. Physical failures leave the prior authoritative input reusable.
Quanta bound internal transitions without changing authored results or effect order.
An unbounded invocation may diverge if the authored program diverges.

A cancelled pending cleanup retains its control and receives a newly bound request.
The environment may re-encode an already acquired typed result against that request;
World does not provide external rollback or global exactly-once effects.

Complete Agent migration, selective/value performance acceptance, remaining legacy
retirement and final package qualification are still in progress. No merge or
release is implied by this development package.
