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

## Result codes

```text
0 success; output is a Frame
1 malformed StepInput
2 application identity mismatch
3 prior Frame or state validation failure
4 EffectResult validation failure
5 fuel exhausted; output is a yielded_fuel Frame
6 deterministic resource limit exceeded
7 deterministic application failure
```

Codes `0` and `5` produce a valid Frame. Other codes do not commit semantic state. A malformed call cannot alter the meaning of a later valid call.

## Memory

The reference layout uses an immutable metadata region, a bounded input region, a bounded output region, and a resettable per-call arena. Linear memory may be reused as an optimization; Frame bytes remain authoritative.

## Manifest

`world_manifest_ptr` and `world_manifest_len` expose the canonical `ApplicationManifest` encoding described by `src/application_v1.zig`. Optional custom sections may duplicate manifest and debug projections, but the ABI export is authoritative for host preflight.
