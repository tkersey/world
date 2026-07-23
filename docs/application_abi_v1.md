# World Application WASM ABI v1

Status: normative.

An application artifact is named `<application>.world.wasm`. It contains the Boundary root machine, every statically closed provider, the World step kernel, and its immutable manifest.

## Structural requirements

The module:

- targets `wasm32-freestanding`;
- imports nothing;
- does not use WASI;
- declares bounded initial and maximum memory;
- requires no external Boundary Module or Executable.Image;
- retains no authoritative semantic state between calls;
- supports continuation from a Frame in a fresh instance.

## Exports

```text
memory

world_abi_version() -> u32

world_manifest_ptr() -> u32
world_manifest_len() -> u32

world_input_ptr() -> u32
world_input_capacity() -> u32

world_step(input_len: u32) -> u32

world_output_ptr() -> u32
world_output_len() -> u32

world_error_ptr() -> u32
world_error_len() -> u32

world_reset() -> u32
```

`world_abi_version` returns `1`. The manifest is readable before the first step. Input must fit wholly within the declared input region. Output and error bytes remain valid until the next mutating export call. The host copies them before reuse or disposal.

`world_reset` returns `0` on success. It clears the input, output, and error regions and resets all scratch or per-call arena state. It preserves the immutable manifest and metadata regions, which remain readable through `world_manifest_ptr` and `world_manifest_len`. Because a conforming module retains no authoritative semantic state between calls, reset cannot advance, rewind, or otherwise change an application run; a later valid `world_step` has the same meaning as it would in a fresh instance. No other reset return value is defined in ABI v1. A v1 guest must not emit a nonzero reset result, and a host must treat one as an ABI failure.

## Result codes

```text
0 success; output is a Frame
1 malformed StepInput
2 application identity mismatch
3 prior Frame or state validation failure
4 EffectResult validation failure
5 fuel exhausted; output is a yielded_fuel Frame
6 deterministic resource limit exceeded
7 internal runtime failure before a valid Frame can be produced
```

Codes `0` and `5` produce a valid Frame. A deterministic application failure is a successful protocol transition: `world_step` returns `0`, and the output is a persistent `failed` Frame. Code `7` is reserved for an internal runtime failure that prevents the guest from producing any valid Frame; it is not an alternate representation of application failure. Other codes do not commit semantic state. A malformed call cannot alter the meaning of a later valid call.

## Memory

The reference layout uses an immutable metadata region, a bounded input region, a bounded output region, and a resettable per-call arena. Linear memory may be reused as an optimization; Frame bytes remain authoritative.

## Manifest

`world_manifest_ptr` and `world_manifest_len` expose the canonical `ApplicationManifest` encoding described by `src/application_v1.zig`. Optional custom sections may duplicate manifest and debug projections, but the ABI export is authoritative for host preflight.
