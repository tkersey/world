// Reproduce the prescribed 30-case schedule from W0's deterministic A0 run.
// Exact commands/results stay in the qualification directory, outside packages.
import assert from "node:assert/strict";
import {readFileSync,writeFileSync} from "node:fs";
import {join} from "node:path";
import {createHash} from "node:crypto";
const [qualification,output]=process.argv.slice(2);assert.equal(process.argv.length,4);
const hash=b=>createHash("sha256").update(b).digest("hex");
const names=[
 ...["reset","rebinding","already-correct","inadequate"].flatMap(n=>["inquiry","react"].map(k=>`paired-${n}-${k}`)),
 ...["subject","key","occurrence","acceptance"].map(n=>`react-rejects-${n}`),"react-inconclusive-candidate",
 ...Array.from({length:4},(_,n)=>`consequence-${n}`),...Array.from({length:13},(_,n)=>`document-${n}`),
];
const source=["inquiry-cases","consequence-economy","document"].flatMap(n=>JSON.parse(readFileSync(join(qualification,`${n}-manifest.json`))).rows);
const rows=names.flatMap(name=>{
 const selected=source.filter(r=>r.name===name);assert(selected.length,`missing original case ${name}`);
 for(const r of selected){assert.equal(hash(readFileSync(r.inputFile)),r.inputSha256);assert.equal(hash(readFileSync(r.outputFile)),r.outputSha256);}
 return selected;
});
assert.equal(rows.length,491);assert.equal(new Set(rows.map(r=>r.name)).size,30);
const scheduleSha256=hash(JSON.stringify(rows.map(({name,inputSha256,outputSha256})=>({name,inputSha256,outputSha256}))));
writeFileSync(output,JSON.stringify({scope:"W0 output of unchanged A0 deterministic assertions; exact commands, responses, images and logical schedules frozen before candidate consumer timings.",agent:"b1f9d2866b5717d16339e7022a3b4d08951f0770",compiler:"65f46131f366bdd21aa98701f4110ecb801d2c8d",scheduleSha256,rows},null,2)+"\n");
console.log(JSON.stringify({cases:30,commands:491,scheduleSha256}));
