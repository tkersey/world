import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const [embedding,oldKernel,newKernel,oldNative,newNative,sampler,corpus,output]=process.argv.slice(2);assert.equal(process.argv.length,10);
const hash=b=>createHash('sha256').update(b).digest('hex'),median=a=>[...a].sort((a,b)=>a-b)[Math.floor(a.length/2)],world=await import(pathToFileURL(embedding)),bytes=readFileSync(oldKernel),k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});k.setLimits({input:256<<20,working:256<<20,output:256<<20});
const report={status:'running',identities:Object.fromEntries(Object.entries({oldKernel,newKernel,oldNative,newNative,sampler}).map(([name,path])=>[name,{path,sha256:hash(readFileSync(path))}])),windows:5,warmups:{native:3,wasm:64},samples:9,cells:[]};
for(const family of ['compatible','fallback'])for(const n of [0,1,8,128,512]){
 const image=`${corpus}/${family}.bpi3`,input=`${corpus}/${family}-${n}.pki3`,expectedBytes=k.invoke(readFileSync(input)),expected=hash(expectedBytes),args=Buffer.alloc(8);args.writeBigUInt64LE(BigInt(n));assert.equal(Buffer.from(world.decodeOutcome(expectedBytes).value).readBigUInt64LE(),0n);
 for(const engine of ['native','wasm'])for(const phase of ['admission','fresh','cycle']){
  if(phase==='admission'&&n!==0)continue;
  const windows=[];
  for(let w=0;w<5;w++){
   const results={};
   for(const arm of w%2?['after','before']:['before','after']){
    const command=engine==='native'?(arm==='before'?oldNative:newNative):process.execPath;
    const argv=engine==='native'?[phase,phase==='admission'?image:input,...(phase==='admission'?[]:[expected])]:[sampler,'sample',embedding,arm==='before'?oldKernel:newKernel,image,input,phase,expected,args.toString('hex'),'64'];
    results[arm]=JSON.parse(execFileSync(command,argv,{encoding:'utf8',timeout:180000}));
   }
   windows.push({...results,ratio:median(results.after.samplesNs)/median(results.before.samplesNs)});
  }
  const ratio=median(windows.map(w=>w.ratio)),confirmedSlowdown=ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4;
  const cold=engine==='wasm'?{coldRampRatio:median(windows.map(w=>w.after.coldRampNs/w.before.coldRampNs)),setupRatio:median(windows.map(w=>w.after.setupNs/w.before.setupNs))}:{};
  report.cells.push({family,n,engine,phase,ratio,deltaNs:median(windows.map(w=>median(w.after.samplesNs)-median(w.before.samplesNs))),confirmedSlowdown,...cold,windows});writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({family,n,engine,phase,ratio,confirmedSlowdown,...cold}));
 }
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
