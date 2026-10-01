// Fresh-process restoration of parked H/Q histories through existing public
// Node, native invocation and Wasmtime APIs. No private Resident facts cross.
import assert from "node:assert/strict";
import {readFileSync,writeFileSync,mkdirSync} from "node:fs";
import {execFileSync} from "node:child_process";
import {pathToFileURL,fileURLToPath} from "node:url";
import {join,resolve} from "node:path";
import {createHash} from "node:crypto";
import {wasmtimePeer} from "./peer.mjs";
const hash=b=>createHash("sha256").update(b).digest("hex");
const args=process.argv.slice(2);
const integer=n=>{const b=Buffer.alloc(8);b.writeBigUInt64LE(BigInt(n));return b;};
async function load(embedding,kernel){
 const world=await import(pathToFileURL(embedding)),bytes=readFileSync(kernel);
 const k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});
 k.setLimits({input:2<<20,working:32<<20,output:2<<20});return {world,k};
}
if(args[0]==="restore"){
 const [,embedding,kernel,imagePath,statePath,control,valuePath,output]=args;
 const {world,k}=await load(embedding,kernel),p=k.prepare(readFileSync(imagePath));
 const s=k.restore(p,readFileSync(statePath));
 const result=Buffer.from(k.drive(s,{control,value:readFileSync(valuePath),quantum:1n,checkpoint:true}));
 writeFileSync(output,result);
 assert.deepEqual(Buffer.from(k.checkpoint(s,{transfer:true})),Buffer.from(world.decodeOutcome(result).state));
 k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);
 console.log(JSON.stringify({kernelSha256:hash(readFileSync(kernel)),outcomeSha256:hash(result),kind:world.decodeOutcome(result).kind}));
}else{
 const [embedding,before,after,nativeBefore,nativeAfter,corpus,output]=args;assert.equal(args.length,7);
 const report={status:"running",scope:"Fresh-process H/Q restoration at prescribed sizes, baseline/candidate transfer in both directions, exact Node/native/Wasmtime outcomes",kernels:{before:hash(readFileSync(before)),after:hash(readFileSync(after))},cells:[]};
 const files=resolve(`${output}.files`);mkdirSync(files,{recursive:true});
 for(const family of ["H","Q"])for(const depth of [1,64,1024])for(const direction of ["before-to-after","after-to-before"]){
  const source=direction.startsWith("before")?before:after,destination=direction.startsWith("before")?after:before;
  const native=direction.startsWith("before")?nativeAfter:nativeBefore;
  const {world,k}=await load(embedding,source),imagePath=resolve(join(corpus,`${family}.bpi3`)),image=readFileSync(imagePath);
  const p=k.prepare(image),s=k.start(p,integer(depth)),initial=world.decodeOutcome(k.drive(s));assert.equal(initial.kind,family==="H"?"yielded":"requested");
  const state=Buffer.from(k.checkpoint(s,{transfer:true}));k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);
  const control=family==="H"?"resume_yield":"reply",value=family==="H"?Buffer.alloc(0):readFileSync(join(corpus,`Q-${depth}-valid.ers3`));
  const stem=join(files,`${family}-${depth}-${direction}`),statePath=`${stem}.pst3`,valuePath=`${stem}.ers3`,inputPath=`${stem}.pki3`,resultPath=`${stem}.pko3`;
  writeFileSync(statePath,state);writeFileSync(valuePath,value);
  const command=world.encodeInput({image,state,control,value,quantum:1n});writeFileSync(inputPath,command);
  const expected=Buffer.from(k.invoke(command));
  const child=JSON.parse(execFileSync(process.execPath,[fileURLToPath(import.meta.url),"restore",embedding,destination,imagePath,statePath,control,valuePath,resultPath],{encoding:"utf8",timeout:180000}));
  assert.deepEqual(readFileSync(resultPath),expected);assert.equal(child.outcomeSha256,hash(expected));
  assert.deepEqual(execFileSync(native,[inputPath],{timeout:180000,maxBuffer:16<<20}),expected);
  const peer=await wasmtimePeer(destination,hash(readFileSync(destination)));
  try{
   const admitted=await peer.call("prepare",{bytes:image}),restored=await peer.call("restore",{handle:admitted.prepared,bytes:state});
   await peer.call("release_prepared",{handle:admitted.prepared});
   const result=await peer.call("drive",{handle:restored.session,control:family==="H"?2:1,bytes:value,quantum:1,checkpoint:true});
   assert.deepEqual(Buffer.from(result.bytes),expected);
   const transferred=await peer.call("checkpoint",{handle:restored.session,transfer:true});
   assert.deepEqual(Buffer.from(transferred.bytes),Buffer.from(world.decodeOutcome(expected).state));assert.equal(transferred.working_live,0);
   report.cells.push({family,depth,direction,imageSha256:hash(image),stateSha256:hash(state),inputSha256:hash(command),outputSha256:hash(expected),engines:["fresh-node-process","fresh-native-process","fresh-wasmtime-process"],wasmtime:peer.identity});
  }finally{await peer.close();}
  writeFileSync(output,JSON.stringify(report,null,2)+"\n");console.log(JSON.stringify({family,depth,direction}));
 }
 report.status="complete";writeFileSync(output,JSON.stringify(report,null,2)+"\n");
}
