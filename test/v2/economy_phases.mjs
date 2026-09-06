import assert from "node:assert/strict";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { encodeInput } from "../../src/process_v2/index.mjs";

const [boundary, profiler, output, baselineProfiler] = process.argv.slice(2);
assert.ok(output, "expected Boundary source, phase profiler, output directory and optional prior cloner profiler");
await mkdir(output, { recursive: true });
const digest = bytes => createHash("sha256").update(bytes).digest("hex");
const median = values => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const workloads = [];
for (const [name, file, initial] of [
  ["one-shot", "source-deep.bpi2", []],
  ["multi", "source-choices-all.bpi2", []],
  ["local-cells", "source-state-local.bpi2", []],
  ["shared-cells", "source-state-shared.bpi2", []],
  ["retained-search", "source-queens-dfs.bpi2", []],
  ["cleanup", "source-unwind.bpi2", [1]],
  ["install-64", "economy-64.bpi2", []],
]) {
  const image = new Uint8Array(await readFile(join(boundary, "zig-out/v2", file)));
  const input = encodeInput({ image, initialArgs: Uint8Array.from(initial), mode: "run" });
  const variants = [];
  for (const [label, executable] of [["after", profiler], ...(baselineProfiler ? [["before", baselineProfiler]] : [])]) {
    const run = spawnSync(executable, [], { input, maxBuffer: 16 << 20, timeout: 60000 });
    assert.equal(run.status, 0, run.stderr?.toString());
    const result = JSON.parse(run.stdout.toString());
    await writeFile(join(output, `${name}-${label}.json`), JSON.stringify(result, null, 2) + "\n");
    const phases = {};
    for (const phase of Object.keys(result.measurements[0].phases)) {
      const samples = result.measurements.map(row => row.phases[phase]);
      phases[phase] = median(samples);
      await writeFile(join(output, `${name}-${label}-${phase}.txt`), samples.join("\n") + "\n");
    }
    const first = result.measurements[0];
    variants.push({ label, executableSha256: digest(await readFile(executable)), phaseMediansNs: phases, statistics: first.statistics, peakWorkingBytes: first.peak_working_bytes, outputBytes: first.output_bytes, outputSha256: first.output_sha256 });
  }
  // Complete results have identical external value bytes across both cloners.
  // A retained snapshot may legitimately contain fewer immutable containers.
  if (baselineProfiler && name !== "retained-search") assert.equal(variants[0].outputSha256, variants[1].outputSha256);
  workloads.push({ name, file, imageSha256: digest(image), variants });
  console.log(JSON.stringify({ name, variants }));
}
await writeFile(join(output, "phases.json"), JSON.stringify({ format: "world-v2-phase-economy/v1", method: "21 native ReleaseSafe samples after five warmups; one shared admitted image; initialization, transition categories, collection and serialization timed independently; branch creation includes activation and return-continuation setup; whole-invocation working peaks; no environmental effects resolved", workloads }, null, 2) + "\n");
