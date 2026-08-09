import { createHash } from "node:crypto";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  callStep,
  copyExported,
  encodeOkResult,
  encodeStepInput,
} from "./world_application_v1_conformance.mjs";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const releaseTag = "v2.0.0";
const releaseCommit = "8adc2df6ae4afa30992a1e97cd7ed0e2da970049";
const options = parseArgs(process.argv.slice(2));

function materializeHarness(root) {
  const resolved = run("git", ["rev-parse", `refs/tags/${releaseTag}^{commit}`], packageRoot).stdout.trim();
  if (resolved !== releaseCommit) throw new Error(`${releaseTag} resolved to ${resolved}, expected ${releaseCommit}`);

  const archive = spawnSync("git", [
    "archive", "--format=tar", releaseTag,
    "src/application_runtime_v1.zig",
    "src/application_v1.zig",
    "src/application_wasm_v1.zig",
  ], { cwd: packageRoot, maxBuffer: 16 * 1024 * 1024 });
  if (archive.status !== 0) throw commandError("git archive", archive);
  mkdirSync(join(root, "world2"));
  const extract = spawnSync("tar", ["-xf", "-", "-C", join(root, "world2")], { input: archive.stdout });
  if (extract.status !== 0) throw commandError("tar extract", extract);

  mkdirSync(join(root, "world3", "src"), { recursive: true });
  for (const file of ["application_runtime_v1.zig", "application_v1.zig", "application_wasm_v1.zig"]) {
    cpSync(join(packageRoot, "src", file), join(root, "world3", "src", file));
  }
  cpSync(join(packageRoot, "test", "parity"), join(root, "parity"), { recursive: true });
  cpSync(join(packageRoot, "test", "parity", "world2.zig"), join(root, "world2", "src", "parity_world.zig"));
  cpSync(join(packageRoot, "test", "parity", "world3.zig"), join(root, "world3", "src", "parity_world.zig"));
  writeFileSync(join(root, "build.zig"), harnessBuild);
  writeFileSync(join(root, "build.zig.zon"), harnessZon);
}

async function runParity(root) {
  const outputs = {};
  for (const release of ["2", "3"]) {
    const prefix = join(root, `out${release}`);
    run(options.zig, ["build", `-Drelease=${release}`, "--prefix", prefix, "--summary", "all"], root);
    outputs[`world${release}`] = readFileSync(join(prefix, "bin", "application.world.wasm"));
  }
  if (!outputs.world2.equals(outputs.world3)) {
    const offset = firstDifference(outputs.world2, outputs.world3);
    throw new Error(`application_wasm differs at offset=${offset} world2_sha256=${sha256(outputs.world2)} world3_sha256=${sha256(outputs.world3)}`);
  }
  const module2 = await WebAssembly.compile(outputs.world2);
  const module3 = await WebAssembly.compile(outputs.world3);
  const world2 = await lifecycle(module2, outputs.world2);
  const world3 = await lifecycle(module3, outputs.world3);
  compareSnapshots(world2, world3);
  return { world2, world3 };
}

async function lifecycle(module, wasm) {
  const genesis = (await WebAssembly.instantiate(module, {})).exports;
  const manifest = copyExported(genesis, "world_manifest_ptr", "world_manifest_len");
  const applicationId = manifest.subarray(12, 44);
  const genesisInput = encodeStepInput({ applicationId, initialArgs: u32(7), fuel: 100n });
  if (callStep(genesis, genesisInput) !== 0) throw new Error("genesis step failed");
  const firstFrame = copyExported(genesis, "world_output_ptr", "world_output_len");
  const first = inspectFrame(firstFrame);
  if (first.pendingRequest === null) throw new Error("genesis did not produce a pending EffectRequest");
  const result = encodeOkResult(first.request, u32(41));
  const continuationInput = encodeStepInput({
    applicationId,
    expectedParentFrameId: first.frameId,
    priorFrame: firstFrame,
    effectResult: result.bytes,
    fuel: 100n,
  });
  const resumed = (await WebAssembly.instantiate(module, {})).exports;
  if (callStep(resumed, continuationInput) !== 0) throw new Error("continuation step failed");
  const terminalFrame = copyExported(resumed, "world_output_ptr", "world_output_len");
  const terminalResult = inspectFrame(terminalFrame).finalResult;
  if (terminalResult === null) throw new Error("continuation did not produce a terminal result");
  const retry = (await WebAssembly.instantiate(module, {})).exports;
  if (callStep(retry, continuationInput) !== 0) throw new Error("retry step failed");
  const retryChild = copyExported(retry, "world_output_ptr", "world_output_len");
  if (!retryChild.equals(terminalFrame)) throw new Error("fresh-instance retry child is not deterministic");
  return { wasm, manifest, firstFrame, pendingRequest: first.pendingRequest, terminalFrame, terminalResult, retryChild };
}

