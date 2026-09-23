import { execFileSync, spawnSync } from "node:child_process";
import { mkdir, writeFile, cp, rename, rm, lstat, realpath } from "node:fs/promises";
import { join, dirname, resolve } from "node:path";
import { platform, arch } from "node:os";
import { fileURLToPath } from "node:url";
import { inventory, sha256, readBounded, reject, requiredChecks, verifyBundle } from "./runtime-bundle.mjs";
import { inspectKernelWasm } from "../embedding/wasm.mjs";
import { packageVersion } from "../embedding/index.mjs";
import { runSmoke } from "./runtime-smoke.mjs";

const dependencyCommit = "1b00c8c159f0cb490a1223fac8d3d208cef41cb1";
const dependencyPackage = "boundary-3.0.0-dev.0-flclaCJBFQCNUnFJK019OyLBDLZdg6_eTW1rzBpwImGA";
const dependencyUrl = `https://github.com/tkersey/boundary/archive/${dependencyCommit}.tar.gz`;
const limits = { input: 65536, working: 1048576, output: 65536 };
const json = value => JSON.stringify(value, null, 2) + "\n";
const text = (command, args, cwd) => execFileSync(command, args, { cwd, encoding: "utf8", timeout: 120000, maxBuffer: 2 << 20 }).trim();
async function absent(path) {
  try { await lstat(path); } catch (error) { if (error.code === "ENOENT") return; throw error; }
  reject("WORLD_BUNDLE_COLLISION", `destination exists; choose a new output or verify it: ${path}`);
}
export async function sourceIdentity(source) {
  source = await realpath(source);
  if (await realpath(fileURLToPath(new URL("../..", import.meta.url))) !== source)
    reject("WORLD_BUNDLE_SOURCE_INVALID", "run prepare from the selected source's bin/world.mjs");
  if (text("git", ["rev-parse", "--show-toplevel"], source) !== source ||
      text("git", ["status", "--porcelain", "--untracked-files=all"], source))
    reject("WORLD_BUNDLE_SOURCE_DIRTY", "qualified preparation requires a clean source checkout");
  const lock = await readBounded(join(source, "build.zig.zon"));
  const zon = new TextDecoder().decode(lock);
  if (!zon.includes(`.url = "${dependencyUrl}"`) || !zon.includes(`.hash = "${dependencyPackage}"`))
    reject("WORLD_BUNDLE_DEPENDENCY_INVALID", "normal locked Boundary-data dependency differs");
  if (text("zig", ["version"], source) !== "0.16.0")
    reject("WORLD_BUNDLE_TOOL_UNAVAILABLE", "Zig 0.16.0 is required");
  return { repository: "https://github.com/tkersey/world", commit: text("git", ["rev-parse", "HEAD"], source),
    tree: text("git", ["rev-parse", "HEAD^{tree}"], source), clean: true,
    dependency: { commit: dependencyCommit, package: dependencyPackage, url: dependencyUrl, lockSha256: sha256(lock) } };
}
async function checked(source, evidence, checks, name, command, args) {
  const started = new Date().toISOString();
  const result = spawnSync(command, args, { cwd: source, encoding: "utf8", maxBuffer: 16 << 20, timeout: 1800000 });
  const status = result.error?.code === "ENOENT" ? "blocked" : result.status === 0 ? "passed" : "failed";
  await writeFile(join(evidence, `${name}.log`), `${result.stdout ?? ""}${result.stderr ?? ""}${result.error ?? ""}`);
  checks.push({ name, command, args, started, status, exitCode: result.status, log: `evidence/${name}.log` });
  await writeFile(join(dirname(evidence), "qualification.json"), json({ checks }));
  if (status !== "passed") reject("WORLD_BUNDLE_QUALIFICATION_FAILED", `${name} ${status}; see ${join(evidence, `${name}.log`)}`);
  return result.stdout.trim();
}
export async function prepareBundle(source, output) {
  source = await realpath(source); output = resolve(output);
  const identity = await sourceIdentity(source);
  await mkdir(dirname(output), { recursive: true });
  for (const path of [output, `${output}.tar.gz`, `${output}.delivery.json`]) await absent(path);
  const lock = `${output}.preparing`;
  try { await mkdir(lock); } catch (error) {
    if (error.code === "EEXIST") reject("WORLD_BUNDLE_COLLISION", `preparation already active/interrupted: ${lock}`);
    throw error;
  }
  const bundle = join(lock, "bundle"), evidence = join(bundle, "evidence"), checks = [];
  await mkdir(evidence, { recursive: true });
  const run = (name, command, args) => checked(source, evidence, checks, name, command, args);
  const prefix = join(lock, "build");
  const cache = join(lock, "zig-global");
  const build = steps => ["build", ...steps, "-Doptimize=ReleaseSafe", "--prefix", prefix, "--global-cache-dir", cache];
  try {
    // A fresh Zig cache authenticates the normal package, independent of consumer trees.
    await run("build", "zig", build(["build-runtime", "check-kernel"]));
    const dependency = join(cache, "p", dependencyPackage);
    await lstat(join(dependency, "build.zig.zon"));
    await cp(join(prefix, "runtime"), join(bundle, "runtime"), { recursive: true, errorOnExist: true });
    await run("browser-tools", "npm", ["ci", "--ignore-scripts", "--prefix", "test/current/browser-tools"]);
    await run("browser-install", process.execPath, ["test/current/browser-tools/node_modules/playwright-core/cli.js", "install", "chromium", "firefox"]);
    await run("check", "zig", build(["check"]));
    await run("check-release-fast", "zig", ["build", "check-storage", "-Doptimize=ReleaseFast", "--global-cache-dir", cache]);
    const kernel = join(bundle, "runtime/world-kernel.wasm"), fixtures = join(prefix, "current/bin/current-fixtures");
    const scripts = { "delivered-kernel": ["kernel.mjs", kernel, fixtures],
      "delivered-package": ["package.mjs", join(bundle, "runtime"), fixtures],
      "delivered-source": ["source_agreement.mjs", kernel, fixtures, join(prefix, "source"), join(dependency, "test/v2/source_oracle.mjs")],
      "delivered-capacity": ["capacity.mjs", kernel, fixtures, dependency],
      "delivered-transfer": ["transfer.mjs", kernel, fixtures] };
    const before = sha256(await readBounded(kernel));
    for (const [name, [script, ...args]] of Object.entries(scripts))
      await run(name, process.execPath, [join(source, "test/current", script), ...args]);
    if (sha256(await readBounded(kernel)) !== before) reject("WORLD_BUNDLE_CORRUPT", "qualification changed kernel bytes");
    await mkdir(join(bundle, "smoke"));
    for (const [file, fixture] of [["pure", "install"], ["effect", "resource"]])
      await writeFile(join(bundle, "smoke", `${file}.bpi3`), execFileSync(fixtures, ["image", fixture], { maxBuffer: 2 << 20 }));
    const smoke = await runSmoke(bundle, before);
    checks.push({ name: "portable-smoke", command: "installed runtime smoke", status: "passed", result: smoke, limits });
    const bytes = await readBounded(kernel), profile = inspectKernelWasm(bytes);
    const module = new WebAssembly.Module(bytes);
    const buildInfo = { zig: "0.16.0", target: "wasm32-freestanding", kernelMode: "ReleaseSmall", hostMode: "ReleaseSafe",
      stackBytes: 65536, maximumMemoryBytes: 268435456, defaults: limits, wasm: profile,
      imports: WebAssembly.Module.imports(module), exports: WebAssembly.Module.exports(module) };
    await writeFile(join(bundle, "qualification.json"), json({ source: identity, host: { platform: platform(), arch: arch(), node: process.version },
      limits: { smoke: limits, kernelTransfer: { input: 2097152, working: 8388608, output: 2097152 }, source: { input: 8388608, working: 67108864, output: 8388608 }, capacity: "per-case forced budgets; see capacity evidence" }, checks }));
    const kernelInfo = { path: "runtime/world-kernel.wasm", bytes: bytes.length, sha256: before, abi: 3 };
    const manifest = { format: "world-runtime-bundle/v1", source: identity, packageVersion, build: buildInfo,
      kernel: kernelInfo, requiredChecks, files: await inventory(bundle) };
    await writeFile(join(bundle, "manifest.json"), json(manifest));
    const manifestSha256 = sha256(await readBounded(join(bundle, "manifest.json")));
    await verifyBundle(bundle, manifestSha256, true);
    if (JSON.stringify(await sourceIdentity(source)) !== JSON.stringify(identity))
      reject("WORLD_BUNDLE_SOURCE_DIRTY", "source changed during qualification");
    const archive = join(lock, "bundle.tar.gz");
    execFileSync("tar", ["--format=ustar", "-czf", archive, "-C", bundle, "."], { timeout: 120000 });
    const transport = await readBounded(archive);
    const delivery = { format: "world-runtime-delivery/v1", source: identity, manifestSha256, kernelSha256: before,
      archive: { path: `${output}.tar.gz`, bytes: transport.length, sha256: sha256(transport) }, bundle: output };
    await writeFile(join(lock, "delivery.json"), json(delivery));
    await rename(archive, `${output}.tar.gz`);
    await rename(join(lock, "delivery.json"), `${output}.delivery.json`);
    await rename(bundle, output); // Publish ready directory last.
    await rm(lock, { recursive: true });
    return delivery;
  } catch (error) {
    // Keep bounded failed-check evidence, but never publish a ready directory.
    error.message += `; incomplete preparation retained at ${lock}`;
    throw error;
  }
}
