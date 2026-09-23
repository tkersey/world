import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { cp, mkdtemp, readFile, rm, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { verifyRuntime } from "../../src/node/runtime-delivery.mjs";

const [bundle, expected] = process.argv.slice(2);
if (!bundle || !expected) throw new Error("bundle and expected manifest SHA-256 are required");
const sha = bytes => createHash("sha256").update(bytes).digest("hex");
const testRoot = await mkdtemp(join(tmpdir(), "world-runtime-delivery-test-"));
try {
  const target = join(testRoot, "bundle");
  await cp(bundle, target, { recursive: true });
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
  console.log(JSON.stringify({ check: "bundle failure and valid-neighbor cases", cases: 10 }));
} finally { await rm(testRoot, { recursive: true, force: true }); }
