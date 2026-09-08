// Execute authenticated Boundary data in three independent native/ABI embeddings.
// This process is launched with a wall-clock bound by the release emitter.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { admitProcessKernel, encodeInput, decodeOutcome, decodeRequest, encodeResult } from '../../src/process_v2/index.mjs';
import { Reader, body } from '../../src/process_v2/codec.mjs';
import { wasmtimePeer } from '../../test/v2/wasmtime_peer.mjs';
import { sha256, json, readBundle, indexedBundle, verifyAssets } from './assets.mjs';

const [kernelPath,nativePath,rejectionsPath,boundaryAssets,project,outputArg]=process.argv.slice(2);
if(process.argv.length!==8)throw new Error('expected kernel, native embedding, malformed-State producer, Boundary assets, Wasmtime project, and output directory');
const output=resolve(outputArg);
const outer=await verifyAssets(boundaryAssets,['boundary-v2-semantic-fixtures.json','boundary-v2-semantic-fixtures.bin','boundary-v2-examples.tar.gz','boundary-v2-release-receipt.json']);
const boundaryReceipt=JSON.parse(outer.get('boundary-v2-release-receipt.json'));
if(boundaryReceipt.format!=='boundary-v2-release-receipt/v1')throw new Error('unexpected Boundary receipt');
for(const item of boundaryReceipt.assets)assert.equal(sha256(outer.get(item.name)),item.sha256);
const fixtureBytes=outer.get('boundary-v2-semantic-fixtures.json'),manifest=JSON.parse(fixtureBytes);
assert.equal(manifest.format,'boundary-v2-semantic-fixtures/v1');
assert.equal(sha256(outer.get(manifest.binary)),manifest.binarySha256);
const files=readBundle(manifest,outer.get(manifest.binary));
const programs=new Map(manifest.programs.map((program)=>[program.name,files.get(program.image)]));
const kernel=await readFile(kernelPath), kernelSha256=sha256(kernel);
const host=await admitProcessKernel(kernel,{expectedSha256:kernelSha256});
const peer=await wasmtimePeer(project,kernelPath,kernelSha256);
const entries=[],checks=[],completed=[];
let serial=0,current='';
const array=(value)=>value instanceof Uint8Array?[...value]:Array.isArray(value)?value.map(array):value;
async function invoke(mode,input,rejection) {
  const encoded=encodeInput({...input,mode}),number=String(serial++).padStart(5,'0');
  const inputName=`records/${number}.pki2`,outputName=`records/${number}.pko2`;
  entries.push({name:inputName,bytes:encoded});
  const native=spawnSync(nativePath,[],{input:encoded,maxBuffer:64<<20,timeout:30000});
  if(rejection) {
    assert.notEqual(native.status,0);assert.ok(native.stderr.toString().includes(rejection),native.stderr.toString());
    await assert.rejects(host[mode](input),(error)=>error.message===rejection);
    await assert.rejects(peer.invoke(encoded),(error)=>error.message===rejection);
    checks.push({case:current,mode,input:inputName,rejection});return;
  }
  assert.equal(native.status,0,native.stderr.toString());
  const javascript=await host[mode](input),independent=await peer.invoke(encoded);
  assert.deepEqual(javascript.bytes,new Uint8Array(native.stdout));assert.deepEqual(independent,javascript.bytes);
  entries.push({name:outputName,bytes:javascript.bytes});
  checks.push({case:current,mode,input:inputName,output:outputName,kind:javascript.kind});
  // The next State alternates its actual producing implementation.
  const chosen=serial%3===0?new Uint8Array(native.stdout):serial%3===1?independent:javascript.bytes;
  return {...decodeOutcome(chosen),bytes:chosen};
}
async function continueWith(input) {
  const step=await invoke('advance',input);
  return step.kind==='Progressed'?invoke('run',{image:input.image,state:step.state}):step;
}
try {
  for(const item of manifest.negatives) {
    current=`image:${item.name}`;
    await invoke('run',{image:files.get(item.image),initialArgs:new Uint8Array()},item.rejection);
  }
  const ownership=manifest.programs.find((program)=>program.name==='ownership');assert.ok(ownership);
  const produced=spawnSync(rejectionsPath,[],{input:files.get(ownership.image),maxBuffer:16<<20,timeout:30000});
  assert.equal(produced.status,0,produced.stderr.toString());
  const malformed=JSON.parse(produced.stdout);assert.equal(malformed.format,'world-v2-state-rejections/v1');
  const expectedNames=[
    'pending-effect','pending-continuation','state-program-identity','state-root-status',
    'blob-schema','blob-value','one-shot-delimiter','multi-delimiter','local-region-alias',
    'return-path-active','return-path-yielded','return-path-continuation','return-path-normal_exit',
    'return-path-protection','return-path-captured',
    'one-shot-captured-handler-state','multi-captured-handler-state','duplicate-token-custody',
  ];
  assert.deepEqual(malformed.cases.map((item)=>item.name).sort(),expectedNames.sort());
  for(const item of malformed.cases) {
    current=`state:${item.name}`;
    assert.match(item.input_hex,/^(?:[a-f0-9]{2})+$/);
    const encoded=Buffer.from(item.input_hex,'hex'),reader=new Reader(body('ABL_PKI2',encoded));
    assert.equal(reader.natural(),1n);const image=reader.field();assert.equal(reader.natural(),1n);const state=reader.field();
    assert.equal(reader.natural(),0n);assert.equal(reader.natural(),0n);reader.finish();
    assert.deepEqual(Buffer.from(encodeInput({mode:'run',image,state})),encoded);
    await invoke('run',{image,state},item.rejection);
  }
  for(const item of manifest.cases) {
    current=item.name;
    const image=programs.get(item.program);assert.ok(image,`missing image ${item.program}`);
    let step=await invoke('run',{image,initialArgs:files.get(item.initial)}),responses=0,controls=0;
    const trace=[];
    while(!['Completed','Failed','Cancelled'].includes(step.kind)) {
      if(trace.length>10000)throw new Error('conformance harness observation limit');
      const request=step.kind==='Requested'?decodeRequest(step.request):null;
      assert.ok(request||step.kind==='Yielded',`${current}: ${step.kind}`);
      trace.push(request?{kind:'Requested',identity:request.semanticIdentity,payload:[...request.payload]}:{kind:'Yielded'});
      // A detached pending request can be recovered without changing its bytes.
      if(request)assert.deepEqual((await invoke('run',{image,state:step.state})).bytes,step.bytes);
      let abandoned=false;
      while(item.cancellations[controls]?.at===trace.length-1) {
        const control=item.cancellations[controls++],before=step;
        const value=request?files.get(item.responses[responses]):null;
        const obtained=request&&value?encodeResult(before.request,value):null;
        step=await invoke('run',{image,state:before.state,cancel:control.reason});
        if(control.preservesRequest) {
          assert.equal(step.kind,'Requested');
          const old=decodeRequest(before.request),next=decodeRequest(step.request);
          assert.equal(next.semanticIdentity,old.semanticIdentity);
          assert.deepEqual(next.payload,old.payload);assert.deepEqual(next.resumeSchema,old.resumeSchema);
          if(!Buffer.from(before.state).equals(Buffer.from(step.state))&&obtained)await invoke('run',{image,state:step.state,result:obtained},'InvalidResult');
        } else {abandoned=true;break;}
      }
      if(abandoned)continue;
      let result;
      if(step.kind==='Requested') {
        const response=files.get(item.responses[responses++]);assert.ok(response,`${current}: missing typed response`);
        result=encodeResult(step.request,response);
      }
      step=await continueWith({image,state:step.state,result});
    }
    assert.equal(responses,item.responses.length,`${current}: unused responses`);
    assert.equal(controls,item.cancellations.length,`${current}: unused cancellation`);
    assert.deepEqual(trace,item.expected.trace,`${current}: source trace`);
    for(const [key,value] of Object.entries(item.expected))if(key!=='trace')assert.deepEqual(array(step[key]),value,`${current}: ${key}`);
    completed.push({name:item.name,program:item.program,expected:item.expected});
  }
  const bundle=indexedBundle(entries);
  const conformance={format:'world-v2-conformance/v1',profile:1,kernelSha256,
    boundary:{version:boundaryReceipt.version,source:boundaryReceipt.source,fixturesSha256:sha256(fixtureBytes),binarySha256:manifest.binarySha256},
    embeddings:{native:true,javascript:process.version,wasmtime:peer.identity.wasmtime,python:peer.identity.python},
    binary:'world-v2-conformance.bin',binarySha256:sha256(bundle.bytes),cases:completed,checks,files:bundle.files};
  await mkdir(output,{recursive:true});
  await writeFile(join(output,'world-v2-conformance.json'),json(conformance));
  await writeFile(join(output,'world-v2-conformance.bin'),bundle.bytes);
  console.log(`${completed.length} source scripts matched native/JavaScript/Wasmtime at ${checks.length} exact record checks`);
} finally {await peer.close();}
