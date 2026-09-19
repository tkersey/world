// Copyright (c) 2026 World contributors. MIT license.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const module = await WebAssembly.compile(await readFile(process.argv[2]));
assert.deepEqual(WebAssembly.Module.imports(module), []);
const instance = await WebAssembly.instantiate(module);
assert.equal(instance.exports.memory.buffer instanceof SharedArrayBuffer, false);
assert.equal(instance.exports.test_storage(), 0);
assert.equal(instance.exports.test_storage(), 0);
console.log("Stable activation storage passed in unshared import-free wasm32.");
