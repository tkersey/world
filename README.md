# World 5

World executes complete Boundary 2 programs through one Zig interpreter,
compiled natively and to an import-free WASM kernel. Computations, handlers,
search and scheduling policies are program data. Environmental effects are
returned as typed requests for the caller to resolve.

The current development version is `5.0.0-dev.0`, using Zig `0.16.0`.

## Run a program

The runtime archive includes `world-process-kernel-v2.wasm`, a minimal
JavaScript adapter/CLI, strict codecs and an identity manifest. Node 26.8.1 or
newer is required for this embedding.

```sh
node bin/world.mjs process run \
  --image example.bpi2 --initial initial.bin --output outcome.pko2
```

Use `process step` for one bounded internal transition. Resume from `--state`
and optionally `--result`; cancel saved State with `--cancel TEXT` or
`--cancel-bytes FILE`. `--kernel FILE --kernel-sha256 HEX` selects a custom
kernel with an explicit expected digest. Unknown, repeated and incompatible
options reject. Invocation failures leave an existing output unchanged.

JavaScript consumers import `@tkersey/world/process-v2`:

```js
import { run, decodeRequest, encodeResult } from "@tkersey/world/process-v2";
const outcome = await run({ image, initialArgs });
// Requested includes detached State and an ERQ2, not a host effect callback.
```

`loadProcessKernel()` authenticates the bundled kernel through the identity
manifest. `admitProcessKernel(bytes, { expectedSha256 })` admits caller-selected
bytes. The admitted object provides `advance` and `run`; strict codecs include
`encodeInput`, `decodeOutcome`, `decodeRequest`, `encodeResult`, and
`validateValue`. Root `advance` and `run` load the bundled runtime.

Native consumers import the Zig module `world` and use `world.process_v2` with
logical Program/State records or serialized BPI2/PST2. The production Zig
dependency contains only Boundary's pure `boundary_data_v2` module.

## Build and verify

During coordinated development, select exact independent inputs:

```sh
zig build build-v2-kernel -Dboundary-v2-source=/absolute/boundary-source
zig build check-v2-portability \
  -Dboundary-v2-source=/absolute/boundary-source \
  -Dboundary-v2-fixtures=/absolute/boundary-fixtures
zig build check-v2-economy \
  -Dboundary-v2-source=/absolute/boundary-source \
  -Dboundary-v2-fixtures=/absolute/boundary-fixtures
```

`check-v2` also runs native/source agreement and frozen BPI1 comparisons; supply
`-Dlegacy-v1-kernel=/absolute/frozen-kernel` and
`-Dbpi1-lift=/absolute/bpi1-lift`. Source agreement has its own separate test
build. The production build never constructs Boundary authoring modules.
Portability checks use Node and independently implemented Wasmtime 48.0.0
embedding calls, with Python dependencies pinned by `test/v2/wasmtime/uv.lock`
and run through `uv`. Requested external checks execute unconditionally.

Emit both candidates with Boundary's assets already available:

```sh
zig build emit-world-v2-release \
  -Dboundary-v2-source=/absolute/boundary-source \
  -Dboundary-v2-release=/absolute/boundary-assets/release \
  --prefix zig-out/v2
node scripts/v2/check_release.mjs \
  /absolute/boundary-assets/release zig-out/v2/release \
  /absolute/boundary-source .cache/v2/package-check
```

Emission writes the kernel, runtime archive, conformance JSON/binary, receipt,
and checksums under `zig-out/v2/release`. It never publishes, merges or tags.
The verifier checks outer checksums and source bindings before executing the
compiler example or bundled runtime. Optional final arguments select the exact
expected Boundary and World public commits and require clean source receipts.
See [the ABI and API](docs/process_v2-abi.md). The source checkout also contains
measured economy in `docs/economy-v2.md` and the semantic and ownership witness
index in `docs/verification-v2.md`.

## State and effects

Each invocation owns its candidate storage and publishes only after admission
and output encoding succeed. State transfers across fresh native/WASM engines;
there is no originating-interpreter binding. Capacity requirements are physical
observations, and retries use the unchanged authoritative input. `run` has no
semantic fuel and may continue indefinitely for an internally divergent program.

Cleanup is explicit portable control. Cancellation of saved State preserves
already-running cleanup and rebinds its request when State changes. An environment
can encode its already-obtained typed result against that successor request.
The runtime does not provide external rollback or global exactly-once effects.

The v1 public adapter and bundled v1 kernel have been removed. The frozen adapter
under `test/v2/legacy/` is isolated comparison tooling. Historical conformance
records remain unchanged, including their original Boundary version identities.
