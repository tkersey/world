// Compile and emit through each version's public authoring interface. Every
// timed build gets empty local/global object caches and already acquired sources.
import assert from "node:assert/strict";
import { readFile, writeFile, mkdir, mkdtemp, cp, readdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { performance } from "node:perf_hooks";
import os from "node:os";

const [boundaryArgument, outputArgument] = process.argv.slice(2);
assert.ok(outputArgument, "expected Boundary source and measurement output directory");
const boundary = resolve(boundaryArgument), output = resolve(outputArgument);
await mkdir(output, { recursive: true });
const run = await mkdtemp(join(output, "run-"));
const frozen = join(run, "frozen-boundary");
await mkdir(frozen);
const commit = "999e936c4a865cd31948b52b2af2baeacf84c9f1";
const digest = bytes => createHash("sha256").update(bytes).digest("hex");
async function compilerIdentity() {
  const files = ["build.zig", "build.zig.zon", "test/v2/economy_v2.zig"];
  async function walk(path) {
    for (const entry of await readdir(join(boundary, path), { withFileTypes: true })) {
      const child = `${path}/${entry.name}`;
      if (entry.isDirectory()) await walk(child);
      else if (entry.isFile()) files.push(child);
      else throw new Error(`unexpected compiler source entry ${child}`);
    }
  }
  await walk("src/v2");
  const hash = createHash("sha256");
  for (const file of files.sort()) {
    const bytes = await readFile(join(boundary, file));
    hash.update(`${file.length}:${file}:${bytes.length}:`); hash.update(bytes);
  }
  return hash.digest("hex");
}
const compilerSourceSha256 = await compilerIdentity();
function command(file, args, options = {}) {
  const result = spawnSync(file, args, { ...options, maxBuffer: 64 << 20 });
  assert.equal(result.status, 0, `${file} ${args.join(" ")}\n${result.stderr?.toString()}`);
  return result.stdout;
}
const archive = command("git", ["archive", "--format=tar", commit], { cwd: boundary });
command("tar", ["-xf", "-", "-C", frozen], { input: archive });
const baselineSource = await readFile(join(boundary, "test/v2/economy_v1.zig"));
const candidateSource = await readFile(join(boundary, "test/v2/economy_v2.zig"));
const memorySource = await readFile(new URL("./economy_v1_probe.zig", import.meta.url));
await writeFile(join(frozen, "test/economy_v1.zig"), baselineSource);
await writeFile(join(frozen, "test/economy_memory.zig"), memorySource);
const buildPath = join(frozen, "build.zig");
const build = await readFile(buildPath, "utf8");
const anchor = "    wirePublicImports(host_boundary, host_core);";
assert.equal(build.split(anchor).length, 2);
await writeFile(buildPath, build.replace(anchor, anchor + `
    const economy_options = b.addOptions();
    economy_options.addOption(usize, "kind", b.option(usize, "economy-kind", "Matched compiler workload") orelse 0);
    const economy_module = b.createModule(.{ .root_source_file = b.path("test/economy_v1.zig"), .target = b.graph.host, .optimize = optimize, .imports = &.{.{ .name = "boundary", .module = host_boundary }} });
    economy_module.addOptions("economy_options", economy_options);
    const economy_exe = b.addExecutable(.{ .name = "economy-compiler", .root_module = economy_module });
    b.step("emit-economy-compiler", "Emit matched compiler workload").dependOn(&b.addRunArtifact(economy_exe).step);
    const memory_module = b.createModule(.{ .root_source_file = b.path("test/economy_memory.zig"), .target = b.graph.host, .optimize = optimize, .imports = &.{ .{ .name = "image_v1", .module = host_core.image_v1 }, .{ .name = "process_advance_v1", .module = host_core.process_advance_v1 } } });
    const memory_exe = b.addExecutable(.{ .name = "v1-economy-probe", .root_module = memory_module });
    b.step("build-economy-memory", "Build isolated memory observer").dependOn(&b.addInstallArtifact(memory_exe, .{}).step);
`));
function argumentsFor(version, kind, directory) {
  return ["build", "--build-file", version === 0 ? buildPath : join(boundary, "build.zig"), "emit-economy-compiler", "-Doptimize=ReleaseSafe", `-Deconomy-kind=${kind}`, "--cache-dir", join(directory, "local"), "--global-cache-dir", join(directory, "global"), "--prefix", join(directory, "output"), "--summary", "none"];
}
const bootstrap = join(run, "bootstrap");
command("zig", argumentsFor(0, 0, bootstrap), { cwd: boundary });
// Only immutable dependency source packages are reused. No compiled objects or
// build-system artifacts enter any timed cache.
const packages = join(bootstrap, "global/p");
const measurements = [];
for (const kind of [0, 1]) {
  const expected = [null, null], times = [[], []];
  for (let sample = 0; sample < 5; sample++) for (const version of (sample % 2 ? [1, 0] : [0, 1])) {
    const directory = join(run, `kind-${kind}-version-${version}-sample-${sample}`);
    await mkdir(join(directory, "global"), { recursive: true });
    await cp(packages, join(directory, "global/p"), { recursive: true });
    const args = argumentsFor(version, kind, directory);
    const start = performance.now();
    const bytes = command("zig", args, { cwd: boundary });
    const elapsed = performance.now() - start;
    assert.equal(bytes.subarray(0, 8).toString(), version === 0 ? "ABL_BPI1" : "ABL_BPI2");
    const hash = digest(bytes);
    expected[version] ??= hash;
    assert.equal(hash, expected[version], "cold builds must emit identical bytes");
    times[version].push(elapsed);
    await writeFile(join(directory, version === 0 ? "image.bpi1" : "image.bpi2"), bytes);
    const row = { kind, version, sample, elapsedMs: elapsed, imageBytes: bytes.length, imageSha256: hash, command: ["zig", ...args] };
    measurements.push(row);
    console.log(JSON.stringify({ kind, version, sample, elapsedMs: elapsed }));
  }
  for (const version of [0, 1]) await writeFile(join(output, `cold-${kind}-${version}.txt`), times[version].join("\n") + "\n");
}
const median = values => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const workloads = [0, 1].map(kind => {
  const times = [0, 1].map(version => measurements.filter(row => row.kind === kind && row.version === version).map(row => row.elapsedMs));
  return { kind, name: kind === 0 ? "one-effect" : "add-32", beforeMedianMs: median(times[0]), afterMedianMs: median(times[1]), ratio: median(times[1]) / median(times[0]) };
});
assert.equal(await compilerIdentity(), compilerSourceSha256, "compiler inputs changed during measurement");
// Building the allocation probe is outside every timed compiler sample.
const probeArguments = argumentsFor(0, 0, bootstrap);
probeArguments[probeArguments.indexOf("emit-economy-compiler")] = "build-economy-memory";
command("zig", probeArguments, { cwd: boundary });
const report = { format: "world-v2-cold-compiler-economy/v1", environment: { date: new Date().toISOString(), node: process.version, platform: os.platform(), release: os.release(), cpu: os.cpus()[0].model, zig: command("zig", ["version"]).toString().trim() }, method: "five serial cold compile-and-emission samples per version and workload; empty Zig object caches; dependency sources acquired before timing; OS file cache uncontrolled; ReleaseSafe", baseline: { commit, archiveSha256: digest(archive), sourceSha256: digest(baselineSource), memoryProbeSourceSha256: digest(memorySource), memoryProbe: join(bootstrap, "output/bin/v1-economy-probe") }, candidate: { sourceSha256: digest(candidateSource), compilerSourceSha256 }, workloads, measurements };
await writeFile(join(output, "cold-compile.json"), JSON.stringify(report, null, 2) + "\n");
for (const row of workloads) assert.ok(row.ratio <= 2, `${row.name} cold compile plus emission exceeds 2x (${row.ratio})`);
