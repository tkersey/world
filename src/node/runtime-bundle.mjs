import { createHash } from "node:crypto";
import { lstat, readdir } from "node:fs/promises";
import { resolve, join } from "node:path";
import { readRegularFile } from "./file-input.mjs";
import { Kernel, packageVersion } from "../embedding/index.mjs";
import { inspectKernelWasm } from "../embedding/wasm.mjs";

export const sha256 = bytes => createHash("sha256").update(bytes).digest("hex");
export const requiredChecks = Object.freeze([
  "check", "check-release-fast", "delivered-kernel", "delivered-package",
  "delivered-source", "delivered-capacity", "delivered-transfer", "portable-smoke",
]);
export function reject(code, message) { throw Object.assign(new Error(message), { code }); }
export async function readBounded(path, limit = 64 << 20) {
  return readRegularFile(path, size => {
    if (size > BigInt(limit)) reject("WORLD_BUNDLE_INVALID", `file exceeds ${limit} bytes: ${path}`);
  });
}
export async function inventory(root, prefix = "", entries = []) {
  if (entries.length > 512) reject("WORLD_BUNDLE_INVALID", "bundle exceeds 512 files");
  for (const name of (await readdir(join(root, prefix))).sort()) {
    const path = prefix ? `${prefix}/${name}` : name;
    if (!/^[A-Za-z0-9_.\/-]+$/.test(path)) reject("WORLD_BUNDLE_INVALID", `unsafe path: ${path}`);
    const stat = await lstat(join(root, path));
    if (stat.isSymbolicLink()) reject("WORLD_BUNDLE_INVALID", `symlink: ${path}`);
    if (stat.isDirectory()) await inventory(root, path, entries);
    else if (stat.isFile()) {
      const bytes = await readBounded(join(root, path));
      entries.push({ path, bytes: bytes.length, sha256: sha256(bytes) });
    } else reject("WORLD_BUNDLE_INVALID", `not a regular file: ${path}`);
  }
  if (entries.length > 512) reject("WORLD_BUNDLE_INVALID", "bundle exceeds 512 files");
  return entries.sort((a, b) => a.path.localeCompare(b.path, "en"));
}
export async function verifyInventory(root, expected) {
  if (!/^[a-f0-9]{64}$/.test(expected ?? ""))
    reject("WORLD_BUNDLE_IDENTITY_INVALID", "an external manifest SHA-256 is required");
  if (!(await lstat(root)).isDirectory()) reject("WORLD_BUNDLE_INVALID", "root must be a directory");
  const bytes = await readBounded(join(root, "manifest.json"), 1 << 20);
  if (sha256(bytes) !== expected) reject("WORLD_BUNDLE_IDENTITY_INVALID", "manifest digest mismatch");
  let manifest;
  try { manifest = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); }
  catch { reject("WORLD_BUNDLE_INVALID", "malformed manifest"); }
  if (manifest.format !== "world-runtime-bundle/v1" || !Array.isArray(manifest.files) ||
      manifest.files.length > 511) reject("WORLD_BUNDLE_INVALID", "unsupported manifest structure");
  const paths = new Set();
  for (const file of manifest.files) {
    if (!file || typeof file.path !== "string" || !/^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/.test(file.path) ||
        file.path.split("/").some(part => part === "." || part === "..") ||
        file.path === "manifest.json" || paths.has(file.path) ||
        !Number.isSafeInteger(file.bytes) || file.bytes < 0 || file.bytes > (64 << 20) ||
        !/^[a-f0-9]{64}$/.test(file.sha256)) reject("WORLD_BUNDLE_INVALID", "invalid inventory entry");
    paths.add(file.path);
  }
  const actual = (await inventory(root)).filter(file => file.path !== "manifest.json");
  if (actual.length !== manifest.files.length) reject("WORLD_BUNDLE_CORRUPT", "missing or unexpected bundle file");
  for (let i = 0; i < actual.length; i++) {
    const a = actual[i], b = manifest.files[i];
    if (a.path !== b.path || a.bytes !== b.bytes || a.sha256 !== b.sha256)
      reject("WORLD_BUNDLE_CORRUPT", `file identity mismatch: ${a.path}`);
  }
  for (const path of ["runtime/world-kernel.wasm", "runtime/package.json", "runtime/bin/world.mjs",
    "runtime/src/node/runtime-bundle.mjs", "runtime/src/embedding/index.mjs", "qualification.json",
    "runtime/LICENSE", "smoke/pure.bpi3", "smoke/effect.bpi3"])
    if (!paths.has(path)) reject("WORLD_BUNDLE_INCOMPLETE", `required file missing: ${path}`);
  return manifest;
}
export async function verifyBundle(root, expected, smoke = false) {
  root = resolve(root);
  const manifest = await verifyInventory(root, expected);
  if (manifest.kernel?.abi !== 3 || manifest.packageVersion !== packageVersion ||
      manifest.kernel.path !== "runtime/world-kernel.wasm" ||
      manifest.build?.target !== "wasm32-freestanding" || manifest.build.kernelMode !== "ReleaseSmall")
    reject("WORLD_BUNDLE_INCOMPATIBLE", "unsupported ABI, package or build profile");
  const qualification = JSON.parse(await readBounded(join(root, "qualification.json"), 1 << 20));
  if (JSON.stringify(manifest.requiredChecks) !== JSON.stringify(requiredChecks) ||
      !Array.isArray(qualification.checks) || requiredChecks.some(name =>
        qualification.checks.filter(check => check.name === name && check.status === "passed").length !== 1))
    reject("WORLD_BUNDLE_INCOMPLETE", "required qualification has not passed");
  const bytes = await readBounded(join(root, manifest.kernel.path));
  if (bytes.length !== manifest.kernel.bytes || sha256(bytes) !== manifest.kernel.sha256)
    reject("WORLD_BUNDLE_IDENTITY_INVALID", "kernel identity mismatch");
  const profile = inspectKernelWasm(bytes);
  if (profile.importCount !== 0 || profile.memory.maximumPages !== 4096 || profile.memory.shared)
    reject("WORLD_BUNDLE_INCOMPATIBLE", "unsupported memory/import profile");
  await Kernel.create({ bytes, expectedSha256: manifest.kernel.sha256 });
  if (smoke) {
    const { runSmoke } = await import("./runtime-smoke.mjs");
    await runSmoke(root, manifest.kernel.sha256);
  }
  return { manifestSha256: expected, kernelSha256: manifest.kernel.sha256, files: manifest.files.length, smoke };
}
