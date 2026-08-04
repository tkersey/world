import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const productionSources = [
  "src/application_v1.zig",
  "src/application_runtime_v1.zig",
  "src/application_wasm_v1.zig",
  "src/application_wasm_main_v1.zig",
  "src/world_v1.zig",
];
const forbidden = [
  "Program.Session",
  "StaticMachine",
  "LoadedModule",
  "loaded_execution",
  "ProgramPlan",
  "InstructionKind",
  "function_ordinal",
  "block_ordinal",
  "instruction_ordinal",
];

const sources = new Map(
  productionSources.map((path) => [path, readFileSync(join(root, path), "utf8")]),
);
const runtime = sources.get("src/application_runtime_v1.zig");

assert(runtime.includes('@import("boundary_machine")'));
for (const delegatedOperation of [
  "Machine.step",
  "Machine.current",
  "Machine.prepareResume",
  'Machine.@"resume"',
  "Machine.encodeState",
  "Machine.decodeState",
]) {
  assert(runtime.includes(delegatedOperation), `Machine path does not delegate ${delegatedOperation}`);
}

for (const [path, source] of sources) {
  for (const marker of forbidden) {
    assert(!source.includes(marker), `${path} retains legacy interpreter marker ${marker}`);
  }
}

console.log("boundary_machine_codec_delegation=true");
console.log("runtime_program_plan_decode=false");
console.log("generic_instruction_dispatch=false");
