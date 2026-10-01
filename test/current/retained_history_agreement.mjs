import assert from "node:assert/strict";
import {readFileSync,writeFileSync} from "node:fs";
import {createHash} from "node:crypto";
import {pathToFileURL} from "node:url";
const [embedding,before,after,corpus,output]=process.argv.slice(2);
const world=await import(pathToFileURL(embedding));
const hash=b=>createHash("sha256").update(b).digest("hex");
const integer=n=>{const b=Buffer.alloc(8);b.writeBigUInt64LE(BigInt(n));return b;};
const report={status:"running",kernels:{before:hash(readFileSync(before)),after:hash(readFileSync(after))},scope:"Exact public resident outcomes/State, rejection retry, read-only export and cross-kernel checkpoint transfer on fixed C0 inputs.",cells:[]};
for(const family of ["H","Q"]) for(const depth of family==="H"?[1,16,64,256,1024,7,31,63,65,257]:[1,64,256,1024,7,31,63,65,257]) {
  const image=readFileSync(`${corpus}/${family}.bpi3`),arms=[];
  for(const path of [before,after]) {
    const bytes=readFileSync(path),k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});
    k.setLimits({input:2<<20,working:32<<20,output:2<<20});const p=k.prepare(image),s=k.start(p,integer(depth));arms.push({k,p,s});
  }
  let boundaries=0;
  const drive=options=>{
    const bytes=arms.map(({k,s})=>Buffer.from(k.drive(s,{checkpoint:true,...options})));
    assert.deepEqual(bytes[1],bytes[0]);boundaries++;return world.decodeOutcome(bytes[0]);
  };
  let out=drive({});assert.equal(out.kind,family==="H"?"yielded":"requested");
  if(family==="Q") {
    for(const index of [0,1,2]) {
      const value=readFileSync(`${corpus}/Q-${depth}-invalid-${index}.ers3`);
      const checkpoints=arms.map(({k,s})=>Buffer.from(k.checkpoint(s)));
      for(const {k,s}of arms) assert.throws(()=>k.drive(s,{control:"reply",value,quantum:0n}),error=>error.code==="WORLD_KERNEL_REJECTED"&&error.details.diagnostic===["InvalidResult","Truncated","InvalidValue"][index]);
      arms.forEach(({k,s},i)=>assert.deepEqual(Buffer.from(k.checkpoint(s)),checkpoints[i]));
    }
    // Late output failure must preserve both State and the original response.
    const value=readFileSync(`${corpus}/Q-${depth}-valid.ers3`);
    for(const {k,s}of arms) {
      const checkpoint=Buffer.from(k.checkpoint(s));
      k.setLimits({input:2<<20,working:32<<20,output:1});
      assert.throws(()=>k.drive(s,{control:"reply",value,quantum:1n}),{code:"WORLD_CAPACITY"});
      k.setLimits({input:2<<20,working:32<<20,output:2<<20});
      assert.deepEqual(Buffer.from(k.checkpoint(s)),checkpoint);
    }
  } else {
    out=drive({control:"resume_yield",quantum:0n});
    for(let cut=0;cut<64;cut++)assert.equal(drive({quantum:1n}).kind,"progressed");
  }
  const checkpoints=arms.map(({k,s})=>Buffer.from(k.checkpoint(s,{transfer:true})));
  assert.deepEqual(checkpoints[1],checkpoints[0]);
  arms.forEach((arm,i)=>{assert.throws(()=>arm.k.drive(arm.s),{code:"WORLD_HANDLE_INVALID"});arm.s=arm.k.restore(arm.p,checkpoints[1-i]);});
  let next=family==="Q"?0n:1n;
  out=family==="Q"?drive({control:"reply",value:readFileSync(`${corpus}/Q-${depth}-valid.ers3`)}):drive({});
  if(family==="Q")next++;
  while(out.kind==="requested") {
    const request=await world.decodeRequest(out.request);assert.equal(Buffer.from(request.payload).readBigUInt64LE(),next++);
    const value=await world.encodeResult(out.request,integer(7));out=drive({control:"reply",value});
  }
  assert.equal(out.kind,"completed");assert.equal(Buffer.from(out.value).readBigUInt64LE(),family==="Q"?135n:128n);
  for(const {k,p,s}of arms){k.close(s);k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);}
  report.cells.push({family,depth,imageSha256:hash(image),boundaries,distinctContinuationEffects:Number(next)-1,transferDirections:2,rejections:family==="Q"?6:0,lateOutputFailures:family==="Q"?2:0});
  writeFileSync(output,JSON.stringify(report,null,2)+"\n");console.log(JSON.stringify(report.cells.at(-1)));
}
report.status="complete";writeFileSync(output,JSON.stringify(report,null,2)+"\n");
