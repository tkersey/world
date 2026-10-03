import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const hash=b=>createHash('sha256').update(b).digest('hex'),median=xs=>[...xs].sort((a,b)=>a-b)[Math.floor(xs.length/2)];
const args=process.argv.slice(2);
if(args[0]==='sample'){
 const [,embedding,kernelPath,corpus,countText,phase]=args,operations=Number(countText);
 const world=await import(pathToFileURL(embedding)),bytes=readFileSync(kernelPath),setupStart=process.hrtime.bigint(),k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)}),setupNs=Number(process.hrtime.bigint()-setupStart);
 k.setLimits({input:256<<20,working:256<<20,output:256<<20});
 const image=readFileSync(`${corpus}/${operations}.bpi3`),request=readFileSync(`${corpus}/${operations}-fresh.pki3`),input=Buffer.alloc(16);input.writeBigUInt64LE(0x123456789abcdef0n);input.writeBigUInt64LE(0xfedcba9876543210n,8);
 const prepared=phase==='prepared'?k.prepare(image):null,retained=k.usage().workingLive,samplesNs=[],warmupSamplesNs=[],warmups=64,batch=operations<32?128:16;
 for(let sample=0;sample<warmups+9;sample++){
  let elapsed=0;
  for(let j=0;j<batch;j++){
   const start=process.hrtime.bigint();
   if(phase==='admission'){const p=k.prepare(image);elapsed+=Number(process.hrtime.bigint()-start);k.releasePrepared(p);}
   else{
    let result;
    if(prepared){const s=k.start(prepared,input);result=k.drive(s);k.close(s);}else result=k.invoke(request);
    elapsed+=Number(process.hrtime.bigint()-start);
    const out=world.decodeOutcome(result);assert.equal(out.kind,'completed');assert.equal(Buffer.from(out.value).readBigUInt64LE(),0x123456789abcdef0n);
   }
   assert.equal(k.usage().workingLive,retained);
  }
  (sample>=warmups?samplesNs:warmupSamplesNs).push(elapsed/batch);
 }
 if(prepared)k.releasePrepared(prepared);
 // This sampler measures latency. Lifecycle calls reset kernel memory peaks;
 // memory qualification belongs to the separate platform/memory probes.
 console.log(JSON.stringify({samplesNs,warmupSamplesNs,warmups,batch,setupNs,coldRampNs:batch*warmupSamplesNs.slice(0,12).reduce((a,b)=>a+b,0)}));
}else{
 const [embedding,before,after,corpus,output]=args;assert.equal(args.length,5);
 const report={status:'running',warmups:64,samples:9,windows:5,kernels:{before:hash(readFileSync(before)),after:hash(readFileSync(after))},cells:[]};
 for(const operations of [0,2,4,16,256,1024])for(const phase of ['admission','prepared','fresh']){
  const windows=[];
  for(let w=0;w<5;w++){
   const results={};for(const arm of w%2?['after','before']:['before','after'])results[arm]=JSON.parse(execFileSync(process.execPath,[new URL(import.meta.url).pathname,'sample',embedding,arm==='before'?before:after,corpus,String(operations),phase],{encoding:'utf8',timeout:60000}));
   windows.push({...results,ratio:median(results.after.samplesNs)/median(results.before.samplesNs)});
  }
  const ratio=median(windows.map(w=>w.ratio)),confirmedSlowdown=ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4;
  const coldRampRatio=median(windows.map(w=>w.after.coldRampNs/w.before.coldRampNs)),setupRatio=median(windows.map(w=>w.after.setupNs/w.before.setupNs));
  report.cells.push({operations,phase,ratio,confirmedSlowdown,coldRampRatio,setupRatio,windows});writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({operations,phase,ratio,confirmedSlowdown}));
 }
 report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
}
