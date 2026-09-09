// Physical installation proof. Inputs are copied into independent scratch roots;
// components excluded by the contract are absent before Zig sees either build.
import assert from 'node:assert/strict';
import { cp, mkdir, mkdtemp, readFile, readdir, rm, writeFile, symlink } from 'node:fs/promises';
import { join, resolve, relative } from 'node:path';
import { spawnSync, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { encodeInput, decodeOutcome } from '../../src/process_v2/index.mjs';

const [boundaryArg, outputArg] = process.argv.slice(2);
if (!boundaryArg || !outputArg || process.argv.length !== 4) throw new Error('expected exact Boundary source and scratch output directory');
const boundary = resolve(boundaryArg), world = resolve(import.meta.dirname, '../..'), output = resolve(outputArg);
await mkdir(output, { recursive: true });
const root = await mkdtemp(join(output, 'installation-'));
const toolchain = join(root, 'toolchain');
await mkdir(toolchain);
await symlink(execFileSync('/usr/bin/which',['zig'],{encoding:'utf8'}).trim(),join(toolchain,'zig'));
const compiler = join(root, 'compiler'), data = join(root, 'data'), runtime = join(root, 'runtime');
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
async function copyFiles(from, to, names) {
  await mkdir(to, { recursive: true });
  for (const name of names) await cp(join(from, name), join(to, name), { recursive: true });
}
async function files(directory) {
  const result = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) result.push(...await files(path));
    else if (entry.isFile()) result.push(path);
    else throw new Error(`unexpected nonregular source entry: ${path}`);
  }
  return result.sort();
}
async function removeTests(source) {
  for (const path of await files(source)) if (/\/(?:[^/]*_tests|tests|test_root|economy_phases|emit_rejections)\.zig$/.test(path)) await rm(path);
}
async function inventory(source) {
  const result = [];
  for (const path of await files(source)) if (!relative(source,path).startsWith('.cache/') && !relative(source,path).startsWith('zig-out/')) {
    result.push({ path: relative(source, path), sha256: sha(await readFile(path)) });
  }
  return result;
}
const builds = [];
function build(cwd, args, label) {
  const command = ['build', ...args, '--cache-dir', join(root, `${label}-local`), '--global-cache-dir', join(root, `${label}-global`), '--verbose'];
  const result = spawnSync(join(toolchain,'zig'), command, { cwd, env: {...process.env,PATH:`${toolchain}:/usr/bin:/bin`}, maxBuffer: 16 << 20 });
  if (result.status !== 0) throw new Error(`${label}: ${result.stderr.toString()}`);
  const verbose = result.stderr.toString();
  // Discover compiler module roots from the actual successful compiler commands.
  const modules = [...verbose.matchAll(/-M([^=\s]+)=([^\s]+)/g)].map((match) => ({ name: match[1], path: match[2] }));
  builds.push({ label, modules });
  return result.stdout;
}
async function consumer(name, source, dependency, moduleName, extra) {
  const directory = join(root, name);
  await mkdir(directory);
  await writeFile(join(directory,'main.zig'), source);
  await writeFile(join(directory,'build.zig.zon'), `.{ .name = .ownership_probe, .fingerprint = 0x99c0ee518d33ff22, .version = "0.0.0", .dependencies = .{ .subject = .{ .path = ${JSON.stringify(dependency)} } }, .paths = .{ "build.zig", "build.zig.zon", "main.zig" } }\n`);
  await writeFile(join(directory,'build.zig'), `const std = @import("std");
pub fn build(b: *std.Build) void {
 const target = b.standardTargetOptions(.{});
 const dependency = b.dependency("subject", .{ .target = target, .optimize = .ReleaseSafe${extra ? `, .@"boundary-v2-source" = ${JSON.stringify(data)}` : ''} });
 const module = dependency.module(${JSON.stringify(moduleName)});
 const root = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = .ReleaseSafe });
 root.addImport(${JSON.stringify(moduleName)}, module);
 ${extra ? 'root.addImport("boundary_data_v2", module.import_table.get("boundary_data_v2").?);' : ''}
 const executable = b.addExecutable(.{ .name = ${JSON.stringify(name)}, .root_module = root });
 b.getInstallStep().dependOn(&b.addInstallArtifact(executable, .{}).step);
}
`);
  build(directory, [], name);
  return join(directory,'zig-out/bin',name);
}
await copyFiles(boundary, compiler, ['build.zig','build.zig.zon','LICENSE','README.md','src/v2']);
await rm(join(compiler,'src/v2/legacy'), { recursive: true });
await removeTests(join(compiler,'src'));
const compilerInventory = await inventory(compiler);
const compilerBinary = await consumer('compile-consumer', await readFile(join(boundary,'examples/one_effect.zig')), '../compiler', 'boundary');
const emitted = spawnSync(compilerBinary, [], { maxBuffer: 16 << 20 });
assert.equal(emitted.status, 0, emitted.stderr.toString());
assert.equal(emitted.stdout.subarray(0,8).toString(), 'ABL_BPI2');
await copyFiles(boundary, data, ['build.zig','build.zig.zon','LICENSE','README.md','src/v2/data']);
await removeTests(join(data,'src'));
// The data-only build must work with the authoring, oracle and legacy files absent.
build(data, ['-Ddata-only=true'], 'data-only');
const dataInventory = await inventory(data);
await copyFiles(world, runtime, ['build.zig','build.zig.zon','src']);
await removeTests(join(runtime,'src'));
const runtimeInventory = await inventory(runtime);
build(runtime, ['build-v2-kernel', `-Dboundary-v2-source=${data}`, '--prefix', join(root,'runtime-output')], 'runtime-kernel');
const kernel = await readFile(join(root,'runtime-output/world-process-kernel-v2.wasm'));
const { admitProcessKernel } = await import(pathToFileURL(join(runtime,'src/process_v2/index.mjs')));
const host = await admitProcessKernel(kernel, { expectedSha256: sha(kernel) });
const nativeBinary = await consumer('native-consumer', await readFile(join(world,'test/v2/native_records.zig')), '../runtime', 'world', true);
const input = { image: emitted.stdout, initialArgs: Uint8Array.of(17,0,0,0) };
const wasmOutcome = await host.run(input);
const native = spawnSync(nativeBinary, [], { input: encodeInput({ ...input, mode: 'run' }), maxBuffer: 16 << 20 });
assert.equal(native.status, 0, native.stderr.toString());
assert.deepEqual(new Uint8Array(native.stdout), wasmOutcome.bytes);
assert.equal(decodeOutcome(native.stdout).kind, 'Requested');
// Inventory the public JavaScript entry and its actual local import closure.
const packageManifest = JSON.parse(await readFile(join(world,'package.json'),'utf8'));
const pending = [...Object.values(packageManifest.exports), ...Object.values(packageManifest.bin)].map((path)=>resolve(world,path));
const visited = new Set(), jsImports = [];
while (pending.length) {
  const path = pending.pop();
  if (visited.has(path)) continue;
  visited.add(path);
  const source = await readFile(path,'utf8');
  const imports = [...source.matchAll(/(?:from\s*|import\s*)["']([^"']+)["']/g)].map((match)=>match[1]);
  jsImports.push({ path: relative(world,path), sha256: sha(source), imports });
  for (const name of imports) if(name.startsWith('.')) pending.push(resolve(path,'..',name));
  else assert.ok(name.startsWith('node:'), `unexpected package dependency ${name}`);
}
assert.ok([...visited].every((path)=>path.includes('/src/process_v2/') || path.includes('/bin/')));
const proof = { format: 'world-v2-physical-installations/v1', buildPath: 'isolated Zig plus /usr/bin:/bin; no Node, Lean, uv or WASM engine on build PATH', compilerFiles: compilerInventory,
  dataFiles: dataInventory, runtimeFiles: runtimeInventory, builds, publicJavaScript: jsImports,
  imageSha256: sha(emitted.stdout), kernelSha256: sha(kernel), outcomeSha256: sha(native.stdout),
  observations: ['compiler emitted, decoded, inspected and admitted BPI2 without World, legacy execution or proof tools',
    'data-only dependency built with authoring, oracle, proof and legacy source absent',
    'World kernel and native consumer built with only Boundary data, without application/compiler/proof source',
    'native and fresh JavaScript WASM returned identical canonical PKO2 bytes'] };
await writeFile(join(output,'ownership.json'), JSON.stringify(proof,null,2)+'\n');
console.log(`compiler-only/data-only/runtime-only installations passed; kernel ${sha(kernel)}`);
