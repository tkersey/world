import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const zon = readFileSync(resolve(root, "build.zig.zon"), "utf8");
const required = [
  '.version = "3.0.0"',
  ".boundary = .{",
  '.url = "git+https://github.com/tkersey/boundary.git#v1.0.0"',
  '.hash = "boundary-1.0.0-flclaPgFEQBhYvlC3eqNVK3X67InkTuaX-pHFvRLzWJ8"',
];
for (const token of required) {
  if (!zon.includes(token)) throw new Error(`missing exact package identity: ${token}`);
}
const dependencyBody = zon.match(/\.dependencies\s*=\s*\.\{([\s\S]*?)\n\s*\},\n\s*\.minimum_zig_version/)?.[1];
if (!dependencyBody) throw new Error("cannot parse build.zig.zon dependencies");
const names = [...dependencyBody.matchAll(/^\s*\.([A-Za-z0-9_]+)\s*=\s*\.\{/gm)].map((match) => match[1]);
if (names.length !== 1 || names[0] !== "boundary") {
  throw new Error(`World must have exactly one dependency named boundary; found ${names.join(", ")}`);
}
if (/boundary_machine|v0\.7\.0/.test(zon)) throw new Error("legacy Boundary dependency identity remains");
console.log("world_boundary_dependency=pass");
