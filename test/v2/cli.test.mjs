import assert from "node:assert/strict";
import test from "node:test";
import fs, { mkdtemp, readFile, writeFile, rm, mkdir, cp, symlink, truncate } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createHash } from "node:crypto";
import { parseArguments, executeCli } from "../../src/process_v2/cli.mjs";
import { loadProcessKernel, advance, run, encodeInput, packageVersion } from "../../src/process_v2/index.mjs";
import { readProcessKernelFile } from "../../src/process_v2/kernel_file.mjs";
import { MAXIMUM_KERNEL_BYTES } from "../../src/process_v2/wasm.mjs";
import { frame } from "../../src/process_v2/codec.mjs";
import { kernel } from "./wasm_fixture.mjs";

const base = ["process", "run", "--image", "image", "--initial", "initial", "--output", "outcome"];
test("top-level and admitted invocations capture bytes before asynchronous loading", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "world-v2-capture-"));
  const originalInstantiate = WebAssembly.instantiate;
  const captured = [];
  try {
    const bytes = kernel({ outcome: frame("ABL_PKO2", Uint8Array.of(3, 0)) });
    const kernelPath = join(root, "kernel.wasm");
    await writeFile(kernelPath, bytes);
    const options = { kernelPath, expectedSha256: createHash("sha256").update(bytes).digest("hex") };
    t.mock.method(WebAssembly, "instantiate", async (...args) => {
      const instance = await originalInstantiate(...args);
      const original = instance.exports;
      return { exports: { ...original, world_process_v2_execute(length) {
        captured.push(new Uint8Array(original.memory.buffer, 0, Number(length)).slice());
        return original.world_process_v2_execute(length);
      } } };
    });
    const host = await loadProcessKernel(options);
    for (const mode of ["advance", "run"]) for (const method of [host[mode], input => ({ advance, run })[mode](input, options)]) {
      for (const fields of [
        { image: [1, 2], initialArgs: [3, 4] },
        { image: [1, 2], state: [3, 4], result: [5, 6] },
        { image: [1, 2], state: [3, 4], cancel: [5, 6] },
      ]) for (const transfer of [false, true]) {
        const input = Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, Uint8Array.from(value)]));
        const expected = encodeInput({ ...input, mode });
        const pending = method(input);
        for (const [key, value] of Object.entries(input)) {
          if (transfer) structuredClone(value, { transfer: [value.buffer] });
          else value.fill(0);
          input[key] = Uint8Array.of(99);
        }
        assert.equal((await pending).kind, "Completed");
        assert.deepEqual(captured.at(-1), expected);
      }
    }
    assert.equal(captured.length, 24);
    for (const method of [host.run, input => run(input, options)]) {
      let pending;
      assert.doesNotThrow(() => { pending = method({}); });
      await assert.rejects(pending, /InvalidInstance/);
    }
  } finally {
    t.mock.restoreAll();
    await rm(root, { recursive: true, force: true });
  }
});

test("kernel files accept regular paths, file URLs and symlinks with their selected identity", async () => {
  const root = await mkdtemp(join(tmpdir(), "world-v2-kernel-"));
  try {
    const bytes = kernel();
    const expectedSha256 = createHash("sha256").update(bytes).digest("hex");
    const path = join(root, "kernel.wasm");
    const alias = join(root, "kernel-link.wasm");
    await writeFile(path, bytes);
    await symlink(path, alias);
    for (const kernelPath of [path, pathToFileURL(path), alias, pathToFileURL(alias)]) {
      const selected = await readProcessKernelFile({ kernelPath, expectedSha256 }, packageVersion);
      assert.deepEqual(selected.bytes, Buffer.from(bytes));
      assert.equal(selected.expectedSha256, expectedSha256);
      assert.deepEqual(selected.files, [kernelPath]);
      assert.equal((await loadProcessKernel({ kernelPath, expectedSha256 })).sha256, expectedSha256);
    }
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("oversized sparse kernels reject before allocating or reading their contents", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "world-v2-kernel-size-"));
  const path = join(root, "oversized.wasm");
  const originalOpen = fs.open;
  let closes = 0;
  try {
    await writeFile(path, "");
    await truncate(path, MAXIMUM_KERNEL_BYTES + 1);
    t.mock.method(fs, "open", async (...args) => {
      const file = await originalOpen(...args);
      return {
        stat: (...args) => file.stat(...args),
        read: () => assert.fail("oversized contents must not be read"),
        close: async () => { closes++; await file.close(); },
      };
    });
    t.mock.method(Buffer, "alloc", () => assert.fail("oversized contents must not be allocated"));
    syncBuiltinESMExports();
    await assert.rejects(readProcessKernelFile({ kernelPath: path }, packageVersion), { code: "WORLD_KERNEL_TOO_LARGE" });
    assert.equal(closes, 1);
  } finally {
    t.mock.restoreAll();
    syncBuiltinESMExports();
    await rm(root, { recursive: true, force: true });
  }
});

