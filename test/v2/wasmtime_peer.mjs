// IPC for an independent ABI embedding; no program instructions are inspected.
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { join, resolve } from "node:path";

export async function wasmtimePeer(project, kernel, digest) {
  const cache = resolve(import.meta.dirname, "../../.cache/v2");
  const child = spawn("uv", ["run", "--locked", "--project", project, "--python", "3.14.7", "python", join(project, "embedding.py"), kernel, digest], {
    stdio: ["pipe", "pipe", "inherit"],
    env: { ...process.env, UV_CACHE_DIR: join(cache, "uv"), UV_PROJECT_ENVIRONMENT: join(cache, "wasmtime-environment") },
  });
  const pending = new Map();
  let next = 0, readyResolve, readyReject, exitResolve, exitReject;
  const ready = new Promise((resolve, reject) => { readyResolve = resolve; readyReject = reject; });
  const exited = new Promise((resolve, reject) => { exitResolve = resolve; exitReject = reject; });
  // Startup errors are handled by ready; suppress an unobserved exit rejection.
  exited.catch(() => {});
  const fail = (error) => {
    readyReject(error);
    for (const request of pending.values()) request.reject(error);
    pending.clear();
    exitReject(error);
  };
  child.on("error", fail);
  child.on("exit", (code, signal) => {
    if (code !== 0 || pending.size) fail(new Error(`Wasmtime embedding exited: ${code ?? signal}`));
    else exitResolve();
  });
  const lines = createInterface({ input: child.stdout });
  lines.on("line", (line) => {
    try {
      const record = JSON.parse(line);
      if (record.ready) { readyResolve(record); return; }
      const request = pending.get(record.id);
      if (!request) throw new Error("Unexpected Wasmtime response");
      pending.delete(record.id);
      if (record.error !== undefined) request.reject(new Error(record.error));
      else request.resolve(new Uint8Array(Buffer.from(record.pko, "base64")));
    } catch (error) { fail(error); child.kill(); }
  });
  const identity = await ready;
  return {
    identity,
    invoke(bytes) {
      const id = next++;
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        child.stdin.write(JSON.stringify({ id, pki: Buffer.from(bytes).toString("base64") }) + "\n", (error) => { if (error) fail(error); });
      });
    },
    async close() { child.stdin.end(); await exited; lines.close(); },
  };
}
