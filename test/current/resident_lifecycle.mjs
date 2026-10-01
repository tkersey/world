// Matched public-Resident lifecycles. Timing and reset-on-command memory passes
// are separate; no application handler or live model is called.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { pathToFileURL, fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
const hash = bytes => createHash("sha256").update(bytes).digest("hex");
const median = values => [...values].sort((a,b) => a-b)[Math.floor(values.length/2)];
const limits = {input:2 << 20, working:32 << 20, output:2 << 20};
const integer = n => {const bytes=Buffer.alloc(8);bytes.writeBigUInt64LE(BigInt(n));return bytes;};

function observation(k, instrumented) {
  const phases = [];
  return {
    phases,
    call(phase, fn) {
      if (!instrumented) return fn();
      try { return fn(); } finally {
        const usage=k.usage();
        phases.push({phase,peak:Number(usage.workingPeak),live:Number(usage.workingLive),reserved:Number(usage.memoryBytes)});
      }
    },
  };
}
// A small later command (including a failed command) must not hide a peak.
{
  let peak=0;
  const sampled=observation({usage:()=>({workingPeak:BigInt(peak),workingLive:0n,memoryBytes:65536})},true);
  sampled.call("large",()=>{peak=12345;});
  assert.throws(()=>sampled.call("failed",()=>{peak=45678;throw Error("fixture");}));
  sampled.call("close",()=>{peak=2;});
  assert.equal(Math.max(...sampled.phases.map(x=>x.peak)),45678);
}

async function load(embedding,kernelPath) {
  const world=await import(pathToFileURL(embedding));
  const bytes=readFileSync(kernelPath),start=process.hrtime.bigint();
  const k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});
  const setupNs=Number(process.hrtime.bigint()-start);
  k.setLimits(limits);
  return {world,k,kernelSha256:hash(bytes),kernelBytes:bytes.length,setupNs};
}
function lifecycle(world,k,image,family,depth,replies,instrumented) {
  const sample=observation(k,instrumented),call=sample.call;
  const p=call("prepare",()=>k.prepare(image));
  let s=call("start",()=>k.start(p,integer(depth)));
  const initial=call("initial-publication",()=>k.drive(s));
  if (instrumented) assert.equal(world.decodeOutcome(initial).kind,family==="H"?"yielded":"requested");
  if (family==="H") {
    call("resume-yield",()=>k.drive(s,{control:"resume_yield",quantum:0n}));
    for(let i=0;i<64;i++) call(`drive-${i}`,()=>k.drive(s,{quantum:1n}));
    const checkpoint=call("checkpoint-transfer",()=>k.checkpoint(s,{transfer:true}));
    s=call("restore",()=>k.restore(p,checkpoint));
  } else {
    for(const [index,value] of replies.invalid.entries()) {
      let rejected=false;
      try { call(`invalid-${index}`,()=>k.drive(s,{control:"reply",value,quantum:0n})); }
      catch(error) {assert.equal(error.code,"WORLD_KERNEL_REJECTED");assert.equal(error.details.diagnostic,replies.diagnostics[index]);rejected=true;}
      assert(rejected,"invalid response accepted");
    }
    call("valid-reply",()=>k.drive(s,{control:"reply",value:replies.valid,quantum:0n}));
  }
  const cancelled=call("cancel",()=>k.drive(s,{control:"cancel_text",value:"lifecycle-complete"}));
  if(instrumented) assert.equal(world.decodeOutcome(cancelled).kind,"cancelled");
  call("close",()=>k.close(s));call("release-prepared",()=>k.releasePrepared(p));
  assert.equal(k.usage().workingLive,0n);
  return sample.phases;
}

