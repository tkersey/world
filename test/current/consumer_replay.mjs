// World-owned test adapter: explicit local bytes and identities, never an
// amended Agent historical lock. Captured Agent assertions remain the oracle.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,readdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {join,resolve,dirname} from 'node:path';
import {createHash} from 'node:crypto';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const median = values => [...values].sort((a,b)=>a-b)[Math.floor(values.length/2)];
const args=process.argv.slice(2);
if(args[0]==='sample') {
  const [,embedding,kernelPath,phase,source,name,pass]=args;
  assert(['admission','replay'].includes(phase)); assert(['timing','memory'].includes(pass));
  const world=await import(pathToFileURL(embedding)),bytes=readFileSync(kernelPath);
  const kernel=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});
  kernel.setLimits({input:256<<20,working:256<<20,output:256<<20});
  const image=phase==='admission'?readFileSync(source):null;
  const rows=phase==='replay'?JSON.parse(readFileSync(source)).rows.filter(r=>r.name===name).map(r=>{
    const input=readFileSync(resolve(dirname(source),r.inputFile)),expected=readFileSync(resolve(dirname(source),r.outputFile));
    assert.equal(hash(input),r.inputSha256);assert.equal(hash(expected),r.outputSha256);return {input,expected};
  }):[];
  assert(phase==='admission'||rows.length);
  let peakBytes=0,retainedBytes=0,reservedBytes=0;
  const observe=()=>{const usage=kernel.usage();peakBytes=Math.max(peakBytes,Number(usage.workingPeak));retainedBytes=Math.max(retainedBytes,Number(usage.workingLive));reservedBytes=Math.max(reservedBytes,usage.memoryBytes);};
  const samplesNs=[];
  for(let sample=0;sample<(pass==='memory'?1:12);sample++) {
    let elapsed=0;
    if(phase==='admission') {
      const start=process.hrtime.bigint(),prepared=kernel.prepare(image);
      elapsed+=Number(process.hrtime.bigint()-start);if(pass==='memory')observe();
      kernel.releasePrepared(prepared);if(pass==='memory')observe();
    } else for(const {input,expected} of rows) {
      const start=process.hrtime.bigint(),output=kernel.invoke(input);
      elapsed+=Number(process.hrtime.bigint()-start);if(pass==='memory')observe();
      assert.deepEqual(Buffer.from(output),expected);
      assert.equal(kernel.usage().workingLive,0n);
    }
    assert.equal(kernel.usage().workingLive,0n);
    if(sample>=3)samplesNs.push(elapsed);
  }
  console.log(JSON.stringify({kernelSha256:hash(bytes),commands:rows.length||1,samplesNs,...(pass==='memory'?{peakBytes,retainedBytes,reservedBytes}:{})}));
} else {
  const [embedding,before,after,corpus,manifest,output]=args;
  assert.equal(args.length,6);
  const cases=readdirSync(corpus).filter(x=>x.endsWith('.bpi3')).sort().map(name=>({name,phase:'admission',source:join(corpus,name)}));
  const rows=JSON.parse(readFileSync(manifest)).rows;
  for(const name of new Set(rows.map(r=>r.name)))cases.push({name,phase:'replay',source:manifest});
  const report={status:'running',scope:'Same frozen images and exact fresh invocations. Each recorded trace sample sums its actual commands, excluding external host/model latency. H/Q live-Resident lifecycles are qualified separately.',kernels:{before:hash(readFileSync(before)),after:hash(readFileSync(after))},manifestSha256:hash(readFileSync(manifest)),warmups:3,samples:9,windows:5,cells:[]};
  for(const cell of cases) {
    const windows=[];
    for(let window=0;window<5;window++) {
      const observed={};
      for(const arm of window%2?['after','before']:['before','after']) observed[arm]=JSON.parse(execFileSync(process.execPath,[fileURLToPath(import.meta.url),'sample',embedding,arm==='before'?before:after,cell.phase,cell.source,cell.name,'timing'],{encoding:'utf8',timeout:180000}));
      windows.push({...observed,ratio:median(observed.after.samplesNs)/median(observed.before.samplesNs)});
    }
    const memory={};
    for(const arm of ['before','after'])memory[arm]=JSON.parse(execFileSync(process.execPath,[fileURLToPath(import.meta.url),'sample',embedding,arm==='before'?before:after,cell.phase,cell.source,cell.name,'memory'],{encoding:'utf8',timeout:180000}));
    const ratios=windows.map(w=>w.ratio),ratio=median(ratios),confirmedSlowdown=ratio>1.05&&ratios.filter(r=>r>1.05).length>=4;
    const memoryExceeded=memory.after.peakBytes-memory.before.peakBytes>Math.max(1024,Math.ceil(memory.before.peakBytes*.01));
    report.cells.push({...cell,ratio,confirmedSlowdown,memoryExceeded,memory,windows});
    writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({name:cell.name,phase:cell.phase,ratio,confirmedSlowdown,memoryExceeded}));
  }
  report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
}
