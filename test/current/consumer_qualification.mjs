// Runs immutable A0's deterministic assertions. Its authenticated installation
// remains verified and supplies an independent reference/bridge. Only the raw
// public Kernel inputs use the explicitly named experimental bytes and digest.
import assert from "node:assert/strict";
import {readFileSync,writeFileSync,mkdirSync} from "node:fs";
import {execFileSync} from "node:child_process";
import {join,resolve,dirname} from "node:path";
import {pathToFileURL} from "node:url";
import {createHash} from "node:crypto";
const [agent,kernel,embedding,images,native,output,family="all"]=process.argv.slice(2).map((x,i)=>i<6?resolve(x):x);
assert.equal(execFileSync("git",["-C",agent,"rev-parse","HEAD"],{encoding:"utf8"}).trim(),"b1f9d2866b5717d16339e7022a3b4d08951f0770");
const hash=b=>createHash("sha256").update(b).digest("hex");
const runtime=join(agent,".agent4/out/world-runtime/runtime"),kernelSha256=hash(readFileSync(kernel));
mkdirSync(output,{recursive:true});
const scenarios=[
  ["inquiry_application_runtime.mjs",[runtime,join(images,"inquiry"),native],"inquiry-application"],
  ["inquiry_cases_runtime.mjs",[runtime,join(images,"inquiry"),native,join(images,"../bin/agent4-multi")],"inquiry-cases"],
  ["document_runtime.mjs",[runtime,join(images,"document/document.bpi3")],"document"],
  ["consequence_runtime.mjs",[runtime,join(images,"document/consequence.bpi3"),"--application-only"],"consequence"],
  ["consequence_runtime.mjs",[runtime,join(images,"document/consequence.bpi3"),"--economy-only"],"consequence-economy"],
  ["recursive_participant.mjs",[embedding,kernel,join(images,"recursive"),"single"],"recursive-single"],
  ["recursive_participant.mjs",[embedding,kernel,join(images,"recursive"),"double"],"recursive-double"],
  ["review_runtime.mjs",[],"review"],
];
const report={status:"running",scope:"World experimental Kernel execution of frozen A0/C0 programs and prescribed fixtures; A0 verification/locks unchanged. This is not a claim of candidate admission under A0's historical lock.",agent:"b1f9d2866b5717d16339e7022a3b4d08951f0770",kernelSha256,kernel,rows:[]};
for(const [file,args,name] of scenarios) {
  if(family!=="all"&&!name.startsWith(family))continue;
  const original=join(agent,"test/agent4",file),originalURL=pathToFileURL(original).href;
  let source=readFileSync(original,"utf8");
  const originalSha256=hash(Buffer.from(source));
  // Keep relative imports and resources bound to the immutable A0 fixture.
  source=source.replace(/(from\s+|import\()(["'])(\.\.?\/[^"']+)\2/g,(_m,p,q,path)=>p+q+pathToFileURL(resolve(dirname(original),path)).href+q);
  source=source.replaceAll("import.meta.dirname",JSON.stringify(dirname(original))).replaceAll("import.meta.url",JSON.stringify(originalURL));
  // Authentication still runs against the real historical installation. The
  // raw Kernel call receives independently identified local experimental bytes.
  for(const owner of ["runtime.identity","runtime","identity"]){
    source=source.replaceAll(`readFile(${owner}.kernelPath)`,`readFile(${JSON.stringify(kernel)})`);
    source=source.replaceAll(`${owner}.kernelSha256`,JSON.stringify(kernelSha256));
  }
  source=source.replaceAll("wasmtime(runtime.identity,",`wasmtime({kernelPath:${JSON.stringify(kernel)},kernelSha256:${JSON.stringify(kernelSha256)}},`)
    .replaceAll("wasmtime(runtime,",`wasmtime({kernelPath:${JSON.stringify(kernel)},kernelSha256:${JSON.stringify(kernelSha256)}},`);
  if(name==="document")source=source.replace("async function execute(name, queues, expectedResult) {","async function execute(name, queues, expectedResult) { worldFixtureLabel = `document-${worldFixtureIndex++}`;");
  if(name==="inquiry-cases"||name==="consequence")source=source.replace(/async function scenario\(([^\n]+)\) \{/,match=>match+" worldFixtureLabel = name;");
  if(name==="consequence-economy")source=source.replace("const fresh = async input => {","const fresh = async input => { if(Object.hasOwn(input,'initialArgs'))worldFixtureLabel=`consequence-${worldFixtureIndex++}`;");
  if(name==="review")source=source.replace("async function start(mode) {","async function start(mode) { worldFixtureLabel = `review-${mode}`;");
  // Record actual commands/results after the original call; returning the
  // original view preserves the public byte-ownership behavior under test.
  const recorder=join(output,`${name}-manifest.json`),prefix=`
import {writeFileSync as worldWrite,readFileSync as worldRead} from "node:fs";
import {createHash as worldHash} from "node:crypto";
let worldFixtureLabel=${JSON.stringify(name)}, worldFixtureIndex=0;
const worldTrace=[];
const worldDigest=b=>worldHash("sha256").update(b).digest("hex");
function worldRecordObserved(command,result){
 const input=Buffer.from(command),out=Buffer.from(result),index=worldTrace.length;
 const inputFile=${JSON.stringify(join(output,name))}+"-"+index+".pki3",outputFile=${JSON.stringify(join(output,name))}+"-"+index+".pko3";
 worldWrite(inputFile,input);worldWrite(outputFile,out);worldTrace.push({name:worldFixtureLabel,inputFile,outputFile,inputSha256:worldDigest(input),outputSha256:worldDigest(out)});
 worldWrite(${JSON.stringify(recorder)},JSON.stringify({rows:worldTrace},null,2)+"\\n");return result;
}\n
function worldRecordInvocation(machine,command){return worldRecordObserved(command,machine.invoke(command));}\n
`;
  // Record raw public calls only. The unchanged authenticated bridge remains
  // independent reference evidence and is excluded from fresh replay totals.
  source=source.replaceAll("kernel.invoke(","worldRecordInvocation(kernel,").replaceAll("machine.invoke(","worldRecordInvocation(machine,");
  if(name.startsWith("recursive"))source=source.replace("let returned = nodeBytes;","worldRecordObserved(command,nodeBytes); let returned = nodeBytes;");
  const adapted=join(output,`${name}-fixture.mjs`);writeFileSync(adapted,prefix+source);
  const env={...process.env,AGENT4_NATIVE:native,AGENT4_MULTI_INSPECTOR:join(images,"../bin/agent4-multi"),AGENT4_WORLD_RUNTIME:runtime,AGENT4_REVIEW_IMAGES:join(images,"review")};
  const stdout=execFileSync(process.execPath,[adapted,...args],{encoding:"utf8",env,timeout:600000,maxBuffer:16<<20});
  writeFileSync(join(output,`${name}.log`),stdout);
  const manifest=JSON.parse(readFileSync(recorder));
  report.rows.push({name,fixture:original,originalSha256,adaptedSha256:hash(readFileSync(adapted)),commands:manifest.rows.length,manifest:recorder});
  writeFileSync(join(output,"qualification.json"),JSON.stringify(report,null,2)+"\n");console.log(JSON.stringify(report.rows.at(-1)));
}
report.status="complete";writeFileSync(join(output,"qualification.json"),JSON.stringify(report,null,2)+"\n");
