import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const hash=b=>createHash('sha256').update(b).digest('hex'),median=xs=>[...xs].sort((a,b)=>a-b)[Math.floor(xs.length/2)],args=process.argv.slice(2);
if(args[0]==='sample'){
 const [,embedding,kernelPath,corpus,family,lengthText,phase]=args,length=Number(lengthText),world=await import(pathToFileURL(embedding)),bytes=readFileSync(kernelPath),k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});
 k.setLimits({input:256<<20,working:256<<20,output:256<<20});const image=readFileSync(`${corpus}/${family}.bpi3`),input=readFileSync(`${corpus}/${family}-${length}.args`),request=world.encodeInput({image,initialArgs:input}),p=phase==='pause'?k.prepare(image):null,expected=['unique','retained'].includes(family)?0n:BigInt(length),samplesNs=[],batch=length<65536?32:8;
 for(let sample=0;sample<12;sample++){
  let elapsed=0;
  for(let i=0;i<batch;i++){
   const s=p?k.start(p,input):null,start=process.hrtime.bigint();
   const result=p?k.drive(s,{quantum:['captured','retained'].includes(family)?2n:1n}):k.invoke(request);elapsed+=Number(process.hrtime.bigint()-start);
   const out=world.decodeOutcome(result);assert.equal(out.kind,p?'progressed':'completed');
   if(p){const final=world.decodeOutcome(k.drive(s));assert.equal(final.kind,'completed');assert.equal(Buffer.from(final.value).readBigUInt64LE(),expected);k.close(s);}else assert.equal(Buffer.from(out.value).readBigUInt64LE(),expected);
  }
  if(sample>=3)samplesNs.push(elapsed/batch);
 }
 // Memory is observed separately by the retention platform/alias probes.
 if(p)k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);console.log(JSON.stringify({samplesNs}));
}else{
 const [embedding,before,after,corpus,output,selection]=args;assert([5,6].includes(args.length));const report={status:'running',kernels:{before:hash(readFileSync(before)),after:hash(readFileSync(after))},cells:[]};
 for(const family of selection?[selection]:['unique','alias','captured','retained'])for(const length of [0,65532,65533,65534,65536,1048576])for(const phase of ['fresh','pause']){
  const windows=[];
  for(let w=0;w<5;w++){
   const results={};for(const arm of w%2?['after','before']:['before','after'])results[arm]=JSON.parse(execFileSync(process.execPath,[new URL(import.meta.url).pathname,'sample',embedding,arm==='before'?before:after,corpus,family,String(length),phase],{encoding:'utf8',timeout:120000}));
   windows.push({...results,ratio:median(results.after.samplesNs)/median(results.before.samplesNs)});
  }
  const ratio=median(windows.map(w=>w.ratio)),confirmedSlowdown=ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4;
  report.cells.push({family,length,phase,ratio,deltaNs:median(windows.map(w=>median(w.after.samplesNs)-median(w.before.samplesNs))),confirmedSlowdown,windows});writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({family,length,phase,ratio,confirmedSlowdown}));
 }
 report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
}
