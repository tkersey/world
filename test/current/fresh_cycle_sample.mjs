// Sampler from Boundary B0 93340dade30b7d27a1e139f107359f91fb66fad3.
// Latency only: reset-on-command memory is measured by separate platform probes.
// Same-image runtime comparison; local candidate bytes are not a delivered bundle.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const hash=b=>createHash('sha256').update(b).digest('hex');
const median=a=>[...a].sort((a,b)=>a-b)[Math.floor(a.length/2)];
const args=process.argv.slice(2);
if(args[0]==='sample'){
 const [,embedding,kernelPath,imagePath,inputPath,phase,expected,argumentsHex]=args;
 const world=await import(pathToFileURL(embedding)),kernelBytes=readFileSync(kernelPath);
 const k=await world.Kernel.create({bytes:kernelBytes,expectedSha256:hash(kernelBytes)});
 k.setLimits({input:256<<20,working:256<<20,output:256<<20});
 const image=readFileSync(imagePath),request=readFileSync(inputPath),initialArgs=Buffer.from(argumentsHex,'hex');
 const samplesNs=[];
 for(let window=0;window<12;window++){
  const batch=phase==='cycle'?1:64;let elapsed=0;
  for(let i=0;i<batch;i++){
   const start=process.hrtime.bigint();
   if(phase==='admission'){const p=k.prepare(image);elapsed+=Number(process.hrtime.bigint()-start);k.releasePrepared(p);}
   else{
    let out=k.invoke(phase==='cycle'?world.encodeInput({image,initialArgs,quantum:1n}):request),decoded=world.decodeOutcome(out),count=0;
    while(decoded.kind==='progressed'){
     assert(phase==='cycle'&&++count<4096);
     out=k.invoke(world.encodeInput({image,state:decoded.state,quantum:1n}));decoded=world.decodeOutcome(out);
    }
    elapsed+=Number(process.hrtime.bigint()-start);assert.equal(hash(out),expected);
   }
   assert.equal(k.usage().workingLive,0n);
  }
  if(window>=3)samplesNs.push(elapsed/batch);
 }
 console.log(JSON.stringify({samplesNs}));
} else throw new Error("expected sample mode");
