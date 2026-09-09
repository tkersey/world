// Deadline and output bounds for release-verification children, not program fuel.
import { spawn } from 'node:child_process';
export function bounded(command,args,{cwd,timeout=180000}={}) {
  return new Promise((accept,reject)=>{
    const child=spawn(command,args,{cwd,detached:true,stdio:['ignore','pipe','pipe']});
    const chunks=[];let length=0,failure=null;
    const stop=(error)=>{failure??=error;try{process.kill(-child.pid,'SIGKILL');}catch{child.kill('SIGKILL');}};
    const timer=setTimeout(()=>stop(new Error('verification process group exceeded its harness deadline')),timeout);
    for(const stream of [child.stdout,child.stderr])stream.on('data',(chunk)=>{length+=chunk.length;if(length>16<<20)stop(new Error('verification diagnostics exceeded harness capacity'));else chunks.push(chunk);});
    child.on('error',(error)=>{clearTimeout(timer);reject(error);});
    child.on('close',(code)=>{clearTimeout(timer);const diagnostic=Buffer.concat(chunks).toString();if(failure||code!==0)reject(failure??new Error(`verification failed (${code}): ${diagnostic}`));else{process.stdout.write(diagnostic);accept();}});
  });
}
