// Native same-image admission and exact recorded-command replay. No host effects.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,readdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {dirname,resolve} from 'node:path';
const [before,after,corpus,output,...manifests]=process.argv.slice(2);
assert(before&&after&&corpus&&output);
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const median=xs=>[...xs].sort((a,b)=>a-b)[Math.floor(xs.length/2)];
const cases=readdirSync(corpus).filter(p=>p.endsWith('.bpi3')).sort().map(name=>({name,phase:'admission',commands:[{path:`${corpus}/${name}`,sha256:hash(`${corpus}/${name}`)}]}));
for(const path of manifests){
 const rows=JSON.parse(readFileSync(path)).rows;
 for(const name of new Set(rows.map(r=>r.name))){
  assert(!cases.some(c=>c.name===name),'duplicate case name');
  const commands=rows.filter(r=>r.name===name).map(r=>{
   const input=resolve(dirname(path),r.inputFile),output=resolve(dirname(path),r.outputFile);
   assert.equal(hash(input),r.inputSha256);assert.equal(hash(output),r.outputSha256);
   return{path:input,sha256:r.inputSha256,expected:r.outputSha256};
  });
  cases.push({name,phase:'replay',commands});
 }
}
assert(cases.length>0,'empty corpus');
const report={status:'running',scope:'Same-image native admission and recorded fresh invocations; every command keeps its exact control, quantum and State. No external host execution. Each command is measured in a separate process with three warmups and nine samples; trace samples sum corresponding per-command samples, not whole-application latency.',executables:{before:hash(before),after:hash(after)},manifests:manifests.map(path=>({path,sha256:hash(path)})),windows:5,warmups:3,samples:9,cells:[]};
for(const c of cases){
 const windows=[];
 for(let w=0;w<5;w++){
  const measured={};
  for(const arm of w%2?['after','before']:['before','after']){
   const samplesNs=Array(9).fill(0);let peakBytes=0,retainedBytes=0;
   for(const command of c.commands){
    assert.equal(hash(command.path),command.sha256);
    const r=JSON.parse(execFileSync(arm==='before'?before:after,[c.phase,command.path,...(command.expected?[command.expected]:[])],{encoding:'utf8',timeout:180000}));
    assert(Number.isSafeInteger(r.peakBytes)&&r.peakBytes>=0);
    assert(Number.isSafeInteger(r.retainedBytes)&&r.retainedBytes>=0);
    assert.equal(r.samplesNs.length,9);r.samplesNs.forEach((n,i)=>{assert(Number.isFinite(n)&&n>=0);samplesNs[i]+=n;});
    peakBytes=Math.max(peakBytes,r.peakBytes);retainedBytes=Math.max(retainedBytes,r.retainedBytes);
   }
   measured[arm]={samplesNs,peakBytes,retainedBytes};
  }
  windows.push({...measured,ratio:median(measured.after.samplesNs)/median(measured.before.samplesNs)});
 }
 const ratio=median(windows.map(w=>w.ratio)),confirmedSlowdown=ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4;
 const memoryExceeded=windows.some(w=>w.after.peakBytes-w.before.peakBytes>Math.max(1024,Math.ceil(w.before.peakBytes*.01)));
 report.cells.push({...c,ratio,confirmedSlowdown,memoryExceeded,windows});
 writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({name:c.name,phase:c.phase,commands:c.commands.length,ratio,confirmedSlowdown,memoryExceeded}));
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
