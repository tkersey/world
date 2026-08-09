import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = readFileSync(resolve(root, "src/world.zig"), "utf8");
const required = [
  "pub const protocol",
  "pub const v1",
  "pub const application",
  "pub const handle",
  "pub const external",
  "pub const Authority",
  "pub const ResponseMode",
  "pub const ApplicationAbiV1",
  "pub const WasmOptions",
  "pub const WasmStatus",
  "pub const validateResultForRequest",
];
for (const token of required) {
  if (!source.includes(token)) throw new Error(`missing canonical public surface: ${token}`);
}
for (const forbidden of [
  'pub const v1 = @import("world_v1.zig")',
  "pub const ApplicationAbi =",
  "boundary_machine",
]) {
  if (source.includes(forbidden)) throw new Error(`legacy public surface remains: ${forbidden}`);
}
console.log("world_public_surface=pass");
