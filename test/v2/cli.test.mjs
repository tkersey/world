import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseArguments, executeCli } from "../../src/process_v2/cli.mjs";

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
