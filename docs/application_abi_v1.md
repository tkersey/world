# World Application WASM ABI v1

Status: normative.

An application artifact is named `<application>.world.wasm`. It targets
`wasm32-freestanding`, imports nothing, declares bounded memory, and retains no
authoritative semantic state between calls.

Exports:

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

`world_abi_version` returns `1`. Result codes are: `0` success, `1` malformed
input, `2` application mismatch, `3` state validation, `4` effect-result
validation, `5` yielded fuel, `6` resource limit, and `7` internal failure.
Codes `0` and `5` produce a canonical Frame. Other codes produce no Frame.

`world_reset` returns `0`, clears mutable byte regions, and preserves the
immutable manifest. `world.ApplicationAbiV1` checks that declared protocol
limits fit the configured input, output, scratch, manifest, and error regions.