test("kernel reads stay bounded when an opened file grows or shrinks", async (t) => {
  try {
    for (const changedSize of [0n, 5n, BigInt(MAXIMUM_KERNEL_BYTES) + 1n]) {
      let stats = 0;
      let closes = 0;
      let readBytes = 0;
      t.mock.method(fs, "open", async () => ({
        stat: async () => ({ isFile: () => true, size: stats++ === 0 ? 4n : changedSize, mtimeNs: 0n, ctimeNs: 0n }),
        read: async (bytes, offset, length, position) => {
          assert.equal(bytes.length, 4);
          assert.equal(position, offset);
          assert.equal(length, 4 - offset);
          if (changedSize === 0n) return { bytesRead: 0 };
          bytes[offset] = 0;
          readBytes++;
          return { bytesRead: 1 };
        },
        close: async () => { closes++; },
      }));
      syncBuiltinESMExports();
      await assert.rejects(readProcessKernelFile({ kernelPath: "changing.wasm" }, packageVersion), {
        code: changedSize > MAXIMUM_KERNEL_BYTES ? "WORLD_KERNEL_TOO_LARGE" : "WORLD_FILE_CHANGED",
      });
      assert.equal(readBytes, changedSize === 0n ? 0 : 4);
      assert.equal(closes, 1);
      t.mock.restoreAll();
      syncBuiltinESMExports();
    }
  } finally { t.mock.restoreAll(); syncBuiltinESMExports(); }
});

