"""Setup timing only; no application evaluation or host imports."""
import json
import sys
from pathlib import Path
from time import perf_counter_ns
import wasmtime

data = Path(sys.argv[1]).read_bytes()
samples = []
for sample in range(21):
    with wasmtime.Engine() as engine:
        started = perf_counter_ns()
        with wasmtime.Module(engine, data) as module:
            compile_ns = perf_counter_ns() - started
            instances = []
            for index in range(26):
                with wasmtime.Store(engine) as store:
                    started = perf_counter_ns()
                    instance = wasmtime.Instance(store, module, [])
                    elapsed = perf_counter_ns() - started
                    assert instance.exports(store)["world_process_v2_abi_version"](store) == 2
                    memory_bytes = instance.exports(store)["memory"].data_len(store)
                    if index >= 5:
                        instances.append(elapsed)
            samples.append({"compileNs": compile_ns, "instantiateNs": instances, "memoryBytes": memory_bytes})
print(json.dumps({"samples": samples}))
