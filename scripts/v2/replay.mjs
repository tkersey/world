// The caller authenticates and extracts the archive before starting this fresh
// process. The package is imported only here, after that outer verification.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join,resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { wasmtimePeer } from '../../test/v2/wasmtime_peer.mjs';
import { sha256,readBundle } from './assets.mjs';
const [runtimeArg,conformanceArg,projectArg,expectedKernel]=process.argv.slice(2);
if(process.argv.length!==6)throw new Error('expected authenticated runtime, conformance directory, Wasmtime project and kernel digest');
const runtime=resolve(runtimeArg),conformance=JSON.parse(await readFile(join(conformanceArg,'world-v2-conformance.json')));
assert.equal(conformance.kernelSha256,expectedKernel);
const binary=await readFile(join(conformanceArg,'world-v2-conformance.bin'));assert.equal(sha256(binary),conformance.binarySha256);
const files=readBundle(conformance,binary);
const api=await import(pathToFileURL(join(runtime,'src/process_v2/index.mjs')));
const host=await api.loadProcessKernel({expectedSha256:expectedKernel});
const kernel=await readFile(join(runtime,'world-process-kernel-v2.wasm'));
assert.equal(sha256(kernel),expectedKernel);
const peer=await wasmtimePeer(projectArg,join(runtime,'world-process-kernel-v2.wasm'),expectedKernel);
// Decode only the PKI2 envelope here; all Program and State admission remains
// in the generic guest. This framing logic is independent of the package codec.
function input(record) {
  assert.equal(record.subarray(0,8).toString(),'ABL_PKI2');
  assert.equal(record.readUInt16LE(8),2);assert.equal(record.readUInt16LE(10),0);assert.equal(record.readBigUInt64LE(12),BigInt(record.length-20));
  let offset=20;
  const nat=()=>{let value=0n;for(let index=0;index<10;index++){const byte=record[offset++];assert.ok(byte!==undefined);value|=BigInt(byte&127)<<BigInt(index*7);if(!(byte&128))return Number(value);}throw new Error('invalid PKI2 integer');};
  const field=()=>{const length=nat();assert.ok(Number.isSafeInteger(length)&&length<=record.length-offset);const bytes=record.subarray(offset,offset+length);offset+=length;return bytes;};
  const mode=nat();assert.ok(mode===0||mode===1);
  const value={image:field()},instance=nat();assert.ok(instance===0||instance===1);
  value[instance?'state':'initialArgs']=field();
  const control=nat();assert.ok(control===0||control===1);
  if(control){const reason=nat();assert.ok(reason===0||reason===1);const bytes=field();value.cancel=reason?bytes:new TextDecoder('utf-8',{fatal:true,ignoreBOM:true}).decode(bytes);}
  else {const present=nat();assert.ok(present===0||present===1);if(present)value.result=field();}
  assert.equal(offset,record.length);return {mode:mode?'run':'advance',value};
}
try {
  for(const check of conformance.checks) {
    const encoded=files.get(check.input),decoded=input(encoded);assert.equal(decoded.mode,check.mode);
    if(check.rejection) {
      await assert.rejects(host[decoded.mode](decoded.value),(error)=>error.message===check.rejection);
      await assert.rejects(peer.invoke(encoded),(error)=>error.message===check.rejection);
    } else {
      const expected=files.get(check.output);
      assert.deepEqual(Buffer.from((await host[decoded.mode](decoded.value)).bytes),expected);
      assert.deepEqual(Buffer.from(await peer.invoke(encoded)),expected);
    }
  }
  console.log(`authenticated runtime replayed ${conformance.checks.length} canonical record checks in both WASM embeddings`);
} finally {await peer.close();}
