import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, readFile, writeFile, rm, mkdir, cp, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createHash } from "node:crypto";
import { parseArguments, executeCli } from "../../src/process_v2/cli.mjs";
import { packageVersion } from "../../src/process_v2/index.mjs";
import { frame } from "../../src/process_v2/codec.mjs";
import { kernel } from "./wasm_fixture.mjs";

const base = ["process", "run", "--image", "image", "--initial", "initial", "--output", "outcome"];
test("CLI rejects ambiguous controls, duplicate and unknown options, and unbound kernels", () => {
  for (const extra of [["--result", "result"], ["--state", "state"], ["--cancel", "stop"], ["--image", "again"],
    ["--fuel", "2"], ["--kernel", "kernel"], ["--kernel-sha256", "a".repeat(64)], ["--result"]]) {
    assert.throws(() => parseArguments([...base, ...extra]), { code: "WORLD_CLI_USAGE" });
  }
  const state = ["process", "step", "--image", "image", "--state", "state", "--output", "outcome"];
  assert.equal(parseArguments([...state, "--cancel", "stop"]).mode, "advance");
  assert.throws(() => parseArguments([...state, "--cancel", "stop", "--result", "result"]), { code: "WORLD_CLI_USAGE" });
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
