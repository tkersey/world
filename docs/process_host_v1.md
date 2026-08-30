# Boundary Process Host v1

World 4 embeds one fixed semantic engine: the Boundary 1.7.0 Process kernel at
commit `4fd4cd959ea283a6b5af12a228f0d80a102683e3`. The kernel is 647,473 bytes,
has SHA-256 `178f9c2fb79402a85ab5a7905586879347ad5c99f988127eec001c9ecfd813f0`,
declares ABI 1 and a 4,096-page memory maximum, and imports nothing. The release
lock in `conformance/boundary.lock.json` binds the complete public source/kernel
tuple. Boundary owns program meaning; World owns only artifact admission,
WebAssembly instantiation, host-facing record framing, and byte transport.

## Kernel admission

`admitProcessKernel(kernelBytes, { expectedSha256 } = {})` synchronously copies
the caller's bytes. Before any guest code executes, it requires a valid wasm32
module with zero imports, no start section, one exported unshared memory with a
declared maximum, and the exact Process Kernel ABI v1 export names, kinds, and
function signatures. It authenticates the bytes against World's fixed Boundary
kernel digest; `expectedSha256`, when supplied, is an additional exact lowercase
digest assertion.

Only after static inspection and digest authentication does World instantiate
one disposable admission instance and require
`boundary_process_kernel_abi_version() === 1`. That instance is discarded. The
admitted host retains the immutable `WebAssembly.Module` and artifact metadata,
not an instance, memory, process state, request, result, or scheduler.

The frozen admitted-host object exposes only `abiVersion`, `byteLength`,
`sha256`, static `inspection`, and `advance`.

## One reduction

```javascript
const outcome = await host.advance({
  image,
  instance: { initialArgs }, // or exactly { state }
  effectResult,              // optional ABL_ERS1 bytes
});
```

`advance` snapshots every input before its first asynchronous operation. It
instantiates a fresh WebAssembly instance from the admitted module and invokes
the kernel preparation path with unsigned 64-bit lengths. The payload order is
exactly:

```text
BPI1 image
InitialArgs or ABL_PST1
optional ABL_ERS1
```

When preparation succeeds, World bounds-checks the exported input range, copies
the payload, and invokes `boundary_process_kernel_execute` exactly once. It
reacquires the memory buffer after calls that may grow memory, copies the
complete output away from guest memory, then discards the instance.

Preparation returning zero is a triage point, not an automatic capacity signal:

1. A nonempty kernel output must strictly decode as `NeedsCapacity` and is
   returned as an ordinary outcome.
2. Otherwise a nonempty bounded kernel diagnostic becomes a redacted
   `WorldProcessHostError`.
3. Otherwise World throws a generic preparation failure.

World never calls `execute` after zero preparation and never retries a
`NeedsCapacity` outcome. The caller decides what happens next.

## Outcomes

`decodeProcessOutcome` strictly validates canonical `ABL_PKO1` framing, version,
reserved bytes, lengths, exact end, and kind-specific shape. It exposes one of:

| Kind | Opaque data |
| --- | --- |
| `Progressed` | portable state |
| `Requested` | portable state and a validated `ABL_ERQ1` request |
| `ExplicitlyYielded` | portable state |
| `Completed` | result bytes |
| `AuthoredFailure` | failure bytes |
| `NeedsCapacity` | four unsigned 64-bit requirements |

World does not interpret the state, result, or failure payloads.

## Effect relay

`decodeEffectRequest` strictly validates the self-contained `ABL_ERQ1` record,
including canonical natural-number framing, UTF-8 semantic identity, digest
bindings, payload digest, and exact record end. The payload and its schema remain
opaque.

Its validated view exposes the owning request bytes, request identity,
transition, pre-request-state, effect-site, payload-schema, resume-schema, and
continuation digests, plus the semantic identity string and opaque payload.

`encodeEffectResult({ request, resume })` revalidates the exact request, carries
its request-identity and resume-schema digests into canonical `ABL_ERS1`, and
copies the caller's canonical typed resume bytes. World does not decide whether
the resume conforms to that schema; the Boundary kernel validates it
authoritatively. `decodeEffectResult` validates only the generic record framing
and exposes the owning record bytes, request-identity digest,
resume-schema digest, and opaque resume as independent byte copies.

World adds no generic success, rejection, retry, cancellation, or failure
status. Those distinctions belong to an effect's typed resume schema when its
program needs them.

## Byte ownership and concurrency

Returned containers are frozen and every byte field is an owning copy. A caller
may mutate its own copy without changing another field, caller input, or
WebAssembly memory. One admitted host may service
overlapping `advance` calls because each call creates a distinct instance and
memory. This proves guest-state isolation, not parallel CPU execution.

## Command-line file boundary

`world process step` opens each kernel, image, instance, and optional result as
an exact regular-file descriptor; records device, inode, size, mtime, and ctime;
reads the declared generation through that descriptor; probes for growth; and
rechecks every generation before execution. It rejects cross-file mutation and
input/output inode aliases. `--out` uses a mode-0600 sibling temporary file,
file synchronization, atomic rename, and parent-directory synchronization.
