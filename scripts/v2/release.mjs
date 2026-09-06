// Build local runtime assets. This command never tags, merges or publishes.
import assert from 'node:assert/strict';
import { readFile, readdir, lstat, mkdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { bounded } from './bounded.mjs';
import { inspectProcessKernelWasm } from '../../src/process_v2/wasm.mjs';
import { sha256, json, safeName, tarGzip, readTarGzip, sourceIdentity, writeAssets, verifyAssets } from './assets.mjs';

const [kernelArg,nativeArg,rejectionsArg,boundaryArg,boundaryAssetsArg,projectArg,outputArg]=process.argv.slice(2);
if(process.argv.length!==9)throw new Error('expected kernel, native embedding, malformed-State producer, Boundary source, Boundary assets, Wasmtime project, output');
const root=resolve(import.meta.dirname,'../..'),kernelPath=resolve(kernelArg),nativePath=resolve(nativeArg),rejectionsPath=resolve(rejectionsArg),boundary=resolve(boundaryArg),boundaryAssets=resolve(boundaryAssetsArg),project=resolve(projectArg),output=resolve(outputArg);
const packageBytes=await readFile(join(root,'package.json')),pkg=JSON.parse(packageBytes),version=pkg.version;
if(!/^5\.0\.0(?:-dev\.0)?$/.test(version??''))throw new Error('unexpected World release version');
const boundaryOuter=await verifyAssets(boundaryAssets,['boundary-v2-semantic-fixtures.json','boundary-v2-semantic-fixtures.bin','boundary-v2-examples.tar.gz','boundary-v2-release-receipt.json']);
const boundaryReceipt=JSON.parse(boundaryOuter.get('boundary-v2-release-receipt.json'));
assert.equal(boundaryReceipt.format,'boundary-v2-release-receipt/v1');
const boundarySource=await sourceIdentity(boundary);
assert.equal(boundarySource.filesSha256,boundaryReceipt.source.filesSha256,'Boundary assets must match the exact selected source');
const source=await sourceIdentity(root),kernel=await readFile(kernelPath),inspection=inspectProcessKernelWasm(kernel);
const kernelSha256=sha256(kernel);
await mkdir(output,{recursive:true});
// Static admission occurs above. Any indispensable guest execution happens in a
// separate process group with a deadline, including all embedding descendants.
await bounded(process.execPath,[join(root,'scripts/v2/conformance.mjs'),kernelPath,nativePath,rejectionsPath,boundaryAssets,project,output],{cwd:root,timeout:180000});
assert.equal(sha256(await readFile(kernelPath)),kernelSha256,'kernel changed during conformance');
assert.equal((await sourceIdentity(boundary)).filesSha256,boundarySource.filesSha256,'Boundary source changed during conformance');
assert.equal((await sourceIdentity(root)).filesSha256,source.filesSha256,'World source changed during conformance');
const conformanceBytes=await readFile(join(output,'world-v2-conformance.json'));
const conformance=JSON.parse(conformanceBytes),binary=await readFile(join(output,'world-v2-conformance.bin'));
assert.equal(conformance.kernelSha256,kernelSha256);
assert.equal(conformance.binarySha256,sha256(binary));
const compact=(identity)=>({git:identity.git,filesSha256:identity.filesSha256});
const identity={format:'world-runtime-identity/v2',version,abi:2,profile:1,source:compact(source),
  boundary:{version:boundaryReceipt.version,source:compact(boundarySource)},
  kernel:{file:'world-process-kernel-v2.wasm',length:kernel.length,sha256:kernelSha256,memory:inspection.memory}};
const entries=new Map([['package.json',{name:'package.json',bytes:packageBytes}],
  ['world-process-kernel-v2.wasm',{name:'world-process-kernel-v2.wasm',bytes:kernel}],
  ['world-runtime-identity.json',{name:'world-runtime-identity.json',bytes:json(identity)}]]);
async function include(name) {
  safeName(name);
  if(entries.has(name)||name==='SHA256SUMS')return;
  const path=join(root,name),stat=await lstat(path);
  if(stat.isDirectory()) {for(const child of (await readdir(path)).sort())await include(`${name}/${child}`);return;}
  if(!stat.isFile())throw new Error(`nonregular package entry: ${name}`);
  entries.set(name,{name,bytes:await readFile(path),executable:(stat.mode&0o111)!==0});
}
for(const name of pkg.files)await include(name.replace(/\/$/,''));
for(const name of [...Object.values(pkg.exports),...Object.values(pkg.bin)])assert.ok(entries.has(name.replace(/^\.\//,'')),`missing exported entry: ${name}`);
const innerSums=[...entries.values()].sort((a,b)=>a.name<b.name?-1:a.name>b.name?1:0).map(({name,bytes})=>`${sha256(bytes)}  ${name}\n`).join('');
entries.set('SHA256SUMS',{name:'SHA256SUMS',bytes:Buffer.from(innerSums)});
const archive=tarGzip([...entries.values()]);
assert.equal(readTarGzip(archive).length,entries.size);
const assets=[{name:'world-process-kernel-v2.wasm',bytes:kernel},
  {name:'world-v5.0.0-process-runtime.tar.gz',bytes:archive},
  {name:'world-v2-conformance.json',bytes:conformanceBytes},{name:'world-v2-conformance.bin',bytes:binary}];
const receipt={format:'world-v2-release-receipt/v1',version,profile:1,source,
  boundary:{version:boundaryReceipt.version,source:boundarySource,receiptSha256:sha256(boundaryOuter.get('boundary-v2-release-receipt.json'))},
  protected:boundaryReceipt.protected,
  toolchain:{zig:execFileSync('zig',['version'],{encoding:'utf8'}).trim(),node:process.version,wasmtime:conformance.embeddings.wasmtime,python:conformance.embeddings.python},
  kernel:identity.kernel,assets:assets.map(({name,bytes})=>({name,length:bytes.length,sha256:sha256(bytes)}))};
assets.push({name:'world-v5.0.0-release-receipt.json',bytes:json(receipt)});
await writeAssets(output,assets);
console.log(`emitted World ${version}; ${kernel.length} kernel bytes, ${conformance.checks.length} exact record checks`);