function compareSnapshots(left, right) {
  for (const [field, label] of [
    ["manifest", "application_manifest"],
    ["wasm", "application_wasm"],
    ["firstFrame", "first_frame"],
    ["pendingRequest", "pending_effect_request"],
    ["terminalFrame", "terminal_frame"],
    ["terminalResult", "terminal_result"],
    ["retryChild", "deterministic_retry_child"],
  ]) {
    if (!left[field].equals(right[field])) throw new Error(`${label} differs at offset=${firstDifference(left[field], right[field])}`);
  }
}

function inspectFrame(bytes) {
  const reader = new Reader(bytes);
  reader.skip(8 + 4);
  const frameId = reader.take(32);
  reader.skip(32);
  reader.optionalDigest();
  reader.skip(8);
  reader.lenBytes();
  const pendingRequest = reader.bool() ? reader.lenBytes() : null;
  const request = pendingRequest === null ? null : inspectRequest(pendingRequest);
  reader.optionalDigest();
  reader.skip(1);
  reader.optionalDigest();
  const finalResult = reader.optionalBytes();
  return { frameId, pendingRequest, request, finalResult };
}

function inspectRequest(bytes) {
  const reader = new Reader(bytes);
  reader.skip(8 + 4);
  const requestId = reader.take(32);
  reader.skip(32 + 32 + 8 + 4 + 8 + 32 + 32);
  const resultSchemaId = reader.take(32);
  return { requestId, resultSchemaId };
}

function structuredCloneSnapshot(value) {
  return Object.fromEntries(Object.entries(value).map(([key, bytes]) => [key, Buffer.from(bytes)]));
}

function firstDifference(left, right) {
  const length = Math.min(left.length, right.length);
  for (let index = 0; index < length; index += 1) if (left[index] !== right[index]) return index;
  return length;
}

function sha256(bytes) { return createHash("sha256").update(bytes).digest("hex"); }
function u32(value) { const bytes = Buffer.alloc(4); bytes.writeUInt32LE(value); return bytes; }

function parseArgs(args) {
  const result = { negativeSelfTest: false, zig: null };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--negative-self-test") {
      if (result.negativeSelfTest) throw new Error("duplicate --negative-self-test");
      result.negativeSelfTest = true;
      continue;
    }
    if (arg === "--zig") {
      index += 1;
      if (!args[index] || result.zig !== null) throw new Error("--zig requires one unique executable path");
      result.zig = resolve(args[index]);
      continue;
    }
    throw new Error(`unknown option: ${arg}`);
  }
  if (result.zig === null) throw new Error("missing required --zig executable path");
  return result;
}

function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8" });
  if (result.status !== 0) throw commandError(`${command} ${args.join(" ")}`, result);
  return result;
}

function commandError(label, result) {
  return new Error(`${label} failed:\n${result.stdout ?? ""}\n${result.stderr ?? ""}`);
}

