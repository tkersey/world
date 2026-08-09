import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const options = parseArgs(process.argv.slice(2));
if (!existsSync(options.zig)) throw new Error(`Zig executable does not exist: ${options.zig}`);

const listed = spawnSync("git", ["ls-files", "-z", "--", "*.zig"], {
  cwd: packageRoot,
  encoding: "buffer",
});
if (listed.status !== 0) throw commandError("git ls-files", listed);
const sources = listed.stdout
  .toString("utf8")
  .split("\0")
  .filter(Boolean)
  .filter((path) => existsSync(resolve(packageRoot, path)));
if (sources.length === 0) throw new Error("no tracked Zig sources found");
if (sources.some((path) => /(^|\/)(\.zig-cache|zig-cache|zig-out|zig-pkg|vendor)(\/|$)/.test(path))) {
  throw new Error("tracked Zig source enumeration entered an ignored cache or vendor tree");
}
const formatted = spawnSync(options.zig, ["fmt", "--check", ...sources], {
  cwd: packageRoot,
  encoding: "utf8",
  maxBuffer: 16 * 1024 * 1024,
});
if (formatted.status !== 0) throw commandError("zig fmt --check", formatted);

console.log(`world_lint_tracked_zig_sources=${sources.length}`);
console.log(`world_lint_max_warnings=${options.maxWarnings}`);
console.log("world_lint=pass");

function parseArgs(args) {
  const result = { zig: null, maxWarnings: null };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--zig") {
      index += 1;
      if (!args[index] || result.zig !== null) throw new Error("--zig requires one unique executable path");
      result.zig = resolve(args[index]);
    } else if (arg === "--max-warnings") {
      index += 1;
      if (!args[index] || result.maxWarnings !== null) throw new Error("--max-warnings requires one unique value");
      if (args[index] !== "0") throw new Error("--max-warnings must equal 0");
      result.maxWarnings = 0;
    } else {
      throw new Error(`unknown option: ${arg}`);
    }
  }
  if (result.zig === null) throw new Error("missing required --zig executable path");
  if (result.maxWarnings === null) result.maxWarnings = 0;
  return result;
}

function commandError(label, result) {
  return new Error(`${label} failed:\n${result.stdout ?? ""}\n${result.stderr ?? ""}`);
}
