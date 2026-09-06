"""Independent Wasmtime ABI embedding; program and State bytes remain opaque.

API reference: https://bytecodealliance.github.io/wasmtime-py/
This is conformance tooling and is not shipped as application execution policy.
"""

import base64
import hashlib
import importlib.metadata
import json
from pathlib import Path
import re
import struct
import sys

import wasmtime


PREFIX = "world_process_v2_"
SIGNATURES = {
    "abi_version": ([], ["i32"]),
    "prepare_input": (["i64"], ["i32"]),
    "input_ptr": ([], ["i32"]),
    "input_capacity": ([], ["i64"]),
    "execute": (["i64"], ["i32"]),
    "output_ptr": ([], ["i32"]),
    "output_len": ([], ["i64"]),
    "error_ptr": ([], ["i32"]),
    "error_len": ([], ["i64"]),
}


def reject_start(code: bytes) -> None:
    if code[:8] != b"\0asm\x01\0\0\0":
        raise ValueError("InvalidWasmHeader")
    cursor = 8
    while cursor < len(code):
        section = code[cursor]
        cursor += 1
        if section == 8:
            raise ValueError("ForbiddenStartFunction")
        size = 0
        for shift in range(0, 35, 7):
            if cursor == len(code):
                raise ValueError("TruncatedWasmSection")
            byte = code[cursor]
            cursor += 1
            if shift == 28 and byte > 15:
                raise ValueError("InvalidWasmSectionLength")
            size |= (byte & 127) << shift
            if not byte & 128:
                break
        else:
            raise ValueError("InvalidWasmSectionLength")
        if size > len(code) - cursor:
            raise ValueError("TruncatedWasmSection")
        cursor += size


class Kernel:
    def __init__(self, code: bytes, expected: str):
        if not re.fullmatch(r"[a-f0-9]{64}", expected) or hashlib.sha256(code).hexdigest() != expected:
            raise ValueError("KernelIdentityMismatch")
        reject_start(code)
        config = wasmtime.Config()
        config.wasm_threads = False
        config.wasm_memory64 = False
        config.wasm_gc = False
        config.wasm_exceptions = False
        config.wasm_tail_call = False
        self.engine = wasmtime.Engine(config)
        self.module = wasmtime.Module(self.engine, code)
        if self.module.imports:
            raise ValueError("ForbiddenImports")
        exports = {item.name: item.type for item in self.module.exports}
        if set(exports) != {"memory", *(PREFIX + key for key in SIGNATURES)}:
            raise ValueError("InvalidExports")
        memory = exports["memory"]
        if not isinstance(memory, wasmtime.MemoryType) or memory.is_64 or memory.is_shared or memory.page_size_log2 != 16:
            raise ValueError("InvalidMemoryType")
        limits = memory.limits
        if limits.max is None or limits.min > limits.max or limits.max > 65536:
            raise ValueError("InvalidMemoryLimits")
        self.memory_limits = {"initial_pages": limits.min, "maximum_pages": limits.max}
        for name, expected_type in SIGNATURES.items():
            actual = exports[PREFIX + name]
            if not isinstance(actual, wasmtime.FuncType):
                raise ValueError("InvalidExportKind")
            if ([str(t) for t in actual.params], [str(t) for t in actual.results]) != expected_type:
                raise ValueError("InvalidFunctionType")

    def invoke(self, encoded: bytes) -> bytes:
        # Store, instance, memory and guest mutable globals are new each time.
        with wasmtime.Store(self.engine) as store:
            instance = wasmtime.Instance(store, self.module, [])
            exports = instance.exports(store)
            memory = exports["memory"]

            def call(name, *args):
                return exports[PREFIX + name](store, *args)

            def read(name):
                pointer = call(name + "_ptr") & 0xFFFFFFFF
                length = call(name + "_len") & 0xFFFFFFFFFFFFFFFF
                total = memory.data_len(store)
                if pointer > total or length > total - pointer:
                    raise ValueError("InvalidGuestRange")
                return bytes(memory.read(store, pointer, pointer + length))

            if call("abi_version") != 2:
                raise ValueError("InvalidAbiVersion")
            prepared = call("prepare_input", len(encoded))
            if prepared not in (0, 1):
                raise ValueError(read("error").decode("utf-8", errors="strict") or "PrepareFailed")
            if prepared == 0:
                capacity = call("input_capacity") & 0xFFFFFFFFFFFFFFFF
                pointer = call("input_ptr") & 0xFFFFFFFF
                total = memory.data_len(store)
                if pointer % 16 or len(encoded) > capacity or pointer > total or len(encoded) > total - pointer:
                    raise ValueError("InvalidInputRange")
                if memory.write(store, encoded, pointer) != len(encoded):
                    raise ValueError("IncompleteInputWrite")
                if call("execute", len(encoded)) != 0:
                    raise ValueError(read("error").decode("utf-8", errors="strict") or "ExecuteFailed")
            output = read("output")
            if len(output) < 20 or output[:12] != b"ABL_PKO2\x02\0\0\0" or struct.unpack_from("<Q", output, 12)[0] != len(output) - 20:
                raise ValueError("InvalidOutcomeFrame")
            if prepared == 1 and output[20:21] != b"\x06":
                raise ValueError("InvalidPreflightOutcome")
            return output


def send(value):
    sys.stdout.write(json.dumps(value, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main():
    if len(sys.argv) != 3 or sys.version_info[:3] != (3, 14, 7) or importlib.metadata.version("wasmtime") != "48.0.0":
        raise ValueError("UseLockedConformanceEnvironment")
    code = Path(sys.argv[1]).read_bytes()
    kernel = Kernel(code, sys.argv[2])
    send({"ready": True, "python": sys.version, "wasmtime": "48.0.0", "kernel_sha256": sys.argv[2], **kernel.memory_limits})
    for line in sys.stdin:
        request = json.loads(line)
        try:
            output = kernel.invoke(base64.b64decode(request["pki"], validate=True))
            send({"id": request["id"], "pko": base64.b64encode(output).decode("ascii")})
        except (ValueError, wasmtime.WasmtimeError, wasmtime.Trap) as error:
            send({"id": request["id"], "error": str(error)})


if __name__ == "__main__":
    main()