class Reader {
  constructor(value) { this.value = value; this.offset = 0; }
  take(length) { const result = this.value.subarray(this.offset, this.offset + length); this.offset += length; return result; }
  skip(length) { this.take(length); }
  bool() { return this.take(1)[0] === 1; }
  u32() { return this.take(4).readUInt32LE(); }
  lenBytes() { return this.take(this.u32()); }
  optionalBytes() { return this.bool() ? this.lenBytes() : null; }
  optionalDigest() { return this.bool() ? this.take(32) : null; }
}

const harnessZon = `.{
    .name = .world_parity_harness,
    .version = "0.0.0",
    .fingerprint = 0x413e143b5dc2870e,
    .dependencies = .{
        .boundary = .{
            .url = "git+https://github.com/tkersey/boundary.git#v1.0.0",
            .hash = "boundary-1.0.0-flclaPgFEQBhYvlC3eqNVK3X67InkTuaX-pHFvRLzWJ8",
        },
    },
    .minimum_zig_version = "0.16.0",
    .paths = .{ "build.zig", "build.zig.zon", "parity", "world2", "world3" },
}`;

const harnessBuild = `const std = @import("std");
pub fn build(b: *std.Build) void {
    const release = b.option(u8, "release", "World release to build (2 or 3)") orelse @panic("missing -Drelease");
    if (release != 2 and release != 3) @panic("release must be 2 or 3");
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding, .abi = .none });
    const boundary = b.dependency("boundary", .{ .target = target, .optimize = .ReleaseSmall }).module("boundary");
    const world = b.createModule(.{
        .root_source_file = b.path(if (release == 2) "world2/src/parity_world.zig" else "world3/src/parity_world.zig"),
        .target = target, .optimize = .ReleaseSmall,
        .imports = if (release == 2) &.{.{ .name = "boundary_machine", .module = boundary }} else &.{.{ .name = "boundary", .module = boundary }},
    });
    const application = b.createModule(.{
        .root_source_file = b.path("parity/application.zig"), .target = target, .optimize = .ReleaseSmall,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    });
    const artifact = b.addExecutable(.{
        .name = "application.world",
        .root_module = b.createModule(.{
            .root_source_file = b.path("parity/wasm_main.zig"), .target = target, .optimize = .ReleaseSmall,
            .imports = &.{ .{ .name = "world", .module = world }, .{ .name = "parity_application", .module = application } },
        }),
    });
    artifact.entry = .disabled;
    artifact.rdynamic = true;
    artifact.export_memory = true;
    artifact.stack_size = 1024 * 1024;
    artifact.initial_memory = 8 * 1024 * 1024;
    artifact.max_memory = 8 * 1024 * 1024;
    b.installArtifact(artifact);
}`;

const temporaryRoot = mkdtempSync(join(tmpdir(), "world-2-3-parity-"));
try {
  materializeHarness(temporaryRoot);
  const snapshots = await runParity(temporaryRoot);
  if (options.negativeSelfTest) {
    const drifted = structuredCloneSnapshot(snapshots.world3);
    drifted.terminalResult[0] ^= 1;
    try {
      compareSnapshots(snapshots.world2, drifted);
      throw new Error("parity comparator accepted injected terminal_result drift");
    } catch (error) {
      if (!String(error.message).includes("terminal_result")) throw error;
    }
    console.log("world2_world3_negative_self_test=true");
    console.log("world2_world3_fixed_identity_parity_negative=true");
  } else {
    console.log("world2_tag_identity=true");
    console.log("boundary_v1_only=true");
    console.log("application_manifest_byte_parity=true");
    console.log("application_wasm_byte_parity=true");
    console.log("first_frame_byte_parity=true");
    console.log("pending_effect_request_byte_parity=true");
    console.log("resumed_frame_byte_parity=true");
    console.log("terminal_frame_byte_parity=true");
    console.log("terminal_result_byte_parity=true");
    console.log("deterministic_retry_child_byte_parity=true");
    console.log("world2_world3_fixed_identity_parity=true");
  }
} finally {
  rmSync(temporaryRoot, { recursive: true, force: true });
}