test("kernel loading rejects directories and FIFOs without blocking", { skip: process.platform === "win32" }, async () => {
  const root = await mkdtemp(join(tmpdir(), "world-v2-kernel-kind-"));
  try {
    const fifo = join(root, "kernel.fifo");
    const alias = join(root, "kernel-link.fifo");
    const made = spawnSync("mkfifo", [fifo], { encoding: "utf8", timeout: 2000 });
    assert.equal(made.status, 0, made.error?.message ?? made.stderr);
    await symlink(fifo, alias);
    const module = new URL("../../src/process_v2/index.mjs", import.meta.url).href;
    const script = `import assert from "node:assert/strict";
      import { loadProcessKernel } from ${JSON.stringify(module)};
      await assert.rejects(loadProcessKernel({ kernelPath: process.env.WORLD_TEST_KERNEL, expectedSha256: "0".repeat(64) }),
        { code: "WORLD_FILE_NOT_REGULAR" });`;
    for (const path of [root, fifo, alias]) {
      const result = spawnSync(process.execPath, ["--input-type=module", "--eval", script], {
        encoding: "utf8", timeout: 2000, env: { ...process.env, WORLD_TEST_KERNEL: path },
      });
      assert.equal(result.error, undefined, result.error?.message);
      assert.equal(result.status, 0, result.stderr);
    }
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("CLI rejects ambiguous controls, duplicate and unknown options, and unbound kernels", () => {
  for (const extra of [["--result", "result"], ["--state", "state"], ["--cancel", "stop"], ["--image", "again"],
    ["--fuel", "2"], ["--kernel", "kernel"], ["--kernel-sha256", "a".repeat(64)], ["--result"]]) {
    assert.throws(() => parseArguments([...base, ...extra]), { code: "WORLD_CLI_USAGE" });
  }
  const state = ["process", "step", "--image", "image", "--state", "state", "--output", "outcome"];
  assert.equal(parseArguments([...state, "--cancel", "stop"]).mode, "advance");
  assert.throws(() => parseArguments([...state, "--cancel", "stop", "--result", "result"]), { code: "WORLD_CLI_USAGE" });
});

test("every CLI data input rejects nonregular files before reading", { skip: process.platform === "win32" }, async () => {
  const root = await mkdtemp(join(tmpdir(), "world-v2-cli-file-kind-"));
  try {
    const fifo = join(root, "input.fifo"), alias = join(root, "input-link.fifo");
    const made = spawnSync("mkfifo", [fifo], { encoding: "utf8", timeout: 2000 });
    assert.equal(made.status, 0, made.error?.message ?? made.stderr);
    await symlink(fifo, alias);
    const regular = join(root, "input.bin"), output = join(root, "output");
    await writeFile(regular, "");
    await writeFile(output, "previous output");
    const module = new URL("../../src/process_v2/cli.mjs", import.meta.url).href;
    const script = `import assert from "node:assert/strict";
      import { executeCli } from ${JSON.stringify(module)};
      await assert.rejects(executeCli(JSON.parse(process.env.WORLD_TEST_ARGS)),
        { code: "WORLD_FILE_NOT_REGULAR" });`;
    for (const flag of ["--image", "--initial", "--state", "--result", "--cancel-bytes"]) {
      for (const path of [root, fifo, alias]) {
        const state = ["--state", "--result", "--cancel-bytes"].includes(flag);
        const args = ["process", "step", "--image", flag === "--image" ? path : regular,
          state ? "--state" : "--initial", ["--state", "--initial"].includes(flag) ? path : regular,
          "--output", output];
        if (["--result", "--cancel-bytes"].includes(flag)) args.push(flag, path);
        const result = spawnSync(process.execPath, ["--input-type=module", "--eval", script], {
          encoding: "utf8", timeout: 2000, env: { ...process.env, WORLD_TEST_ARGS: JSON.stringify(args) },
        });
        assert.equal(result.error, undefined, result.error?.message);
        assert.equal(result.status, 0, `${flag}: ${result.stderr}`);
        assert.equal(await readFile(output, "utf8"), "previous output");
        assert.equal(await readFile(regular, "utf8"), "");
      }
    }
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("bundled identity admission rejects a FIFO before reading metadata", { skip: process.platform === "win32" }, async () => {
  const root = await mkdtemp(join(tmpdir(), "world-v2-identity-kind-"));
  try {
    await mkdir(join(root, "src"));
    await cp(resolve(import.meta.dirname, "../../src/process_v2"), join(root, "src/process_v2"), { recursive: true });
    const made = spawnSync("mkfifo", [join(root, "world-runtime-identity.json")], { encoding: "utf8", timeout: 2000 });
    assert.equal(made.status, 0, made.error?.message ?? made.stderr);
    const module = pathToFileURL(join(root, "src/process_v2/index.mjs")).href;
    const script = `import assert from "node:assert/strict";
      import { loadProcessKernel } from ${JSON.stringify(module)};
      await assert.rejects(loadProcessKernel(), { code: "WORLD_FILE_NOT_REGULAR" });`;
    const result = spawnSync(process.execPath, ["--input-type=module", "--eval", script], { encoding: "utf8", timeout: 2000 });
    assert.equal(result.error, undefined, result.error?.message);
    assert.equal(result.status, 0, result.stderr);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("rejected kernel admission leaves an existing output byte-identical", async () => {
  const root = await mkdtemp(join(tmpdir(), "world-v2-cli-"));
  try {
    for (const name of ["image", "initial", "kernel"]) await writeFile(join(root, name), new Uint8Array());
    await writeFile(join(root, "outcome"), "authoritative previous bytes");
    await assert.rejects(executeCli(["process", "run", "--image", join(root, "image"), "--initial", join(root, "initial"),
      "--output", join(root, "outcome"), "--kernel", join(root, "kernel"), "--kernel-sha256", "0".repeat(64)]), /KernelIdentityMismatch/);
    assert.equal(await readFile(join(root, "outcome"), "utf8"), "authoritative previous bytes");
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("CLI preserves custom and bundled kernel inputs when output aliases them", async () => {
  const root = await mkdtemp(join(tmpdir(), "world-v2-cli-inputs-"));
  try {
    const outcome = frame("ABL_PKO2", Uint8Array.of(3, 0));
    const bytes = kernel({ outcome });
    assert.ok(WebAssembly.validate(bytes));
    const digest = createHash("sha256").update(bytes).digest("hex");
    const selected = join(root, "selected.wasm");
    await writeFile(selected, bytes);
    for (const name of ["image", "initial"]) await writeFile(join(root, name), new Uint8Array());
    const args = output => ["process", "run", "--image", join(root, "image"), "--initial", join(root, "initial"), "--output", output];
    const custom = ["--kernel", selected, "--kernel-sha256", digest];
    const output = join(root, "outcome");
    await executeCli([...args(output), ...custom]);
    assert.deepEqual(await readFile(output), Buffer.from(outcome));
    const alias = join(root, "kernel-alias");
    await symlink(selected, alias);
    for (const destination of [selected, alias]) {
      await assert.rejects(executeCli([...args(destination), ...custom]), { code: "WORLD_CLI_USAGE" });
      assert.deepEqual(await readFile(selected), Buffer.from(bytes));
    }
    const runtime = join(root, "runtime");
    await mkdir(join(runtime, "src"), { recursive: true });
    await cp(resolve(import.meta.dirname, "../../src/process_v2"), join(runtime, "src/process_v2"), { recursive: true });
    const bundledKernel = join(runtime, "world-process-kernel-v2.wasm");
    const identityPath = join(runtime, "world-runtime-identity.json");
    const identity = Buffer.from(JSON.stringify({ format: "world-runtime-identity/v2", version: packageVersion, abi: 2,
      kernel: { file: "world-process-kernel-v2.wasm", sha256: digest } }));
    await writeFile(bundledKernel, bytes);
    await writeFile(identityPath, identity);
    const bundled = (await import(pathToFileURL(join(runtime, "src/process_v2/cli.mjs")).href)).executeCli;
    await bundled(args(output));
    assert.deepEqual(await readFile(output), Buffer.from(outcome));
    for (const destination of [bundledKernel, identityPath]) {
      await assert.rejects(bundled(args(destination)), { code: "WORLD_CLI_USAGE" });
      assert.deepEqual(await readFile(bundledKernel), Buffer.from(bytes));
      assert.deepEqual(await readFile(identityPath), identity);
    }
  } finally { await rm(root, { recursive: true, force: true }); }
});
