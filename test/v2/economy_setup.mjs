// Separate cold kernel builds, engine setup, and paired program sizes.
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import os from 'node:os';
import { inspectProcessKernelWasm } from '../../src/process_v2/wasm.mjs';
import { sha256, sourceIdentity, json } from '../../scripts/v2/assets.mjs';

const [boundaryArgument, kernelArgument, outputArgument] = process.argv.slice(2);
assert.ok(outputArgument && process.argv.length === 5, 'expected Boundary source, kernel, output');
const boundary = resolve(boundaryArgument), kernel = resolve(kernelArgument), output = resolve(outputArgument), world = resolve(import.meta.dirname, '../..');
await mkdir(output, { recursive: true });
const scratch = await mkdtemp(join(output, 'setup-'));
async function executionInputs(root) {
  const identity = await sourceIdentity(root);
  const files = identity.files.filter(({ name }) => name.startsWith('src/') || ['build.zig', 'build.zig.zon', 'package.json', 'test/v2/economy_setup.mjs', 'test/v2/engine_setup.mjs', 'test/v2/wasmtime/engine_setup.py', 'test/v2/wasmtime/pyproject.toml', 'test/v2/wasmtime/uv.lock', 'scripts/v2/assets.mjs'].includes(name));
  return { git: identity.git, fileScope: 'source, build driver and engine measurement code', files, filesSha256: sha256(json(files)) };
}
const sources = { boundary: await executionInputs(boundary), world: await executionInputs(world) };
const bytes = await readFile(kernel), kernelSha256 = sha256(bytes), abi = inspectProcessKernelWasm(bytes);
function command(file, args, env = process.env) {
  const run = spawnSync(file, args, { cwd: world, env, maxBuffer: 16 << 20, timeout: 180000 });
  assert.equal(run.status, 0, `${file}: ${run.stderr?.toString()}`);
  return run.stdout;
}
const builds = [];
for (let sample = 0; sample < 5; sample++) {
  const directory = join(scratch, `build-${sample}`);
  const started = performance.now();
  command('zig', ['build', 'build-v2-kernel', `-Dboundary-v2-source=${boundary}`, '-Doptimize=ReleaseSafe',
    '--cache-dir', join(directory, 'local'), '--global-cache-dir', join(directory, 'global'), '--prefix', join(directory, 'output')]);
  const elapsedMs = performance.now() - started;
  assert.equal(sha256(await readFile(join(directory, 'output/world-process-kernel-v2.wasm'))), kernelSha256);
  builds.push({ sample, elapsedMs });
  console.log(JSON.stringify({ build: sample, elapsedMs }));
}
const javascript = [];
for (let sample = 0; sample < 21; sample++) javascript.push(JSON.parse(command(process.execPath, [join(world, 'test/v2/engine_setup.mjs'), kernel])));
const project = join(world, 'test/v2/wasmtime');
const wasmtime = JSON.parse(command('uv', ['run', '--locked', '--project', project, '--python', '3.14.7', 'python', join(project, 'engine_setup.py'), kernel],
  { ...process.env, UV_CACHE_DIR: join(world, '.cache/v2/uv'), UV_PROJECT_ENVIRONMENT: join(world, '.cache/v2/wasmtime-environment') }));
const sizePairs = [];
for (const [name, before, after] of [
  ['seven additional installations of shared code', 'economy-1.bpi2', 'economy-8.bpi2'],
  ['sixty-three additional installations of shared code', 'economy-1.bpi2', 'economy-64.bpi2'],
  ['same resource client with pair rather than scalar private representation', 'source-resource-scalar.bpi2', 'source-resource-pair.bpi2'],
  ['State outside versus inside Choice', 'source-state-local.bpi2', 'source-state-shared.bpi2'],
]) {
  const left = await readFile(join(boundary, 'zig-out/v2', before)), right = await readFile(join(boundary, 'zig-out/v2', after));
  sizePairs.push({ name, before: { file: before, bytes: left.length, sha256: sha256(left) }, after: { file: after, bytes: right.length, sha256: sha256(right) }, deltaBytes: right.length - left.length });
}
assert.equal((await executionInputs(boundary)).filesSha256, sources.boundary.filesSha256);
assert.equal((await executionInputs(world)).filesSha256, sources.world.filesSha256);
assert.equal(sha256(await readFile(kernel)), kernelSha256);
const median = values => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const summary = { kernelBuildMedianMs: median(builds.map(row => row.elapsedMs)), javascriptCompileMedianMs: median(javascript.map(row => row.compileMs)),
  javascriptInstantiateMedianMs: median(javascript.flatMap(row => row.instantiateMs)), wasmtimeCompileMedianMs: median(wasmtime.samples.map(row => row.compileNs / 1e6)),
  wasmtimeInstantiateMedianMs: median(wasmtime.samples.flatMap(row => row.instantiateNs.map(ns => ns / 1e6))) };
await writeFile(join(output, 'setup.json'), JSON.stringify({ format: 'world-v2-build-engine-economy/v1',
  environment: { date: new Date().toISOString(), cpu: os.cpus()[0].model, platform: os.platform(), release: os.release(), node: process.version, zig: command('zig', ['version']).toString().trim(), wasmtime: '48.0.0', python: '3.14.7' },
  method: 'five serial kernel builds with empty independent Zig caches; 21 fresh V8 processes for compilation; 21 Wasmtime engines with default compilation cache disabled; five warmups and 21 fresh instances per module; process/tool startup excluded from engine timings; OS file cache uncontrolled; paired image deltas are complete program comparisons, not isolated kernel-feature costs',
  sources, kernelSha256, kernelBytes: bytes.length, abi, summary, builds, javascript, wasmtime, sizePairs }, null, 2) + '\n');
console.log(JSON.stringify(summary));
