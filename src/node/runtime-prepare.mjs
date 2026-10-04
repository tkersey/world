import { execFileSync, spawnSync } from "node:child_process";
import { mkdir, writeFile, cp, rename, lstat, realpath, access } from "node:fs/promises";
import { constants } from "node:fs";
import { join, dirname, basename, resolve, relative, isAbsolute, delimiter, sep } from "node:path";
import { platform, arch, homedir } from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";
import { inventory, packageInventory, sha256, readBounded, reject, requiredChecks, verifyBundle } from "./runtime-bundle.mjs";
import { inspectKernelWasm } from "../embedding/wasm.mjs";
import { packageVersion, encodeInput } from "../embedding/index.mjs";
import { runSmoke } from "./runtime-smoke.mjs";
import { reserveOutput } from "./runtime-output.mjs";
import { selectZig } from "./toolchain.mjs";
import runtimeProfile from "./runtime-profile.json" with { type: "json" };

const { commit: dependencyCommit, package: dependencyPackage, url: dependencyUrl } = runtimeProfile.boundary;
const limits = runtimeProfile.defaults;
const json = value => JSON.stringify(value, null, 2) + "\n";
const gitEnvironment = () => ({ ...process.env, GIT_NO_REPLACE_OBJECTS: "1" });
const text = (command, args, cwd) => execFileSync(command, args, {
  cwd, encoding: "utf8", timeout: 120000, maxBuffer: 2 << 20,
  env: command === "git" ? gitEnvironment() : process.env,
}).trim();
export async function sourceIdentity(source) {
  source = await realpath(source);
  if (await realpath(fileURLToPath(new URL("../..", import.meta.url))) !== source)
    reject("WORLD_BUNDLE_SOURCE_INVALID", "run prepare from the selected source's bin/world.mjs");
  if (text("git", ["rev-parse", "--show-toplevel"], source) !== source ||
      text("git", ["status", "--porcelain", "--untracked-files=all"], source))
    reject("WORLD_BUNDLE_SOURCE_DIRTY", "qualified preparation requires a clean source checkout");
  const commit = text("git", ["rev-parse", "HEAD"], source);
  const tree = text("git", ["rev-parse", `${commit}^{tree}`], source);
  const lock = execFileSync("git", ["show", `${commit}:build.zig.zon`], {
    cwd: source, timeout: 120000, maxBuffer: 1 << 20, env: gitEnvironment(),
  });
  const zon = new TextDecoder().decode(lock);
  if (!zon.includes(`.url = "${dependencyUrl}"`) || !zon.includes(`.hash = "${dependencyPackage}"`))
    reject("WORLD_BUNDLE_DEPENDENCY_INVALID", "normal locked Boundary-data dependency differs");
  if (text("git", ["rev-parse", "HEAD"], source) !== commit ||
      text("git", ["status", "--porcelain", "--untracked-files=all"], source))
    reject("WORLD_BUNDLE_SOURCE_CHANGED", "source changed during snapshot selection; retry from a clean checkout");
  return { repository: "https://github.com/tkersey/world", commit, tree, clean: true,
    cleanScope: "snapshot-selection",
    dependency: { commit: dependencyCommit, package: dependencyPackage, url: dependencyUrl, lockSha256: sha256(lock) } };
}
async function checked(source, evidence, checks, name, command, args, env) {
  const started = new Date().toISOString();
  const result = spawnSync(command, args, { cwd: source, env, encoding: "utf8", maxBuffer: 16 << 20, timeout: 1800000 });
  const status = result.error?.code === "ENOENT" ? "blocked" : result.status === 0 ? "passed" : "failed";
  await writeFile(join(evidence, `${name}.log`), `${result.stdout ?? ""}${result.stderr ?? ""}${result.error ?? ""}`);
  checks.push({ name, command, args, cwd: source, started, finished: new Date().toISOString(), status, exitCode: result.status,
    signal: result.signal, log: `evidence/${name}.log` });
  await writeFile(join(dirname(evidence), "qualification.json"), json({ checks }));
  if (status !== "passed") reject("WORLD_BUNDLE_QUALIFICATION_FAILED", `${name} ${status}; see ${join(evidence, `${name}.log`)}`);
  return result.stdout.trim();
}
/** The caller supplies an independently selected package-inventory identity. */
export async function verifyPackage(root, expected) {
  if (!/^[a-f0-9]{64}$/.test(expected ?? "")) reject("WORLD_BUNDLE_DEPENDENCY_INVALID", "package inventory identity required");
  if (!(await lstat(root)).isDirectory()) reject("WORLD_BUNDLE_DEPENDENCY_INVALID", "package root must be a directory, not an alias");
  const contents = await packageInventory(root), actual = sha256(JSON.stringify(contents));
  if (actual !== expected) reject("WORLD_BUNDLE_DEPENDENCY_INVALID", "consumed Boundary package inventory differs");
  return { inventorySha256: actual, files: contents.files.length, directories: contents.directories.length };
}
/** Copy verified bytes into a new run-owned directory before any build code runs. */
export async function copyVerifiedPackage(source, destination, expected) {
  await verifyPackage(source, expected);
  await mkdir(dirname(destination), { recursive: true });
  await cp(source, destination, { recursive: true, errorOnExist: true, force: false });
  return verifyPackage(destination, expected);
}

