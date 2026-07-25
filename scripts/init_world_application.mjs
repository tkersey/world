import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const options = parseArgs(process.argv.slice(2));
const output = resolve(options.output);
if (existsSync(output) && readdirSync(output).length !== 0) {
  throw new Error(`output directory is not empty: ${output}`);
}
const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const template = resolve(packageRoot, "templates/application-v1");
mkdirSync(output, { recursive: true });
cpSync(template, output, { recursive: true, errorOnExist: true });

const zonPath = resolve(output, "build.zig.zon");
const zon = readFileSync(zonPath, "utf8")
  .replace("__WORLD_RELEASE_URL__", options.worldUrl)
  .replace("__WORLD_RELEASE_HASH__", options.worldHash);
if (zon.includes("__WORLD_RELEASE_")) {
  throw new Error("World release identity substitution was incomplete");
}
writeFileSync(zonPath, zon);

console.log(`world_application_output=${output}`);
console.log(`world_release_url=${options.worldUrl}`);
console.log(`world_release_hash=${options.worldHash}`);

function parseArgs(args) {
  const values = new Map();
  for (let index = 0; index < args.length; index += 2) {
    const key = args[index];
    const value = args[index + 1];
    if (!key?.startsWith("--") || value === undefined) {
      throw new Error(
        "usage: node init_world_application.mjs --output PATH --world-url URL --world-hash HASH",
      );
    }
    if (values.has(key)) throw new Error(`duplicate option: ${key}`);
    values.set(key, value);
  }
  for (const key of ["--output", "--world-url", "--world-hash"]) {
    if (!values.get(key)) throw new Error(`missing required option: ${key}`);
  }
  return {
    output: values.get("--output"),
    worldUrl: values.get("--world-url"),
    worldHash: values.get("--world-hash"),
  };
}
