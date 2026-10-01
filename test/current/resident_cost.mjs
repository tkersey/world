import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const [before,after,frameCorpus,blobCorpus,output]=process.argv.slice(2);assert.equal(process.argv.length,7);
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex'),median=xs=>[...xs].sort((a,b)=>a-b)[Math.floor(xs.length/2)];
mkdirSync(`${frameCorpus}/arguments`,{recursive:true});
const cases=[];
for(const family of ['compatible','fallback'])for(const n of [0,8,128,512]){
 const input=`${frameCorpus}/arguments/${family}-${n}.bin`,bytes=Buffer.alloc(8);bytes.writeBigUInt64LE(BigInt(n));writeFileSync(input,bytes);
 cases.push({family,n,image:`${frameCorpus}/${family}.bpi3`,input,quantum:'18446744073709551615',expected:'0'});
}
for(const family of ['unique','alias','captured'])for(const n of [0,65532,65536,1048576])cases.push({family,n,image:`${blobCorpus}/${family}.bpi3`,input:`${blobCorpus}/${family}-${n}.args`,quantum:family==='captured'?'2':'1',expected:family==='unique'?'0':String(n)});
const report={status:'running',scope:'Native resident allocation traffic and separately timed uninstrumented drives; baseline World c61edfc, fixed runtime Boundary 511fe38',executables:{before:hash(before),after:hash(after)},cells:[]};
for(const c of cases){
 const windows=[];
 for(let w=0;w<5;w++){
  const results={};for(const arm of w%2?['after','before']:['before','after'])results[arm]=JSON.parse(execFileSync(arm==='before'?before:after,[c.image,c.input,c.quantum,c.expected],{encoding:'utf8',timeout:120000}));
  assert.deepEqual(results.after.imageDigest,results.before.imageDigest);assert.equal(results.after.batch,results.before.batch);windows.push({...results,ratio:median(results.after.samplesNs)/median(results.before.samplesNs)});
 }
 const ratio=median(windows.map(w=>w.ratio)),confirmedSlowdown=ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4,memoryExceeded=windows.some(w=>w.after.peakBytes-w.before.peakBytes>Math.max(1024,Math.ceil(w.before.peakBytes*.01)));
 report.cells.push({...c,imageSha256:hash(c.image),inputSha256:hash(c.input),ratio,confirmedSlowdown,memoryExceeded,deltaNs:median(windows.map(w=>median(w.after.samplesNs)-median(w.before.samplesNs))),windows});writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({family:c.family,n:c.n,ratio,confirmedSlowdown,memoryExceeded}));
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
