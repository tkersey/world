import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const hash=b=>createHash('sha256').update(b).digest('hex'),median=xs=>[...xs].sort((a,b)=>a-b)[Math.floor(xs.length/2)],args=process.argv.slice(2);
if(args[0]==='sample'){
 const [,embedding,kernelPath,corpus,family,lengthText,phase,pass='timing']=args,length=Number(lengthText),world=await import(pathToFileURL(embedding)),bytes=readFileSync(kernelPath),setupStart=process.hrtime.bigint(),k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)}),setupNs=Number(process.hrtime.bigint()-setupStart);
 assert(['fresh','pause','resident-lifecycle'].includes(phase));
 assert(['timing','memory'].includes(pass));
 k.setLimits({input:256<<20,working:256<<20,output:256<<20});const image=readFileSync(`${corpus}/${family}.bpi3`),input=readFileSync(`${corpus}/${family}-${length}.args`),request=world.encodeInput({image,initialArgs:input}),expected=['unique','retained'].includes(family)?0n:BigInt(length);
 if(pass==='memory'){
  let peakBytes=0,reservedBytes=0,preparedLive=0,pauseLive=0;
  const observed=operation=>{try{return operation();}finally{const u=k.usage();peakBytes=Math.max(peakBytes,Number(u.workingPeak));reservedBytes=Math.max(reservedBytes,u.memoryBytes);}};
  let final;
  if(phase==='fresh')final=observed(()=>k.invoke(request));
  else{
   const prepared=observed(()=>k.prepare(image));preparedLive=Number(k.usage().workingLive);
   const session=observed(()=>k.start(prepared,input));
   const paused=observed(()=>k.drive(session,{quantum:['captured','retained'].includes(family)?2n:1n}));
   assert.equal(world.decodeOutcome(paused).kind,'progressed');pauseLive=Number(k.usage().workingLive);
   final=observed(()=>k.drive(session));observed(()=>k.close(session));observed(()=>k.releasePrepared(prepared));
  }
  const out=world.decodeOutcome(final);assert.equal(out.kind,'completed');assert.equal(Buffer.from(out.value).readBigUInt64LE(),expected);assert.equal(k.usage().workingLive,0n);
  console.log(JSON.stringify({peakBytes,reservedBytes,preparedLive,pauseLive}));
 }else{
 const p=phase==='pause'?k.prepare(image):null,samplesNs=[],warmupSamplesNs=[],warmups=64,batch=length<65536?32:8;
 for(let sample=0;sample<warmups+9;sample++){
  let elapsed=0;
  for(let i=0;i<batch;i++){
   if(phase==='resident-lifecycle'){
    const start=process.hrtime.bigint(),prepared=k.prepare(image),session=k.start(prepared,input);
    const paused=k.drive(session,{quantum:['captured','retained'].includes(family)?2n:1n}),final=k.drive(session);
    k.close(session);k.releasePrepared(prepared);elapsed+=Number(process.hrtime.bigint()-start);
    assert.equal(world.decodeOutcome(paused).kind,'progressed');const out=world.decodeOutcome(final);
    assert.equal(out.kind,'completed');assert.equal(Buffer.from(out.value).readBigUInt64LE(),expected);
    assert.equal(k.usage().workingLive,0n);continue;
   }
   const s=p?k.start(p,input):null,start=process.hrtime.bigint();
   const result=p?k.drive(s,{quantum:['captured','retained'].includes(family)?2n:1n}):k.invoke(request);elapsed+=Number(process.hrtime.bigint()-start);
   const out=world.decodeOutcome(result);assert.equal(out.kind,p?'progressed':'completed');
   if(p){const final=world.decodeOutcome(k.drive(s));assert.equal(final.kind,'completed');assert.equal(Buffer.from(final.value).readBigUInt64LE(),expected);k.close(s);}else assert.equal(Buffer.from(out.value).readBigUInt64LE(),expected);
  }
  (sample>=warmups?samplesNs:warmupSamplesNs).push(elapsed/batch);
 }
 // Memory is observed separately by the retention platform/alias probes.
 if(p)k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);console.log(JSON.stringify({samplesNs,warmupSamplesNs,warmups,batch,setupNs,coldRampNs:batch*warmupSamplesNs.slice(0,12).reduce((a,b)=>a+b,0)}));
 }
}else{
 const [embedding,before,after,corpus,output,selection]=args;assert([5,6].includes(args.length));const report={status:'running',kernels:{before:hash(readFileSync(before)),after:hash(readFileSync(after))},cells:[]};
 for(const family of selection?[selection]:['unique','alias','captured','retained'])for(const length of [0,65532,65533,65534,65536,1048576])for(const phase of ['fresh','pause','resident-lifecycle']){
  const windows=[];
  for(let w=0;w<5;w++){
   const results={};for(const arm of w%2?['after','before']:['before','after'])results[arm]=JSON.parse(execFileSync(process.execPath,[new URL(import.meta.url).pathname,'sample',embedding,arm==='before'?before:after,corpus,family,String(length),phase],{encoding:'utf8',timeout:120000}));
   windows.push({...results,ratio:median(results.after.samplesNs)/median(results.before.samplesNs)});
  }
  const ratio=median(windows.map(w=>w.ratio)),confirmedSlowdown=ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4;
  const coldRampRatio=median(windows.map(w=>w.after.coldRampNs/w.before.coldRampNs)),setupRatio=median(windows.map(w=>w.after.setupNs/w.before.setupNs));
  const memory={};for(const arm of ['before','after'])memory[arm]=JSON.parse(execFileSync(process.execPath,[new URL(import.meta.url).pathname,'sample',embedding,arm==='before'?before:after,corpus,family,String(length),phase,'memory'],{encoding:'utf8',timeout:120000}));
  const memoryExceeded=memory.after.peakBytes-memory.before.peakBytes>Math.max(1024,Math.ceil(memory.before.peakBytes*.01));
  report.cells.push({family,length,phase,ratio,deltaNs:median(windows.map(w=>median(w.after.samplesNs)-median(w.before.samplesNs))),confirmedSlowdown,coldRampRatio,setupRatio,memory,memoryExceeded,windows});writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({family,length,phase,ratio,confirmedSlowdown,coldRampRatio,setupRatio,memoryExceeded}));
 }
 report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
}
