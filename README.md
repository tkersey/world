# World

World is the minimal reference host for Boundary Process ABI programs.

```text
BPI1 + InitialArgs or ABL_PST1 [+ ABL_ERS1]
                         |
                         v
        fixed Boundary Process kernel WASM
                         |
                         v
             World one-reduction host
                         |
                         v
              canonical ABL_PKO1
                         |
                         +-- Requested: typed ABL_ERQ1
```

World pins the fixed Boundary 1.8.0 candidate Process kernel bytes and records
commit `186e0555ca00ffeffbcecfc8a16a8c29ac37c4e1` as the reviewed dependency
binding. It creates a fresh WebAssembly
instance, performs exactly one finite reduction, copies the canonical outcome
bytes out of guest memory, and discards the instance. The published Boundary
1.7.0 lock remains a separate historical conformance source. A caller may
answer a residual request by supplying typed resume bytes in an `ABL_ERS1`
record on a later call.

The World source and release artifact authenticate this configured tuple by
their own Git and distribution identities. A source-free runtime cannot prove
that an upstream Boundary source commit produced the kernel bytes without an
external attestation or rebuild; its embedded verifier checks internal
consistency against the expected tuple supplied by the outer archive checker.

World does not compile programs. It does not define Agent semantics, interpret
BPI1 or Process State in JavaScript, drive a process loop, persist runs, or
resolve effects. The surrounding environment decides whether another reduction
occurs and holds all effect authority.

## JavaScript API

The single public module is `@tkersey/world/process-v1`. It exports exactly:

```text
admitProcessKernel
decodeProcessOutcome
decodeEffectRequest
encodeEffectResult
decodeEffectResult
WorldProcessHostError
```

```javascript
import { readFile, writeFile } from "node:fs/promises";
import { admitProcessKernel } from "@tkersey/world/process-v1";

const processModuleUrl = import.meta.resolve("@tkersey/world/process-v1");
const kernelUrl = new URL("../../boundary-process-kernel-v1.wasm", processModuleUrl);
const kernel = await readFile(kernelUrl);
const image = await readFile("system.bpi1");
const initialArgs = await readFile("initial.bin");

const host = await admitProcessKernel(kernel);
const outcome = await host.advance({
  image,
  instance: { initialArgs },
});

await writeFile("outcome.pko1", outcome.bytes);
```

`advance` accepts byte arrays, snapshots them before asynchronous work, and
requires exactly one of `instance.initialArgs` or `instance.state`. An optional
`effectResult` supplies an exact `ABL_ERS1` record. Returned byte fields are
independent copies and never expose mutable guest memory.

## CLI

World exposes one command and never loops automatically:

```bash
world process step \
  --image system.bpi1 \
  --initial-args initial.bin \
  > outcome.pko1
```

Resume a portable state with an environmental result:

```bash
world process step \
  --image system.bpi1 \
  --state process.pst1 \
  --result effect-result.ers1 \
  --out outcome.pko1
```

Without `--kernel`, the command uses the exact kernel bundled with World 4.
Input paths are admitted as coherent regular-file generations. `--out` publishes
through a sibling temporary file and an atomic rename.

See [Process Host v1](https://github.com/tkersey/world/blob/v4.1.0/docs/process_host_v1.md), the
[security model](https://github.com/tkersey/world/blob/v4.1.0/docs/security_model.md), and
[migration from World 3](https://github.com/tkersey/world/blob/v4.1.0/docs/migration_from_world_3.md).
