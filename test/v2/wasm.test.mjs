import assert from 'node:assert/strict';
import test from 'node:test';
import { inspectProcessKernelWasm, wasmRange, wasmOffset } from '../../src/process_v2/wasm.mjs';

import { kernel } from "./wasm_fixture.mjs";

test('static ABI admission accepts the exact interface and rejects altered types, imports and names',()=>{
  const valid=kernel();assert.ok(WebAssembly.validate(valid));
  const admitted=inspectProcessKernelWasm(valid);
  assert.equal(admitted.importCount,0);assert.equal(admitted.exportCount,10);
  for(const change of [{wrongType:true},{extraExport:true},{missingExport:true},{imports:true},{start:true},{shared:true},
    {rename:(name)=>name==='memory'?'\uFEFFmemory':name},
    {rename:(name)=>name==='world_process_v2_execute'?'\uFEFFworld_process_v2_execute':name}]) {
    const bytes=kernel(change);assert.ok(WebAssembly.validate(bytes),'negative fixture must be structurally valid WASM');
    assert.throws(()=>inspectProcessKernelWasm(bytes),{name:'WorldProcessHostError'});
  }
});

test('guest ranges require exact unsigned offsets and complete memory containment',()=>{
  const memory=new WebAssembly.Memory({initial:1,maximum:1});
  assert.equal(wasmRange(memory,65535,1n,'value').length,1);
  assert.equal(wasmOffset(-1,'pointer'),0xffffffff);
  for(const [pointer,length] of [[65535,2n],[-1,1n],[0,-1n],[0,1n<<64n],[1.5,1n]]) {
    assert.throws(()=>wasmRange(memory,pointer,length,'value'),{name:'WorldProcessHostError'});
  }
});
