import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {field,concat} from '../../src/embedding/wire.mjs';
const hash=b=>createHash('sha256').update(b).digest('hex'),median=a=>[...a].sort((a,b)=>a-b)[Math.floor(a.length/2)],args=process.argv.slice(2);
if(args[0]==='sample'){
 const [,embedding,kernelPath,corpus,countText,phase='drive']=args,count=Number(countText),world=await import(pathToFileURL(embedding)),bytes=readFileSync(kernelPath),k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});k.setLimits({input:256<<20,working:256<<20,output:256<<20});assert(['drive','complete'].includes(phase));
 const image=readFileSync(`${corpus}/${count}.bpi3`),input=readFileSync(`${corpus}/${count}.args`),samplesNs=[];let p=k.prepare(image),pausedLive=0,steps=0,peakBytes=Number(k.usage().workingPeak);
 // Observe memory in a separate untimed drive sequence; API calls reset peaks.
 {const s=k.start(p,input);peakBytes=Math.max(peakBytes,Number(k.usage().workingPeak));let step=0;while(true){const out=world.decodeOutcome(k.drive(s,{quantum:1n}));peakBytes=Math.max(peakBytes,Number(k.usage().workingPeak));if(++step===1)pausedLive=Number(k.usage().workingLive);if(out.kind==='completed'){assert.equal(Buffer.from(out.value).readBigUInt64LE(),65536n);break;}assert.equal(out.kind,'progressed');}k.close(s);peakBytes=Math.max(peakBytes,Number(k.usage().workingPeak));k.releasePrepared(p);peakBytes=Math.max(peakBytes,Number(k.usage().workingPeak));assert.equal(k.usage().workingLive,0n);}
 p=phase==='drive'?k.prepare(image):null; // Latency cannot reset the saved memory result.
 const warmups=64,warmupSamplesNs=[];
 for(let sample=0;sample<warmups+9;sample++){
  let start=process.hrtime.bigint();if(phase==='complete')p=k.prepare(image);
  const s=k.start(p,input);if(phase==='drive')start=process.hrtime.bigint();steps=0;
  while(true){const result=world.decodeOutcome(k.drive(s,{quantum:1n}));assert(++steps<=count+4);if(result.kind==='completed'){assert.equal(Buffer.from(result.value).readBigUInt64LE(),65536n);break;}assert.equal(result.kind,'progressed');}
  let elapsed=Number(process.hrtime.bigint()-start);k.close(s);
  if(phase==='complete'){k.releasePrepared(p);elapsed=Number(process.hrtime.bigint()-start);}
  (sample>=warmups?samplesNs:warmupSamplesNs).push(elapsed);
 }
 if(phase==='drive')k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);console.log(JSON.stringify({phase,samplesNs,warmupSamplesNs,warmups,coldRampNs:warmupSamplesNs.slice(0,12).reduce((a,b)=>a+b,0),pausedLive,peakBytes,steps}));
}else{
 const [embedding,before,after,emitter,corpus,output]=args;assert.equal(args.length,6);mkdirSync(corpus,{recursive:true});const world=await import(pathToFileURL(embedding)),report={status:'running',kernels:{before:hash(readFileSync(before)),after:hash(readFileSync(after))},cells:[]};
 for(const count of [1,4,16,64]){
  const image=execFileSync(emitter,[`aliases-${count}`]),input=concat(...Array(count).fill(field(Buffer.alloc(65536,120))));writeFileSync(`${corpus}/${count}.bpi3`,image);writeFileSync(`${corpus}/${count}.args`,input);
  const states=[];for(const path of [before,after]){const bytes=readFileSync(path),k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});k.setLimits({input:256<<20,working:256<<20,output:256<<20});const p=k.prepare(image),s=k.start(p,input),trace=[];while(true){const result=k.drive(s,{quantum:1n,checkpoint:true});trace.push(Buffer.from(result));const out=world.decodeOutcome(result);if(out.kind==='completed'){assert.equal(Buffer.from(out.value).readBigUInt64LE(),65536n);break;}assert.equal(out.kind,'progressed');}k.close(s);k.releasePrepared(p);states.push(trace);}assert.deepEqual(states[1],states[0]);
  for(const phase of ['drive','complete']){
   const windows=[];for(let w=0;w<5;w++){const results={};for(const arm of w%2?['after','before']:['before','after'])results[arm]=JSON.parse(execFileSync(process.execPath,[new URL(import.meta.url).pathname,'sample',embedding,arm==='before'?before:after,corpus,String(count),phase],{encoding:'utf8',timeout:120000}));windows.push({...results,ratio:median(results.after.samplesNs)/median(results.before.samplesNs)});}
   const ratio=median(windows.map(w=>w.ratio)),confirmedSlowdown=ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4,coldRampRatio=median(windows.map(w=>w.after.coldRampNs/w.before.coldRampNs)),memoryExceeded=windows.some(w=>w.after.peakBytes-w.before.peakBytes>Math.max(1024,Math.ceil(w.before.peakBytes*.01)));
   report.cells.push({count,phase,imageSha256:hash(image),ratio,confirmedSlowdown,coldRampRatio,memoryExceeded,windows});writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({count,phase,ratio,confirmedSlowdown,coldRampRatio,memoryExceeded}));
  }
 }
 report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
}
