import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { appendFile, chmod, cp, lstat, mkdtemp, readFile, readdir, rm, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { verifyRuntime } from "../../src/node/runtime-delivery.mjs";

const [bundle, expected, source] = process.argv.slice(2);
if (!bundle || !expected) throw new Error("bundle and expected manifest SHA-256 are required");
const sha = bytes => createHash("sha256").update(bytes).digest("hex");
async function writable(path) {
  const stat = await lstat(path);
  await chmod(path, stat.mode | 0o200);
  if (stat.isDirectory()) for (const name of await readdir(path)) await writable(join(path, name));
}
const testRoot = await mkdtemp(join(tmpdir(), "world-runtime-delivery-test-"));
try {
  const target = join(testRoot, "bundle");
  await cp(bundle, target, { recursive: true });
  await writable(target);
  assert.equal((await verifyRuntime(target, expected, true)).smoke, true);
  await assert.rejects(verifyRuntime(target, "0".repeat(64)), { code: "WORLD_MANIFEST_IDENTITY_INVALID" });
  for (const relative of ["runtime/world-kernel.wasm", "runtime/src/embedding/kernel.mjs", "runtime/src/node/runtime-delivery.mjs"]) {
    const path = join(target, relative), original = await readFile(path);
    await unlink(path);
    await assert.rejects(verifyRuntime(target, expected), { code: "WORLD_INVENTORY_INVALID" });
    await writeFile(path, original);
    const changed = Buffer.from(original); changed[0] ^= 1;
    await writeFile(path, changed);
    await assert.rejects(verifyRuntime(target, expected), { code: "WORLD_FILE_IDENTITY_INVALID" });
    await writeFile(path, original);
  }
  const manifestPath = join(target, "manifest.json"), originalManifest = await readFile(manifestPath);
  for (const paths of [["../outside"], ["runtime/world-kernel.wasm", "runtime/world-kernel.wasm"]]) {
    const manifest = JSON.parse(originalManifest);
    manifest.files[0].path = paths[0];
    if (paths.length > 1) manifest.files[1].path = paths[1];
    const bytes = Buffer.from(JSON.stringify(manifest));
    await writeFile(manifestPath, bytes);
    await assert.rejects(verifyRuntime(target, sha(bytes)), { code: "WORLD_MANIFEST_INVALID" });
  }
  await writeFile(manifestPath, originalManifest);
  const qualifier = join(target, "qualification.json"), originalQualification = await readFile(qualifier);
  const incomplete = JSON.parse(originalQualification); incomplete.checks.check.status = "skipped";
  const incompleteBytes = Buffer.from(JSON.stringify(incomplete));
  await writeFile(qualifier, incompleteBytes);
  const manifest = JSON.parse(originalManifest);
  const entry = manifest.files.find(file => file.path === "qualification.json");
  entry.length = incompleteBytes.length; entry.sha256 = sha(incompleteBytes);
  const changedManifest = Buffer.from(JSON.stringify(manifest));
  await writeFile(manifestPath, changedManifest);
  await assert.rejects(verifyRuntime(target, sha(changedManifest)), { code: "WORLD_QUALIFICATION_INCOMPLETE" });
  let cases = 10;
  if (source) {
    const cli = join(source, "bin/world.mjs");
    for (const sidecar of [".tar.gz", ".runtime-delivery.json"]) {
      const output = join(testRoot, `reserved-${cases}`), path = output + sidecar;
      const original = Buffer.from(`retained ${sidecar}`);
      await writeFile(path, original);
      const attempt = spawnSync(process.execPath, [cli, "runtime", "prepare", "--source", source, "--output", output], { encoding: "utf8", timeout: 30000 });
      assert.notEqual(attempt.status, 0);
      assert.match(attempt.stderr, /WORLD_OUTPUT_EXISTS/);
      assert.deepEqual(await readFile(path), original);
      cases++;
    }
    const clone = join(testRoot, "hidden-source");
    execFileSync("git", ["clone", "--quiet", "--no-local", source, clone]);
    execFileSync("git", ["-C", clone, "update-index", "--assume-unchanged", "build.zig.zon"]);
    await appendFile(join(clone, "build.zig.zon"), "\n// hidden local edit\n");
    assert.equal(execFileSync("git", ["-C", clone, "status", "--porcelain=v1"], { encoding: "utf8" }), "");
    const hidden = spawnSync(process.execPath, [cli, "runtime", "prepare", "--source", clone, "--output", join(testRoot, "hidden-bundle")], { encoding: "utf8", timeout: 30000 });
    assert.notEqual(hidden.status, 0);
    assert.match(hidden.stderr, /WORLD_SOURCE_DIRTY/);
    cases++;
  }
  console.log(JSON.stringify({ check: "bundle failure and valid-neighbor cases", cases }));
} finally { await rm(testRoot, { recursive: true, force: true }); }
