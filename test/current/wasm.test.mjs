import assert from 'node:assert/strict';
import test from 'node:test';
import crypto from 'node:crypto';
import { syncBuiltinESMExports } from 'node:module';
import { runInNewContext } from 'node:vm';
import { inspectKernelWasm, MAXIMUM_KERNEL_BYTES, wasmRange, wasmOffset } from '../../src/embedding/wasm.mjs';
import { Kernel } from '../../src/embedding/kernel.mjs';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

import { kernel } from "./wasm_fixture.mjs";
const admit = (bytes, options) => Kernel.create({ bytes, ...options, instanceId: 1n });

test('layout sampler preserves every operation peak across resetting lifecycle calls', () => {
  const directory = mkdtempSync(join(tmpdir(), 'world-layout-peaks-'));
  try {
    // Independent reset-on-call model: later calls deliberately erase a larger
    // earlier observation. Real-kernel qualification supplies separate evidence.
    const embedding = join(directory, 'embedding.mjs');
    writeFileSync(embedding, `export class Kernel {
      static async create({bytes}) { return new Kernel(JSON.parse(Buffer.from(bytes))); }
      constructor(peaks) { this.peaks=peaks; this.live=0n; this.peak=0n; }
      setLimits() {}
      observe(operation,live) { this.peak=BigInt(this.peaks[operation]); this.live=BigInt(live); }
      prepare() { this.observe('prepare',10); return {}; }
      start() { this.observe('start',20); return {}; }
      drive() { this.observe('drive',20); return Buffer.from([42]); }
      invoke() { this.observe('invoke',0); return Buffer.from([42]); }
      close() { this.observe('close',10); }
      releasePrepared() { this.observe('release',0); }
      usage() { return {workingLive:this.live,workingPeak:this.peak}; }
    }`);
    const image = join(directory, 'image'), input = join(directory, 'input');
    const initialArgs = join(directory, 'args'), kernelPath = join(directory, 'kernel');
    for (const path of [image, input, initialArgs]) writeFileSync(path, Buffer.alloc(1));
    const expected = crypto.createHash('sha256').update(Buffer.from([42])).digest('hex');
    const sampler = fileURLToPath(new URL('./frame_layout_qualification.mjs', import.meta.url));
    for (const phase of ['admission', 'resident', 'fresh']) {
      const operations = phase === 'admission' ? ['prepare', 'release'] :
        phase === 'resident' ? ['prepare', 'start', 'drive', 'close', 'release'] : ['invoke'];
      for (const largest of operations) {
        const peaks = {prepare:100, start:200, drive:300, invoke:400, close:20, release:10};
        peaks[largest] = 900;
        writeFileSync(kernelPath, JSON.stringify(peaks));
        const result = JSON.parse(execFileSync(process.execPath,
          [sampler, 'sample', embedding, kernelPath, image, input, phase, expected, initialArgs],
          {encoding:'utf8'}));
        assert.equal(result.peakBytes, 900, `${phase}: preserve ${largest} peak`);
        assert.equal(result.retainedBytes, phase === 'fresh' ? 0 : 10);
        assert.equal(result.samplesNs.length, 9);
      }
    }
  } finally { rmSync(directory, {recursive:true, force:true}); }
});

test('blob lifecycle and alias samplers preserve each peak before cleanup resets it', () => {
  const directory=mkdtempSync(join(tmpdir(),'world-blob-peaks-'));
  try {
    const embedding=join(directory,'embedding.mjs'),kernelPath=join(directory,'kernel');
    writeFileSync(embedding, `
const encoded=(kind,value)=>{const bytes=Buffer.alloc(8);bytes.writeBigUInt64LE(BigInt(value));return Buffer.from(JSON.stringify({kind,value:Array.from(bytes)}));};
export const encodeInput=()=>Buffer.alloc(1);
export const decodeOutcome=bytes=>{const out=JSON.parse(Buffer.from(bytes));out.value=Buffer.from(out.value);return out;};
export class Kernel {
 static async create({bytes}){return new Kernel(JSON.parse(Buffer.from(bytes)));}
 constructor({largest,value}){this.largest=largest;this.value=value;this.live=0n;this.peak=0n;}
 setLimits(){}
 observe(name,live){this.peak=BigInt(name===this.largest?900:10);this.live=BigInt(live);}
 prepare(){this.observe('prepare',10);return {};}
 start(){this.step=0;this.observe('start',20);return {};}
 drive(){this.observe('drive'+(++this.step),20);return encoded(this.step===1?'progressed':'completed',this.value);}
 invoke(){this.observe('invoke',0);return encoded('completed',this.value);}
 close(){this.observe('close',10);}
 releasePrepared(){this.observe('release',0);}
 usage(){return {workingLive:this.live,workingPeak:this.peak,memoryBytes:1024};}
}`);
    for(const name of ['unique.bpi3','unique-0.args','1.bpi3','1.args'])writeFileSync(join(directory,name),Buffer.alloc(1));
    const phases=['prepare','start','drive1','drive2','close','release'];
    for(const phase of ['fresh','resident-lifecycle'])for(const largest of phase==='fresh'?['invoke']:phases){
      writeFileSync(kernelPath,JSON.stringify({largest,value:0}));
      const script=fileURLToPath(new URL('./blob_retention_timing.mjs',import.meta.url));
      const result=JSON.parse(execFileSync(process.execPath,[script,'sample',embedding,kernelPath,directory,'unique','0',phase,'memory'],{encoding:'utf8'}));
      assert.equal(result.peakBytes,900,phase+': '+largest);
    }
    for(const largest of phases){
      writeFileSync(kernelPath,JSON.stringify({largest,value:65536}));
      const script=fileURLToPath(new URL('./blob_alias_scaling.mjs',import.meta.url));
      const result=JSON.parse(execFileSync(process.execPath,[script,'sample',embedding,kernelPath,directory,'1','complete'],{encoding:'utf8'}));
      assert.equal(result.peakBytes,900,'alias: '+largest);assert.equal(result.samplesNs.length,9);
    }
  }finally{rmSync(directory,{recursive:true,force:true});}
});

