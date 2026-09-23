import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtemp, mkdir, writeFile, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { inventory, sha256, verifyInventory } from "../../src/node/runtime-bundle.mjs";

const required = ["runtime/world-kernel.wasm", "runtime/package.json", "runtime/bin/world.mjs",
  "runtime/src/node/runtime-bundle.mjs", "runtime/src/embedding/index.mjs", "qualification.json",
  "runtime/LICENSE", "smoke/pure.bpi3", "smoke/effect.bpi3"];
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "world bundle "));
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const file of required) {
    await mkdir(join(root, file, ".."), { recursive: true });
    await writeFile(join(root, file), "fixture");
  }
  const manifest = { format: "world-runtime-bundle/v1", files: await inventory(root) };
  const seal = async () => {
    const bytes = JSON.stringify(manifest);
    await writeFile(join(root, "manifest.json"), bytes);
    return sha256(bytes);
  };
  return { root, manifest, seal, hash: await seal() };
}
test("external identity and complete file inventory survive spaces", async t => {
  const f = await fixture(t);
  await verifyInventory(f.root, f.hash);
  await assert.rejects(verifyInventory(f.root, "0".repeat(64)), { code: "WORLD_BUNDLE_IDENTITY_INVALID" });
  await writeFile(join(f.root, "runtime/src/node/runtime-bundle.mjs"), "substituted");
  await assert.rejects(verifyInventory(f.root, f.hash), { code: "WORLD_BUNDLE_CORRUPT" });
});
test("missing and additional modules reject", async t => {
  const f = await fixture(t);
  await writeFile(join(f.root, "runtime/extra.mjs"), "unexpected");
  await assert.rejects(verifyInventory(f.root, f.hash), { code: "WORLD_BUNDLE_CORRUPT" });
  await rm(join(f.root, "runtime/extra.mjs"));
  await rm(join(f.root, "runtime/world-kernel.wasm"));
  await assert.rejects(verifyInventory(f.root, f.hash), { code: "WORLD_BUNDLE_CORRUPT" });
});
test("traversal, duplicate entries, and links reject", async t => {
  const f = await fixture(t);
  f.manifest.files.push(f.manifest.files[0]);
  await assert.rejects(verifyInventory(f.root, await f.seal()), { code: "WORLD_BUNDLE_INVALID" });
  f.manifest.files.pop();
  f.manifest.files[0].path = "../escape";
  await assert.rejects(verifyInventory(f.root, await f.seal()), { code: "WORLD_BUNDLE_INVALID" });
  await symlink(tmpdir(), join(f.root, "link"));
  await assert.rejects(inventory(f.root), { code: "WORLD_BUNDLE_INVALID" });
});

test("safe acquisition binds archive before extraction and refuses destination collision", async t => {
  const { execFileSync } = await import("node:child_process");
  const { readFile } = await import("node:fs/promises");
  const { acquireBundle, unpackArchive } = await import("../../src/node/runtime-acquire.mjs");
  const f = await fixture(t);
  const scratch = await mkdtemp(join(tmpdir(), "world acquisition "));
  t.after(() => rm(scratch, { recursive: true, force: true }));
  const archive = join(scratch, "bundle.tar.gz"), output = join(scratch, "relocated bundle");
  execFileSync("tar", ["--format=ustar", "-czf", archive, "-C", f.root, "."]);
  const bytes = await readFile(archive), digest = sha256(bytes);
  await assert.rejects(acquireBundle(archive, "0".repeat(64), f.hash, output), { code: "WORLD_BUNDLE_IDENTITY_INVALID" });
  await acquireBundle(archive, digest, f.hash, output);
  await verifyInventory(output, f.hash);
  await assert.rejects(acquireBundle(archive, digest, f.hash, output), { code: "WORLD_BUNDLE_COLLISION" });
  await symlink("/tmp", join(f.root, "escape"));
  execFileSync("tar", ["--format=ustar", "-czf", archive, "-C", f.root, "."]);
  const badArchive = await readFile(archive);
  assert.throws(() => unpackArchive(badArchive), { code: "WORLD_BUNDLE_ARCHIVE_INVALID" });
});

test("unsupported profile and unexecuted qualification cannot pass", async t => {
  const { verifyBundle, requiredChecks } = await import("../../src/node/runtime-bundle.mjs");
  const f = await fixture(t);
  await assert.rejects(verifyBundle(f.root, f.hash), { code: "WORLD_BUNDLE_INCOMPATIBLE" });
  f.manifest.kernel = { abi: 3, path: "runtime/world-kernel.wasm" };
  f.manifest.packageVersion = "6.0.0-dev.0";
  f.manifest.build = { target: "wasm32-freestanding", kernelMode: "ReleaseSmall" };
  f.manifest.requiredChecks = requiredChecks;
  await writeFile(join(f.root, "qualification.json"), JSON.stringify({ checks: requiredChecks.map(name => ({ name, status: "skipped" })) }));
  f.manifest.files = (await inventory(f.root)).filter(file => file.path !== "manifest.json");
  await assert.rejects(verifyBundle(f.root, await f.seal()), { code: "WORLD_BUNDLE_INCOMPLETE" });
});
