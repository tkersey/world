import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
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

  for (const path of [["src/world", "_v1.zig"].join(""), "src/protocol.zig"]) {
    if (existsSync(resolve(root, path))) throw new Error(`legacy path remains: ${path}`);
  }
  const legacyConformanceFiles = existsSync(resolve(root, "conformance/v0"))
    ? readdirOrFile(resolve(root, "conformance/v0"), root)
    : [];
  if (legacyConformanceFiles.length !== 0) {
    throw new Error(`legacy conformance files remain: ${legacyConformanceFiles.join(", ")}`);
  }

  const declared = declaredPackageSurfaces(readFileSync(resolve(root, "build.zig.zon"), "utf8"));
  const semanticTerms = forbiddenSemanticTerms();
  const migrationDocument = "docs/migration_from_world_2.md";
  const parityHarness = "scripts/check_world_2_3_parity.mjs";
  const parityException = ["boundary", "_machine"].join("");
  for (const path of walk(root, declared)) {
    const relative = path.slice(root.length + 1);
    if (isForbiddenLegacyPath(relative)) throw new Error(`legacy path remains: ${relative}`);
    const text = readFileSync(path, "utf8");
    for (const term of semanticTerms) {
      if (relative === migrationDocument) continue;
      if (relative === parityHarness && term.marker === parityException) continue;
      if (containsTerm(text, term.marker)) {
        throw new Error(`forbidden semantic marker ${term.marker} remains in ${relative}`);
      }
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
    const pathRoot = resolve(temporaryRoot, "legacy-path");
    copyDeclaredPackage(pathRoot);
    const legacyWorldName = ["world", "_v1.zig"].join("");
    const legacyWorldPath = `src/${legacyWorldName}`;
    writeFileSync(
      resolve(pathRoot, legacyWorldPath),
      "pub const legacy_world_surface = true;\n",
    );
    const pathResult = spawnSync(
      process.execPath,
      [fileURLToPath(import.meta.url), "--root", pathRoot],
      { encoding: "utf8" },
    );
    const pathDiagnostic = `${pathResult.stdout ?? ""}\n${pathResult.stderr ?? ""}`;
    if (pathResult.status === 0) {
      throw new Error(`singularity checker accepted an injected ${legacyWorldPath} surface`);
    }
    if (!pathDiagnostic.includes(legacyWorldName)) {
      throw new Error(`singularity checker rejected the path injection for the wrong reason:\n${pathDiagnostic}`);
    }

    const semanticRoot = resolve(temporaryRoot, "semantic-marker");
    copyDeclaredPackage(semanticRoot);
    const retainedScript = resolve(semanticRoot, "scripts/init_world_application.mjs");
    const injectedMarker = ["Loaded", "Session"].join("");
    writeFileSync(retainedScript, `${readFileSync(retainedScript, "utf8")}\n// ${injectedMarker}\n`);
    const semanticResult = spawnSync(
      process.execPath,
      [fileURLToPath(import.meta.url), "--root", semanticRoot],
      { encoding: "utf8" },
    );
    const semanticDiagnostic = `${semanticResult.stdout ?? ""}\n${semanticResult.stderr ?? ""}`;
    if (semanticResult.status === 0) {
      throw new Error(`singularity checker accepted injected semantic marker ${injectedMarker}`);
    }
    if (!semanticDiagnostic.includes(injectedMarker)) {
      throw new Error(`singularity checker rejected the semantic injection for the wrong reason:\n${semanticDiagnostic}`);
    }
    console.log("world_singularity_negative_path=true");
    console.log("world_singularity_negative_semantic=true");
    console.log("world_singularity_negative=pass");
  } finally {
    rmSync(temporaryRoot, { recursive: true, force: true });
  }
}

function copyDeclaredPackage(destination) {
  const zon = readFileSync(resolve(packageRoot, "build.zig.zon"), "utf8");
  mkdirSync(destination, { recursive: true });
  for (const path of declaredPackageSurfaces(zon)) {
    cpSync(resolve(packageRoot, path), resolve(destination, path), {
      recursive: true,
      filter: (source) => !isIgnoredGeneratedCheckoutPath(source),
    });
  }
}

