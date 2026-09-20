// Test-only exact-ABI kernels, including a constant canonical output.
// Independent transcription of the ABI 3 contract, not the inspector's table.
const signatures = {
  world_abi_version: [[], ['i32']], world_initialize: [['i64'], ['i32']],
  world_set_limits: [['i64','i64','i64','i64'], ['i32']],
  world_prepare_input: [['i64','i64'], ['i32']],
  world_input_ptr: [[], ['i32']], world_input_capacity: [[], ['i64']],
  world_output_ptr: [[], ['i32']], world_output_len: [[], ['i64']],
  world_error_ptr: [[], ['i32']], world_error_len: [[], ['i64']],
  world_prepared_handle: [[], ['i64']], world_session_handle: [[], ['i64']],
  world_working_live: [[], ['i64']], world_working_peak: [[], ['i64']],
  world_invoke: [['i64','i64'], ['i32']], world_prepare: [['i64','i64'], ['i32']],
  world_release_prepared: [['i64','i64'], ['i32']],
  world_start: [['i64','i64','i64'], ['i32']], world_restore: [['i64','i64','i64'], ['i32']],
  world_drive: [['i64','i64','i32','i32','i64','i32','i64'], ['i32']],
  world_checkpoint: [['i64','i64','i32'], ['i32']], world_close: [['i64','i64'], ['i32']],
};

const nat=(value)=>{const bytes=[];do{const low=value&127;value=Math.floor(value/128);bytes.push(low|(value?128:0));}while(value);return bytes;};
const text=(value)=>{const bytes=[...new TextEncoder().encode(value)];return [...nat(bytes.length),...bytes];};
const section=(tag,bytes)=>[tag,...nat(bytes.length),...bytes];
export function kernel({rename=(name)=>name,wrongType=false,extraExport=false,missingExport=false,imports=false,start=false,shared=false,outcome}={}) {
  const rows=Object.entries(signatures).map(([name,[parameters,results]])=>({name,parameters:[...parameters],results:[...results]}));
  if(wrongType)rows.find((row)=>row.name==='world_invoke').parameters=['i32'];
  if(start)rows.push({name:'start',parameters:[],results:[]});
  const type=(name)=>name==='i32'?0x7f:0x7e;
  const types=rows.flatMap((row)=>[0x60,...nat(row.parameters.length),...row.parameters.map(type),...nat(row.results.length),...row.results.map(type)]);
  const exports=[...text(rename('memory')),2,0];
  const exported=rows.filter((row)=>row.name!=='start');
  if(missingExport)exported.pop();
  for(const row of exported)exports.push(...text(rename(row.name)),0,...nat(rows.indexOf(row)+(imports?1:0)));
  if(extraExport)exports.push(...text('unexpected'),0,imports?1:0);
  const bodies=rows.flatMap((row)=>{
    const value=row.name.endsWith('abi_version')?3:outcome?({world_input_capacity:32768,world_output_ptr:32768,world_output_len:outcome.length}[row.name]??0):0;
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
