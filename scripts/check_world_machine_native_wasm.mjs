import { readFile } from "node:fs/promises";
import {
  abiFailure,
  callStep,
  copyExported,
  decodeFrame,
  encodeOkResult,
  encodeStepInput,
  instantiate,
} from "./world_application_v1_conformance.mjs";

const args = process.argv.slice(2);
const negativeSelfTest = args[0] === "--negative-self-test";
const paths = negativeSelfTest ? args.slice(1) : args;
if (paths.length !== 2 || (args[0]?.startsWith("--") && !negativeSelfTest)) {
  throw new Error("usage: check_world_machine_native_wasm.mjs [--negative-self-test] <application.wasm> <native.trace>");
}

const [wasmPath, tracePath] = paths;

async function wasmTrace(wasmBytes) {
  const module = await WebAssembly.compile(wasmBytes);
  if (WebAssembly.Module.imports(module).length !== 0) throw new Error("one-effect WASM imports runtime state");
  const genesisInstance = await instantiate(module);
  const initialBytes = genesisInstance.memory.buffer.byteLength;
  let bounded = false;
  try {
    genesisInstance.memory.grow(1);
  } catch (error) {
    if (error instanceof RangeError) bounded = true;
    else throw error;
  }
  if (!bounded || genesisInstance.memory.buffer.byteLength !== initialBytes) throw new Error("one-effect WASM memory is not bounded");
  const manifest = copyExported(genesisInstance, "world_manifest_ptr", "world_manifest_len");
  const applicationId = manifest.subarray(12, 44);
  const genesis = encodeStepInput({ applicationId, initialArgs: u32(7), fuel: 100n });
  if (callStep(genesisInstance, genesis) !== 0) throw abiFailure(genesisInstance, "one-effect genesis failed");
  const firstFrame = copyExported(genesisInstance, "world_output_ptr", "world_output_len");
  const first = decodeFrame(firstFrame);
  if (first.request === null) throw new Error("one-effect genesis did not park");
  const raw = inspectFrame(firstFrame);
  const result = encodeOkResult(first.request, u32(41));
  const continuation = encodeStepInput({
    applicationId,
    expectedParentFrameId: first.frameId,
    priorFrame: firstFrame,
    effectResult: result.bytes,
    fuel: 100n,
  });
  const childInstance = await instantiate(module);
  if (callStep(childInstance, continuation) !== 0) throw abiFailure(childInstance, "one-effect continuation failed");
  const terminalFrame = copyExported(childInstance, "world_output_ptr", "world_output_len");
  const terminal = decodeFrame(terminalFrame);
  if (terminal.status !== 1 || terminal.finalResult === null) throw new Error("one-effect did not complete");
  const retryInstance = await instantiate(module);
  if (callStep(retryInstance, continuation) !== 0) throw abiFailure(retryInstance, "one-effect retry failed");
  const retryChild = copyExported(retryInstance, "world_output_ptr", "world_output_len");
  if (!retryChild.equals(terminalFrame)) throw new Error("one-effect retry child differs");
  return {
    manifest,
    firstFrame,
    firstState: raw.state,
    pendingRequest: raw.request,
    terminalFrame,
    terminalResult: terminal.finalResult,
    retryChild,
  };
}

function compare(native, wasm) {
  for (const [field, label] of [
    ["manifest", "manifest"],
    ["firstFrame", "first_frame"],
    ["firstState", "first_state"],
    ["pendingRequest", "pending_effect_request"],
    ["terminalFrame", "terminal_frame"],
    ["terminalResult", "terminal_result"],
    ["retryChild", "deterministic_retry_child"],
  ]) {
    if (!native[field].equals(wasm[field])) throw new Error(`${label} byte mismatch`);
  }
}

function decodeTrace(bytes) {
  const reader = new Reader(bytes);
  if (reader.take(8).toString("ascii") !== "WRLDNTR1") throw new Error("invalid native trace magic");
  const names = ["manifest", "firstFrame", "firstState", "pendingRequest", "terminalFrame", "terminalResult", "retryChild"];
  const result = Object.fromEntries(names.map((name) => [name, reader.lenBytes()]));
  reader.finish();
  return result;
}

function inspectFrame(bytes) {
  const reader = new Reader(bytes);
  reader.take(8 + 4 + 32 + 32);
  reader.optionalDigest();
  reader.take(8);
  const state = reader.lenBytes();
  const request = reader.bool() ? reader.lenBytes() : null;
  if (request === null) throw new Error("first Frame has no pending request bytes");
  return { state, request };
}

function u32(value) {
  const bytes = Buffer.alloc(4);
  bytes.writeUInt32LE(value);
  return bytes;
}

class Reader {
  constructor(value) { this.value = value; this.offset = 0; }
  take(length) {
    const end = this.offset + length;
    if (end > this.value.length) throw new Error("truncated trace record");
    const result = this.value.subarray(this.offset, end);
    this.offset = end;
    return result;
  }
  bool() { const value = this.take(1)[0]; if (value > 1) throw new Error("invalid trace boolean"); return value === 1; }
  u32() { return this.take(4).readUInt32LE(); }
  lenBytes() { return this.take(this.u32()); }
  optionalDigest() { return this.bool() ? this.take(32) : null; }
  finish() { if (this.offset !== this.value.length) throw new Error("trailing trace bytes"); }
}

const native = decodeTrace(await readFile(tracePath));
const wasm = await wasmTrace(await readFile(wasmPath));
compare(native, wasm);

if (negativeSelfTest) {
  const drifted = Object.fromEntries(
    Object.entries(wasm).map(([name, bytes]) => [name, Buffer.from(bytes)]),
  );
  drifted.terminalResult[0] ^= 1;
  try {
    compare(native, drifted);
    throw new Error("native/WASM comparator accepted injected terminal result drift");
  } catch (error) {
    if (!String(error.message).includes("terminal_result")) throw error;
  }
  console.log("world_machine_native_wasm_negative=true");
} else {
  console.log("native_wasm_manifest_parity=true");
  console.log("native_wasm_first_frame_parity=true");
  console.log("native_wasm_first_state_parity=true");
  console.log("native_wasm_pending_effect_request_parity=true");
  console.log("native_wasm_terminal_frame_parity=true");
  console.log("native_wasm_terminal_result_parity=true");
  console.log("native_wasm_deterministic_retry_child_parity=true");
  console.log("world_machine_native_wasm=true");
}
