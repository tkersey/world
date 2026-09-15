// Independent loaded hosts remove cross-configuration Node JIT/GC interference.
// Each measured public call still creates a fresh WASM instance through World.
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { fork } from 'node:child_process';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { performance } from 'node:perf_hooks';
import { admitProcessKernel, encodeResult, encodeInput } from '../../src/process_v2/index.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const median = values => values.toSorted((a,b) => a-b)[values.length >> 1];
async function load(path) {
  const bytes = await readFile(path), sha256 = hash(bytes), start = performance.now();
  const host = await admitProcessKernel(bytes, {expectedSha256:sha256});
  return {host, sha256, bytes:bytes.length, setupMs:performance.now()-start};
}

if (process.argv[2] === '--worker') {
  const loaded = await load(process.argv[3]);
  let input;
  process.on('disconnect', () => process.exit(0));
  process.on('message', async message => {
    try {
      if (message.input) {
        input = Object.fromEntries(Object.entries(message.input).map(([key,value]) =>
          [key, new Uint8Array(Buffer.from(value, 'base64'))]));
        const expected = await loaded.host.run(input);
        for (let n=0; n<message.warmups; n++) await loaded.host.run(input);
        process.send({id:message.id, hash:hash(expected.bytes), kind:expected.kind});
      } else {
        let outcome;
        const start = performance.now();
        for (let n=0; n<message.batch; n++) outcome = await loaded.host.run(input);
        const milliseconds = (performance.now()-start)/message.batch;
        process.send({id:message.id, milliseconds, hash:hash(outcome.bytes)});
      }
    } catch (error) { process.send({id:message.id,error:error.stack}); }
  });
  process.send({ready:true, kernel:{sha256:loaded.sha256,bytes:loaded.bytes,setupMs:loaded.setupMs}});
} else {
  const [reference,candidate,fixtures,output] = process.argv.slice(2);
  assert.ok(output, 'reference kernel, candidate kernel, fixtures, new output JSON');
  const children = [], kernels = [], pending = new Map();
  let nextId = 0;
  function request(child, fields) {
    return new Promise((resolve,reject) => { const id=nextId++; pending.set(id,{resolve,reject}); child.send({id,...fields}); });
  }
  try {
    for (const path of [reference,candidate,candidate]) {
      const child = fork(import.meta.filename,['--worker',path],{stdio:['ignore','inherit','inherit','ipc']});
      children.push(child);
      await new Promise((resolve,reject) => {
        child.on('error',reject);
        child.on('exit',code => { if(code) { const error=new Error(`benchmark worker exited ${code}`); reject(error); for(const p of pending.values())p.reject(error); } });
        child.on('message',message => {
          if(message.ready) { kernels.push(message.kernel); resolve(); return; }
          const p=pending.get(message.id); pending.delete(message.id);
          if(message.error)p.reject(new Error(message.error)); else p.resolve(message);
        });
      });
    }
    const cases=[];
    for(const [name,stem] of [['small','economy-1'],['install-64','install-64'],
      ['retained-search','source-queens-dfs'],['install-128','install-128'],['constant','constant-64k']]) {
      const images=await Promise.all(['bpi2','bpc1'].map(ext=>readFile(join(fixtures,`${stem}.${ext}`))));
      cases.push({name,images,base:{initialArgs:new Uint8Array()}});
    }
    const referenceHost=(await load(reference)).host, search=cases[2];
    let parked=await referenceHost.run({...search.base,image:search.images[0]});
    for(let n=0; parked.kind==='Yielded' && n<16; n++)parked=await referenceHost.run({image:search.images[0],state:parked.state});
    assert.equal(parked.kind,'Requested');
    cases.push({name:'saved-search-response',images:search.images,base:{state:parked.state,
      result:encodeResult(parked.request,Uint8Array.of(201,0,0,0,0,0,0,0))}});
    const rows=[], orders=[[0,1,2],[2,1,0],[1,2,0],[0,2,1],[2,0,1],[1,0,2]],batch=200,pairs=21;
    for(const {name,images,base} of cases) {
      const inputs=[images[0],images[0],images[1]].map(image=>({...base,image}));
      let expected;
      for(let side=0;side<3;side++) {
        const encoded=Object.fromEntries(Object.entries(inputs[side]).map(([key,value])=>[key,Buffer.from(value).toString('base64')]));
        const result=await request(children[side],{input:encoded,warmups:5*batch});
        assert.notEqual(result.kind,'NeedsCapacity');
        if(side===0)expected=result.hash; else assert.equal(result.hash,expected);
      }
      const samplesMs=[[],[],[]];
      for(let sample=0;sample<pairs;sample++)for(const side of orders[sample%6]) {
        const result=await request(children[side],{batch}); assert.equal(result.hash,expected);
        samplesMs[side].push(result.milliseconds);
      }
      const mediansMs=samplesMs.map(median), row={name,mediansMs,
        ratios:mediansMs.map(value=>value/mediansMs[0]),samplesMs,
        inputSha256:inputs.map(input=>hash(encodeInput({...input,mode:'run'}))),outputSha256:expected};
      rows.push(row); console.log(JSON.stringify({name,mediansMs,ratios:row.ratios}));
    }
    await writeFile(output,JSON.stringify({method:'Three independent Node processes; loaded hosts, fresh WASM instance every call; 5 warmup batches,21 rotating-order pairs,200 full calls per batch; IPC outside call timers',date:new Date().toISOString(),node:process.version,kernels,harnessSha256:hash(await readFile(import.meta.filename)),rows},null,2)+'\n',{flag:'wx'});
  } finally { for(const child of children)child.disconnect(); }
}
