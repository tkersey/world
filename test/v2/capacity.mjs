import assert from 'node:assert/strict';
import { readFile,writeFile,mkdir } from 'node:fs/promises';
import { resolve,join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { admitProcessKernel,encodeInput,decodeOutcome,encodeResult } from '../../src/process_v2/index.mjs';
import { inspectProcessKernelWasm,wasmRange } from '../../src/process_v2/wasm.mjs';
import { sha256,json } from '../../scripts/v2/assets.mjs';
const [boundaryArg,fixturesArg,normalKernelArg,outputArg]=process.argv.slice(2);
if(process.argv.length!==6)throw new Error('expected Boundary source, fixtures, normal kernel and output directory');
const root=resolve(import.meta.dirname,'../..'),boundary=resolve(boundaryArg),fixtures=resolve(fixturesArg),output=resolve(outputArg);
await mkdir(output,{recursive:true});
const image=await readFile(join(fixtures,'capacity.bpi2'));
const initialArgs=new Uint8Array(65539).fill(0x5a);initialArgs.set([0x80,0x80,0x04]);
const input={image,initialArgs},encoded=encodeInput({...input,mode:'run'}),inputHash=sha256(encoded);
const normalBytes=await readFile(normalKernelArg),normal=await admitProcessKernel(normalBytes,{expectedSha256:sha256(normalBytes)});
const expected=await normal.run(input);assert.equal(expected.kind,'Requested');assert.ok(expected.bytes.length>65536);
const response=encodeResult(expected.request,new Uint8Array());
const resumed={image,state:expected.state,result:response};
const completed=await normal.run(resumed);
assert.equal(completed.kind,'Completed');assert.deepEqual(completed.value,initialArgs);
await writeFile(join(output,'normal.wasm'),normalBytes);
await writeFile(join(output,'capacity.bpi2'),image);
await writeFile(join(output,'normal-0.pki2'),encoded);
await writeFile(join(output,'normal-0.pko2'),expected.bytes);
await writeFile(join(output,'normal-1.pki2'),encodeInput({...resumed,mode:'run'}));
await writeFile(join(output,'normal-1.pko2'),completed.bytes);
const rows=[];
for(const [arena,capacities] of [['input',[1,1048576,65536]],['working',[262144,1,65536]],['output',[262144,1048576,1]]]) {
  const prefix=join(output,arena);
  const options=[`-Dv2-input-capacity=${capacities[0]}`,`-Dv2-working-capacity=${capacities[1]}`,`-Dv2-output-capacity=${capacities[2]}`];
  function build(maximum) {
    const result=spawnSync('zig',['build','build-v2-kernel',`-Dboundary-v2-source=${boundary}`,...options,
      ...(maximum?[`-Dv2-maximum-memory=${maximum}`]:[]),'--cache-dir',join(output,'local'),'--global-cache-dir',join(output,'global'),'--prefix',prefix],
      {cwd:root,maxBuffer:16<<20,timeout:180000});
    assert.equal(result.status,0,result.stderr.toString());
  }
  build();
  const unrestricted=await readFile(join(prefix,'world-process-kernel-v2.wasm'));
  await writeFile(join(output,`${arena}-retry.wasm`),unrestricted);
  const minimum=inspectProcessKernelWasm(unrestricted).memory.initialPages;
  build(minimum*65536);
  const limited=await readFile(join(prefix,'world-process-kernel-v2.wasm'));
  const inspection=inspectProcessKernelWasm(limited);assert.equal(inspection.memory.maximumPages,minimum);
  const module=await WebAssembly.compile(limited),{exports:e}=await WebAssembly.instantiate(module,{});
  assert.equal(e.world_process_v2_input_ptr()%16,0);
  const prepared=e.world_process_v2_prepare_input(BigInt(encoded.length));
  let executed=null;
  if(arena==='input')assert.equal(prepared,1);
  else {
    assert.equal(prepared,0);
    const destination=wasmRange(e.memory,e.world_process_v2_input_ptr(),BigInt(encoded.length),'input');destination.set(encoded);
    executed=e.world_process_v2_execute(BigInt(encoded.length));
    assert.equal(executed,0);
    assert.deepEqual(wasmRange(e.memory,e.world_process_v2_input_ptr(),BigInt(encoded.length),'input'),encoded,'guest must preserve input bytes');
  }
  const pko=wasmRange(e.memory,e.world_process_v2_output_ptr(),e.world_process_v2_output_len(),'output').slice();
  await writeFile(join(prefix,'invocation.pki2'),encoded);
  await writeFile(join(prefix,'capacity.pko2'),pko);
  await writeFile(join(prefix,'caller-input-after.bin'),encoded);
  if(arena!=='input')await writeFile(join(prefix,'input-after.bin'),
    wasmRange(e.memory,e.world_process_v2_input_ptr(),BigInt(encoded.length),'input'));
  const outcome=decodeOutcome(pko);assert.equal(outcome.kind,'NeedsCapacity');assert.equal(outcome.arena,arena);
  assert.equal(outcome.state,undefined);assert.equal(outcome.memoryPages.provenance,'lower_bound');assert.ok(outcome.memoryPages.minimum>BigInt(minimum));
  assert.equal(outcome[arena].provenance,arena==='working'?'lower_bound':'exact');
  if(arena==='input')assert.equal(outcome.input.minimum,BigInt(encoded.length));
  if(arena==='output')assert.equal(outcome.output.minimum,BigInt(expected.bytes.length));
  assert.equal(sha256(encoded),inputHash);
  const hostedRetry=await (await admitProcessKernel(unrestricted,{expectedSha256:sha256(unrestricted)})).run(input);
  assert.deepEqual(hostedRetry.bytes,expected.bytes);
  const {exports:retry}=await WebAssembly.instantiate(await WebAssembly.compile(unrestricted),{});
  const retryPrepared=retry.world_process_v2_prepare_input(BigInt(encoded.length));
  assert.equal(retryPrepared,0);
  wasmRange(retry.memory,retry.world_process_v2_input_ptr(),BigInt(encoded.length),'retry input').set(encoded);
  const retryInput=wasmRange(retry.memory,retry.world_process_v2_input_ptr(),BigInt(encoded.length),'retry input').slice();
  const retryExecuted=retry.world_process_v2_execute(BigInt(encoded.length));
  assert.equal(retryExecuted,0);
  const retryBytes=wasmRange(retry.memory,retry.world_process_v2_output_ptr(),retry.world_process_v2_output_len(),'retry output').slice();
  const retryInputAfter=wasmRange(retry.memory,retry.world_process_v2_input_ptr(),BigInt(encoded.length),'retry input').slice();
  assert.deepEqual(retryBytes,expected.bytes);
  assert.deepEqual(retryInput,encoded);
  assert.deepEqual(retryInputAfter,retryInput);
  await writeFile(join(prefix,'retry.pki2'),retryInput);
  await writeFile(join(prefix,'retry.pko2'),retryBytes);
  await writeFile(join(prefix,'retry-input-after.bin'),retryInputAfter);
  const retried=decodeOutcome(retryBytes);
  assert.equal(retried.kind,'Requested');
  const finishInput=encodeInput({image,state:retried.state,result:encodeResult(retried.request,new Uint8Array()),mode:'run'});
  const finishPrepared=retry.world_process_v2_prepare_input(BigInt(finishInput.length));
  assert.equal(finishPrepared,0);
  wasmRange(retry.memory,retry.world_process_v2_input_ptr(),BigInt(finishInput.length),'retry continuation input').set(finishInput);
  const finishInstalled=wasmRange(retry.memory,retry.world_process_v2_input_ptr(),BigInt(finishInput.length),'retry continuation input').slice();
  assert.deepEqual(finishInstalled,finishInput);
  const finishExecuted=retry.world_process_v2_execute(BigInt(finishInput.length));
  assert.equal(finishExecuted,0);
  const finishBytes=wasmRange(retry.memory,retry.world_process_v2_output_ptr(),retry.world_process_v2_output_len(),'retry completion').slice();
  const finishInputAfter=wasmRange(retry.memory,retry.world_process_v2_input_ptr(),BigInt(finishInput.length),'retry continuation input').slice();
  assert.deepEqual(finishInputAfter,finishInput);
  assert.deepEqual(finishBytes,completed.bytes);
  assert.equal(decodeOutcome(finishBytes).kind,'Completed');
  await writeFile(join(prefix,'retry-continuation.pki2'),finishInstalled);
  await writeFile(join(prefix,'retry-completion.pko2'),finishBytes);
  await writeFile(join(prefix,'retry-continuation-input-after.bin'),finishInputAfter);
  // A rejected ABI call clears any previous outcome and cannot forge capacity.
  assert.equal(e.world_process_v2_prepare_input((1n<<64n)-1n),2);
  assert.equal(e.world_process_v2_output_len(),0n);
  assert.equal(e.world_process_v2_execute(0n),2);
  assert.equal(e.world_process_v2_output_len(),0n);
  rows.push({arena,initialReservations:capacities,memory:inspection.memory,kernelSha256:sha256(limited),inputSha256:inputHash,
    capacity:outcome,retryKernelSha256:sha256(unrestricted),retryOutcomeSha256:sha256(retryBytes),
    prepareStatus:prepared,executeStatus:executed,inputInstalled:arena!=='input',input:join(prefix,'invocation.pki2'),
    callerInputAfter:join(prefix,'caller-input-after.bin'),
    output:join(prefix,'capacity.pko2'),inputAfter:arena==='input'?null:join(prefix,'input-after.bin'),
    retryPrepareStatus:retryPrepared,retryExecuteStatus:retryExecuted,
    retryInput:join(prefix,'retry.pki2'),retryInputAfter:join(prefix,'retry-input-after.bin'),
    followups:[{input:join(prefix,'retry-continuation.pki2'),output:join(prefix,'retry-completion.pko2'),
      inputAfter:join(prefix,'retry-continuation-input-after.bin'),prepareStatus:finishPrepared,executeStatus:finishExecuted}],
    retryOutput:join(prefix,'retry.pko2'),kernel:join(prefix,'world-process-kernel-v2.wasm'),
    retryKernel:join(output,`${arena}-retry.wasm`)});
}
const normalExecution={image:join(output,'capacity.bpi2'),records:[
  {input:join(output,'normal-0.pki2'),output:join(output,'normal-0.pko2')},
  {input:join(output,'normal-1.pki2'),output:join(output,'normal-1.pko2')},
]};
await writeFile(join(output,'capacity.json'),JSON.stringify({format:'world-v2-transactional-capacity/v1',normalKernelSha256:normal.sha256,normalExecution,rows},(_,value)=>typeof value==='bigint'?value.toString():value,2)+'\n');
console.log('input, working and output exhaustion published no State; unchanged retries matched the unconstrained record');
