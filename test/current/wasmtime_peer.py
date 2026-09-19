"""Independent ABI 3 Wasmtime peer; all execution and State remain guest-owned."""
import base64
import hashlib
import importlib.metadata
import json
from pathlib import Path
import re
import sys
import wasmtime

SIGNATURES = {
    "abi_version": ([], ["i32"]), "initialize": (["i64"], ["i32"]),
    "set_limits": (["i64"] * 4, ["i32"]), "prepare_input": (["i64"] * 2, ["i32"]),
    "input_ptr": ([], ["i32"]), "input_capacity": ([], ["i64"]),
    "output_ptr": ([], ["i32"]), "output_len": ([], ["i64"]),
    "error_ptr": ([], ["i32"]), "error_len": ([], ["i64"]),
    "prepared_handle": ([], ["i64"]), "session_handle": ([], ["i64"]),
    "working_live": ([], ["i64"]), "working_peak": ([], ["i64"]),
    "invoke": (["i64"] * 2, ["i32"]), "prepare": (["i64"] * 2, ["i32"]),
    "release_prepared": (["i64"] * 2, ["i32"]), "start": (["i64"] * 3, ["i32"]),
    "restore": (["i64"] * 3, ["i32"]),
    "drive": (["i64", "i64", "i32", "i32", "i64", "i32", "i64"], ["i32"]),
    "checkpoint": (["i64", "i64", "i32"], ["i32"]), "close": (["i64"] * 2, ["i32"]),
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
    def __init__(self, code, expected):
        if not re.fullmatch(r"[a-f0-9]{64}", expected) or hashlib.sha256(code).hexdigest() != expected:
            raise ValueError("KernelIdentityMismatch")
        reject_start(code)
        config = wasmtime.Config()
        config.wasm_threads = False
        config.wasm_memory64 = False
        config.wasm_gc = False
        config.wasm_exceptions = False
        config.wasm_tail_call = False
        config.wasm_relaxed_simd = False
        config.wasm_simd = False
        self.engine = wasmtime.Engine(config)
        self.module = wasmtime.Module(self.engine, code)
        if self.module.imports:
            raise ValueError("ForbiddenImports")
        exports = {item.name: item.type for item in self.module.exports}
        if set(exports) != {"memory", *("world_" + key for key in SIGNATURES)}:
            raise ValueError("InvalidExports")
        memory = exports["memory"]
        if not isinstance(memory, wasmtime.MemoryType) or memory.is_64 or memory.is_shared or memory.limits.max is None:
            raise ValueError("InvalidMemoryType")
        for name, signature in SIGNATURES.items():
            actual = exports["world_" + name]
            if not isinstance(actual, wasmtime.FuncType) or ([str(t) for t in actual.params], [str(t) for t in actual.results]) != signature:
                raise ValueError("InvalidFunctionType")
        self.store = wasmtime.Store(self.engine)
        self.instance = wasmtime.Instance(self.store, self.module, [])
        self.exports = self.instance.exports(self.store)
        self.memory = self.exports["memory"]
        if self.call("abi_version") != 3:
            raise ValueError("InvalidAbiVersion")
        self.check(self.call("initialize", 73))
        self.check(self.call("set_limits", 73, 2 << 20, 8 << 20, 2 << 20))

    def call(self, name, *args):
        return self.exports["world_" + name](self.store, *args)

    def read(self, name):
        pointer = self.call(name + "_ptr") & 0xffffffff
        length = self.call(name + "_len") & 0xffffffffffffffff
        size = self.memory.data_len(self.store)
        if pointer > size or length > size - pointer:
            raise ValueError("InvalidGuestRange")
        return bytes(self.memory.read(self.store, pointer, pointer + length))

    def check(self, status):
        if status == 1:
            raise ValueError("NeedsCapacity")
        if status != 0:
            raise ValueError(self.read("error").decode("utf8"))

    def stage(self, data):
        self.check(self.call("prepare_input", 73, len(data)))
        pointer = self.call("input_ptr") & 0xffffffff
        size = self.memory.data_len(self.store)
        if len(data) > self.call("input_capacity") or pointer > size or len(data) > size - pointer:
            raise ValueError("InvalidInputRange")
        if data and self.memory.write(self.store, data, pointer) != len(data):
            raise ValueError("IncompleteInputWrite")

    def execute(self, request):
        operation = request["op"]
        data = base64.b64decode(request.get("bytes", ""), validate=True)
        handle = int(request.get("handle", 0))
        if operation in ("prepare", "invoke", "start", "restore", "drive"):
            self.stage(data)
        if operation in ("prepare", "invoke"):
            status = self.call(operation, 73, len(data))
        elif operation in ("start", "restore"):
            status = self.call(operation, 73, handle, len(data))
        elif operation == "drive":
            quantum = request.get("quantum")
            status = self.call("drive", 73, handle, request.get("control", 0), int(quantum is not None), quantum or 0, int(request.get("checkpoint", True)), len(data))
        elif operation == "checkpoint":
            status = self.call(operation, 73, handle, int(request.get("transfer", False)))
        elif operation in ("close", "release_prepared"):
            status = self.call(operation, 73, handle)
        else:
            raise ValueError("InvalidOperation")
        self.check(status)
        return {"bytes": base64.b64encode(self.read("output")).decode(),
                "prepared": str(self.call("prepared_handle")), "session": str(self.call("session_handle")),
                "working_live": self.call("working_live")}


def main():
    if sys.version_info[:3] != (3, 14, 7) or importlib.metadata.version("wasmtime") != "48.0.0":
        raise ValueError("UseLockedConformanceEnvironment")
    kernel = Kernel(Path(sys.argv[1]).read_bytes(), sys.argv[2])
    print(json.dumps({"ready": True, "wasmtime": "48.0.0", "python": sys.version}), flush=True)
    for line in sys.stdin:
        request = json.loads(line)
        try:
            result = kernel.execute(request)
            print(json.dumps({"id": request["id"], **result}), flush=True)
        except (ValueError, wasmtime.WasmtimeError, wasmtime.Trap) as error:
            print(json.dumps({"id": request["id"], "error": str(error)}), flush=True)

if __name__ == "__main__":
    main()
