// Current public-API sampler for the existing frame timing driver. Cycle is
// deliberately fresh checkpoint replay, distinct from the H/Q Resident lane.
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {pathToFileURL} from "node:url";
import {createHash} from "node:crypto";
const [mode,embedding,kernel,imagePath,inputPath,phase,expected,argumentHex]=process.argv.slice(2);
assert.equal(mode,"sample");
const hash=b=>createHash("sha256").update(b).digest("hex"),world=await import(pathToFileURL(embedding)),bytes=readFileSync(kernel);
const k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});k.setLimits({input:256<<20,working:256<<20,output:256<<20});
const image=readFileSync(imagePath),command=readFileSync(inputPath),initialArgs=Buffer.from(argumentHex,"hex"),samplesNs=[];
const batch=phase==="cycle"?1:phase==="admission"?64:16;
function execute(){
 if(phase==="admission"){const p=k.prepare(image);k.releasePrepared(p);return;}
 if(phase!=="cycle"){assert.equal(hash(k.invoke(command)),expected);return;}
 let input={image,initialArgs,quantum:1n};
 for(let steps=0;steps<4096;steps++){
  const result=Buffer.from(k.invoke(world.encodeInput(input))),out=world.decodeOutcome(result);
  if(out.kind==="completed"){assert.equal(hash(result),expected);return;}
  assert(["progressed","yielded"].includes(out.kind));input={image,state:out.state,quantum:1n,control:out.kind==="yielded"?"resume_yield":"none"};
 }
 throw Error("frame cycle step limit");
}
for(let sample=0;sample<12;sample++){const start=process.hrtime.bigint();for(let i=0;i<batch;i++)execute();const elapsed=Number(process.hrtime.bigint()-start)/batch;assert.equal(k.usage().workingLive,0n);if(sample>=3)samplesNs.push(elapsed);}
console.log(JSON.stringify({samplesNs}));
