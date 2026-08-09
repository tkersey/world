import {
  cpSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const options = parseArgs(process.argv.slice(2));

if (options.negativeSelfTest) {
  checkSingularity(packageRoot);
  runNegativeSelfTest();
} else {
  checkSingularity(options.root ?? packageRoot);
  console.log("world_singularity=pass");
}

function checkSingularity(root) {
  const exact = new Map([
    ["src", ["application_manifest_emit_v1.zig", "application_runtime_v1.zig", "application_selector_v1.zig", "application_v1.zig", "application_wasm_main_v1.zig", "application_wasm_v1.zig", "world.zig"]],
    ["examples", ["world_application_v1_manifest.zig", "world_application_v1_one_effect_wasm.zig", "world_application_v1_wasm.zig"]],
    ["docs", ["application.md", "application_abi_v1.md", "application_state.md", "application_wasm.md", "comptime_closure.md", "dynamic_subagents.md", "effect_protocol_v1.md", "migration_from_world_2.md", "sdk.md", "security_model.md", "zero_to_world_application.md"]],
    ["scripts", ["check_world_2_3_parity.mjs", "check_world_boundary_dependency.mjs", "check_world_lint.mjs", "check_world_machine_native_wasm.mjs", "check_world_public_surface.mjs", "check_world_singularity.mjs", "check_world_source_archive.mjs", "init_world_application.mjs", "world_application_v1_agent_conformance.mjs", "world_application_v1_artifact_check.mjs", "world_application_v1_conformance.mjs", "world_application_v1_research_digest_conformance.mjs"]],
    ["test", ["application_build_options_test.zig", "application_v1_agent_fixtures.zig", "application_v1_fixture_app.zig", "application_v1_golden_test.zig", "application_v1_native_trace.zig", "application_v1_research_digest_app.zig", "application_v1_research_digest_test.zig", "application_v1_skeleton_app.zig", "application_v1_test.zig"]],
  ]);
  for (const [dir, expected] of exact) {
    const actual = readdirSync(resolve(root, dir), { withFileTypes: true })
      .filter((entry) => entry.isFile())
      .map((entry) => entry.name)
      .sort();
    if (actual.join("\n") !== [...expected].sort().join("\n")) {
      throw new Error(`${dir} is not singular:\n${actual.join("\n")}`);
    }
  }

  for (const path of ["src/world_v1.zig", "src/protocol.zig"]) {
    if (existsSync(resolve(root, path))) throw new Error(`legacy path remains: ${path}`);
  }
  const legacyConformanceFiles = existsSync(resolve(root, "conformance/v0"))
    ? readdirOrFile(resolve(root, "conformance/v0"))
    : [];
  if (legacyConformanceFiles.length !== 0) {
    throw new Error(`legacy conformance files remain: ${legacyConformanceFiles.join(", ")}`);
  }

  const scan = ["build.zig", "build_support/application.zig", "src", "examples", "templates", "test"];
  for (const path of walk(root, scan)) {
    const text = readFileSync(path, "utf8");
    if (/world\.v1\b|boundary_machine|world_v1\.zig/.test(text)) {
      throw new Error(`legacy construction surface remains in ${path.slice(root.length + 1)}`);
    }
  }

  for (const name of exact.get("docs")) {
    if (name === "migration_from_world_2.md") continue;
    const text = readFileSync(resolve(root, "docs", name), "utf8");
    if (/World v0|World 2|Boundary v0\.7|TurnClosure|Capsule/.test(text)) {
      throw new Error(`historical concept outside migration document: docs/${name}`);
    }
  }

  const readme = readFileSync(resolve(root, "README.md"), "utf8");
  const first = "World is a Zig comptime application compiler for Boundary Machines.";
  if (!readme.startsWith(first)) throw new Error("README opening sentence is not canonical");
  const flow = "Boundary Machine -> world.application -> application.world.wasm -> world-host -> Effect v1 capabilities";
  if (!readme.slice(0, 1000).includes(flow)) throw new Error("README does not lead with the canonical flow");
}

function runNegativeSelfTest() {
  const temporaryRoot = mkdtempSync(join(tmpdir(), "world-singularity-negative-"));
  try {
    for (const path of [
      "README.md",
      "build.zig",
      "build.zig.zon",
      "build_support",
      "docs",
      "examples",
      "scripts",
      "src",
      "templates",
      "test",
    ]) {
      cpSync(resolve(packageRoot, path), resolve(temporaryRoot, path), { recursive: true });
    }
    writeFileSync(
      resolve(temporaryRoot, "src/world_v1.zig"),
      "pub const legacy_world_surface = true;\n",
    );
    const result = spawnSync(
      process.execPath,
      [fileURLToPath(import.meta.url), "--root", temporaryRoot],
      { encoding: "utf8" },
    );
    const diagnostic = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
    if (result.status === 0) {
      throw new Error("singularity checker accepted an injected src/world_v1.zig surface");
    }
    if (!diagnostic.includes("world_v1.zig")) {
      throw new Error(`singularity checker rejected for the wrong reason:\n${diagnostic}`);
    }
    console.log("world_singularity_negative=pass");
  } finally {
    rmSync(temporaryRoot, { recursive: true, force: true });
  }
}

function parseArgs(args) {
  const result = { root: null, negativeSelfTest: false };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--negative-self-test") {
      if (result.negativeSelfTest) throw new Error("duplicate --negative-self-test");
      result.negativeSelfTest = true;
      continue;
    }
    if (arg === "--root") {
      index += 1;
      if (!args[index] || result.root !== null) throw new Error("--root requires one unique path");
      result.root = resolve(args[index]);
      continue;
    }
    throw new Error(`unknown option: ${arg}`);
  }
  if (result.negativeSelfTest && result.root !== null) {
    throw new Error("--negative-self-test does not accept --root");
  }
  return result;
}

function* walk(root, entries) {
  for (const entry of entries) {
    const path = resolve(root, entry);
    const stat = existsSync(path) ? readdirOrFile(path) : [];
    for (const child of stat) yield child;
  }
}

function readdirOrFile(path) {
  try {
    return readdirSync(path, { withFileTypes: true }).flatMap((entry) => {
      if (entry.name.startsWith(".zig-cache") || entry.name === "zig-out") return [];
      const child = resolve(path, entry.name);
      return entry.isDirectory() ? readdirOrFile(child) : [child];
    });
  } catch {
    return [path];
  }
}
