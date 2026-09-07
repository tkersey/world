// Test-only exact-ABI kernels, including a constant canonical output.
import { PROCESS_KERNEL_EXPORT_SIGNATURES } from "../../src/process_v2/wasm.mjs";

const nat=(value)=>{const bytes=[];do{const low=value&127;value=Math.floor(value/128);bytes.push(low|(value?128:0));}while(value);return bytes;};
const text=(value)=>{const bytes=[...new TextEncoder().encode(value)];return [...nat(bytes.length),...bytes];};
const section=(tag,bytes)=>[tag,...nat(bytes.length),...bytes];
export function kernel({rename=(name)=>name,wrongType=false,extraExport=false,missingExport=false,imports=false,start=false,shared=false,outcome}={}) {
  const rows=Object.entries(PROCESS_KERNEL_EXPORT_SIGNATURES).map(([name,type])=>({name,parameters:[...type.parameters],results:[...type.results]}));
  if(wrongType)rows.find((row)=>row.name==='world_process_v2_execute').parameters=['i32'];
  if(start)rows.push({name:'start',parameters:[],results:[]});
  const type=(name)=>name==='i32'?0x7f:0x7e;
  const types=rows.flatMap((row)=>[0x60,...nat(row.parameters.length),...row.parameters.map(type),...nat(row.results.length),...row.results.map(type)]);
  const exports=[...text(rename('memory')),2,0];
  const exported=rows.filter((row)=>row.name!=='start');
  if(missingExport)exported.pop();
  for(const row of exported)exports.push(...text(rename(row.name)),0,...nat(rows.indexOf(row)+(imports?1:0)));
  if(extraExport)exports.push(...text('unexpected'),0,imports?1:0);
  const bodies=rows.flatMap((row)=>{
    const value=row.name.endsWith('abi_version')?2:outcome?({world_process_v2_input_capacity:32768,world_process_v2_output_ptr:32768,world_process_v2_output_len:outcome.length}[row.name]??0):0;
    const encoded=nat(value);
    if(encoded.at(-1)&64){encoded[encoded.length-1]|=128;encoded.push(0);}
    const body=[0,...(row.results.length?[row.results[0]==='i32'?0x41:0x42,...encoded]:[]),0x0b];
    return [...nat(body.length),...body];
  });
  return Uint8Array.from([0,97,115,109,1,0,0,0,
    ...section(1,[...nat(rows.length),...types]),
    ...(imports?section(2,[1,...text('host'),...text('effect'),0,0]):[]),
    ...section(3,[...nat(rows.length),...rows.map((_,index)=>index)]),
    ...section(5,[1,shared?3:1,1,2]),
    ...section(7,[...nat(exported.length+1+(extraExport?1:0)),...exports]),
    ...(start?section(8,nat(rows.length-1)):[]),
    ...section(10,[...nat(rows.length),...bodies]),
    ...(outcome?section(11,[1,0,0x41,...nat(32768),0x0b,...nat(outcome.length),...outcome]):[])]);
}
