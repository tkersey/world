import assert from "node:assert/strict";
import { readFile, mkdtemp, rm } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createHash } from "node:crypto";
import { Kernel, encodeInput, decodeOutcome, decodeRequest, encodeResult } from "../../src/embedding/index.mjs";
import { inspectKernelWasm, wasmRange } from "../../src/embedding/wasm.mjs";
import { concat, natural } from "../../src/embedding/wire.mjs";

const [kernelPath, fixtures, boundary] = process.argv.slice(2);
const code = new Uint8Array(await readFile(kernelPath));
const host = await Kernel.create({ bytes: code, expectedSha256: createHash("sha256").update(code).digest("hex") });
const limits = { input: 4 << 20, working: 16 << 20, output: 4 << 20 };
host.setLimits(limits);
const image = new Uint8Array(execFileSync(fixtures, ["image", "largeRequest"]));
// Exceed the kernel's initial 1 MiB backing to require physical memory growth.
const payloadLength = (1 << 20) + 65536;
const initialArgs = concat(natural(payloadLength), new Uint8Array(payloadLength).fill(97));
const command = encodeInput({ image, initialArgs });
const unchanged = command.slice();
const expected = host.invoke(command), request = decodeOutcome(expected);
assert.equal(request.kind, "requested");
assert.deepEqual((await decodeRequest(request.request)).payload, initialArgs);
assert.ok(expected.length > 65536);
assert.deepEqual(expected, new Uint8Array(execFileSync(fixtures, ["invoke"], {
  input: command, maxBuffer: 8 << 20,
})));
const final = decodeOutcome(host.invoke(encodeInput({ image, state: request.state,
  control: "reply", value: await encodeResult(request.request, new Uint8Array()) })));
assert.equal(final.kind, "completed");
assert.deepEqual(final.value, initialArgs);

function invoke(exports, bytes) {
  const prepared = exports.world_prepare_input(1n, BigInt(bytes.length));
  if (prepared !== 0) return prepared;
  wasmRange(exports.memory, exports.world_input_ptr(), BigInt(bytes.length), "input").set(bytes);
  const status = exports.world_invoke(1n, BigInt(bytes.length));
  assert.deepEqual(wasmRange(exports.memory, exports.world_input_ptr(), BigInt(bytes.length), "input"), bytes);
  return status;
}
const output = e => new Uint8Array(wasmRange(e.memory, e.world_output_ptr(), e.world_output_len(), "output"));
const module = new WebAssembly.Module(code);
for (const arena of ["input", "working", "output"]) {
  const e = new WebAssembly.Instance(module, {}).exports;
  assert.equal(e.world_initialize(1n), 0);
  const limited = { ...limits, [arena]: 1 };
  assert.equal(e.world_set_limits(1n, BigInt(limited.input), BigInt(limited.working), BigInt(limited.output)), 0);
  assert.equal(invoke(e, command), 1);
  const capacity = decodeOutcome(output(e));
  assert.equal(capacity.kind, "needs_capacity");
  assert.equal(capacity.arena, arena);
  assert.equal(capacity.state, undefined);
  // ABI 3 labels allocator observations as lower bounds; only final output is exact.
  assert.equal(capacity[arena].provenance, arena === "output" ? "exact" : "lower_bound");
  if (arena === "input") assert.equal(capacity.input.bytes, BigInt(command.length));
  if (arena === "output") assert.equal(capacity.output.bytes, BigInt(expected.length));
  assert.equal(e.world_set_limits(1n, BigInt(limits.input), BigInt(limits.working), BigInt(limits.output)), 0);
  assert.equal(invoke(e, command), 0);
  assert.deepEqual(output(e), expected);
  assert.deepEqual(command, unchanged);
  assert.equal(e.world_prepare_input(1n, (1n << 64n) - 1n), 2);
  assert.equal(e.world_output_len(), 0n);
  assert.equal(e.world_invoke(1n, 0n), 2);
  assert.equal(e.world_output_len(), 0n);
}

const directory = await mkdtemp(join(tmpdir(), "world-fixed-memory-"));
try {
  const pages = inspectKernelWasm(code).memory.initialPages;
  execFileSync("zig", ["build", "build-kernel", `-Dboundary-source=${boundary}`,
    `-Dmaximum-memory=${pages * 65536}`, "--prefix", directory,
    "--cache-dir", ".cache/capacity-local", "--global-cache-dir", ".cache/activation-global"],
    { cwd: resolve(import.meta.dirname, "../.."), stdio: "pipe" });
  const fixed = new Uint8Array(await readFile(join(directory, "world-kernel.wasm")));
  assert.equal(inspectKernelWasm(fixed).memory.maximumPages, pages);
  const e = new WebAssembly.Instance(new WebAssembly.Module(fixed), {}).exports;
  assert.equal(e.world_initialize(1n), 0);
  assert.equal(e.world_set_limits(1n, BigInt(limits.input), BigInt(limits.working), BigInt(limits.output)), 0);
  assert.equal(invoke(e, command), 1);
  const capacity = decodeOutcome(output(e));
  assert.equal(capacity.kind, "needs_capacity");
  assert.equal(capacity.arena, "memory");
  assert.equal(capacity.state, undefined);
  assert.equal(capacity.memoryPages.provenance, "lower_bound");
  assert.ok(capacity.memoryPages.bytes > BigInt(pages));
  assert.deepEqual(host.invoke(command), expected);
} finally { await rm(directory, { recursive: true, force: true }); }
console.log("Current input, working, output and physical-memory failures preserve unchanged retry input");
