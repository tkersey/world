// Uninstalled, same-image live-Resident lifecycle probe. Freeze with W0 first.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {frame, concat, field} from '../../src/embedding/wire.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
const [action, embedding, kernelPath, imagePath, mode, depthText, recordPath, profile = 'normal'] = process.argv.slice(2);
assert(['freeze', 'sample', 'memory', 'complete'].includes(action));
assert(['H','Q'].includes(mode));
assert(['normal','failure'].includes(profile));
const world = await import(pathToFileURL(embedding));
const bytes = readFileSync(kernelPath), image = readFileSync(imagePath), depth = Number(depthText);
assert(Number.isSafeInteger(depth) && depth >= 0);
const initialArgs = Buffer.alloc(16);
initialArgs.writeBigUInt64LE(BigInt(depth)); initialArgs.writeBigUInt64LE(17n, 8);
const limits = {input:16<<20, working:128<<20, output:16<<20};
const kernel = await world.Kernel.create({bytes, expectedSha256:hash(bytes)});
kernel.setLimits(limits);
const outcomeHash = outcome => typeof outcome === 'string' ? outcome : hash(outcome);
const cancel = {control:'cancel_text', value:'retained lifecycle complete'};
const encodeRawReply = (identity, value) => frame('ABL_ERS3', concat(identity, field(value)));

async function replies() {
  const p = kernel.prepare(image), s = kernel.start(p, initialArgs);
  const pending = world.decodeOutcome(kernel.drive(s));
  assert.equal(pending.kind, 'requested');
  const expected = await world.decodeRequest(pending.request), integer = Buffer.alloc(8);
  integer.writeBigUInt64LE(17n);
  const wrong = new Uint8Array(expected.requestIdentity); wrong[0] ^= 1;
  const result = [new Uint8Array([0]), encodeRawReply(wrong, integer),
    encodeRawReply(expected.requestIdentity, new Uint8Array()), encodeRawReply(expected.requestIdentity, integer)];
  assert.equal(world.decodeOutcome(kernel.drive(s, cancel)).kind, 'cancelled');
  kernel.close(s); kernel.releasePrepared(p);
  return result;
}

let frozen = action === 'freeze' ? null : JSON.parse(readFileSync(recordPath, 'utf8'));
const replyBytes = mode === 'Q' ? (frozen ? frozen.replies.map(x => Buffer.from(x, 'hex')) : await replies()) : [];
if (frozen) {
  assert.equal(frozen.imageSha256, hash(image)); assert.equal(frozen.mode, mode);
  assert.equal(frozen.depth, depth); assert.deepEqual(frozen.limits, limits);
  assert.equal(frozen.profile ?? 'normal', profile);
}

