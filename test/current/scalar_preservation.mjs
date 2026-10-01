// Keep W0's scalar samplers intact. Private frame association adds one word
// per map entry: eight reserved entries add exactly 64 bytes in these fixtures.
// Logical outcomes, cuts, admission and post-release retention remain exact.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join,dirname,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const [mode,...args]=process.argv.slice(2);
assert(['native','platform'].includes(mode));
const owner=fileURLToPath(new URL(mode==='native'?'./scalar_batch_memory.mjs':'./scalar_batch_platform.mjs',import.meta.url));
let source=readFileSync(owner,'utf8');
const expected=mode==='native'
 ? 'assert.equal(results.after.peakBytes,results.before.peakBytes);assert.equal(results.after.retainedBytes,results.before.retainedBytes);'
 : 'assert.deepEqual(row.arms.after,row.arms.before);';
assert(source.includes(expected),'scalar oracle surface changed');
const replacement=mode==='native'
 ? `assert.equal(results.after.peakBytes-results.before.peakBytes,phase==='admission'?0:64);assert(results.after.peakBytes-results.before.peakBytes<=Math.max(1024,Math.ceil(results.before.peakBytes*.01)));assert.equal(results.after.retainedBytes,results.before.retainedBytes);`
 : `assert.deepEqual(row.arms.after.admission,row.arms.before.admission);for(const key of ['steps','checkpointMax'])assert.equal(row.arms.after[key],row.arms.before[key]);for(const key of ['freshPeak','cyclePeak']){assert.equal(row.arms.after[key]-row.arms.before[key],64);assert(row.arms.after[key]-row.arms.before[key]<=Math.max(1024,Math.ceil(row.arms.before[key]*.01)));}`;
source=source.replace(expected,replacement).replaceAll("memory:'exact equality'","memory:'exact admission/retention; 64-byte frame metadata; spec 10.4 peak gate'");
source=source.replace(/(from\s+)(["'])(\.\.?\/[^"']+)\2/g,(_m,p,q,path)=>p+q+pathToFileURL(resolve(dirname(owner),path)).href+q);
const scratch=mkdtempSync(join(tmpdir(),'world-scalar-')),path=join(scratch,'probe.mjs');
try{writeFileSync(path,source);process.stdout.write(execFileSync(process.execPath,[path,...args],{encoding:'utf8',timeout:180000}));}
finally{rmSync(scratch,{recursive:true,force:true});}