test('retained lifecycle sampler observes failed commands and cleanup before peak reset', () => {
  const directory = mkdtempSync(join(tmpdir(), 'world-retained-peaks-'));
  try {
    const embedding=join(directory,'embedding.mjs'),kernelPath=join(directory,'kernel'),image=join(directory,'image'),record=join(directory,'record.json');
    writeFileSync(image,Buffer.from([1]));
    // An independent command model makes any selected phase the sole peak.
    // Rejection throws after its observation, and close/release reset the peak.
    writeFileSync(embedding,`const output=kind=>Buffer.from(JSON.stringify({kind,request:[]}));
export const decodeOutcome=bytes=>JSON.parse(Buffer.from(bytes));
export const decodeRequest=async()=>({requestIdentity:new Uint8Array(32)});
export class Kernel {
  static async create({bytes}){return new Kernel(JSON.parse(Buffer.from(bytes)));}
  constructor({mode,largest}){this.mode=mode;this.largest=largest;this.live=0n;this.peak=0n;}
  setLimits(){}
  observe(name,live){this.peak=BigInt(name===this.largest?900:10);this.live=BigInt(live);}
  prepare(){this.observe('prepare',10);return {};}
  start(){this.calls=0;this.replies=0;this.observe('start',20);return {};}
  drive(_session,options={}){
    if(options.control==='cancel_text'){this.observe('cancel',20);return output('cancelled');}
    if(options.control==='reply'){
      const n=this.replies++;this.observe(n<3?'reject-'+n:'valid-reply',20);
      if(n<3)throw Object.assign(new Error('rejected'),{code:'REJECT_'+n});
      return output('progressed');
    }
    const n=this.calls++;this.observe(n===0?'initial':'drive-'+(n-1),20);
    return output(n===0?(this.mode==='H'?'yielded':'requested'):'progressed');
  }
  checkpoint(){this.observe('checkpoint',20);return Buffer.from([3]);}
  close(){this.observe('close',10);}
  releasePrepared(){this.observe('release',0);}
  usage(){return {workingLive:this.live,workingPeak:this.peak,memoryBytes:1024};}
}`);
    const sampler=fileURLToPath(new URL('./retained_history_wasm.mjs',import.meta.url));
    for(const mode of ['H','Q']) {
      const phases=['prepare','start','initial',...(mode==='H'?['drive-0','drive-63','checkpoint']:['reject-0','reject-1','reject-2','valid-reply']),'cancel','close','release'];
      for(const largest of phases){
        writeFileSync(kernelPath,JSON.stringify({mode,largest}));
        const result=JSON.parse(execFileSync(process.execPath,[sampler,'freeze',embedding,kernelPath,image,mode,'1',record],{encoding:'utf8'}));
        assert.equal(result.peakBytes,900,mode+': preserve '+largest+' peak');
        const memory=JSON.parse(readFileSync(record)).baselineMemory;
        assert.equal(memory.phases.at(-1).live,0);
        assert(memory.phases.some(p=>p.name===largest && p.peak===900));
      }
    }
  } finally { rmSync(directory,{recursive:true,force:true}); }
});

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

