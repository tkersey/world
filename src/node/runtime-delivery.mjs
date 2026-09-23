// Copyright (c) 2026 World contributors. MIT license.
// Node-only package custody. The browser-neutral embedding does not import this module.
import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { cp, link, lstat, mkdir, mkdtemp, open, readFile, readlink, readdir, rename, rm, unlink, writeFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, resolve, sep } from "node:path";
import { Kernel, inspectKernelWasm, packageVersion } from "../embedding/index.mjs";
import { readRegularFile } from "./file-input.mjs";

const FORMAT = "world-runtime-bundle/v1";
const CHECK_STEPS = ["check", "check-kernel", "check-package", "check-source", "check-capacity", "check-transfer", "check-browser", "check-codecs"];
const REQUIRED = [...CHECK_STEPS, "bundle-smoke"];
const MAX_JSON = 4 * 1024 * 1024;
const SHA = /^[0-9a-f]{64}$/;
const profile = Object.freeze({ target: "wasm32-freestanding", kernelOptimize: "ReleaseSmall", hostOptimize: "ReleaseSafe", inputCapacity: 65536, workingCapacity: 1048576, outputCapacity: 65536, stackBytes: 65536, maximumMemoryBytes: 268435456 });
const digest = bytes => createHash("sha256").update(bytes).digest("hex");
const json = object => Buffer.from(JSON.stringify(object, null, 2) + "\n");
function failure(code, message) { const error = new Error(message); error.code = code; return error; }
function exactOptions(args, allowed, flags = []) {
  const options = new Map();
  while (args.length) {
    const key = args.shift();
    if (flags.includes(key)) { if (options.has(key)) throw failure("WORLD_OPTION_INVALID", `duplicate ${key}`); options.set(key, true); continue; }
    const value = args.shift();
    if (!allowed.includes(key) || options.has(key) || !value || value.startsWith("--")) throw failure("WORLD_OPTION_INVALID", `invalid ${key}`);
    options.set(key, value);
  }
  return options;
}
function readJsonBytes(bytes, path) {
  if (bytes.length > MAX_JSON) throw failure("WORLD_MANIFEST_INVALID", `${path} exceeds JSON limit`);
  try { return JSON.parse(bytes.toString("utf8")); }
  catch { throw failure("WORLD_MANIFEST_INVALID", `invalid JSON in ${path}`); }
}
async function readJson(path) {
  await regular(path);
  return readJsonBytes(await readRegularFile(path, length => {
    if (length > BigInt(MAX_JSON)) throw failure("WORLD_MANIFEST_INVALID", `${path} exceeds JSON limit`);
  }), path);
}
async function regular(path) {
  const stat = await lstat(path);
  if (!stat.isFile()) throw failure("WORLD_FILE_INVALID", `expected regular file: ${path}`);
  return stat;
}
async function files(root, prefix = "", state = { count: 0 }, depth = 0) {
  if (depth > 16) throw failure("WORLD_INVENTORY_INVALID", "bundle directory nesting exceeds limit");
  const names = await readdir(join(root, prefix));
  if (names.length > 256) throw failure("WORLD_INVENTORY_INVALID", "bundle directory has too many entries");
  const result = [];
  for (const name of names.sort()) {
    if (++state.count > 256) throw failure("WORLD_INVENTORY_INVALID", "bundle has too many entries");
    const relative = prefix ? `${prefix}/${name}` : name;
    const stat = await lstat(join(root, relative));
    if (stat.isSymbolicLink()) throw failure("WORLD_FILE_INVALID", `symlink in bundle: ${relative}`);
    if (stat.isDirectory()) result.push(...await files(root, relative, state, depth + 1));
    else if (stat.isFile()) result.push(relative);
    else throw failure("WORLD_FILE_INVALID", `special file in bundle: ${relative}`);
  }
  return result.sort();
}
function safeRelative(value) {
  return typeof value === "string" && value.length > 0 && value.length < 512 && !value.includes("\\") &&
    !value.includes("\0") && !value.startsWith("/") && value.split("/").every(part => part && part !== "." && part !== "..") &&
    !isAbsolute(value);
}
async function inventory(root) {
  const result = [];
  for (const path of await files(root)) {
    if (path === "manifest.json") continue;
    const bytes = await readFile(join(root, path));
    result.push({ path, length: bytes.length, sha256: digest(bytes) });
  }
  return result;
}
export async function verifyRuntime(root, expectedManifest, smoke = false) {
  if (!SHA.test(expectedManifest ?? "")) throw failure("WORLD_EXPECTED_IDENTITY_INVALID", "caller must supply a manifest SHA-256");
  root = resolve(root);
  const manifestPath = join(root, "manifest.json");
  await regular(manifestPath);
  const manifestBytes = await readRegularFile(manifestPath, length => {
    if (length > BigInt(MAX_JSON)) throw failure("WORLD_MANIFEST_INVALID", "manifest exceeds JSON limit");
  });
  if (digest(manifestBytes) !== expectedManifest) throw failure("WORLD_MANIFEST_IDENTITY_INVALID", "manifest differs from caller-supplied SHA-256");
  const manifest = readJsonBytes(manifestBytes, manifestPath);
  if (manifest.format !== FORMAT || manifest.abi !== 3 || manifest.package?.version !== packageVersion ||
      JSON.stringify(manifest.profile) !== JSON.stringify(profile) ||
      !Array.isArray(manifest.requiredChecks) || JSON.stringify(manifest.requiredChecks) !== JSON.stringify(REQUIRED) ||
      !Array.isArray(manifest.files) || manifest.files.length > 128 || !manifest.source?.commit || !manifest.source?.tree ||
      manifest.source.clean !== true || !SHA.test(manifest.kernel?.sha256 ?? "") || manifest.kernel?.path !== "runtime/world-kernel.wasm")
    throw failure("WORLD_MANIFEST_INCOMPATIBLE", "manifest ABI, package, profile or required checks are incompatible");
  const paths = manifest.files.map(item => item.path);
  if (paths.some(path => !safeRelative(path)) || new Set(paths).size !== paths.length || JSON.stringify(paths) !== JSON.stringify([...paths].sort()))
    throw failure("WORLD_MANIFEST_INVALID", "manifest paths must be unique, safe and sorted");
  const actualPaths = await files(root);
  if (JSON.stringify(actualPaths) !== JSON.stringify([...paths, "manifest.json"].sort()))
    throw failure("WORLD_INVENTORY_INVALID", "bundle files differ from manifest inventory");
  for (const item of manifest.files) {
    if (!Number.isSafeInteger(item.length) || item.length < 0 || !SHA.test(item.sha256 ?? "")) throw failure("WORLD_MANIFEST_INVALID", `invalid inventory entry ${item.path}`);
    const path = join(root, item.path);
    const stat = await regular(path);
    if (stat.size !== item.length || digest(await readFile(path)) !== item.sha256) throw failure("WORLD_FILE_IDENTITY_INVALID", `file differs from manifest: ${item.path}`);
  }
  const qualification = await readJson(join(root, "qualification.json"));
  if (qualification.format !== "world-runtime-qualification/v1" ||
      REQUIRED.some(name => qualification.checks?.[name]?.status !== "passed"))
    throw failure("WORLD_QUALIFICATION_INCOMPLETE", "required qualification check is absent or not passed");
  const kernelBytes = await readFile(join(root, manifest.kernel.path));
  if (kernelBytes.length !== manifest.kernel.length || digest(kernelBytes) !== manifest.kernel.sha256)
    throw failure("WORLD_KERNEL_IDENTITY_INVALID", "kernel differs from manifest");
  const wasm = inspectKernelWasm(kernelBytes);
  if (wasm.importCount !== 0 || wasm.memory.shared || wasm.memory.maximumPages !== 4096 ||
      JSON.stringify(manifest.kernel.wasm) !== JSON.stringify(wasm))
    throw failure("WORLD_KERNEL_PROFILE_INVALID", "kernel physical profile differs from selected build");
  await Kernel.create({ bytes: kernelBytes, expectedSha256: manifest.kernel.sha256 });
  const packageInfo = await readJson(join(root, "runtime/package.json"));
  if (packageInfo.name !== "@tkersey/world" || packageInfo.version !== packageVersion || packageInfo.exports?.["."] !== "./src/embedding/index.mjs")
    throw failure("WORLD_PACKAGE_INCOMPATIBLE", "runtime package identity differs from manifest");
  if (smoke) {
    const run = spawnSync(process.execPath, [join(root, "runtime/src/node/runtime-smoke.mjs"), root, manifest.kernel.sha256], { cwd: root, encoding: "utf8", timeout: 30000, env: { PATH: process.env.PATH } });
    if (run.status !== 0) throw failure("WORLD_SMOKE_FAILED", `runtime smoke failed: ${run.stderr || run.error || run.status}`);
  }
  return { manifestSha256: expectedManifest, kernelSha256: manifest.kernel.sha256, files: manifest.files.length, smoke: !!smoke };
}
function run(file, args, cwd, timeout = 600000) {
  const child = spawnSync(file, args, { cwd, encoding: "utf8", timeout, maxBuffer: 8 << 20 });
  if (child.error || child.status !== 0) throw failure("WORLD_QUALIFICATION_FAILED", `${file} ${args.join(" ")} failed: ${child.stderr || child.error || child.status}`);
  return { stdout: child.stdout, stderr: child.stderr };
}
const git = (args, cwd) => {
  const child = spawnSync("git", args, { cwd, maxBuffer: 8 << 20, env: { ...process.env, GIT_NO_REPLACE_OBJECTS: "1" } });
  if (child.error || child.status !== 0) throw failure("WORLD_SOURCE_INVALID", `git ${args[0]} failed: ${child.stderr || child.error || child.status}`);
  return child.stdout;
};
async function cleanSource(source, expectedCommit = null) {
  const root = git(["rev-parse", "--show-toplevel"], source).toString().trim();
  const commit = git(["rev-parse", "HEAD"], source).toString().trim();
  const tree = git(["rev-parse", "HEAD^{tree}"], source).toString().trim();
  if (root !== source || (expectedCommit && commit !== expectedCommit) ||
      git(["rev-parse", "--show-object-format"], source).toString().trim() !== "sha1" ||
      git(["status", "--porcelain=v1", "--untracked-files=all"], source).length)
    throw failure("WORLD_SOURCE_DIRTY", "source must be the exact clean World repository root");
  const rows = git(["ls-tree", "-r", "-z", "HEAD"], source).toString().split("\0").filter(Boolean);
  for (const row of rows) {
    const match = /^(100644|100755|120000) blob ([0-9a-f]{40})\t(.+)$/s.exec(row);
    if (!match) throw failure("WORLD_SOURCE_INVALID", "unsupported tracked source entry");
    const [, mode, expected, path] = match;
    const name = join(source, path), stat = await lstat(name);
    if (mode === "120000" ? !stat.isSymbolicLink() : !stat.isFile() || !!(stat.mode & 0o111) !== (mode === "100755"))
      throw failure("WORLD_SOURCE_DIRTY", `tracked source mode changed: ${path}`);
    const bytes = mode === "120000" ? Buffer.from(await readlink(name)) : await readFile(name);
    const actual = createHash("sha1").update(`blob ${bytes.length}\0`).update(bytes).digest("hex");
    if (actual !== expected) throw failure("WORLD_SOURCE_DIRTY", `tracked source bytes differ from HEAD: ${path}`);
  }
  return { commit, tree };
}
const exists = async path => lstat(path).then(() => true, error => { if (error.code === "ENOENT") return false; throw error; });
async function prepareRuntime(source, output) {
  if (!isAbsolute(source) || !isAbsolute(output)) throw failure("WORLD_OPTION_INVALID", "source and output must be absolute paths");
  source = resolve(source); output = resolve(output);
  const archive = `${output}.tar.gz`, descriptor = `${output}.runtime-delivery.json`;
  for (const path of [output, archive, descriptor]) if (await exists(path))
    throw failure("WORLD_OUTPUT_EXISTS", `delivery path exists: ${path}; verify it or choose a new output`);
  const { commit, tree } = await cleanSource(source);
  const zonBytes = await readFile(join(source, "build.zig.zon"));
  const zon = zonBytes.toString("utf8");
  const dependencyCommit = zon.match(/boundary\/archive\/([0-9a-f]{40})\.tar\.gz/)?.[1];
  const dependencyPackage = zon.match(/\.hash\s*=\s*"(boundary-[^"]+)"/)?.[1];
  if (dependencyCommit !== "1b00c8c159f0cb490a1223fac8d3d208cef41cb1" || !dependencyPackage)
    throw failure("WORLD_DEPENDENCY_INVALID", "normal locked Boundary data dependency changed");
  const zig = run("zig", ["version"], source).stdout.trim();
  if (zig !== "0.16.0") throw failure("WORLD_TOOLCHAIN_INVALID", `Zig 0.16.0 required; found ${zig}`);
  const dependencyUrl = `https://github.com/tkersey/boundary/archive/${dependencyCommit}.tar.gz`;
  const resolvedPackage = run("zig", ["fetch", dependencyUrl], source).stdout.trim();
  if (resolvedPackage !== dependencyPackage) throw failure("WORLD_DEPENDENCY_INVALID", `resolved Boundary package ${resolvedPackage} differs from lock ${dependencyPackage}`);
  const sourceLocal = output.startsWith(`${source}${sep}`);
  const parent = sourceLocal ? dirname(source) : dirname(output);
  const lockPath = sourceLocal ? join(parent, `.${basename(output)}-${digest(Buffer.from(output)).slice(0, 16)}.lock`) : `${output}.lock`;
  let lock;
  try { lock = await open(lockPath, "wx"); }
  catch (error) {
    if (error.code === "EEXIST") throw failure("WORLD_PREPARE_BUSY", `preparation lock exists: ${lockPath}; confirm no producer is running before removing a stale lock, or choose a new output`);
    throw error;
  }
  let staging, publishedBundle = false, publishedArchive = false, publishedDescriptor = false;
  try {
    await lock.writeFile(json({ pid: process.pid, source, output, startedAt: new Date().toISOString() }));
    staging = await mkdtemp(join(parent, `.${basename(output)}-stage-`));
    const prefix = join(staging, "build");
    const checkCommand = ["build", "build-runtime", ...CHECK_STEPS, "-Doptimize=ReleaseSafe", "--summary", "all", "--prefix", prefix];
    const result = run("zig", checkCommand, source, 1800000);
    const bundle = join(staging, "bundle");
    await mkdir(bundle);
    await cp(join(prefix, "runtime"), join(bundle, "runtime"), { recursive: true, force: false, errorOnExist: true });
    await mkdir(join(bundle, "smoke"));
    const fixture = join(prefix, "current/bin/current-fixtures");
    const fixtureBytes = execFileSync(fixture, ["image", "resource"], { cwd: source });
    await writeFile(join(bundle, "smoke/resource.bpi3"), fixtureBytes);
    const kernelBytes = await readFile(join(bundle, "runtime/world-kernel.wasm"));
    const kernelSha256 = digest(kernelBytes);
    const smokeRun = run(process.execPath, [join(bundle, "runtime/src/node/runtime-smoke.mjs"), bundle, kernelSha256], bundle);
    const checks = Object.fromEntries(CHECK_STEPS.map(name => [name, { status: "passed", command: `zig build ${name} -Doptimize=ReleaseSafe`, input: { sourceCommit: commit, kernelSha256 }, zig, node: process.version }]));
    checks["bundle-smoke"] = { status: "passed", command: "node runtime/src/node/runtime-smoke.mjs BUNDLE KERNEL_SHA256", input: { kernelSha256, image: "smoke/resource.bpi3" }, node: process.version };
    await writeFile(join(bundle, "qualification.json"), json({ format: "world-runtime-qualification/v1", checks, limits: { input: 65536, working: 1048576, output: 65536 }, source: { commit, tree } }));
    await mkdir(join(bundle, "evidence"));
    await writeFile(join(bundle, "evidence/check.log"), result.stdout + result.stderr);
    await writeFile(join(bundle, "evidence/smoke.log"), smokeRun.stdout + smokeRun.stderr);
    const manifest = { format: FORMAT, source: { repository: "tkersey/world", commit, tree, clean: true }, dependency: { repository: "tkersey/boundary", commit: dependencyCommit, package: dependencyPackage, lockSha256: digest(zonBytes) }, zig, profile, abi: 3, package: { name: "@tkersey/world", version: packageVersion }, kernel: { path: "runtime/world-kernel.wasm", length: kernelBytes.length, sha256: kernelSha256, wasm: inspectKernelWasm(kernelBytes) }, requiredChecks: REQUIRED, files: await inventory(bundle) };
    const manifestBytes = json(manifest), manifestSha256 = digest(manifestBytes);
    await writeFile(join(bundle, "manifest.json"), manifestBytes);
    await verifyRuntime(bundle, manifestSha256, true);
    const tests = run(process.execPath, [join(source, "test/current/runtime_delivery.test.mjs"), bundle, manifestSha256, source], source);
    await writeFile(join(bundle, "evidence/verification-tests.log"), tests.stdout + tests.stderr);
    manifest.files = await inventory(bundle);
    const finalManifestBytes = json(manifest), finalManifestSha256 = digest(finalManifestBytes);
    await writeFile(join(bundle, "manifest.json"), finalManifestBytes);
    await verifyRuntime(bundle, finalManifestSha256, true);
    try { await cleanSource(source, commit); }
    catch (error) { if (error.code === "WORLD_SOURCE_DIRTY") throw failure("WORLD_SOURCE_CHANGED", error.message); throw error; }
    const prepared = join(staging, basename(output));
    await rename(bundle, prepared);
    const stagedArchive = join(staging, "runtime-bundle.tar.gz");
    run("tar", ["-czf", stagedArchive, "-C", staging, basename(output)], staging);
    const archiveBytes = await readFile(stagedArchive);
    for (const path of [output, archive, descriptor]) if (await exists(path))
      throw failure("WORLD_OUTPUT_EXISTS", `delivery path appeared during qualification: ${path}`);
    await rename(prepared, output);
    publishedBundle = true;
    await link(stagedArchive, archive);
    publishedArchive = true;
    const delivery = { format: "world-runtime-delivery/v1", source: manifest.source, dependency: manifest.dependency, bundle: output, archive, archiveLength: archiveBytes.length, archiveSha256: digest(archiveBytes), manifestSha256: finalManifestSha256, kernelSha256, provider: null };
    const receipt = await open(descriptor, "wx");
    publishedDescriptor = true;
    try { await receipt.writeFile(json(delivery)); }
    finally { await receipt.close(); }
    return delivery;
  } catch (error) {
    if (publishedDescriptor) await rm(descriptor, { force: true });
    if (publishedArchive) await rm(archive, { force: true });
    if (publishedBundle) await rm(output, { recursive: true, force: true });
    throw error;
  } finally {
    if (staging) await rm(staging, { recursive: true, force: true });
    await lock.close();
    await rm(lockPath, { force: true });
  }
}
export async function runtimeCommand(args) {
  const operation = args.shift();
  if (operation === "verify") {
    const options = exactOptions(args, ["--root", "--manifest-sha256"], ["--smoke"]);
    if (!options.has("--root") || !options.has("--manifest-sha256")) throw failure("WORLD_OPTION_INVALID", "verify requires --root and --manifest-sha256");
    console.log(JSON.stringify(await verifyRuntime(options.get("--root"), options.get("--manifest-sha256"), options.has("--smoke"))));
  } else if (operation === "prepare") {
    const options = exactOptions(args, ["--source", "--output"]);
    if (!options.has("--source") || !options.has("--output")) throw failure("WORLD_OPTION_INVALID", "prepare requires --source and --output");
    console.log(JSON.stringify(await prepareRuntime(options.get("--source"), options.get("--output"))));
  } else throw failure("WORLD_OPTION_INVALID", "expected runtime prepare or runtime verify");
}
