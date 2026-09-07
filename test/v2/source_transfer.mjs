// Source oracle comparison belongs to conformance tooling, outside the kernel.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { admitProcessKernel, encodeInput, decodeRequest, encodeResult, decodeOutcome } from "../../src/process_v2/index.mjs";
import { wasmtimePeer } from "./wasmtime_peer.mjs";

if (process.argv.length !== 6 && process.argv.length !== 7) throw new Error("expected kernel, native embedding, fixtures, oracle, and optional Wasmtime project paths");
const [kernelPath, nativePath, fixtures, oraclePath, project] = process.argv.slice(2);
const { execute } = await import(pathToFileURL(oraclePath).href);
const kernel = new Uint8Array(await readFile(kernelPath));
const host = await admitProcessKernel(kernel, { expectedSha256: createHash("sha256").update(kernel).digest("hex") });
const peer = project ? await wasmtimePeer(project, kernelPath, host.sha256) : null;
let observations = 0;
async function compare(mode, input) {
  const encoded = encodeInput({ ...input, mode });
  const native = spawnSync(nativePath, [], { input: encoded, maxBuffer: 64 << 20 });
  let result;
  try { result = await host[mode](input); }
  catch (error) {
    assert.notEqual(native.status, 0);
    assert.ok(native.stderr.toString().includes(error.message));
    if (peer) await assert.rejects(peer.invoke(encoded), (other) => other.message === error.message);
    throw error;
  }
  assert.equal(native.status, 0, native.stderr?.toString());
  assert.deepEqual(result.bytes, new Uint8Array(native.stdout));
  if (peer) {
    const independent = await peer.invoke(encoded);
    assert.deepEqual(independent, result.bytes);
    // Alternate the actual producer of the next detached State bytes.
    if (observations++ % 2 === 0) return { ...decodeOutcome(independent), bytes: independent };
  }
  return result;
}
try {
  {
    const source = JSON.parse(await readFile(join(fixtures, "source-scalar-contracts.json"), "utf8"));
    const image = new Uint8Array(await readFile(join(fixtures, "source-scalar-contracts.bpi2")));
    for (let index = 0; index < 19; index++) {
      const oracle = execute(source, [index]);
      const result = await compare("run", { image, initialArgs: Uint8Array.of(index) });
      assert.equal(result.kind, oracle.kind, `scalar-contracts ${index}`);
      assert.deepEqual(result.value, Uint8Array.from(oracle.value), `scalar-contracts ${index}`);
      let step = await compare("advance", { image, initialArgs: Uint8Array.of(index) });
      while (step.kind === "Progressed") step = await compare("advance", { image, state: step.state });
      assert.deepEqual(step.bytes, result.bytes);
    }
  }
  for (const [name, initial] of [["lexical", [40, 0, 0, 0, 0, 0, 0, 0]], ["deep", []], ["recursive", [16, 39, 0, 0, 0, 0, 0, 0]], ["choices-all", []], ["choices-first", []], ["state-local", []], ["state-shared", []], ["answers", []], ["writer-raise", []], ["cell-order", []], ["nested", []], ["shallow", [0]], ["shallow", [1]], ["injection", [0]], ["injection", [1]], ["abort-custody", [1]], ["bounded-values", []], ["shallow-resumptions", []], ["shallow-injection", [0]], ["shallow-injection", [1]], ["handle-operand-order", []], ["protect-operand-order", []]]) {
    const source = JSON.parse(await readFile(join(fixtures, `source-${name}.json`), "utf8"));
    const image = new Uint8Array(await readFile(join(fixtures, `source-${name}.bpi2`)));
    const oracle = execute(source, initial);
    const result = await compare("run", { image, initialArgs: Uint8Array.from(initial) });
    assert.equal(result.kind, oracle.kind);
    assert.deepEqual(result.value, Uint8Array.from(oracle.value));
    assert.deepEqual(oracle.trace, []);
    if (name !== "recursive") {
      let step = await compare("advance", { image, initialArgs: Uint8Array.from(initial) });
      while (step.kind === "Progressed") step = await compare("advance", { image, state: step.state });
      assert.deepEqual(step.bytes, result.bytes);
    }
  }
  for (const name of ["generator", "scheduler", "reentrant", "cloned", "ownership", "successor-state", "clause-payload"]) {
    const source = JSON.parse(await readFile(join(fixtures, `source-${name}.json`), "utf8"));
    const image = new Uint8Array(await readFile(join(fixtures, `source-${name}.bpi2`)));
    const oracle = execute(source, [], name === "generator" ? [[]] : []);
    for (const mode of ["advance", "run"]) {
      const trace = [];
      let step = await compare(mode, { image, initialArgs: new Uint8Array() });
      while (step.kind !== "Completed") {
        let result;
        if (step.kind === "Yielded") trace.push({ kind: step.kind });
        else if (step.kind === "Requested") {
          const request = decodeRequest(step.request);
          trace.push({ kind: step.kind, identity: request.semanticIdentity, payload: [...request.payload] });
          result = encodeResult(step.request, new Uint8Array());
        } else assert.equal(step.kind, "Progressed");
        step = await compare(mode, { image, state: step.state, result });
      }
      assert.deepEqual(step.value, Uint8Array.from(oracle.value));
      assert.deepEqual(trace, oracle.trace);
    }
  }
  for (const name of ["resource-scalar", "resource-pair", "scoped-reader", "indexed", "abort-custody", "clause-abort"]) {
    const source = JSON.parse(await readFile(join(fixtures, `source-${name}.json`), "utf8"));
    const image = new Uint8Array(await readFile(join(fixtures, `source-${name}.bpi2`)));
    const responses = name === "scoped-reader" ? [[], [], []] : name === "indexed" ? [[37, 0, 0, 0, 0, 0, 0, 0], [1]] : name === "abort-custody" || name === "clause-abort" ? [[]] : [[41, 0, 0, 0, 0, 0, 0, 0], [], []];
    const initialArgs = Uint8Array.from(name === "abort-custody" ? [0] : []);
    const oracle = execute(source, [...initialArgs], responses);
    for (const mode of ["advance", "run"]) {
      const trace = [];
      let step = await compare(mode, { image, initialArgs });
      while (step.kind !== "Completed" && step.kind !== "Failed") {
        let result;
        if (step.kind === "Requested") {
          const request = decodeRequest(step.request);
          result = encodeResult(step.request, Uint8Array.from(responses[trace.length]));
          trace.push({ kind: step.kind, identity: request.semanticIdentity, payload: [...request.payload] });
        } else assert.equal(step.kind, "Progressed");
        step = await compare(mode, { image, state: step.state, result });
      }
      assert.equal(step.kind, oracle.kind);
      assert.deepEqual(step.value, Uint8Array.from(oracle.value));
      assert.deepEqual(trace, oracle.trace);
    }
  }
  for (const name of ["queens-dfs", "queens-bfs"]) {
    const source = JSON.parse(await readFile(join(fixtures, `source-${name}.json`), "utf8"));
    const image = new Uint8Array(await readFile(join(fixtures, `source-${name}.bpi2`)));
    const responses = [[201, 0, 0, 0, 0, 0, 0, 0], [], [], [202, 0, 0, 0, 0, 0, 0, 0], [], []];
    const oracle = execute(source, [], responses);
    const trace = [];
    let step = await compare("run", { image, initialArgs: new Uint8Array() });
    let requests = 0;
    while (step.kind !== "Completed") {
      let result;
      if (step.kind === "Yielded") trace.push({ kind: step.kind });
      else {
        assert.equal(step.kind, "Requested");
        const request = decodeRequest(step.request);
        trace.push({ kind: step.kind, identity: request.semanticIdentity, payload: [...request.payload] });
        result = encodeResult(step.request, Uint8Array.from(responses[requests++]));
      }
      // Every checkpoint crosses a fresh engine. Compare one bounded transition
      // and then the public run boundary from that exact successor in both engines.
      step = await compare("advance", { image, state: step.state, result });
      if (step.kind === "Progressed") step = await compare("run", { image, state: step.state });
    }
    assert.equal(requests, 6);
    assert.deepEqual(step.value, Uint8Array.from(oracle.value));
    assert.deepEqual(trace, oracle.trace);
  }
  for (const name of ["resource-scalar", "resource-pair"]) for (const duringCleanup of [false, true]) {
    const source = JSON.parse(await readFile(join(fixtures, `source-${name}.json`), "utf8"));
    const image = new Uint8Array(await readFile(join(fixtures, `source-${name}.bpi2`)));
    const controls = duringCleanup ? [{ at: 2, reason: "stop" }, { at: 2, reason: "later" }] : [{ at: 1, reason: "stop" }, { at: 2, reason: "later" }];
    const number = [41, 0, 0, 0, 0, 0, 0, 0];
    const oracle = execute(source, [], duringCleanup ? [number, [], []] : [number, []], controls);
    const trace = [];
    const observe = (step) => {
      assert.equal(step.kind, "Requested");
      const request = decodeRequest(step.request);
      trace.push({ kind: "Requested", identity: request.semanticIdentity, payload: [...request.payload] });
    };
    let step = await compare("run", { image, initialArgs: new Uint8Array() });
    observe(step);
    step = await compare("run", { image, state: step.state, result: encodeResult(step.request, Uint8Array.from(number)) });
    observe(step);
    step = duringCleanup
      ? await compare("run", { image, state: step.state, result: encodeResult(step.request, new Uint8Array()) })
      : await compare("run", { image, state: step.state, cancel: "stop" });
    observe(step);
    const obtained = encodeResult(step.request, new Uint8Array());
    const oldRequest = decodeRequest(step.request);
    const rebound = await compare("run", { image, state: step.state, cancel: duringCleanup ? "stop" : "later" });
    const newRequest = decodeRequest(rebound.request);
    assert.deepEqual(newRequest.payload, oldRequest.payload);
    assert.deepEqual(newRequest.residualContractDigest, oldRequest.residualContractDigest);
    if (duringCleanup) {
      assert.notDeepEqual(newRequest.requestIdentity, oldRequest.requestIdentity);
      await assert.rejects(compare("run", { image, state: rebound.state, result: obtained }), /InvalidResult/);
    } else assert.deepEqual(rebound.bytes, step.bytes);
    const repeated = await compare("run", { image, state: rebound.state, cancel: "later" });
    assert.deepEqual(repeated.bytes, rebound.bytes);
    step = await compare("run", { image, state: repeated.state, result: encodeResult(repeated.request, new Uint8Array()) });
    assert.equal(step.kind, oracle.kind);
    assert.equal(step.reason, oracle.reason);
    assert.deepEqual(step.cleanupFailures.map((bytes) => [...bytes]), oracle.cleanupFailures);
    assert.deepEqual(trace, oracle.trace);
  }
  for (const primary of [0, 1]) for (const cancel of [false, true]) {
    const source = JSON.parse(await readFile(join(fixtures, "source-unwind.json"), "utf8"));
    const image = new Uint8Array(await readFile(join(fixtures, "source-unwind.bpi2")));
    const oracle = execute(source, [primary], [[], []], cancel ? [{ at: 0, reason: "stop" }, { at: 0, reason: "later" }] : []);
    const trace = [];
    let step = await compare("run", { image, initialArgs: Uint8Array.of(primary) });
    while (step.kind === "Requested") {
      const request = decodeRequest(step.request);
      trace.push({ kind: "Requested", identity: request.semanticIdentity, payload: [...request.payload] });
      if (cancel && trace.length === 1) {
        const obtained = encodeResult(step.request, new Uint8Array());
        step = await compare("run", { image, state: step.state, cancel: "stop" });
        await assert.rejects(compare("run", { image, state: step.state, result: obtained }), /InvalidResult/);
        const repeated = await compare("run", { image, state: step.state, cancel: "later" });
        assert.deepEqual(repeated.bytes, step.bytes);
        step = repeated;
      }
      step = await compare("run", { image, state: step.state, result: encodeResult(step.request, new Uint8Array()) });
    }
    assert.equal(step.kind, oracle.kind);
    assert.deepEqual(step.value, Uint8Array.from(oracle.value));
    assert.deepEqual(step.cleanupFailures.map((bytes) => [...bytes]), oracle.cleanupFailures);
    assert.equal(step.cancellation, oracle.cancellation);
    assert.deepEqual(trace, oracle.trace);
  }
  console.log("source oracle/native/WASM agreement and fresh transfers passed for thirty-five compiled source examples and cancellation scenarios");
  if (peer) console.log(`Wasmtime ${peer.identity.wasmtime} matched all source checkpoints; kernel ${peer.identity.kernel_sha256}`);
} finally { if (peer) await peer.close(); }
