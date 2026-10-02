import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import * as world from '../../src/embedding/index.mjs';
const [beforeKernel,afterKernel,beforeNative,afterNative,corpus,output]=process.argv.slice(2);
assert.equal(process.argv.length,8);
const hash=b=>createHash('sha256').update(b).digest('hex');
const sampler=fileURLToPath(new URL('./retained_history_wasm.mjs',import.meta.url));
const embedding=fileURLToPath(new URL('../../src/embedding/index.mjs',import.meta.url));
const report={status:'running',neighbors:[],changes:[],plateaus:[]};
for(const mode of ['H','Q'])for(const depth of [7,31,63,65,257]) {
  const image=join(corpus,mode+'.bpi3'),record=join(corpus,`${mode}-${depth}-neighbor.json`);
  const call=(action,kernel)=>JSON.parse(execFileSync(process.execPath,[sampler,action,embedding,kernel,image,mode,String(depth),record],{encoding:'utf8',timeout:120000}));
  const baseline=call('freeze',beforeKernel),candidate=call('memory',afterKernel);
  const complete=call('complete',afterKernel);
  report.neighbors.push({mode,depth,baseline,candidate,complete});
}
for(const quantum of [0,1,4,8]) {
  const arms={};
  for(const [name,executable]of Object.entries({before:beforeNative,after:afterNative}))arms[name]=JSON.parse(execFileSync(executable,[join(corpus,'H.bpi3'),'1024','C',String(quantum)],{encoding:'utf8'}));
  assert.equal(arms.after.removedFrames,arms.before.removedFrames);
  assert.equal(arms.after.savedEntries,arms.after.removedFrames);
  assert.equal(arms.after.commitEntries,arms.after.removedFrames);
  report.changes.push({quantum,...arms});
}
// Unchanged parked execution is retained across 1024 failed public commands.
const frozen=JSON.parse(readFileSync(join(corpus,'Q-1024.json'))),image=readFileSync(join(corpus,'Q.bpi3'));
for(const [name,path]of Object.entries({before:beforeKernel,after:afterKernel})) {
  const bytes=readFileSync(path),k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});
  k.setLimits(frozen.limits);
  let peak=0;
  const observed=operation=>{try{return operation();}finally{peak=Math.max(peak,Number(k.usage().workingPeak));}};
  const p=observed(()=>k.prepare(image)),args=Buffer.alloc(16);args.writeBigUInt64LE(1024n);args.writeBigUInt64LE(17n,8);
  const s=observed(()=>k.start(p,args));observed(()=>k.drive(s));
  const original=observed(()=>k.checkpoint(s)),initialLive=Number(k.usage().workingLive);
  const wrong=Buffer.from(frozen.replies[1],'hex');let plateau,reservation;
  for(let i=0;i<1024;i++) {
    assert.throws(()=>observed(()=>k.drive(s,{control:'reply',value:wrong})),e=>e.details?.diagnostic==='InvalidResult');
    if(i===16){plateau=Number(k.usage().workingLive);reservation=k.usage().memoryBytes;}
    if(i>16){assert.equal(Number(k.usage().workingLive),plateau);assert.equal(k.usage().memoryBytes,reservation);}
  }
  assert.deepEqual(Buffer.from(observed(()=>k.checkpoint(s))),Buffer.from(original));
  const completed=observed(()=>k.drive(s,{control:'cancel_text',value:'plateau complete'}));assert.equal(world.decodeOutcome(completed).kind,'cancelled');
  observed(()=>k.close(s));observed(()=>k.releasePrepared(p));assert.equal(k.usage().workingLive,0n);
  report.plateaus.push({name,commands:1024,initialLive,plateau,reservation,peak});
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({neighbors:report.neighbors.length,changedSets:report.changes.length,plateaus:report.plateaus}));
