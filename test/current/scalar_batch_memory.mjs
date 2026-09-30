import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const [embedding,kernelPath,before,after,corpus,output]=process.argv.slice(2);assert.equal(process.argv.length,8);
const world=await import(pathToFileURL(embedding)),hash=b=>createHash('sha256').update(b).digest('hex'),bytes=readFileSync(kernelPath),k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});k.setLimits({input:256<<20,working:256<<20,output:256<<20});
const report={status:'running',scope:'Native memory comparison; incidental timing samples are not a paired latency qualification',binaryHashes:{before:hash(readFileSync(before)),after:hash(readFileSync(after))},cells:[]};
for(const operations of [0,2,4,16,256,1024]){
 const image=`${corpus}/${operations}.bpi3`,input=`${corpus}/${operations}-fresh.pki3`,expected=hash(k.invoke(readFileSync(input)));
 for(const phase of ['admission','fresh','cycle']){
  const args=phase==='admission'?[phase,image]:[phase,input,expected],results={};
  for(const arm of ['before','after'])results[arm]=JSON.parse(execFileSync(arm==='before'?before:after,args,{encoding:'utf8',timeout:120000}));
  assert.equal(results.after.peakBytes,results.before.peakBytes);assert.equal(results.after.retainedBytes,results.before.retainedBytes);
  report.cells.push({operations,phase,...results});writeFileSync(output,JSON.stringify(report,null,2)+'\n');
 }
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({cells:report.cells.length,memory:'exact equality'}));
