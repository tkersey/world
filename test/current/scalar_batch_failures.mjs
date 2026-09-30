import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const [embedding,beforePath,afterPath,emitter,output]=process.argv.slice(2);assert.equal(process.argv.length,7);
const world=await import(pathToFileURL(embedding)),hash=b=>createHash('sha256').update(b).digest('hex'),limits={input:256<<20,working:256<<20,output:256<<20};
const kernels={before:readFileSync(beforePath),after:readFileSync(afterPath)},report={status:'running',kernelHashes:Object.fromEntries(Object.entries(kernels).map(([k,b])=>[k,hash(b)])),arms:{}};
const fresh=async arm=>{const bytes=kernels[arm],k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});k.setLimits(limits);return k;};
const image=execFileSync(emitter,['4']),failingImage=execFileSync(emitter,['4','failure']),args=Buffer.alloc(16);args.fill(0xff,0,8);
const checked={before:await fresh('before'),after:await fresh('after')};
let failureCuts=0;
for(let quantum=0;quantum<9;quantum++){
 const request=world.encodeInput({image:failingImage,initialArgs:args,quantum:BigInt(quantum)}),left=checked.before.invoke(request),right=checked.after.invoke(request);assert.deepEqual(Buffer.from(right),Buffer.from(left));
 const out=world.decodeOutcome(right);
 if(out.kind==='progressed'){const resume=world.encodeInput({image:failingImage,state:out.state}),l=checked.before.invoke(resume),r=checked.after.invoke(resume);assert.deepEqual(Buffer.from(r),Buffer.from(l));assert.equal(world.decodeOutcome(r).kind,'failed');}else assert.equal(out.kind,'failed');
 failureCuts++;
}
for(const arm of ['before','after']){
 const outcomes=[];
 for(const limit of [{arena:'output',extra:1},...[0,16,64,256,1024,4096,16384].map(extra=>({arena:'working',extra}))]){
  const k=await fresh(arm),p=k.prepare(image),s=k.start(p,args),checkpoint=k.checkpoint(s),live=Number(k.usage().workingLive);
  k.setLimits({...limits,[limit.arena]:limit.arena==='working'?live+limit.extra:limit.extra});
  let failed=false;
  try{const out=world.decodeOutcome(k.drive(s));assert.equal(out.kind,'completed');assert.equal(Buffer.from(out.value).readBigUInt64LE(),0xffffffffffffffffn);}
  catch(error){assert.equal(error.code,'WORLD_CAPACITY');assert.equal(error.details.arena,limit.arena);failed=true;}
  k.setLimits(limits);
  if(failed){assert.deepEqual(Buffer.from(k.checkpoint(s)),Buffer.from(checkpoint));const out=world.decodeOutcome(k.drive(s));assert.equal(out.kind,'completed');assert.equal(Buffer.from(out.value).readBigUInt64LE(),0xffffffffffffffffn);}
  k.close(s);k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);outcomes.push({...limit,failed});
 }
 assert(outcomes.some(x=>x.arena==='working'&&x.failed));assert(outcomes.some(x=>x.arena==='output'&&x.failed));
 report.arms[arm]=outcomes;
}
assert.deepEqual(report.arms.after,report.arms.before);
report.failureCuts=failureCuts;report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({failureCuts,capacityCases:16,failed:report.arms.after.filter(x=>x.failed).length*2}));
