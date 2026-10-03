// Capture the fixed Agent fixtures against their genuinely authenticated W0
// runtime. All policy, expected results, and fixture assertions remain intact.
// Candidate qualification replays these bytes through World's public Kernel API.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdirSync, readdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {resolve, join, dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';

const [agentArg, runtimeArg, corpusArg, nativeArg, inspectorArg, outputArg] = process.argv.slice(2);
assert.equal(process.argv.length, 8);
const [agent, runtime, corpus, native, inspector, output] = [agentArg,runtimeArg,corpusArg,nativeArg,inspectorArg,outputArg].map(p=>resolve(p));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const {verifyRuntime} = await import(pathToFileURL(join(agent,'tools/agent4/dependencies.mjs')));
const identity = verifyRuntime(runtime);
mkdirSync(output); // A new capture never overwrites earlier evidence.
// The original document fixture creates disposable children under this root.
mkdirSync(join(agent,'.agent4/out'),{recursive:true});
const report = {status:'running',identity,agent:'b1f9d2866b5717d16339e7022a3b4d08951f0770',compiler:'65f46131f366bdd21aa98701f4110ecb801d2c8d',captures:[],rows:[]};
const save = () => writeFileSync(join(output,'manifest.json'),JSON.stringify(report,null,2)+'\n');
function run(script, args, name, env = {}) {
  const stdout = execFileSync(process.execPath,[script,...args],{cwd:agent,env:{...process.env,...env},encoding:'utf8',maxBuffer:16<<20,timeout:600000});
  writeFileSync(join(output,name+'.log'),stdout);
  return stdout;
}
function add(directory, prefix, name) {
  const inputFile=join(directory,prefix+'.input'),outputFile=join(directory,prefix+'.output');
  report.rows.push({name,inputFile,outputFile,inputSha256:hash(readFileSync(inputFile)),outputSha256:hash(readFileSync(outputFile))});
}
function relocate(source, path) {
  const url=pathToFileURL(path);
  return source.replace(/from (["'])(\.\.?\/[^"']+)\1/g,(_,q,p)=>`from ${q}${new URL(p,url).href}${q}`)
    .replace(/import\((["'])(\.\.?\/[^"']+)\1\)/g,(_,q,p)=>`import(${q}${new URL(p,url).href}${q})`)
    .replaceAll('import.meta.dirname',JSON.stringify(dirname(path)))
    .replaceAll('import.meta.url',JSON.stringify(url.href));
}
function replace(source, before, after) {
  assert.equal(source.split(before).length,2,`changed fixture anchor: ${before}`);
  return source.replace(before,after);
}

const inquiry=join(output,'inquiry');
run(join(agent,'tools/agent4/capture-inquiry.mjs'),[agent,runtime,join(corpus,'inquiry'),native,inspector,'cases','bpi3',inquiry],'inquiry');
for(const name of readdirSync(inquiry).filter(x=>x.endsWith('.input')).sort()) {
  const prefix=name.slice(0,-6),group=prefix.replace(/^\d+-/,'');add(inquiry,prefix,group);
}
report.captures.push({kind:'inquiry',fixtureSha256:hash(readFileSync(join(agent,'test/agent4/inquiry_cases_runtime.mjs')))});save();

const consequence=join(output,'consequence');
run(join(agent,'tools/agent4/benchmark-clarification.mjs'),[agent,runtime,join(corpus,'document/consequence.bpi3'),consequence,'--capture'],'consequence');
const measured=JSON.parse(readFileSync(join(consequence,'benchmark.json')));
let index=0;
for(const [group,row] of measured.results.entries()) for(let i=0;i<row.freshCalls;i++) add(consequence,'capture-'+String(index++).padStart(3,'0'),'consequence-'+group);
assert.equal(index,readdirSync(consequence).filter(x=>x.endsWith('.input')).length);
report.captures.push({kind:'consequence',fixtureSha256:measured.fixtureSourceSha256});save();

const document=join(output,'document');mkdirSync(document);
const docPath=join(agent,'test/agent4/document_runtime.mjs'),docOriginal=readFileSync(docPath,'utf8');
let doc=relocate(docOriginal,docPath);
doc=replace(doc,'const fresh = async input =>','const freshImplementation = async input =>');
doc=replace(doc,'function interaction(payload, purpose) {',`let captureIndex=0, captureGroup=-1;
const fresh = async input => {
  const result=await freshImplementation(input);
  const prefix=join(${JSON.stringify(document)}, String(captureIndex++).padStart(4,'0')+'-document-'+captureGroup);
  await writeFile(prefix+'.input',world.encodeInput(input));
  await writeFile(prefix+'.output',result.bytes);
  return result;
};
function interaction(payload, purpose) {`);
doc=replace(doc,'async function execute(name, queues, expectedResult) {','async function execute(name, queues, expectedResult) { captureGroup++;');
const docDriver=join(document,'driver.mjs');writeFileSync(docDriver,doc);
run(docDriver,[runtime,join(corpus,'document/document.bpi3')],'document');
assert.equal(readFileSync(docPath,'utf8'),docOriginal);
for(const name of readdirSync(document).filter(x=>x.endsWith('.input')).sort()) {
  const prefix=name.slice(0,-6);add(document,prefix,prefix.replace(/^\d+-/,''));
}
report.captures.push({kind:'document',fixtureSha256:hash(docOriginal),driverSha256:hash(doc)});save();

// The parser's original fixture uses actual live Residents. Record each public
// cut as a portable fresh-invocation reference, without changing the driver.
const parserPath=join(agent,'test/agent4/parser_comparison.mjs'),parserOriginal=readFileSync(parserPath,'utf8');
for(const strategy of ['react','recursive','complete']) for(const scenario of ['easy','repair','unresolved','stale']) {
  const name=`parser-${strategy}-${scenario}`,directory=join(output,name);mkdirSync(directory);
  let driver=relocate(parserOriginal,parserPath);
  driver=replace(driver,"'zig-out/agent4/parser-construction/'",JSON.stringify(join(corpus,'parser-construction')+'/'));
  driver=replace(driver,'world=await import(pathToFileURL(runtime.entrypoint));',`rawWorld=await import(pathToFileURL(runtime.entrypoint));
let captureIndex=0;
const world={...rawWorld,Kernel:{async create(options){
  const kernel=await rawWorld.Kernel.create(options),images=new WeakMap(),sessions=new WeakMap();
  const prepare=kernel.prepare.bind(kernel),start=kernel.start.bind(kernel),restore=kernel.restore.bind(kernel),drive=kernel.drive.bind(kernel);
  kernel.prepare=image=>{const p=prepare(image);images.set(p,image);return p;};
  kernel.start=(p,args)=>{const s=start(p,args);sessions.set(s,images.get(p));return s;};
  kernel.restore=(p,state)=>{const s=restore(p,state);sessions.set(s,images.get(p));return s;};
  kernel.drive=(s,options)=>{
    assert.equal(options.checkpoint,true);
    const input=rawWorld.encodeInput({image:sessions.get(s),state:kernel.checkpoint(s),...options});
    const output=drive(s,options),prefix=${JSON.stringify(directory+'/')}+String(captureIndex++).padStart(4,'0');
    captureWrite(prefix+'.input',input);captureWrite(prefix+'.output',output);return output;
  };return kernel;
}}};`);
  driver=`import {writeFileSync as captureWrite} from 'node:fs';\n`+driver;
  const path=join(directory,'driver.mjs');writeFileSync(path,driver);
  run(path,[runtime,strategy,scenario],name);
  for(const file of readdirSync(directory).filter(x=>x.endsWith('.input')).sort()) add(directory,file.slice(0,-6),name);
  report.captures.push({kind:name,fixtureSha256:hash(parserOriginal),driverSha256:hash(driver)});save();
}
assert.equal(readFileSync(parserPath,'utf8'),parserOriginal);
report.status='complete';save();
console.log(JSON.stringify({manifest:join(output,'manifest.json'),commands:report.rows.length,cases:new Set(report.rows.map(x=>x.name)).size,identity}));
