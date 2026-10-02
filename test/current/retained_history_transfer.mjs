// Cross-version, cross-engine, and fresh-process transfer of the H/Q witnesses.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import * as world from '../../src/embedding/index.mjs';
import {frame,concat,field} from '../../src/embedding/wire.mjs';
import {wasmtimePeer} from './peer.mjs';
const hash=b=>createHash('sha256').update(b).digest('hex');
const args=process.argv.slice(2);
const load=async path=>{const bytes=readFileSync(path),k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});k.setLimits({input:2<<20,working:8<<20,output:2<<20});return k;};
const argumentsFor=depth=>{const b=Buffer.alloc(16);b.writeBigUInt64LE(BigInt(depth));b.writeBigUInt64LE(17n,8);return b;};
if(args[0]==='produce') {
  const [,kernelPath,imagePath,depth]=args,k=await load(kernelPath),p=k.prepare(readFileSync(imagePath)),s=k.start(p,argumentsFor(depth));
  const output=k.drive(s,{checkpoint:true}),state=k.checkpoint(s,{transfer:true});k.releasePrepared(p);
  assert.equal(k.usage().workingLive,0n);
  process.stdout.write(JSON.stringify({output:Buffer.from(output).toString('base64'),state:Buffer.from(state).toString('base64')}));
} else {
  const [beforeKernel,afterKernel,beforeNative,afterNative,corpus,reportPath]=args;assert.equal(args.length,6);
  const kernels={before:beforeKernel,after:afterKernel},natives={before:beforeNative,after:afterNative};
  const peers={};for(const [name,path]of Object.entries(kernels))peers[name]=await wasmtimePeer(path,hash(readFileSync(path)));
  const scratch=mkdtempSync(join(tmpdir(),'world-retained-transfer-')),rows=[];
  try {
    for(const mode of ['H','Q'])for(const depth of [1,64,1024])for(const source of ['before','after']) {
      const target=source==='before'?'after':'before',imagePath=join(corpus,mode+'.bpi3'),image=readFileSync(imagePath);
      // execFileSync returns only after the original owning process has exited.
      const produced=JSON.parse(execFileSync(process.execPath,[fileURLToPath(import.meta.url),'produce',kernels[source],imagePath,String(depth)],{encoding:'utf8'}));
      const initialOutput=Buffer.from(produced.output,'base64'),state=Buffer.from(produced.state,'base64'),inputPath=join(scratch,'input.pki3');
      writeFileSync(inputPath,world.encodeInput({image,initialArgs:argumentsFor(depth)}));
      assert.deepEqual(execFileSync(natives[source],[inputPath]),initialOutput);
      const initial=world.decodeOutcome(initialOutput);assert.equal(initial.kind,mode==='H'?'yielded':'requested');assert.deepEqual(Buffer.from(initial.state),state);
      const value=mode==='Q'?await world.encodeResult(initial.request,argumentsFor(0).subarray(8)):new Uint8Array();
      const control=mode==='Q'?'reply':'resume_yield',command=world.encodeInput({image,state,control,value,quantum:1n});
      writeFileSync(inputPath,command);
      const expected=execFileSync(natives.before,[inputPath]);assert.deepEqual(execFileSync(natives.after,[inputPath]),expected);
      const k=await load(kernels[target]),p=k.prepare(image),s=k.restore(p,state);k.releasePrepared(p);
      const peer=peers[target],prepared=await peer.call('prepare',{bytes:image}),session=await peer.call('restore',{handle:prepared.prepared,bytes:state});
      await peer.call('release_prepared',{handle:prepared.prepared});
      if(mode==='Q') {
        const request=await world.decodeRequest(initial.request),wrong=new Uint8Array(request.requestIdentity);wrong[0]^=1;
        const invalid=frame('ABL_ERS3',concat(wrong,field(argumentsFor(0).subarray(8))));
        assert.throws(()=>k.drive(s,{control:'reply',value:invalid}),e=>e.details?.diagnostic==='InvalidResult');
        await assert.rejects(peer.call('drive',{handle:session.session,control:1,bytes:invalid}),/InvalidResult/);
        assert.deepEqual(Buffer.from(k.checkpoint(s)),state);
        assert.deepEqual(Buffer.from((await peer.call('checkpoint',{handle:session.session})).bytes),state);
      }
      const actual=k.drive(s,{control,value,quantum:1n,checkpoint:true});
      const independent=await peer.call('drive',{handle:session.session,control:mode==='Q'?1:2,bytes:value,quantum:1,checkpoint:true});
      assert.deepEqual(Buffer.from(actual),expected);assert.deepEqual(Buffer.from(independent.bytes),expected);
      const cancelled=k.drive(s,{control:'cancel_text',value:'transfer complete'});
      const peerCancelled=await peer.call('drive',{handle:session.session,control:3,bytes:Buffer.from('transfer complete')});
      assert.deepEqual(Buffer.from(peerCancelled.bytes),Buffer.from(cancelled));assert.equal(world.decodeOutcome(cancelled).kind,'cancelled');
      k.close(s);const closed=await peer.call('close',{handle:session.session});assert.equal(closed.working_live,0);assert.equal(k.usage().workingLive,0n);
      rows.push({mode,depth,source,target,checkpointSha256:hash(state),outcomeSha256:hash(expected)});
    }
    writeFileSync(reportPath,JSON.stringify({status:'complete',kernels:Object.fromEntries(Object.entries(kernels).map(([k,p])=>[k,hash(readFileSync(p))])),rows,engines:Object.fromEntries(Object.entries(peers).map(([k,p])=>[k,p.identity])),originalProcessesExited:rows.length},null,2)+'\n');
    console.log(JSON.stringify({cases:rows.length,native:'both revisions',wasm:'Node and Wasmtime',originalProcessesExited:rows.length}));
  } finally {for(const peer of Object.values(peers))await peer.close();rmSync(scratch,{recursive:true,force:true});}
}
