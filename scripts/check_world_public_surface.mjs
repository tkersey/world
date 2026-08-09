import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const options = parseArgs(process.argv.slice(2));
const rootDeclarations = [
  "protocol", "Authority", "ResponseMode", "handle", "external", "application",
  "valueSchemaId", "siteId", "encodeValue", "WasmOptions", "WasmStatus", "ApplicationAbiV1",
];
const protocolDeclarations = [
  "format_version", "abi_version", "Digest", "zero_digest", "Error", "Limits",
  "EffectStatus", "AllowedStatuses", "EffectLimits", "EffectRequest", "EffectResult",
  "FrameStatus", "ResourceCounters", "Frame", "StepInput", "ResidualEffect",
  "ApplicationManifest", "digestLabel", "validateResultForRequest",
];

if (options.negativeSelfTest) {
  checkSurface(packageRoot);
  runNegativeSelfTest();
} else {
  checkSurface(options.root ?? packageRoot);
  console.log("world_public_surface=pass");
}

function checkSurface(root) {
  const source = readFileSync(resolve(root, "src/world.zig"), "utf8");
  const actualRoot = [...source.matchAll(/^pub (?:const|fn|var) ([A-Za-z0-9_]+)\b/gm)].map((match) => match[1]);
  assertExact("top-level root declarations", actualRoot, rootDeclarations);
  const protocolBody = source.match(/pub const protocol = struct \{\n\s*pub const v1 = struct \{([\s\S]*?)\n\s*\};\n\};/)?.[1];
  if (!protocolBody) throw new Error("missing canonical protocol.v1 nesting");
  const actualProtocol = [...protocolBody.matchAll(/^\s*pub (?:const|fn|var) ([A-Za-z0-9_]+)\b/gm)].map((match) => match[1]);
  assertExact("protocol.v1 declarations", actualProtocol, protocolDeclarations);
  if (/boundary_machine|world_v1|pub const ApplicationAbi\s*=/.test(source)) {
    throw new Error("legacy public declaration remains");
  }
}

function assertExact(label, actual, expected) {
  if (actual.join("\n") !== expected.join("\n")) {
    const extra = actual.filter((name) => !expected.includes(name));
    const missing = expected.filter((name) => !actual.includes(name));
    throw new Error(`${label} differ; extra=${extra.join(",")}; missing=${missing.join(",")}`);
  }
}

function runNegativeSelfTest() {
  const temporaryRoot = mkdtempSync(join(tmpdir(), "world-public-negative-"));
  try {
    cpSync(resolve(packageRoot, "src"), resolve(temporaryRoot, "src"), { recursive: true });
    const worldPath = resolve(temporaryRoot, "src/world.zig");
    writeFileSync(worldPath, `${readFileSync(worldPath, "utf8")}\npub const legacy_runtime = true;\n`);
    const result = spawnSync(process.execPath, [fileURLToPath(import.meta.url), "--root", temporaryRoot], { encoding: "utf8" });
    const diagnostic = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
    if (result.status === 0) throw new Error("public surface checker accepted injected legacy_runtime");
    if (!diagnostic.includes("legacy_runtime")) throw new Error(`public surface checker rejected for the wrong reason:\n${diagnostic}`);
    console.log("world_public_surface_negative=pass");
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