// Instrumentation is optional and excluded completely from latency runs.
function run(memory = false) {
  const outputs = [], phases = [];
  let peak = 0, reserved = 0, preparedLive, pauseLive, failureBefore, failureAfter;
  const observe = (name, start) => {
    const usage = kernel.usage();
    peak = Math.max(peak, Number(usage.workingPeak));
    reserved = Math.max(reserved, usage.memoryBytes);
    phases.push({name, elapsedNs:Number(process.hrtime.bigint()-start), live:Number(usage.workingLive), peak:Number(usage.workingPeak)});
  };
  function command(name, body) {
    const start = memory ? process.hrtime.bigint() : null;
    try { return body(); } finally { if (memory) observe(name, start); }
  }
  const start = process.hrtime.bigint();
  const p = command('prepare', () => kernel.prepare(image));
  if (memory) preparedLive = Number(kernel.usage().workingLive);
  const preparationEnd = process.hrtime.bigint();
  const s = command('start', () => kernel.start(p, initialArgs));
  function failPublication(options) {
    if(profile!=='failure')return;
    failureBefore=command('before-failure-checkpoint',()=>kernel.checkpoint(s));outputs.push(failureBefore);
    command('limit-output',()=>kernel.setLimits({...limits,output:1}));
    let failed=false;
    try { command('failed-publication',()=>kernel.drive(s,options)); }
    catch(error){assert.equal(error.code,'WORLD_CAPACITY');assert.equal(error.details.arena,'output');outputs.push(error.code);failed=true;}
    assert(failed,'output limit must fail after logical progress');
    command('restore-limits',()=>kernel.setLimits(limits));
    failureAfter=command('after-failure-checkpoint',()=>kernel.checkpoint(s));outputs.push(failureAfter);
  }
  outputs.push(command('initial', () => kernel.drive(s)));
  if (mode === 'H') {
    for (let i=0; i<64; i++) {
      const options={control:i ? 'none' : 'resume_yield', quantum:1n};
      if(i===63)failPublication(options);
      outputs.push(command(`drive-${i}`, () => kernel.drive(s, options)));
    }
    if (memory) pauseLive = Number(kernel.usage().workingLive);
    outputs.push(command('checkpoint', () => kernel.checkpoint(s)));
  } else {
    for (let i=0; i<3; i++) {
      let error;
      try { outputs.push(command(`reject-${i}`, () => kernel.drive(s, {control:'reply', value:replyBytes[i], quantum:0n}))); }
      catch (caught) { error = caught.code ?? caught.name; outputs.push(error); }
      assert(error, 'invalid response was accepted');
    }
    if (memory) pauseLive = Number(kernel.usage().workingLive);
    failPublication({control:'reply',value:replyBytes[3],quantum:0n});
    outputs.push(command('valid-reply', () => kernel.drive(s, {control:'reply', value:replyBytes[3], quantum:0n})));
  }
  outputs.push(command('cancel', () => kernel.drive(s, cancel)));
  command('close', () => kernel.close(s));
  command('release', () => kernel.releasePrepared(p));
  const end = process.hrtime.bigint();
  assert.equal(kernel.usage().workingLive, 0n);
  if(profile==='failure')assert.deepEqual(Buffer.from(failureAfter),Buffer.from(failureBefore));
  const hashes = outputs.map(outcomeHash);
  if (frozen) assert.deepEqual(hashes, frozen.outcomes);
  assert.equal(world.decodeOutcome(outputs[0]).kind, mode === 'H' ? 'yielded' : 'requested');
  assert.equal(world.decodeOutcome(outputs.at(-1)).kind, 'cancelled');
  return {totalNs:Number(end-start), executionNs:Number(end-preparationEnd), preparationNs:Number(preparationEnd-start), hashes,
    ...(memory ? {peakBytes:peak, reservedBytes:reserved, preparedLive, pauseLive, phases} : {})};
}

if (action === 'freeze') {
  const result = run(true);
  frozen = {mode, depth, profile, imageSha256:hash(image), baselineKernelSha256:hash(bytes), limits,
    replies:replyBytes.map(x=>Buffer.from(x).toString('hex')), outcomes:result.hashes,
    baselineMemory:result};
  writeFileSync(recordPath, JSON.stringify(frozen, null, 2)+'\n');
  console.log(JSON.stringify({mode, depth, imageSha256:hash(image), peakBytes:result.peakBytes, pauseLive:result.pauseLive}));
} else if (action === 'sample') {
  const samples = [];
  for (let i=0; i<12; i++) { const result = run(); if (i>=3) samples.push({totalNs:result.totalNs, executionNs:result.executionNs, preparationNs:result.preparationNs}); }
  console.log(JSON.stringify({mode, depth, imageSha256:hash(image), kernelSha256:hash(bytes), warmups:3, samples}));
} else if (action === 'memory') {
  const result = run(true);
  console.log(JSON.stringify({mode, depth, kernelSha256:hash(bytes), ...result}));
} else {
  // Every saved continuation has a distinct expected effect, not a checksum.
  const p = kernel.prepare(image), s = kernel.start(p, initialArgs);
  let output = world.decodeOutcome(kernel.drive(s));
  if (mode === 'H') {
    assert.equal(output.kind, 'yielded');
    for (let i=0; i<64; i++) output = world.decodeOutcome(kernel.drive(s, {control:i ? 'none' : 'resume_yield', quantum:1n}));
    output = world.decodeOutcome(kernel.drive(s));
  } else output = world.decodeOutcome(kernel.drive(s, {control:'reply', value:replyBytes[3]}));
  for (let i=1; i<=depth; i++) {
    assert.equal(output.kind, 'requested');
    const request = await world.decodeRequest(output.request);
    assert.equal(request.semanticIdentity, 'retained-history/depth');
    assert.equal(Buffer.from(request.payload).readBigUInt64LE(), BigInt(i));
    output = world.decodeOutcome(kernel.drive(s, {control:'reply', value:await world.encodeResult(output.request, new Uint8Array())}));
  }
  assert.equal(output.kind, 'completed'); assert.equal(Buffer.from(output.value).readBigUInt64LE(), 273n);
  kernel.close(s); kernel.releasePrepared(p); assert.equal(kernel.usage().workingLive, 0n);
  console.log(JSON.stringify({mode, depth, distinctContinuations:depth, result:273}));
}