const args=process.argv.slice(2);
if(args[0]==="freeze") {
  const [,embedding,kernelPath,corpus]=args;
  const {world,k}=await load(embedding,kernelPath);
  const wire=await import(pathToFileURL(fileURLToPath(new URL("../../src/embedding/wire.mjs",import.meta.url))));
  for(const depth of [1,64,256,1024,7,31,63,65,257]) {
    const p=k.prepare(readFileSync(`${corpus}/Q.bpi3`)),s=k.start(p,integer(depth));
    const out=world.decodeOutcome(k.drive(s));assert.equal(out.kind,"requested");
    const request=await world.decodeRequest(out.request),valid=await world.encodeResult(out.request,integer(7));
    const wrong=request.requestIdentity.slice();wrong[0]^=1;
    const invalid=[wire.frame("ABL_ERS3",wire.concat(wrong,wire.field(integer(7)))),Uint8Array.of(0),wire.frame("ABL_ERS3",wire.concat(request.requestIdentity,wire.field(Uint8Array.of(0))))];
    for(const [index,value] of invalid.entries())writeFileSync(`${corpus}/Q-${depth}-invalid-${index}.ers3`,value);
    writeFileSync(`${corpus}/Q-${depth}-valid.ers3`,valid);
    writeFileSync(`${corpus}/Q-${depth}.erq3`,out.request);
    k.drive(s,{control:"cancel_text",value:"freeze"});k.close(s);k.releasePrepared(p);
  }
  console.log("Frozen baseline request bindings and prescribed reply bytes.");
} else if(args[0]==="sample") {
  const [,embedding,kernelPath,corpus,family,size]=args,depth=Number(size);
  const runtime=await load(embedding,kernelPath),{world,k}=runtime,image=readFileSync(`${corpus}/${family}.bpi3`);
  const replies=family==="Q"?{invalid:[0,1,2].map(i=>readFileSync(`${corpus}/Q-${depth}-invalid-${i}.ers3`)),valid:readFileSync(`${corpus}/Q-${depth}-valid.ers3`),diagnostics:["InvalidResult","Truncated","InvalidValue"]}:null;
  const samplesNs=[];
  for(let sample=0;sample<12;sample++) {
    const start=process.hrtime.bigint();lifecycle(world,k,image,family,depth,replies,false);const elapsed=Number(process.hrtime.bigint()-start);
    if(sample>=3)samplesNs.push(elapsed);
  }
  // No timings from this instrumentation pass qualify latency.
  const phases=lifecycle(world,k,image,family,depth,replies,true);
  console.log(JSON.stringify({family,depth,limits,imageSha256:hash(image),kernelSha256:runtime.kernelSha256,kernelBytes:runtime.kernelBytes,setupNs:runtime.setupNs,samplesNs,phases,peakBytes:Math.max(...phases.map(x=>x.peak)),reservedBytes:Math.max(...phases.map(x=>x.reserved))}));
} else if(args[0]==="compare") {
  const [,embedding,before,after,corpus,output,nativeBefore,nativeAfter]=args;
  const report={status:"running",scope:"Complete live Resident lifecycles including prepare/start, maintenance, publication, checkpoint/transfer, cancellation, close/release; kernel compilation/instantiation reported separately.",windows:5,warmups:3,samples:9,limits,cells:[]};
  for(const engine of nativeBefore&&nativeAfter?["wasm","native"]:["wasm"]) for(const family of ["H","Q"]) for(const depth of family==="H"?[1,16,64,256,1024]:[1,64,256,1024]) {
    const windows=[];
    for(let window=0;window<5;window++) {
      const results={};
      for(const arm of window%2?["after","before"]:["before","after"]) results[arm]=JSON.parse(execFileSync(engine==="wasm"?process.execPath:arm==="before"?nativeBefore:nativeAfter,engine==="wasm"?[fileURLToPath(import.meta.url),"sample",embedding,arm==="before"?before:after,corpus,family,String(depth)]:[family,corpus,String(depth)],{encoding:"utf8",timeout:180000}));
      windows.push({...results,ratio:median(results.after.samplesNs)/median(results.before.samplesNs)});
    }
    const ratio=median(windows.map(x=>x.ratio)),confirmedWin=ratio<.95&&windows.filter(x=>x.ratio<.95).length>=4,confirmedSlowdown=ratio>1.05&&windows.filter(x=>x.ratio>1.05).length>=4;
    const memoryExceeded=windows.some(x=>x.after.peakBytes-x.before.peakBytes>Math.max(1024,Math.ceil(x.before.peakBytes*.01)));
    const cell={engine,family,depth,ratio,confirmedWin,confirmedSlowdown,memoryExceeded,deltaNs:median(windows.map(x=>median(x.after.samplesNs)-median(x.before.samplesNs))),windows};
    report.cells.push(cell);writeFileSync(output,JSON.stringify(report,null,2)+"\n");console.log(JSON.stringify({...cell,windows:undefined}));
  }
  report.status="complete";writeFileSync(output,JSON.stringify(report,null,2)+"\n");
} else throw new Error("expected freeze, sample or compare");
