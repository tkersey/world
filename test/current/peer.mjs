import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { resolve } from "node:path";
export async function wasmtimePeer(kernel, digest) {
  const child = spawn("uv", ["run", "--frozen", "--project", resolve(import.meta.dirname, "../v2/wasmtime"), "--python", "3.14.7", "python", resolve(import.meta.dirname, "wasmtime_peer.py"), kernel, digest], { stdio: ["pipe", "pipe", "inherit"] });
  const pending = new Map();
  let next = 0, readyResolve, readyReject, exitResolve, exitReject;
  const ready = new Promise((resolve, reject) => { readyResolve = resolve; readyReject = reject; });
  const exited = new Promise((resolve, reject) => { exitResolve = resolve; exitReject = reject; });
  exited.catch(() => {});
  const fail = error => { readyReject(error); for (const item of pending.values()) item.reject(error); pending.clear(); exitReject(error); };
  child.on("error", fail);
  child.on("exit", (code, signal) => code === 0 && pending.size === 0 ? exitResolve() : fail(new Error(`Wasmtime exited: ${code ?? signal}`)));
  const lines = createInterface({ input: child.stdout });
  lines.on("line", line => {
    try {
      const record = JSON.parse(line);
      if (record.ready) return readyResolve(record);
      const item = pending.get(record.id);
      if (!item) throw new Error("unexpected Wasmtime response");
      pending.delete(record.id);
      if (record.error) item.reject(new Error(record.error));
      else item.resolve({ ...record, bytes: new Uint8Array(Buffer.from(record.bytes, "base64")) });
    } catch (error) { fail(error); child.kill(); }
  });
  return {
    identity: await ready,
    call(op, { bytes = new Uint8Array(), ...options } = {}) {
      const id = next++;
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        child.stdin.write(JSON.stringify({ id, op, ...options, bytes: Buffer.from(bytes).toString("base64") }) + "\n", error => { if (error) fail(error); });
      });
    },
    async close() { child.stdin.end(); await exited; lines.close(); },
  };
}