function declaredPackageSurfaces(zon) {
  const body = zon.match(/\.paths\s*=\s*\.\{([\s\S]*?)\n\s*\},\n\}/)?.[1];
  if (!body) throw new Error("cannot parse declared package paths");
  const paths = [...body.matchAll(/"([^"]+)"/g)].map((match) => match[1]);
  if (paths.length === 0) throw new Error("declared package paths are empty");
  return paths;
}

function forbiddenSemanticTerms() {
  const term = (...parts) => parts.join("");
  return [
    term("boundary", "_machine"),
    term("Boundary v0", ".7"),
    term("boundary-v0", ".7"),
    term("world", ".v1"),
    term("world", "_v1"),
    term("Program", "Plan"),
    term("program", "_plan"),
    term("Boundary", "Module"),
    term("boundary", "_module"),
    term("Certified", "Module"),
    term("Certified", "Target"),
    term("CertifiedBoundary", "Module"),
    term("decode", "Boundary", "Module"),
    term("decode", "Program", "Plan"),
    term("world", "_appliance", "_load", "_executable"),
    term("load", "Executable"),
    term("dynamic", "_loader"),
    term("universal", "_world"),
    term("universal", "_world", "_runtime"),
    term("universal", "_world", "_wasm"),
    term("universal", "_world", "_appliance"),
    term("world", "_universal"),
    term("world", "_universal", "_runtime"),
    term("world", "_universal", "_wasm"),
    term("world", "_universal", "_appliance"),
    term("universal", "_appliance"),
    term("Executable", ".Image"),
    term("Turn", "Closure"),
    term("Run", "space"),
    term("Fab", "ric", "Plan"),
    term("Fab", "ric"),
    term("Link", "er"),
    term("Appli", "ance"),
    term("Cap", "sule"),
    term("Chron", "icle"),
    term("Arch", "ive"),
    term("Actu", "ation"),
    term("Super", "vision"),
    term("Environ", "ment"),
    term("Trans", "cript"),
    term("Hand", "off"),
    term("Loaded", "Session"),
    term("Certified Boundary", " Module"),
  ].map((marker) => ({ marker }));
}

function isForbiddenLegacyPath(path) {
  const term = (...parts) => parts.join("");
  const forbiddenNames = new Set([
    term("world", "_v1.zig"),
    "protocol.zig",
    term("appli", "ance.zig"),
    term("run", "space.zig"),
    term("link", "er.zig"),
    term("arch", "ive.zig"),
  ]);
  const parts = path.split("/");
  if (parts.some((part) => forbiddenNames.has(part))) return true;
  if (parts.includes("conformance") && parts.some((part) => /^v0(?:\b|[._-])/.test(part))) return true;
  return parts.some((part) => part.includes(term("universal", "_world")) || part.includes(term("world", "_universal")));
}

function containsTerm(text, marker) {
  const escaped = marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(^|[^A-Za-z0-9_])${escaped}([^A-Za-z0-9_]|$)`).test(text);
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
    const stat = existsSync(path) ? readdirOrFile(path, root) : [];
    for (const child of stat) yield child;
  }
}

function readdirOrFile(path, root) {
  if (isGeneratedDirectoryName(path)) {
    if (root === packageRoot && isGitIgnored(path)) return [];
    throw new Error(`packaged generated/cache path remains: ${relative(root, path)}`);
  }
  let entries;
  try {
    entries = readdirSync(path, { withFileTypes: true });
  } catch {
    return [path];
  }
  return entries.flatMap((entry) => {
    const child = resolve(path, entry.name);
    return entry.isDirectory() ? readdirOrFile(child, root) : [child];
  });
}

function isIgnoredGeneratedCheckoutPath(path) {
  const parts = relative(packageRoot, path).split(/[\\/]/);
  for (let index = 0; index < parts.length; index += 1) {
    if (!generatedDirectoryNames().has(parts[index])) continue;
    return isGitIgnored(resolve(packageRoot, ...parts.slice(0, index + 1)));
  }
  return false;
}

function isGeneratedDirectoryName(path) {
  const name = path.split(/[\\/]/).at(-1);
  return generatedDirectoryNames().has(name);
}

function generatedDirectoryNames() {
  return new Set([".zig-cache", "zig-out", "zig-pkg"]);
}

function isGitIgnored(path) {
  const result = spawnSync("git", ["check-ignore", "-q", "--", path], { cwd: packageRoot });
  if (result.status === 0) return true;
  if (result.status === 1) return false;
  throw new Error(`git check-ignore failed for ${path}`);
}
