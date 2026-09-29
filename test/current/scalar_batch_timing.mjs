import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const [before, after, output] = process.argv.slice(2);
assert.equal(process.argv.length, 5);
const hash = p => createHash('sha256').update(readFileSync(p)).digest('hex');
const median = xs => [...xs].sort((a,b) => a-b)[Math.floor(xs.length/2)];
const report = {status:'running', beforeSha256:hash(before), afterSha256:hash(after), windows:5, warmups:3, samples:9, cells:[]};
for (const operations of [0, 2, 4, 16, 256, 1024]) for (const mode of ['prepared','fresh']) {
  const windows=[];
  for(let window=0;window<5;window++) {
    const results={};
    for(const arm of window%2 ? ['after','before'] : ['before','after']) {
      results[arm]=JSON.parse(execFileSync(arm==='before'?before:after,[String(operations),mode],{encoding:'utf8',timeout:60000}));
    }
    assert.deepEqual(results.before.imageDigest,results.after.imageDigest);
    windows.push({...results,ratio:median(results.after.samplesNs)/median(results.before.samplesNs)});
  }
  const ratio=median(windows.map(w=>w.ratio));
  const cell={operations,mode,ratio,confirmedSlowdown:ratio>1.05 && windows.filter(w=>w.ratio>1.05).length>=4,windows};
  report.cells.push(cell);
  writeFileSync(output,JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({operations,mode,ratio,confirmedSlowdown:cell.confirmedSlowdown}));
}
report.status='complete';
writeFileSync(output,JSON.stringify(report,null,2)+'\n');
