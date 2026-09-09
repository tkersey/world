// Trusted outer verifier: check inventories, source identities and byte digests
// before extracting files or executing any code from a selected package.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir, mkdtemp } from 'node:fs/promises';
import { dirname,join,resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { sha256,json,readTarGzip,readBundle,verifyAssets,safeName,readSource,verifyExampleSources,verifyRuntimeSources } from './assets.mjs';
import { inspectProcessKernelWasm } from '../../src/process_v2/wasm.mjs';
import { bounded } from './bounded.mjs';
const [boundaryArg,worldArg,boundarySourceArg,outputArg,expectedBoundaryCommit,expectedWorldCommit]=process.argv.slice(2);
if(![6,8].includes(process.argv.length))throw new Error('expected Boundary assets, World assets, Boundary source, scratch output, and optional exact public commits');
const ownRoot=resolve(import.meta.dirname,'../..'),boundaryAssets=resolve(boundaryArg),worldAssets=resolve(worldArg),boundarySource=resolve(boundarySourceArg),output=resolve(outputArg);
const b=await verifyAssets(boundaryAssets,['boundary-v2-semantic-fixtures.json','boundary-v2-semantic-fixtures.bin','boundary-v2-examples.tar.gz','boundary-v2-release-receipt.json']);
const w=await verifyAssets(worldAssets,['world-process-kernel-v2.wasm','world-v5.0.0-process-runtime.tar.gz','world-v2-conformance.json','world-v2-conformance.bin','world-v5.0.0-release-receipt.json']);
const br=JSON.parse(b.get('boundary-v2-release-receipt.json')),wr=JSON.parse(w.get('world-v5.0.0-release-receipt.json'));
assert.equal(br.format,'boundary-v2-release-receipt/v1');assert.equal(wr.format,'world-v2-release-receipt/v1');
for(const [receipt,assets] of [[br,b],[wr,w]])for(const row of receipt.assets){assert.equal(assets.get(row.name).length,row.length);assert.equal(sha256(assets.get(row.name)),row.sha256);}
assert.equal(wr.boundary.receiptSha256,sha256(b.get('boundary-v2-release-receipt.json')));
assert.equal(wr.boundary.source.filesSha256,br.source.filesSha256);
assert.deepEqual(wr.protected,br.protected);
if(expectedBoundaryCommit){assert.equal(br.source.git.dirty,false);assert.equal(br.source.git.head,expectedBoundaryCommit);assert.equal(wr.source.git.dirty,false);assert.equal(wr.source.git.head,expectedWorldCommit);}
const compilerFiles=await readSource(boundarySource,br.source,expectedBoundaryCommit);
const worldSourceFiles=await readSource(ownRoot,wr.source,expectedWorldCommit);
const runtimeEntries=readTarGzip(w.get('world-v5.0.0-process-runtime.tar.gz')),runtimeMap=new Map(runtimeEntries.map((entry)=>[entry.name,entry.bytes]));
verifyRuntimeSources(runtimeEntries,worldSourceFiles);
const identity=JSON.parse(runtimeMap.get('world-runtime-identity.json')),pkg=JSON.parse(runtimeMap.get('package.json'));
assert.equal(identity.format,'world-runtime-identity/v2');assert.equal(identity.version,wr.version);assert.equal(pkg.version,wr.version);
assert.equal(identity.kernel.sha256,sha256(w.get('world-process-kernel-v2.wasm')));
assert.deepEqual(runtimeMap.get('world-process-kernel-v2.wasm'),w.get('world-process-kernel-v2.wasm'));
assert.deepEqual(identity.source.git,wr.source.git);assert.equal(identity.source.filesSha256,wr.source.filesSha256);
const inspection=inspectProcessKernelWasm(w.get('world-process-kernel-v2.wasm'));assert.deepEqual(identity.kernel.memory,inspection.memory);
const sums=new Map();
for(const line of runtimeMap.get('SHA256SUMS').toString().trimEnd().split('\n')){const match=/^([a-f0-9]{64})  (.+)$/.exec(line);assert.ok(match);safeName(match[2]);assert.ok(!sums.has(match[2]));sums.set(match[2],match[1]);}
assert.equal(sums.size,runtimeMap.size-1);
for(const [name,bytes] of runtimeMap)if(name!=='SHA256SUMS')assert.equal(sha256(bytes),sums.get(name));
const examples=readTarGzip(b.get('boundary-v2-examples.tar.gz'));
verifyExampleSources(examples,compilerFiles);
const bm=JSON.parse(b.get('boundary-v2-semantic-fixtures.json')),bf=readBundle(bm,b.get('boundary-v2-semantic-fixtures.bin'));
assert.equal(bm.binarySha256,sha256(b.get('boundary-v2-semantic-fixtures.bin')));
const wm=JSON.parse(w.get('world-v2-conformance.json'));assert.equal(wm.kernelSha256,identity.kernel.sha256);assert.equal(wm.boundary.fixturesSha256,sha256(b.get('boundary-v2-semantic-fixtures.json')));
assert.equal(wm.binarySha256,sha256(w.get('world-v2-conformance.bin')));const wf=readBundle(wm,w.get('world-v2-conformance.bin'));
await mkdir(output,{recursive:true});const scratch=await mkdtemp(join(output,'packages-')),runtime=join(scratch,'runtime'),exampleRoot=join(scratch,'examples');
async function extract(entries,directory){for(const entry of entries){const path=join(directory,safeName(entry.name));await mkdir(dirname(path),{recursive:true});await writeFile(path,entry.bytes,{flag:'wx',mode:entry.executable?0o755:0o644});}}
await extract(runtimeEntries,runtime);await extract(examples,exampleRoot);
// Populate the compiler from receipt-bound regular source bytes, before executing
// its build script. The receipt is bound to the expected public commit above.
await extract(compilerFiles,join(scratch,'boundary'));
const compiler=spawnSync('zig',['build','emit','-Dexample=14','--cache-dir',join(scratch,'zig-local'),'--global-cache-dir',join(scratch,'zig-global')],{cwd:exampleRoot,maxBuffer:16<<20,timeout:180000});
assert.equal(compiler.status,0,compiler.stderr.toString());
assert.deepEqual(compiler.stdout,bf.get(bm.programs.find((program)=>program.name==='queens-dfs').image));
const first=bm.cases[0],program=bm.programs.find((program)=>program.name===first.program);
await writeFile(join(scratch,'image.bpi2'),bf.get(program.image));await writeFile(join(scratch,'initial.bin'),bf.get(first.initial));
const cli=spawnSync(process.execPath,[join(runtime,'bin/world.mjs'),'process','run','--image',join(scratch,'image.bpi2'),'--initial',join(scratch,'initial.bin'),'--output',join(scratch,'outcome.pko2')],{cwd:runtime,timeout:30000,maxBuffer:16<<20});
assert.equal(cli.status,0,cli.stderr.toString());assert.deepEqual(await readFile(join(scratch,'outcome.pko2')),wf.get(wm.checks.find((check)=>check.case===first.name).output));
await bounded(process.execPath,[join(ownRoot,'scripts/v2/replay.mjs'),runtime,worldAssets,join(ownRoot,'test/v2/wasmtime'),identity.kernel.sha256],{cwd:ownRoot,timeout:180000});
// Run the fresh consumer from verified source in a fresh process. The selected
// runtime package supplies the JavaScript embedding; no native World build is needed.
const verifiedWorld=join(scratch,'world-source'),externalOutput=join(scratch,'external-result');
await extract(worldSourceFiles,verifiedWorld);
await bounded(process.execPath,[join(verifiedWorld,'test/v2/external.mjs'),join(scratch,'boundary'),join(runtime,'world-process-kernel-v2.wasm'),'-',externalOutput,runtime],{cwd:verifiedWorld,timeout:180000});
const external=JSON.parse(await readFile(join(externalOutput,'external.json')));
assert.equal(external.kernelSha256,identity.kernel.sha256);
await writeFile(join(output,'packages.json'),json({format:'world-v2-package-check/v1',boundary:br.source.git,world:wr.source.git,publicCommitsChecked:!!expectedBoundaryCommit,kernelSha256:identity.kernel.sha256,checks:wm.checks.length,externalConsumer:{name:external.consumer,checks:external.records.length,imageSha256:external.imageSha256,embeddings:external.embeddings},compilerExample:'queens-dfs',compilerImageSha256:sha256(compiler.stdout),runtimeEntries:runtimeEntries.map(({name,bytes})=>({name,sha256:sha256(bytes)}))}));
console.log('compiler example, bundled CLI, verified archives and runtime-only replay passed');
