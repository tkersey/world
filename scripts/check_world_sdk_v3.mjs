import assert from "node:assert/strict";
import { appendFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const options = parseArgs(process.argv.slice(2));
const root = mkdtempSync(join(tmpdir(), "world-sdk-v3-check-"));
const sdkRoot = join(root, "world-sdk-v3.0.0");

try {
  const built = run(process.execPath, [
    join(sourceRoot, "scripts/build_world_sdk_v3.mjs"),
    "--output",
    sdkRoot,
    "--zig",
    options.zig,
  ]);
  assert(built.stdout.includes("sdk_archives_authenticated=true"));
  const checked = run(process.execPath, [join(sdkRoot, "conformance/check-sdk.mjs")]);
  assert(checked.stdout.includes("world_sdk_v3=true"));
  const external = run(process.execPath, [
    join(sdkRoot, "conformance/external-consumer/run.mjs"),
    "--zig",
    options.zig,
  ]);
  assert(external.stdout.includes("world_3_released_artifact_externality=true"));
  appendFileSync(join(sdkRoot, "world/archive/world-v3.0.0.tar.gz"), Buffer.from([0]));
  const tampered = spawnSync(process.execPath, [join(sdkRoot, "conformance/check-sdk.mjs")], {
    cwd: sourceRoot,
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  assert.notEqual(tampered.status, 0, "SDK verifier accepted a tampered World archive");
  assert(`${tampered.stdout ?? ""}\n${tampered.stderr ?? ""}`.includes("SDK checksum mismatch"));
  console.log("check_world_3_externality=pass");
  console.log("check_world_sdk_v3_negative=pass");
  console.log("check_world_sdk_v3=pass");
} finally {
  rmSync(root, { recursive: true, force: true });
}

function run(command, args) {
  const result = spawnSync(command, args, { cwd: sourceRoot, encoding: "utf8", maxBuffer: 128 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed:\n${result.stdout ?? ""}\n${result.stderr ?? ""}`);
  return result;
}

function parseArgs(args) {
  const result = { zig: "zig" };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    const value = args[++index];
    if (key !== "--zig" || !value) throw new Error("usage: node scripts/check_world_sdk_v3.mjs [--zig <path>]");
    result.zig = value.includes("/") ? resolve(value) : value;
  }
  return result;
}
