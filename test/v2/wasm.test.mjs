import assert from 'node:assert/strict';
import test from 'node:test';
import crypto from 'node:crypto';
import { syncBuiltinESMExports } from 'node:module';
import { runInNewContext } from 'node:vm';
import { inspectProcessKernelWasm, MAXIMUM_KERNEL_BYTES, wasmRange, wasmOffset } from '../../src/process_v2/wasm.mjs';
import { admitProcessKernel } from '../../src/process_v2/index.mjs';

import { kernel } from "./wasm_fixture.mjs";

test('oversized kernel bytes reject before copying or hashing', async (t) => {
  const input = new Uint8Array(MAXIMUM_KERNEL_BYTES + 1);
  Object.defineProperty(input, 'byteLength', { value: 0 });
  try {
    t.mock.method(globalThis, 'Uint8Array', new Proxy(Uint8Array, {
      construct: () => assert.fail('oversized kernel must not be copied'),
      get: (target, key) => key === 'from' ? () => assert.fail('oversized kernel must not be copied') : Reflect.get(target, key),
    }));
    t.mock.method(crypto, 'createHash', () => assert.fail('oversized kernel must not be hashed'));
    syncBuiltinESMExports();
    await assert.rejects(admitProcessKernel(input, { expectedSha256: '0'.repeat(64) }), { code: 'WORLD_KERNEL_TOO_LARGE' });
  } finally { t.mock.restoreAll(); syncBuiltinESMExports(); }
});

test('kernel snapshots preserve Buffer and Uint8Array views without invoking iterators', async () => {
  const bytes = kernel();
  const expectedSha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  const backing = new Uint8Array(bytes.length + 2);
  backing.set(bytes, 1);
  for (const input of [backing.subarray(1, -1), Buffer.from(backing.buffer, 1, bytes.length)]) {
    input[Symbol.iterator] = () => assert.fail('kernel admission must copy the byte view');
    assert.equal((await admitProcessKernel(input, { expectedSha256 })).sha256, expectedSha256);
  }
});

test('kernel admission preserves the cross-realm Uint8Array domain', async () => {
  const bytes = kernel();
  const foreign = runInNewContext('Uint8Array.from(values)', { values: [...bytes] });
  const expectedSha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  assert.deepEqual(inspectProcessKernelWasm(foreign), inspectProcessKernelWasm(bytes));
  assert.equal((await admitProcessKernel(foreign, { expectedSha256 })).sha256, expectedSha256);
  await assert.rejects(admitProcessKernel(Object.create(Uint8Array.prototype), { expectedSha256 }),
    /kernel must be bytes/);
});

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