test('kernel factory checks identity before compilation and ABI before instantiation', async (t) => {
  const bytes = kernel();
  t.mock.method(WebAssembly, 'compile', () => assert.fail('identity mismatch must not compile'));
  await assert.rejects(admit(bytes, { expectedSha256: '0'.repeat(64) }), { code: 'WORLD_KERNEL_IDENTITY_INVALID' });
  t.mock.restoreAll();
  t.mock.method(WebAssembly, 'instantiate', () => assert.fail('rejected kernel must not instantiate'));
  for (const change of [{wrongType:true},{extraExport:true},{missingExport:true},{imports:true},{start:true},{shared:true}]) {
    const input = kernel(change);
    await assert.rejects(admit(input, { expectedSha256: crypto.createHash('sha256').update(input).digest('hex') }), { name: 'WorldHostError' });
  }
});

test('kernel compilation owns its bytes across asynchronous suspension', async (t) => {
  const bytes = kernel({ outcome: Uint8Array.of(51, 52) });
  const expectedSha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  const compile = WebAssembly.compile.bind(WebAssembly);
  t.mock.method(WebAssembly, 'compile', async input => {
    assert.notStrictEqual(input, bytes);
    const result = compile(input);
    bytes.fill(0xff);
    await Promise.resolve();
    return result;
  });
  assert.ok(await admit(bytes, { expectedSha256 }) instanceof Kernel);
  assert.ok(bytes.every(byte => byte === 0xff));
});

test('kernel compilation rejects invalid function bodies without instantiation', async (t) => {
  const bytes = kernel();
  bytes[bytes.length - 1] = 0xff;
  assert.equal(WebAssembly.validate(bytes), false);
  t.mock.method(WebAssembly, 'instantiate', () => assert.fail('invalid code must not instantiate'));
  await assert.rejects(admit(bytes, { expectedSha256: crypto.createHash('sha256').update(bytes).digest('hex') }), { code: 'WORLD_KERNEL_WASM_INVALID' });
});

test('cached code rechecks identity and creates independent guest instances', async (t) => {
  const firstBytes = kernel({ outcome: Uint8Array.of(91, 92) });
  const secondBytes = kernel({ outcome: Uint8Array.of(81, 82) });
  const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
  const compile = WebAssembly.compile.bind(WebAssembly);
  let compilations = 0;
  const memories = [], instantiate = WebAssembly.instantiate.bind(WebAssembly);
  t.mock.method(WebAssembly, 'instantiate', async (...args) => { const result = await instantiate(...args); memories.push(result.exports.memory); return result; });
  t.mock.method(WebAssembly, 'compile', async bytes => { compilations++; return compile(bytes); });
  const first = await admit(firstBytes, { expectedSha256: digest(firstBytes) });
  const second = await admit(firstBytes, { expectedSha256: digest(firstBytes) });
  assert.equal(compilations, 1);
  assert.equal(memories.length, 2);
  assert.notStrictEqual(memories[0], memories[1]);
  first.setLimits({ input: 1, working: 1, output: 1 });
  assert.deepEqual(first.invoke(new Uint8Array()), Uint8Array.of(91, 92));
  assert.deepEqual(second.invoke(new Uint8Array()), Uint8Array.of(91, 92));
  await assert.rejects(admit(secondBytes, { expectedSha256: digest(firstBytes) }), { code: 'WORLD_KERNEL_IDENTITY_INVALID' });
  const different = await admit(secondBytes, { expectedSha256: digest(secondBytes) });
  assert.deepEqual(different.invoke(new Uint8Array()), Uint8Array.of(81, 82));
  assert.equal(compilations, 2);
});

test('a collected module or missing WeakRef safely recompiles', async (t) => {
  const bytes = kernel({ outcome: Uint8Array.of(73, 74) });
  const expectedSha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  const compile = WebAssembly.compile.bind(WebAssembly);
  let count = 0;
  t.mock.method(WebAssembly, 'compile', async input => { count++; return compile(input); });
  const original = globalThis.WeakRef;
  try {
    globalThis.WeakRef = class { constructor() {} deref() { return undefined; } };
    await admit(bytes, { expectedSha256 });
    await admit(bytes, { expectedSha256 });
    assert.equal(count, 2);
    globalThis.WeakRef = undefined;
    await admit(bytes, { expectedSha256 });
    await admit(bytes, { expectedSha256 });
    assert.equal(count, 4);
  } finally { globalThis.WeakRef = original; }
});

test('concurrent admission keeps different kernel identities separate', async () => {
  const inputs = [kernel({outcome:Uint8Array.of(61)}), kernel({outcome:Uint8Array.of(62)})];
  const hosts = await Promise.all(inputs.map(bytes => admit(bytes, { expectedSha256: crypto.createHash('sha256').update(bytes).digest('hex') })));
  assert.deepEqual(hosts[0].invoke(new Uint8Array()), Uint8Array.of(61));
  assert.deepEqual(hosts[1].invoke(new Uint8Array()), Uint8Array.of(62));
});
