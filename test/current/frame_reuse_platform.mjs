import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const [embedding,beforePath,afterPath,emitter,corpus,output]=process.argv.slice(2);assert.equal(process.argv.length,8);
const world=await import(pathToFileURL(embedding)),hash=b=>createHash('sha256').update(b).digest('hex'),kernels={before:readFileSync(beforePath),after:readFileSync(afterPath)};
const fresh=async arm=>{const bytes=kernels[arm],k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;};
mkdirSync(corpus,{recursive:true});
const report={status:'running',kernelHashes:Object.fromEntries(Object.entries(kernels).map(([k,b])=>[k,hash(b)])),nativeStackScratch:JSON.parse(execFileSync(emitter,['sizes'],{encoding:'utf8'})),requests:0,rows:[]};
for(const family of ['compatible','fallback']){
 const image=execFileSync(emitter,[family]);writeFileSync(`${corpus}/${family}.bpi3`,image);
 for(const n of [0,1,8,128,512]){
  const args=Buffer.alloc(8);args.writeBigUInt64LE(BigInt(n));const request=world.encodeInput({image,initialArgs:args});writeFileSync(`${corpus}/${family}-${n}.pki3`,request);
  const row={family,n,imageSha256:hash(image),arms:{}};
  const ks={before:await fresh('before'),after:await fresh('after')},terminal={};
  for(const arm of ['before','after']){
   const k=ks[arm],p=k.prepare(image),admission={peak:Number(k.usage().workingPeak),retained:Number(k.usage().workingLive)};k.releasePrepared(p);
   terminal[arm]=Buffer.from(k.invoke(request));const out=world.decodeOutcome(terminal[arm]);assert.equal(out.kind,'completed');assert.equal(Buffer.from(out.value).readBigUInt64LE(),0n);
   row.arms[arm]={admission,freshPeak:Number(k.usage().workingPeak)};assert.equal(k.usage().workingLive,0n);
  }
  assert.deepEqual(terminal.after,terminal.before);
  const cycles={before:await fresh('before'),after:await fresh('after')};let input={image,initialArgs:args,quantum:1n},steps=0,checkpointMax=0;
  while(true){
   const encoded=world.encodeInput(input),left=cycles.before.invoke(encoded),right=cycles.after.invoke(encoded);assert.deepEqual(Buffer.from(right),Buffer.from(left));report.requests++;assert(++steps<n*8+16);
   const out=world.decodeOutcome(right);if(out.kind==='completed'){assert.deepEqual(Buffer.from(right),terminal.after);break;}
   assert.equal(out.kind,'progressed');checkpointMax=Math.max(checkpointMax,out.state.length);input={image,state:out.state,quantum:1n};
   if(n===8&&steps%5===0){const cancel=world.encodeInput({image,state:out.state,control:'cancel_text',value:'frame cut'}),l=cycles.before.invoke(cancel),r=cycles.after.invoke(cancel);assert.deepEqual(Buffer.from(r),Buffer.from(l));assert.equal(world.decodeOutcome(r).kind,'cancelled');}
  }
  for(const arm of ['before','after']){assert.equal(cycles[arm].usage().workingLive,0n);Object.assign(row.arms[arm],{cyclePeak:Number(cycles[arm].usage().workingPeak),steps,checkpointMax});}
  report.rows.push(row);writeFileSync(output,JSON.stringify(report,null,2)+'\n');
 }
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({rows:report.rows.length,requests:report.requests,stack:report.nativeStackScratch}));
