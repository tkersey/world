import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {field,concat} from '../../src/embedding/wire.mjs';
const [embedding,beforePath,afterPath,emitter,corpus,output]=process.argv.slice(2);assert.equal(process.argv.length,8);
const world=await import(pathToFileURL(embedding)),hash=b=>createHash('sha256').update(b).digest('hex'),limits={input:256<<20,working:256<<20,output:256<<20},kernels={before:readFileSync(beforePath),after:readFileSync(afterPath)};
const fresh=async arm=>{const bytes=kernels[arm],k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});k.setLimits(limits);return k;};
mkdirSync(corpus,{recursive:true});const report={status:'running',kernels:Object.fromEntries(Object.entries(kernels).map(([k,b])=>[k,hash(b)])),rows:[],prefixes:0,capacity:[]};
for(const family of ['unique','alias','captured']){
 const image=execFileSync(emitter,[family]);writeFileSync(`${corpus}/${family}.bpi3`,image);
 for(const length of [0,65532,65533,65536,1048576]){
  const value=field(Buffer.alloc(length,120)),args=family==='alias'?concat(value,value):value,expected=family==='unique'?0n:BigInt(length);writeFileSync(`${corpus}/${family}-${length}.args`,args);
  const row={family,length,encodedBlobBytes:value.length,arms:{}};
  for(const quantum of [0,1,2,3,4,8]){
   const results={};
   for(const arm of ['before','after']){
    const k=await fresh(arm),p=k.prepare(image),s=k.start(p,args),beforeLive=Number(k.usage().workingLive),result=k.drive(s,{quantum:BigInt(quantum),checkpoint:true}),out=world.decodeOutcome(result);
    results[arm]=Buffer.from(result);
    if(quantum===(family==='captured'?2:1))row.arms[arm]={beforeLive,pausedLive:Number(k.usage().workingLive),peak:Number(k.usage().workingPeak),linearMemoryBytes:k.usage().memoryBytes};
    if(out.kind==='progressed'){
     const checkpoint=k.checkpoint(s);assert.deepEqual(Buffer.from(checkpoint),Buffer.from(out.state));
     const resumed=world.decodeOutcome(k.drive(s));assert.equal(resumed.kind,'completed');assert.equal(Buffer.from(resumed.value).readBigUInt64LE(),expected);
     k.close(s);
     const saved=k.restore(p,checkpoint),restored=world.decodeOutcome(k.drive(saved));assert.equal(restored.kind,'completed');assert.equal(Buffer.from(restored.value).readBigUInt64LE(),expected);k.close(saved);
    }else {assert.equal(out.kind,'completed');assert.equal(Buffer.from(out.value).readBigUInt64LE(),expected);k.close(s);}
    k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);
   }
   assert.deepEqual(results.after,results.before);report.prefixes++;
  }
  if(family==='unique'&&value.length>=65536)assert(row.arms.after.pausedLive<row.arms.before.pausedLive-length+8192);
  if(family!=='unique'&&length)assert(row.arms.after.pausedLive>=length);
  report.rows.push(row);writeFileSync(output,JSON.stringify(report,null,2)+'\n');
 }
}
const image=readFileSync(`${corpus}/unique.bpi3`),args=readFileSync(`${corpus}/unique-65536.args`);
for(const arm of ['before','after'])for(const limit of [{arena:'output',extra:1},...[0,64,256,1024].map(extra=>({arena:'working',extra}))]){
 const k=await fresh(arm),p=k.prepare(image),s=k.start(p,args),checkpoint=k.checkpoint(s),live=Number(k.usage().workingLive);k.setLimits({...limits,[limit.arena]:limit.arena==='working'?live+limit.extra:limit.extra});let failed=false;
 try{assert.equal(world.decodeOutcome(k.drive(s,{quantum:1n,checkpoint:true})).kind,'progressed');}catch(error){assert.equal(error.code,'WORLD_CAPACITY');failed=true;}
 k.setLimits(limits);
 if(failed){assert.deepEqual(Buffer.from(k.checkpoint(s)),Buffer.from(checkpoint));assert.equal(world.decodeOutcome(k.drive(s,{quantum:1n,checkpoint:true})).kind,'progressed');}
 const final=world.decodeOutcome(k.drive(s));assert.equal(final.kind,'completed');assert.equal(Buffer.from(final.value).readBigUInt64LE(),0n);k.close(s);k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);report.capacity.push({arm,...limit,failed});
}
assert(report.capacity.some(c=>c.arm==='after'&&c.failed));report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({rows:report.rows.length,prefixes:report.prefixes,capacityCases:report.capacity.length}));
