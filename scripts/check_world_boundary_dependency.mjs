import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const options = parseArgs(process.argv.slice(2));

if (options.negativeSelfTest) {
  checkDependency(packageRoot);
  runNegativeSelfTest();
} else {
  checkDependency(options.root ?? packageRoot);
  console.log("world_boundary_dependency=pass");
}

function checkDependency(root) {
  const zon = readFileSync(resolve(root, "build.zig.zon"), "utf8");
  for (const token of [
    '.version = "3.1.4"',
    ".boundary = .{",
    '.url = "https://github.com/tkersey/boundary/archive/f83bd53a42ced5f5fa1fa7e28c5a7a4e4c2ae372.tar.gz"',
    '.hash = "boundary-1.6.1-flclaETcIgCBxvodwCf6F244764SgbLCdj5qD0Aisn3s"',
  ]) {
    if (!zon.includes(token)) throw new Error(`missing exact package identity: ${token}`);
  }
  const dependencyBody = zon.match(/\.dependencies\s*=\s*\.\{([\s\S]*?)\n\s*\},\n\s*\.minimum_zig_version/)?.[1];
  if (!dependencyBody) throw new Error("cannot parse build.zig.zon dependencies");
  const names = [...dependencyBody.matchAll(/^\s*\.([A-Za-z0-9_]+)\s*=\s*\.\{/gm)].map((match) => match[1]);
  if (names.length !== 1 || names[0] !== "boundary") {
    throw new Error(`World must have exactly one dependency named boundary; found ${names.join(", ")}`);
  }
  const legacyNames = [["boundary", "_machine"].join(""), ["v0", ".7.0"].join("")];
  if (legacyNames.some((name) => zon.includes(name))) throw new Error("legacy Boundary dependency identity remains");
}

function runNegativeSelfTest() {
  const temporaryRoot = mkdtempSync(join(tmpdir(), "world-boundary-negative-"));
  try {
    cpSync(resolve(packageRoot, "build.zig.zon"), resolve(temporaryRoot, "build.zig.zon"));
    const zonPath = resolve(temporaryRoot, "build.zig.zon");
    const injectedName = ["boundary", "_legacy"].join("");
    const injectedVersion = ["v0", ".7.0"].join("");
    const injected = readFileSync(zonPath, "utf8").replace(
      "    .minimum_zig_version",
      `        .${injectedName} = .{\n            .url = "https://example.invalid/boundary-${injectedVersion}.tar.gz",\n            .hash = "${injectedName}_injected",\n        },\n    },\n    .minimum_zig_version`,
    ).replace(`    },\n        .${injectedName}`, `        .${injectedName}`);
    writeFileSync(zonPath, injected);
    const result = spawnSync(process.execPath, [fileURLToPath(import.meta.url), "--root", temporaryRoot], { encoding: "utf8" });
    const diagnostic = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
    if (result.status === 0) throw new Error(`dependency checker accepted injected ${injectedName}`);
    if (!diagnostic.includes(injectedName)) throw new Error(`dependency checker rejected for the wrong reason:\n${diagnostic}`);
    console.log("world_boundary_dependency_negative=pass");
  } finally {
    rmSync(temporaryRoot, { recursive: true, force: true });
  }
}

function parseArgs(args) {
  const result = { root: null, negativeSelfTest: false };
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === "--negative-self-test") {
      if (result.negativeSelfTest) throw new Error("duplicate --negative-self-test");
      result.negativeSelfTest = true;
    } else if (args[index] === "--root") {
      index += 1;
      if (!args[index] || result.root !== null) throw new Error("--root requires one unique path");
      result.root = resolve(args[index]);
    } else {
      throw new Error(`unknown option: ${args[index]}`);
    }
  }
  if (result.negativeSelfTest && result.root !== null) throw new Error("--negative-self-test does not accept --root");
  return result;
}
