// The old P26 sampler compares against a pre-reclamation baseline. W0 already
// owns that capability; keep its test intact and select a preservation oracle.
import assert from "node:assert/strict";
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from "node:fs";
import {execFileSync} from "node:child_process";
import {tmpdir} from "node:os";
import {join,dirname,resolve} from "node:path";
import {fileURLToPath,pathToFileURL} from "node:url";
const owner=fileURLToPath(new URL("./blob_retention_platform.mjs",import.meta.url));
let source=readFileSync(owner,"utf8");
const old="if(family==='unique'&&value.length>=65536)assert(row.arms.after.pausedLive<row.arms.before.pausedLive-length+8192);";
assert(source.includes(old),"retention oracle surface changed");
source=source.replace(old,"if(family==='unique'&&value.length>=65536){assert(row.arms.before.pausedLive<length/4);assert(row.arms.after.pausedLive<length/4);assert(row.arms.after.pausedLive-row.arms.before.pausedLive<=1024);}");
source=source.replace(/(from\s+)(["'])(\.\.?\/[^"']+)\2/g,(_m,p,q,path)=>p+q+pathToFileURL(resolve(dirname(owner),path)).href+q);
const scratch=mkdtempSync(join(tmpdir(),"world-retention-")),path=join(scratch,"probe.mjs");
try{writeFileSync(path,source);process.stdout.write(execFileSync(process.execPath,[path,...process.argv.slice(2)],{encoding:"utf8",timeout:180000}));}
finally{rmSync(scratch,{recursive:true,force:true});}
