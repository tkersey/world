import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const [embedding,oldPath,newPath,emitter,native,corpus,output]=process.argv.slice(2);
assert.equal(process.argv.length,9);
mkdirSync(corpus,{recursive:true});
const world=await import(pathToFileURL(embedding)),hash=b=>createHash('sha256').update(b).digest('hex');
const kernels={before:readFileSync(oldPath),after:readFileSync(newPath)};
const fresh=async arm=>{const bytes=kernels[arm],k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;};
const report={status:'running',kernelHashes:Object.fromEntries(Object.entries(kernels).map(([k,v])=>[k,hash(v)])),nativeSha256:hash(readFileSync(native)),rows:[],requests:0};
const args=Buffer.alloc(16);args.writeBigUInt64LE(0x123456789abcdef0n);args.writeBigUInt64LE(0xfedcba9876543210n,8);
for(const operations of [0,2,4,16,256,1024]){
 const image=execFileSync(emitter,[String(operations)]);writeFileSync(`${corpus}/${operations}.bpi3`,image);
 const expected=0x123456789abcdef0n^(operations%2?0xfedcba9876543210n:0n),row={operations,imageSha256:hash(image),arms:{}};
 const ks={before:await fresh('before'),after:await fresh('after')};
 const invoke=request=>{const left=ks.before.invoke(request),right=ks.after.invoke(request);assert.deepEqual(Buffer.from(right),Buffer.from(left));report.requests++;return world.decodeOutcome(right);};
 const cuts=operations<=16?Array.from({length:operations+3},(_,i)=>i):[0,1,2,3,7,8,9,254,255,256,257,operations,operations+1];
 for(const cut of cuts){
  const request=world.encodeInput({image,initialArgs:args,quantum:BigInt(cut)}),out=invoke(request),path=`${corpus}/${operations}-${cut}.pki3`;writeFileSync(path,request);
  assert.deepEqual(execFileSync(native,[path],{timeout:60000}),Buffer.from(ks.after.invoke(request)));
  if(out.kind==='completed')assert.equal(Buffer.from(out.value).readBigUInt64LE(),expected);
  else{
   assert.equal(out.kind,'progressed');
   const resumed=invoke(world.encodeInput({image,state:out.state}));assert.equal(resumed.kind,'completed');assert.equal(Buffer.from(resumed.value).readBigUInt64LE(),expected);
   const cancelled=invoke(world.encodeInput({image,state:out.state,control:'cancel_text',value:'p25 cut'}));assert.equal(cancelled.kind,'cancelled');
  }
 }
 for(const arm of ['before','after']){
  const admission=await fresh(arm),p=admission.prepare(image),admitted={peak:Number(admission.usage().workingPeak),retained:Number(admission.usage().workingLive)};admission.releasePrepared(p);assert.equal(admission.usage().workingLive,0n);
  const execution=await fresh(arm),request=world.encodeInput({image,initialArgs:args}),out=world.decodeOutcome(execution.invoke(request));assert.equal(out.kind,'completed');assert.equal(Buffer.from(out.value).readBigUInt64LE(),expected);assert.equal(execution.usage().workingLive,0n);writeFileSync(`${corpus}/${operations}-fresh.pki3`,request);
  const cycle=await fresh(arm);let input={image,initialArgs:args,quantum:1n},checkpointMax=0,steps=0;
  while(true){const outcome=world.decodeOutcome(cycle.invoke(world.encodeInput(input)));assert(++steps<operations+10);if(outcome.kind==='completed'){assert.equal(Buffer.from(outcome.value).readBigUInt64LE(),expected);break;}assert.equal(outcome.kind,'progressed');checkpointMax=Math.max(checkpointMax,outcome.state.length);input={image,state:outcome.state,quantum:1n};}
  assert.equal(cycle.usage().workingLive,0n);
  row.arms[arm]={admission:admitted,freshPeak:Number(execution.usage().workingPeak),cyclePeak:Number(cycle.usage().workingPeak),checkpointMax,steps};
 }
 assert.deepEqual(row.arms.after,row.arms.before);
 report.rows.push(row);writeFileSync(output,JSON.stringify(report,null,2)+'\n');
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({rows:report.rows.length,requests:report.requests,memory:'exact equality'}));
