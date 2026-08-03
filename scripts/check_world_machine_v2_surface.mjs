import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const surfaces = new Map([
  ["README.md", ["Boundary Machine ABI v2", "world.application"]],
  ["docs/application_v1.md", ["Boundary Machine ABI v2", "RNF Machine state"]],
  ["docs/static_handlers.md", ["Boundary Machine ABI v2"]],
  ["templates/application-v1/README.md", ["research.lookup.v2", "Vector"]],
]);
const forbidden = ["StaticMachine", "Program.Session"];

for (const [path, required] of surfaces) {
  const source = readFileSync(join(root, path), "utf8");
  for (const marker of required) {
    assert(source.includes(marker), `${path} is missing ${marker}`);
  }
  for (const marker of forbidden) {
    assert(!source.includes(marker), `${path} retains ${marker}`);
  }
}

console.log("boundary_machine_abi=2");
console.log("static_machine_primary_docs=false");
console.log("program_session_primary_docs=false");
