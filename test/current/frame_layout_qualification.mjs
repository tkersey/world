// Uninstalled same-image regression and cost probe for immutable layout classes.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL, fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const median = values => [...values].sort((a,b)=>a-b)[Math.floor(values.length/2)];
const args = process.argv.slice(2);
if (args[0] === 'sample') {
  const [, embedding, kernel, imagePath, inputPath, phase, expected, argumentsPath] = args;
  const world = await import(pathToFileURL(embedding)), bytes = readFileSync(kernel);
  const k = await world.Kernel.create({bytes, expectedSha256:hash(bytes)});
  k.setLimits({input:256<<20, working:256<<20, output:256<<20});
  const image = readFileSync(imagePath), input = readFileSync(inputPath), initialArgs = readFileSync(argumentsPath);
  let peakBytes = 0;
  // The kernel resets its peak on every operation, including cleanup.
  // Fold each observation before another operation can replace it.
  const observePeak = () => { peakBytes = Math.max(peakBytes, Number(k.usage().workingPeak)); };
  const prepared = phase === 'resident' ? k.prepare(image) : null;
  observePeak();
  const live = k.usage().workingLive, samplesNs = [], batch = image.length > 8192 || phase === 'resident' ? 1 : 64;
  let retainedBytes = Number(live);
  for (let sample=0; sample<12; sample++) {
    let elapsed=0;
    for (let iteration=0; iteration<batch; iteration++) {
      if (phase === 'admission') {
        const start=process.hrtime.bigint(), p=k.prepare(image);
        elapsed+=Number(process.hrtime.bigint()-start);
        observePeak();
        retainedBytes=Math.max(retainedBytes,Number(k.usage().workingLive)); k.releasePrepared(p); observePeak();
      } else if (phase === 'resident') {
        const session=k.start(prepared,initialArgs); observePeak();
        const start=process.hrtime.bigint();
        const result=k.drive(session,{}); elapsed+=Number(process.hrtime.bigint()-start);
        observePeak(); assert.equal(hash(result),expected); k.close(session); observePeak();
      } else {
        const start=process.hrtime.bigint(), result=k.invoke(input);
        elapsed+=Number(process.hrtime.bigint()-start); observePeak(); assert.equal(hash(result),expected);
      }
      assert.equal(k.usage().workingLive,live);
    }
    if (sample>=3) samplesNs.push(elapsed/batch);
  }
  if (prepared) { k.releasePrepared(prepared); observePeak(); }
  assert.equal(k.usage().workingLive,0n);
  console.log(JSON.stringify({samplesNs,peakBytes,retainedBytes,batch}));
} else {
  const [embedding,beforeKernel,afterKernel,emitter,beforeNative,afterNative,beforeResident,afterResident,corpus,output] = args;
  assert.equal(args.length,10); mkdirSync(corpus,{recursive:true});
  const world=await import(pathToFileURL(embedding));
  const kernels={before:beforeKernel,after:afterKernel}, natives={before:beforeNative,after:afterNative}, residents={before:beforeResident,after:afterResident};
  const fresh=async arm=>{const bytes=readFileSync(kernels[arm]),k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;};
  const report={status:'running',scope:'Same admitted images; exact per-prefix outcomes for0/1/8calls; admission,fresh8,resident1000 timing; no installable alternate evaluator.',kernels:Object.fromEntries(Object.entries(kernels).map(([k,p])=>[k,hash(readFileSync(p))])),windows:5,warmups:3,samples:9,requests:0,cells:[]};
  for (const width of [4,4096,65536]) for (const family of ['compatible','fallback']) {
    const image=execFileSync(emitter,[family,String(width)]), imagePath=join(corpus,`${width}-${family}.bpi3`); writeFileSync(imagePath,image);
    for (const n of [0,1,8]) {
      const initialArgs=Buffer.alloc(8);initialArgs.writeBigUInt64LE(BigInt(n));
      const pair={before:await fresh('before'),after:await fresh('after')};let request={image,initialArgs,quantum:1n},steps=0;
      while(true){
        const encoded=world.encodeInput(request),left=pair.before.invoke(encoded),right=pair.after.invoke(encoded);assert.deepEqual(Buffer.from(right),Buffer.from(left));report.requests++;assert(++steps<n*8+16);
        const out=world.decodeOutcome(right);if(out.kind==='completed'){assert.equal(Buffer.from(out.value).readBigUInt64LE(),0n);break;}
        assert.equal(out.kind,'progressed');
        if(n===8&&steps%5===0){const cancellation=world.encodeInput({image,state:out.state,control:'cancel_text',value:'layout cut'});assert.deepEqual(Buffer.from(pair.before.invoke(cancellation)),Buffer.from(pair.after.invoke(cancellation)));}
        request={image,state:out.state,quantum:1n};
      }
      for(const k of Object.values(pair))assert.equal(k.usage().workingLive,0n);
    }
    for(const phase of ['admission','fresh','resident']) {
      const n=phase==='resident'?1000:phase==='fresh'?8:0,initialArgs=Buffer.alloc(8);initialArgs.writeBigUInt64LE(BigInt(n));
      const input=world.encodeInput({image,initialArgs}),inputPath=join(corpus,`${width}-${family}-${n}.pki3`),argumentsPath=join(corpus,`${width}-${family}-${n}.args`);writeFileSync(inputPath,input);writeFileSync(argumentsPath,initialArgs);
      const reference=await fresh('before'),result=reference.invoke(input),decoded=world.decodeOutcome(result);assert.equal(decoded.kind,'completed');assert.equal(Buffer.from(decoded.value).readBigUInt64LE(),0n);const expected=hash(result);
      for(const engine of ['native','wasm']) {
        const windows=[];
        for(let window=0;window<5;window++) {
          const measured={};
          for(const arm of window%2?['after','before']:['before','after']) {
            const command=engine==='wasm'?process.execPath:phase==='resident'?residents[arm]:natives[arm];
            const argv=engine==='wasm'?[fileURLToPath(import.meta.url),'sample',embedding,kernels[arm],imagePath,inputPath,phase,expected,argumentsPath]:phase==='resident'?[imagePath,argumentsPath,'100000','0']:[phase,phase==='admission'?imagePath:inputPath,...(phase==='admission'?[]:[expected])];
            measured[arm]=JSON.parse(execFileSync(command,argv,{encoding:'utf8',timeout:180000}));
          }
          windows.push({...measured,ratio:median(measured.after.samplesNs)/median(measured.before.samplesNs)});
        }
        const ratio=median(windows.map(w=>w.ratio)),slow=ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4;
        const memory=windows.map(w=>({before:w.before.peakBytes,after:w.after.peakBytes})).filter(x=>x.before!==undefined&&x.after!==undefined);
        const memoryExceeded=memory.length ? memory.some(x=>x.after-x.before>Math.max(1024,Math.ceil(x.before*0.01))) : null;
        report.cells.push({width,family,phase,n,engine,imageSha256:hash(image),ratio,confirmedSlowdown:slow,memoryExceeded,windows});writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({width,family,phase,engine,ratio,slow,memoryExceeded}));
      }
    }
  }
  report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
}
