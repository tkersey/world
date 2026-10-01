// Explicit local kernel identities for the frozen regression lane. No Agent
// lock is changed and no candidate is presented as its historical delivery.
import assert from "node:assert/strict";
import {readFileSync,writeFileSync,readdirSync} from "node:fs";
import {execFileSync} from "node:child_process";
import {pathToFileURL,fileURLToPath} from "node:url";
import {createHash} from "node:crypto";
const hash=b=>createHash("sha256").update(b).digest("hex"),median=a=>[...a].sort((x,y)=>x-y)[Math.floor(a.length/2)],args=process.argv.slice(2);
if(args[0]==="sample"){
 const [,embedding,kernelPath,phase,path,name]=args,world=await import(pathToFileURL(embedding)),bytes=readFileSync(kernelPath);
 const k=await world.Kernel.create({bytes,expectedSha256:hash(bytes)});k.setLimits({input:256<<20,working:256<<20,output:256<<20});
 const commands=phase==="admission"?[{bytes:readFileSync(path)}]:JSON.parse(readFileSync(path)).rows.filter(r=>r.name===name).map(r=>{const bytes=readFileSync(r.inputFile),expected=readFileSync(r.outputFile);assert.equal(hash(bytes),r.inputSha256);assert.equal(hash(expected),r.outputSha256);return{bytes,expected};});assert(commands.length);
 const samplesNs=[];
 for(let sample=0;sample<12;sample++){
  let elapsed=0;
  for(const command of commands){const start=process.hrtime.bigint();if(phase==="admission"){const p=k.prepare(command.bytes);elapsed+=Number(process.hrtime.bigint()-start);k.releasePrepared(p);}else{const actual=k.invoke(command.bytes);elapsed+=Number(process.hrtime.bigint()-start);assert.deepEqual(Buffer.from(actual),command.expected);}assert.equal(k.usage().workingLive,0n);}
  if(sample>=3)samplesNs.push(elapsed);
 }
 // Instrumentation is a separate pass. Observe before the next command,
 // especially releasePrepared, can reset the previous allocation maximum.
 let peakBytes=0,retainedBytes=0;
 const observe=()=>{peakBytes=Math.max(peakBytes,Number(k.usage().workingPeak));retainedBytes=Math.max(retainedBytes,Number(k.usage().workingLive));};
 for(const command of commands){if(phase==="admission"){const p=k.prepare(command.bytes);observe();k.releasePrepared(p);observe();}else{assert.deepEqual(Buffer.from(k.invoke(command.bytes)),command.expected);observe();}assert.equal(k.usage().workingLive,0n);}
 console.log(JSON.stringify({kernelSha256:hash(bytes),samplesNs,peakBytes,retainedBytes,commands:commands.length}));
}else{
 const [embedding,before,after,corpus,manifestPath,output]=args;
 const cells=readdirSync(corpus).filter(x=>x.endsWith(".bpi3")).sort().map(name=>({phase:"admission",name,path:`${corpus}/${name}`}));assert.equal(cells.length,18);
 const manifest=JSON.parse(readFileSync(manifestPath));assert.equal(manifest.rows.length,491);const names=[...new Set(manifest.rows.map(x=>x.name))];assert.equal(names.length,30);
 cells.push(...names.map(name=>({phase:"replay",name,path:manifestPath})));
 const report={status:"running",scope:"Same-image WASM admission and frozen fresh-invocation replay including admission/restoration; no host/model execution and no whole-application or live-Resident latency claim.",manifestSha256:hash(readFileSync(manifestPath)),kernels:{before:hash(readFileSync(before)),after:hash(readFileSync(after))},windows:5,warmups:3,samples:9,cells:[]};
 for(const cell of cells){const windows=[];for(let window=0;window<5;window++){const measured={};for(const arm of window%2?["after","before"]:["before","after"])measured[arm]=JSON.parse(execFileSync(process.execPath,[fileURLToPath(import.meta.url),"sample",embedding,arm==="before"?before:after,cell.phase,cell.path,cell.name],{encoding:"utf8",timeout:180000}));windows.push({...measured,ratio:median(measured.after.samplesNs)/median(measured.before.samplesNs)});}
  const ratio=median(windows.map(x=>x.ratio)),confirmedSlowdown=ratio>1.05&&windows.filter(x=>x.ratio>1.05).length>=4,memoryExceeded=windows.some(x=>x.after.peakBytes-x.before.peakBytes>Math.max(1024,Math.ceil(x.before.peakBytes*.01)));
  report.cells.push({...cell,ratio,confirmedSlowdown,memoryExceeded,deltaNs:median(windows.map(x=>median(x.after.samplesNs)-median(x.before.samplesNs))),windows});writeFileSync(output,JSON.stringify(report,null,2)+"\n");console.log(JSON.stringify({...cell,ratio,confirmedSlowdown,memoryExceeded}));
 }
 report.status="complete";writeFileSync(output,JSON.stringify(report,null,2)+"\n");
}