// Canonicalize existing ancestors without creating a caller-owned store.
async function location(path) {
  const suffix = [];
  for (let current = resolve(path); ; current = dirname(current)) {
    try { return join(await realpath(current), ...suffix.reverse()); }
    catch (error) {
      if (error.code !== "ENOENT") throw error;
      if (dirname(current) === current) throw error;
      suffix.push(basename(current));
    }
  }
}
const contains = (parent, child) => { const part = relative(parent, child); return part === "" || (part !== ".." && !part.startsWith(".." + sep) && !isAbsolute(part)); };
export async function packageStore(requested, source, output, owned) {
  if (!requested) return { root: owned, owned: true };
  const root = await location(requested), destination = await location(output), stage = await location(`${output}.preparing`);
  if ([await realpath(homedir()), await realpath(source), dirname(root)].includes(root) ||
      contains(stage, root) || contains(destination, root))
    reject("WORLD_BUNDLE_DESTINATION_INVALID", "package store must be separate from source, home and output ownership");
  return { root, owned: false };
}

export async function prepareBundle(source, output, options = {}) {
  source = await realpath(source); output = resolve(output);
  const originalSource = source;
  const identity = await sourceIdentity(source);
  let compiler;
  try {
    compiler = selectZig([
      ...(options.zigExe ? ["--zig-exe", options.zigExe] : []),
      ...(options.zigLib ? ["--zig-lib", options.zigLib] : []),
    ]);
  } catch (error) { reject("WORLD_BUNDLE_TOOL_UNAVAILABLE", error.message); }
  const requested = options.packageRoot ?? process.env.ZIG_LOCAL_PKG_DIR;
  const store = await packageStore(requested, originalSource, output, join(`${output}.preparing`, "packages"));
  const reservation = await reserveOutput(output, [`${output}.tar.gz`, `${output}.delivery.json`]);
  output = reservation.output;
  const lock = reservation.stage;
  const bundle = join(lock, "bundle"), evidence = join(bundle, "evidence"), checks = [];
  const prefix = join(lock, "build");
  const cache = join(lock, "zig-global");
  const packages = join(lock, "packages");
  const env = { ...compiler.env, PATH: dirname(process.execPath) + delimiter + (compiler.env.PATH ?? ""),
    ZIG_GLOBAL_CACHE_DIR: cache, ZIG_LOCAL_CACHE_DIR: join(lock, "zig-local"), ZIG_LOCAL_PKG_DIR: packages,
    PLAYWRIGHT_SKIP_BROWSER_GC: "1", ...(options.offline ? { UV_OFFLINE: "true" } : {}) };
  const run = (name, command, args, selectedEnv = env) => checked(source, evidence, checks, name, command, args, selectedEnv);
  const build = steps => ["build", ...steps, `-Doptimize=${runtimeProfile.hostMode}`, "--prefix", prefix, "--verbose"];
  try {
    await mkdir(evidence, { recursive: true });
    if (store.owned) store.root = packages;
    // Export only committed source: ignored zig-pkg/build state cannot influence qualification.
    source = join(lock, "source");
    await mkdir(source);
    const sourceArchive = execFileSync("git", ["archive", identity.commit], {
      cwd: originalSource, maxBuffer: 64 << 20, env: gitEnvironment(),
    });
    execFileSync("tar", ["-xf", "-", "-C", source], { input: sourceArchive, timeout: 120000 });
    const selectedPackage = join(store.root, dependencyPackage);
    const present = await lstat(selectedPackage).catch(error => { if (error.code !== "ENOENT") throw error; return null; });
    if (!present) {
      if (options.offline) reject("WORLD_BUNDLE_TOOL_UNAVAILABLE", "authenticated Boundary package is unavailable offline");
      // --fetch=all exits after passive manifest acquisition, before configuring
      // or executing dependency build code. Existing stores are verified first.
      await run("fetch-package", compiler.executable, ["build", "--fetch=all"], { ...env, ZIG_LOCAL_PKG_DIR: store.root });
    }
    const dependency = join(packages, dependencyPackage);
    const consumed = store.owned ? await verifyPackage(dependency, runtimeProfile.boundary.inventorySha256) :
      await copyVerifiedPackage(selectedPackage, dependency, runtimeProfile.boundary.inventorySha256);
    identity.dependency.inventorySha256 = consumed.inventorySha256;
    checks.push({ name: "dependency-package", operation: "verifyPackage", status: "passed", ...consumed,
      selectedRoot: store.root, consumedRoot: packages, selection: options.packageRoot ? "argument" : requested ? "environment" : "run-owned" });
    await run("build", compiler.executable, build(["build-runtime", "check-kernel"]));
    await cp(join(prefix, "runtime"), join(bundle, "runtime"), { recursive: true, errorOnExist: true });
    await run("browser-tools", "npm", ["ci", "--ignore-scripts", ...(options.offline ? ["--offline"] : []), "--prefix", "test/current/browser-tools"]);
    if (options.offline) {
      const { chromium, firefox } = await import(pathToFileURL(join(source, "test/current/browser-tools/node_modules/playwright-core/index.mjs")));
      for (const browser of [chromium, firefox]) {
        try { await access(browser.executablePath(), constants.X_OK); }
        catch { reject("WORLD_BUNDLE_TOOL_UNAVAILABLE", "locked browser executable is unavailable offline"); }
      }
      checks.push({ name: "browser-install", operation: "offline executable availability", status: "passed" });
    } else await run("browser-install", process.execPath, ["test/current/browser-tools/node_modules/playwright-core/cli.js", "install", "chromium", "firefox"]);
    await run("check", compiler.executable, build(["check"]));
    await run("check-release-fast", compiler.executable, ["build", "check-storage", "-Doptimize=fast"]);
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
    await writeFile(join(bundle, "smoke/pure.pki3"), encodeInput({ image: await readBounded(join(bundle, "smoke/pure.bpi3")), initialArgs: new Uint8Array() }));
    const smoke = await runSmoke(bundle, before);
    checks.push({ name: "portable-smoke", command: "installed runtime smoke", status: "passed", result: smoke, limits });
    const bytes = await readBounded(kernel), profile = inspectKernelWasm(bytes);
    const module = new WebAssembly.Module(bytes);
    const resolvedProfile = JSON.parse(await readBounded(join(prefix, "kernel-profile.json"), 65536));
    if (resolvedProfile.target !== runtimeProfile.target || resolvedProfile.mode !== runtimeProfile.kernelMode ||
        resolvedProfile.backend !== runtimeProfile.wasmBackend || resolvedProfile.linker !== runtimeProfile.wasmLinker ||
        resolvedProfile.cpu !== runtimeProfile.cpu || JSON.stringify(resolvedProfile.features) !== JSON.stringify(runtimeProfile.features) ||
        resolvedProfile.stackBytes !== runtimeProfile.stackBytes || resolvedProfile.maximumMemoryBytes !== runtimeProfile.maximumMemoryBytes)
      reject("WORLD_BUNDLE_INCOMPATIBLE", "configured kernel profile differs from delivery policy");
    await verifyPackage(dependency, runtimeProfile.boundary.inventorySha256);
    compiler.assertUnchanged();
    checks.push({ name: "toolchain-unchanged", operation: "executable and library identity recheck", status: "passed" });
    const buildInfo = { zig: runtimeProfile.zig, target: runtimeProfile.target, kernelMode: runtimeProfile.kernelMode, hostMode: runtimeProfile.hostMode,
      backend: resolvedProfile.backend, linker: resolvedProfile.linker, cpu: resolvedProfile.cpu, features: resolvedProfile.features,
      toolchain: compiler.identity, stackBytes: runtimeProfile.stackBytes, maximumMemoryBytes: runtimeProfile.maximumMemoryBytes, defaults: limits, wasm: profile,
      imports: WebAssembly.Module.imports(module), exports: WebAssembly.Module.exports(module) };
    await writeFile(join(bundle, "qualification.json"), json({ source: identity, host: { platform: platform(), arch: arch(), node: process.version },
      limits: { smoke: limits, kernelTransfer: { input: 2097152, working: 8388608, output: 2097152 }, source: { input: 8388608, working: 67108864, output: 8388608 }, capacity: "per-case forced budgets; see capacity evidence" }, checks }));
    const kernelInfo = { path: "runtime/world-kernel.wasm", bytes: bytes.length, sha256: before, abi: 3 };
    const manifest = { format: "world-runtime-bundle/v1", source: identity, packageVersion, build: buildInfo,
      kernel: kernelInfo, requiredChecks, files: await inventory(bundle) };
    await writeFile(join(bundle, "manifest.json"), json(manifest));
    const manifestSha256 = sha256(await readBounded(join(bundle, "manifest.json")));
    await verifyBundle(bundle, manifestSha256, true);
    // All build and qualification inputs came from git archive(identity.commit).
    // Later live-checkout changes, including this producer's output, are not inputs.
    const archive = join(lock, "bundle.tar.gz");
    execFileSync("tar", ["--format=ustar", "-czf", archive, "-C", bundle, "."], { timeout: 120000 });
    const transport = await readBounded(archive);
    compiler.assertUnchanged();
    const delivery = { format: "world-runtime-delivery/v1", source: identity, manifestSha256, kernelSha256: before,
      archive: { path: `${output}.tar.gz`, bytes: transport.length, sha256: sha256(transport) }, bundle: output };
    await writeFile(join(lock, "delivery.json"), json(delivery));
    await reservation.assertOwned();
    await rename(archive, `${output}.tar.gz`);
    await reservation.assertOwned();
    await rename(join(lock, "delivery.json"), `${output}.delivery.json`);
    await reservation.assertOwned();
    await rename(bundle, output); // Publish ready directory last.
    await reservation.cleanup();
    return delivery;
  } catch (error) {
    try {
      await reservation.assertOwned();
      await writeFile(join(bundle, "qualification.json"), json({ source: identity, checks,
        failure: { status: error.code === "WORLD_BUNDLE_TOOL_UNAVAILABLE" ? "blocked" : "failed", code: error.code, message: error.message } }));
    } catch { /* Never write evidence through a replaced reservation. */ }
    // Keep bounded failed-check evidence, but never publish a ready directory.
    error.message += `; incomplete preparation retained at ${lock}`;
    throw error;
  } finally { await reservation.close(); }
}
