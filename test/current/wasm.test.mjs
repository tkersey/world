import assert from 'node:assert/strict';
import test from 'node:test';
import crypto from 'node:crypto';
import { syncBuiltinESMExports } from 'node:module';
import { runInNewContext } from 'node:vm';
import { inspectKernelWasm, MAXIMUM_KERNEL_BYTES, wasmRange, wasmOffset } from '../../src/embedding/wasm.mjs';
import { Kernel } from '../../src/embedding/kernel.mjs';

import { kernel } from "./wasm_fixture.mjs";
const admit = (bytes, options) => Kernel.create({ bytes, ...options, instanceId: 1n });

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
    await assert.rejects(admit(input, { expectedSha256: '0'.repeat(64) }), { name: 'RangeError' });
  } finally { t.mock.restoreAll(); syncBuiltinESMExports(); }
});

test('kernel snapshots preserve Buffer and Uint8Array views without invoking iterators', async () => {
  const bytes = kernel();
  const expectedSha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  const backing = new Uint8Array(bytes.length + 2);
  backing.set(bytes, 1);
  for (const input of [backing.subarray(1, -1), Buffer.from(backing.buffer, 1, bytes.length)]) {
    input[Symbol.iterator] = () => assert.fail('kernel admission must copy the byte view');
    assert.ok(await admit(input, { expectedSha256 }) instanceof Kernel);
  }
});

test('kernel admission preserves the cross-realm Uint8Array domain', async () => {
  const bytes = kernel();
  const foreign = runInNewContext('Uint8Array.from(values)', { values: [...bytes] });
  const expectedSha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  assert.deepEqual(inspectKernelWasm(foreign), inspectKernelWasm(bytes));
  assert.ok(await admit(foreign, { expectedSha256 }) instanceof Kernel);
  await assert.rejects(admit(Object.create(Uint8Array.prototype), { expectedSha256 }),
    /expected Uint8Array/);
});

test('static ABI admission accepts the exact interface and rejects altered types, imports and names',()=>{
  const valid=kernel();assert.ok(WebAssembly.validate(valid));
  const admitted=inspectKernelWasm(valid);
  assert.equal(admitted.importCount,0);assert.equal(admitted.exportCount,23);
  for(const change of [{wrongType:true},{extraExport:true},{missingExport:true},{imports:true},{start:true},{shared:true},
    {rename:(name)=>name==='memory'?'\uFEFFmemory':name},
    {rename:(name)=>name==='world_invoke'?'\uFEFFworld_invoke':name}]) {
    const bytes=kernel(change);assert.ok(WebAssembly.validate(bytes),'negative fixture must be structurally valid WASM');
    assert.throws(()=>inspectKernelWasm(bytes),{name:'WorldHostError'});
  }
});

test('guest ranges require exact unsigned offsets and complete memory containment',()=>{
  const memory=new WebAssembly.Memory({initial:1,maximum:1});
  assert.equal(wasmRange(memory,65535,1n,'value').length,1);
  assert.equal(wasmOffset(-1,'pointer'),0xffffffff);
  for(const [pointer,length] of [[65535,2n],[-1,1n],[0,-1n],[0,1n<<64n],[1.5,1n]]) {
    assert.throws(()=>wasmRange(memory,pointer,length,'value'),{name:'WorldHostError'});
  }
});
