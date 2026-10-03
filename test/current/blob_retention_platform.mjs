import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {field,concat} from '../../src/embedding/wire.mjs';
const [embedding,beforePath,afterPath,emitter,corpus,output,selection]=process.argv.slice(2);assert([8,9].includes(process.argv.length));
const world=await import(pathToFileURL(embedding)),hash=b=>createHash('sha256').update(b).digest('hex'),limits={input:256<<20,working:256<<20,output:256<<20},kernels={before:readFileSync(beforePath),after:readFileSync(afterPath)};
const fresh=async arm=>{const bytes=kernels[arm],k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});k.setLimits(limits);return k;};
mkdirSync(corpus,{recursive:true});const report={status:'running',kernels:Object.fromEntries(Object.entries(kernels).map(([k,b])=>[k,hash(b)])),rows:[],prefixes:0,capacity:[]};
for(const family of selection?[selection]:['unique','alias','captured','retained']){
 const image=execFileSync(emitter,[family]);writeFileSync(`${corpus}/${family}.bpi3`,image);
 for(const length of [0,65532,65533,65534,65536,1048576]){
  const value=field(Buffer.alloc(length,120)),args=family==='alias'?concat(value,value):value,expected=['unique','retained'].includes(family)?0n:BigInt(length);writeFileSync(`${corpus}/${family}-${length}.args`,args);
  const row={family,length,encodedBlobBytes:value.length,arms:{before:{lifecyclePeak:0},after:{lifecyclePeak:0}}};
  for(const quantum of family==='retained'?[0,1,2,3,4,5,6,7,8]:[0,1,2,3,4,8]){
   const results={};
   for(const arm of ['before','after']){
    const k=await fresh(arm);
    const observed=operation=>{try{return operation();}finally{row.arms[arm].lifecyclePeak=Math.max(row.arms[arm].lifecyclePeak,Number(k.usage().workingPeak));}};
    const p=observed(()=>k.prepare(image)),s=observed(()=>k.start(p,args)),beforeLive=Number(k.usage().workingLive),result=observed(()=>k.drive(s,{quantum:BigInt(quantum),checkpoint:true})),out=world.decodeOutcome(result);
    results[arm]=Buffer.from(result);
    if(quantum===(['captured','retained'].includes(family)?2:1))Object.assign(row.arms[arm],{beforeLive,pausedLive:Number(k.usage().workingLive),peak:Number(k.usage().workingPeak),linearMemoryBytes:k.usage().memoryBytes});
    if(family==='retained'&&(quantum===5||quantum===7)){
     assert.equal(out.kind,'progressed');
     row.arms[arm][quantum===5?'afterFirstBranchLive':'afterLastReadLive']=Number(k.usage().workingLive);
    }
    if(out.kind==='progressed'){
     const checkpoint=observed(()=>k.checkpoint(s));assert.deepEqual(Buffer.from(checkpoint),Buffer.from(out.state));
     const resumed=world.decodeOutcome(observed(()=>k.drive(s)));assert.equal(resumed.kind,'completed');assert.equal(Buffer.from(resumed.value).readBigUInt64LE(),expected);
     observed(()=>k.close(s));
     const saved=observed(()=>k.restore(p,checkpoint)),restored=world.decodeOutcome(observed(()=>k.drive(saved)));assert.equal(restored.kind,'completed');assert.equal(Buffer.from(restored.value).readBigUInt64LE(),expected);observed(()=>k.close(saved));
    }else {assert.equal(out.kind,'completed');assert.equal(Buffer.from(out.value).readBigUInt64LE(),expected);observed(()=>k.close(s));}
    observed(()=>k.releasePrepared(p));assert.equal(k.usage().workingLive,0n);
   }
   assert.deepEqual(results.after,results.before);report.prefixes++;
  }
  // W0 already reclaims dead large backing. Check the absolute pause contract
  // independently in both arms, rather than demanding the historic win again.
  for(const arm of Object.values(row.arms)){
   if(family==='unique'&&value.length>=65536){assert(arm.pausedLive<8192);assert(arm.pausedLive<arm.beforeLive-length+8192);}
   if(family!=='unique'&&length)assert(arm.pausedLive>=length);
   if(family==='retained'){
    assert(arm.afterFirstBranchLive>=length);
    if(value.length>=65536)assert(arm.afterLastReadLive<8192);
   }
  }
  report.rows.push(row);writeFileSync(output,JSON.stringify(report,null,2)+'\n');
 }
}
if(!selection||selection==='unique'){
const image=readFileSync(`${corpus}/unique.bpi3`),args=readFileSync(`${corpus}/unique-65536.args`);
for(const arm of ['before','after'])for(const limit of [{arena:'output',extra:1},...[0,64,256,1024].map(extra=>({arena:'working',extra}))]){
 const k=await fresh(arm),p=k.prepare(image),s=k.start(p,args),checkpoint=k.checkpoint(s),live=Number(k.usage().workingLive);k.setLimits({...limits,[limit.arena]:limit.arena==='working'?live+limit.extra:limit.extra});let failed=false;
 try{assert.equal(world.decodeOutcome(k.drive(s,{quantum:1n,checkpoint:true})).kind,'progressed');}catch(error){assert.equal(error.code,'WORLD_CAPACITY');failed=true;}
 k.setLimits(limits);
 if(failed){assert.deepEqual(Buffer.from(k.checkpoint(s)),Buffer.from(checkpoint));assert.equal(world.decodeOutcome(k.drive(s,{quantum:1n,checkpoint:true})).kind,'progressed');}
 const final=world.decodeOutcome(k.drive(s));assert.equal(final.kind,'completed');assert.equal(Buffer.from(final.value).readBigUInt64LE(),0n);k.close(s);k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);report.capacity.push({arm,...limit,failed});
}
assert(report.capacity.some(c=>c.arm==='after'&&c.failed));}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({rows:report.rows.length,prefixes:report.prefixes,capacityCases:report.capacity.length}));
