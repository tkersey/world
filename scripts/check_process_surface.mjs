#!/usr/bin/env bun

import { execFileSync } from "node:child_process";
import {
  lstatSync,
  readFileSync,
  realpathSync,
} from "node:fs";
import { isBuiltin } from "node:module";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const EXPECTED_PUBLIC_EXPORTS = Object.freeze([
  "WorldProcessHostError",
  "admitProcessKernel",
  "decodeEffectRequest",
  "decodeEffectResult",
  "decodeProcessOutcome",
  "encodeEffectResult",
]);

export const EXPECTED_PACKAGE_FILES = Object.freeze([
  "LICENSE",
  "README.md",
  "bin/",
  "src/process_v1/",
  "boundary-process-kernel-v1.wasm",
]);

export const EXPECTED_SCRIPTS = Object.freeze({
  check:
    "bun run check:process-v1 && bun run check:runtime && bun run conformance:runtime",
  "check:process-v1": "bun scripts/check_process_surface.mjs && bun test",
  "build:runtime": "bun scripts/build_runtime_archive.mjs",
  "check:runtime": "bun scripts/check_runtime_archive.mjs",
  "conformance:runtime": "bun scripts/run_clean_room_conformance.mjs",
});

const EXPECTED_EXPORT_MAP = Object.freeze({
  "./process-v1": "./src/process_v1/index.mjs",
});

const EXPECTED_BIN_MAP = Object.freeze({
  world: "./bin/world.mjs",
});

const EXPECTED_ENGINES = Object.freeze({
  bun: ">=1.4.0",
});

const EVIDENCE_FILES = Object.freeze([
  ".learnings.jsonl",
  ".ledger/learnings/events.jsonl",
]);

const REQUIRED_ROOT_FILES = Object.freeze([
  ".gitignore",
  ...EVIDENCE_FILES,
  "README.md",
  "LICENSE",
  "package.json",
  "boundary-process-kernel-v1.wasm",
]);

const REQUIRED_DOCS = new Set([
  "docs/migration_from_world_3.md",
  "docs/process_host_v1.md",
  "docs/security_model.md",
]);

const REQUIRED_SCRIPTS = new Set([
  "scripts/acquire_boundary_process_assets.mjs",
  "scripts/acquire_process_conformance_assets.mjs",
  "scripts/acquire_repository_repair_transcript.mjs",
  "scripts/build_runtime_archive.mjs",
  "scripts/check_process_surface.mjs",
  "scripts/check_runtime_archive.mjs",
  "scripts/run_clean_room_conformance.mjs",
  "scripts/write_release_receipt.mjs",
]);

const DEPENDENCY_FIELDS = Object.freeze([
  "dependencies",
  "devDependencies",
  "optionalDependencies",
  "peerDependencies",
  "peerDependenciesMeta",
  "bundledDependencies",
  "bundleDependencies",
]);

const ALTERNATE_SURFACE_FIELDS = Object.freeze([
  "main",
  "module",
  "browser",
  "types",
  "typings",
  "man",
  "directories",
  "workspaces",
]);

const NATIVE_ADDON_FIELDS = Object.freeze([
  "gypfile",
  "binary",
  "napi",
]);

const LEGACY_ROOTS = Object.freeze([
  "build_support/",
  "examples/",
  "sdk/",
  "templates/",
]);

function fail(message) {
  throw new Error(`process surface: ${message}`);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function sortedKeys(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return [];
  }
  return Object.keys(value).sort();
}

function assertExactObject(actual, expected, label) {
  const actualKeys = sortedKeys(actual);
  const expectedKeys = sortedKeys(expected);
  assert(
    JSON.stringify(actualKeys) === JSON.stringify(expectedKeys),
    `${label} keys must be exactly ${expectedKeys.join(", ")}; got ${actualKeys.join(", ") || "none"}`,
  );
  for (const key of expectedKeys) {
    assert(
      actual[key] === expected[key],
      `${label}.${key} must be ${JSON.stringify(expected[key])}; got ${JSON.stringify(actual[key])}`,
    );
  }
}

export function validatePackageManifest(manifest) {
  assert(manifest && typeof manifest === "object" && !Array.isArray(manifest), "package.json must contain an object");
  assert(manifest.name === "@tkersey/world", "package name must be @tkersey/world");
  assert(manifest.version === "4.0.0", "package version must be 4.0.0");
  assert(manifest.type === "module", "package type must be module");
  assert(manifest.private === false, "package private must be false");
  assert(manifest.license === "MIT", "package license must be MIT");

  assertExactObject(manifest.exports, EXPECTED_EXPORT_MAP, "exports");
  assertExactObject(manifest.bin, EXPECTED_BIN_MAP, "bin");
  assertExactObject(manifest.engines, EXPECTED_ENGINES, "engines");
  assertExactObject(manifest.scripts, EXPECTED_SCRIPTS, "scripts");

  assert(Array.isArray(manifest.files), "package files must be an array");
  assert(
    JSON.stringify(manifest.files) === JSON.stringify(EXPECTED_PACKAGE_FILES),
    `package files must be exactly ${EXPECTED_PACKAGE_FILES.join(", ")}`,
  );

  for (const field of DEPENDENCY_FIELDS) {
    assert(!(field in manifest), `package dependency surface ${field} is forbidden`);
  }
  for (const field of ALTERNATE_SURFACE_FIELDS) {
    assert(!(field in manifest), `alternate package surface ${field} is forbidden`);
  }
  for (const field of NATIVE_ADDON_FIELDS) {
    assert(!(field in manifest), `native-addon surface ${field} is forbidden`);
  }

  return Object.freeze({
    exportRoots: Object.freeze(Object.values(EXPECTED_EXPORT_MAP)),
    binRoots: Object.freeze(Object.values(EXPECTED_BIN_MAP)),
  });
}

function gitPaths(root, args) {
  const bytes = execFileSync("git", [...args, "-z"], {
    cwd: root,
    encoding: "buffer",
    stdio: ["ignore", "pipe", "pipe"],
  });
  return bytes
    .toString("utf8")
    .split("\0")
    .filter(Boolean)
    .map((entry) => entry.replaceAll(path.sep, "/"));
}

export function deriveGitWorkingInventory(root) {
  const tracked = new Set(gitPaths(root, ["ls-files", "--cached"]));
  const candidates = new Set([
    ...tracked,
    ...gitPaths(root, ["ls-files", "--others", "--exclude-standard"]),
  ]);

  const entries = [];
  for (const relativePath of [...candidates].sort()) {
    if (
      relativePath === "dist" ||
      relativePath.startsWith("dist/") ||
      relativePath.startsWith(".zig-cache/") ||
      relativePath.startsWith("zig-cache/") ||
      relativePath.startsWith("zig-out/") ||
      relativePath.startsWith("node_modules/")
    ) {
      continue;
    }

    let stat;
    try {
      stat = lstatSync(path.join(root, relativePath));
    } catch (error) {
      if (error?.code === "ENOENT") continue;
      throw error;
    }
    entries.push(Object.freeze({
      path: relativePath,
      tracked: tracked.has(relativePath),
      regular: stat.isFile(),
      symlink: stat.isSymbolicLink(),
      mode: stat.mode,
    }));
  }
  return Object.freeze(entries);
}

function isAllowedRepositoryPath(relativePath) {
  if (REQUIRED_ROOT_FILES.includes(relativePath)) return true;
  if (relativePath === "verify-runtime.mjs") return true;
  if (REQUIRED_DOCS.has(relativePath)) return true;
  if (relativePath === "bin/world.mjs") return true;
  if (relativePath.startsWith("src/process_v1/") && relativePath.endsWith(".mjs")) return true;
  if (REQUIRED_SCRIPTS.has(relativePath)) return true;
  if (relativePath.startsWith("test/")) return true;
  if (relativePath.startsWith("conformance/")) return true;
  return false;
}

export function validateRepositoryInventory(entries) {
  const paths = new Set(entries.map((entry) => entry.path));
  for (const required of REQUIRED_ROOT_FILES) {
    assert(paths.has(required), `required repository file is missing: ${required}`);
  }
  for (const required of REQUIRED_DOCS) {
    assert(paths.has(required), `required World 4 document is missing: ${required}`);
  }
  for (const required of REQUIRED_SCRIPTS) {
    assert(paths.has(required), `required World 4 support script is missing: ${required}`);
  }

  for (const entry of entries) {
    const relativePath = entry.path;
    assert(
      relativePath !== "build.zig" && relativePath !== "build.zig.zon",
      `retired World 3 build surface remains active: ${relativePath}`,
    );
    assert(
      !LEGACY_ROOTS.some((prefix) => relativePath.startsWith(prefix)),
      `retired World 3 source root remains active: ${relativePath}`,
    );
    assert(
      !relativePath.endsWith(".zig") && !relativePath.endsWith(".zon"),
      `Zig source-language surface remains active: ${relativePath}`,
    );
    assert(
      !relativePath.startsWith("src/") || relativePath.startsWith("src/process_v1/"),
      `production source exists outside src/process_v1: ${relativePath}`,
    );
    assert(isAllowedRepositoryPath(relativePath), `unexpected active repository surface: ${relativePath}`);
  }

  for (const evidencePath of EVIDENCE_FILES) {
    const entry = entries.find((candidate) => candidate.path === evidencePath);
    assert(entry?.tracked === true, `repository evidence must remain tracked: ${evidencePath}`);
    assert(entry.regular, `repository evidence must remain a regular file: ${evidencePath}`);
  }
}

function packagePatternMatches(relativePath, pattern) {
  if (pattern.endsWith("/")) return relativePath.startsWith(pattern);
  return relativePath === pattern;
}

export function derivePackageInventory(entries, manifest) {
  const members = new Set(["package.json"]);
  for (const entry of entries) {
    if (manifest.files.some((pattern) => packagePatternMatches(entry.path, pattern))) {
      assert(entry.regular, `package member must be a regular file: ${entry.path}`);
      assert(!entry.symlink, `package member must not be a symbolic link: ${entry.path}`);
      members.add(entry.path);
    }
  }

  for (const required of [
    "package.json",
    "LICENSE",
    "README.md",
    "bin/world.mjs",
    "src/process_v1/index.mjs",
    "boundary-process-kernel-v1.wasm",
  ]) {
    assert(members.has(required), `required package member is missing: ${required}`);
  }
  for (const evidencePath of EVIDENCE_FILES) {
    assert(!members.has(evidencePath), `repository evidence leaked into package inventory: ${evidencePath}`);
  }
  return Object.freeze([...members].sort());
}

export function scanModuleSpecifiers(source) {
  const specifiers = new Set();
  const patterns = [
    /\bimport\s+(?:[^"'();]*?\s+from\s*)?["']([^"']+)["']/gu,
    /\bexport\s+(?:\*|\{[^}]*\})\s+from\s*["']([^"']+)["']/gu,
    /\bimport\s*\(\s*["']([^"']+)["']\s*\)/gu,
  ];
  for (const pattern of patterns) {
    for (const match of source.matchAll(pattern)) specifiers.add(match[1]);
  }
  return Object.freeze([...specifiers]);
}

export function validateModuleImportSyntax(source, importer) {
  const dynamicCalls = [...source.matchAll(/\bimport\s*\(/gu)].length;
  const literalDynamicCalls = [
    ...source.matchAll(/\bimport\s*\(\s*["'][^"']+["']\s*\)/gu),
  ].length;
  assert(
    dynamicCalls === literalDynamicCalls,
    `production module ${importer} contains a non-literal dynamic import`,
  );
  assert(
    !/\brequire\s*\(/u.test(source),
    `production module ${importer} contains CommonJS require`,
  );
}

export function validateProductionSpecifier(specifier, importer) {
  if (specifier.startsWith("node:") && isBuiltin(specifier)) return "builtin";
  assert(
    specifier.startsWith("./") || specifier.startsWith("../"),
    `production module ${importer} imports forbidden bare package ${JSON.stringify(specifier)}`,
  );
  assert(!specifier.includes("?") && !specifier.includes("#"), `production import must not contain query or fragment: ${specifier}`);
  assert(specifier.endsWith(".mjs"), `production relative import must name an .mjs file exactly: ${specifier}`);
  return "relative";
}

export function deriveReachableProduction(root, manifest, entries, packageMembers) {
  const entryByPath = new Map(entries.map((entry) => [entry.path, entry]));
  const packaged = new Set(packageMembers);
  const queue = [
    ...Object.values(manifest.exports),
    ...Object.values(manifest.bin),
  ].map((entry) => entry.replace(/^\.\//u, ""));
  const reachable = new Set();

  while (queue.length > 0) {
    const relativePath = queue.shift();
    if (reachable.has(relativePath)) continue;
    const entry = entryByPath.get(relativePath);
    assert(entry?.regular && !entry.symlink, `production entry is not a regular file: ${relativePath}`);
    assert(packaged.has(relativePath), `reachable production module is absent from package inventory: ${relativePath}`);
    reachable.add(relativePath);

    const source = readFileSync(path.join(root, relativePath), "utf8");
    validateModuleImportSyntax(source, relativePath);
    for (const specifier of scanModuleSpecifiers(source)) {
      if (validateProductionSpecifier(specifier, relativePath) === "builtin") continue;
      const absoluteTarget = path.resolve(path.dirname(path.join(root, relativePath)), specifier);
      const relativeTarget = path.relative(root, absoluteTarget).replaceAll(path.sep, "/");
      assert(
        relativeTarget !== ".." && !relativeTarget.startsWith("../") && !path.isAbsolute(relativeTarget),
        `production import escapes repository root: ${relativePath} -> ${specifier}`,
      );
      assert(
        relativeTarget === "bin/world.mjs" || relativeTarget.startsWith("src/process_v1/"),
        `production import escapes the admitted source roots: ${relativePath} -> ${relativeTarget}`,
      );
      queue.push(relativeTarget);
    }
  }

  const productionModules = entries
    .map((entry) => entry.path)
    .filter((relativePath) =>
      relativePath === "bin/world.mjs" ||
      (relativePath.startsWith("src/process_v1/") && relativePath.endsWith(".mjs")),
    )
    .sort();
  const missing = productionModules.filter((relativePath) => !reachable.has(relativePath));
  assert(missing.length === 0, `unreachable production modules are forbidden: ${missing.join(", ")}`);
  return Object.freeze([...reachable].sort());
}

export function validatePublicExportNames(actualNames) {
  const actual = [...actualNames].sort();
  assert(
    JSON.stringify(actual) === JSON.stringify(EXPECTED_PUBLIC_EXPORTS),
    `public namespace must be exactly ${EXPECTED_PUBLIC_EXPORTS.join(", ")}; got ${actual.join(", ") || "none"}`,
  );
}

async function validatePublicNamespace(root) {
  const indexUrl = pathToFileURL(path.join(root, "src/process_v1/index.mjs"));
  indexUrl.searchParams.set("surface", `${process.pid}-${Date.now()}`);
  const namespace = await import(indexUrl.href);
  validatePublicExportNames(Object.keys(namespace));

  const smoke = [
    `const ns = await import(${JSON.stringify(indexUrl.href)});`,
    `const actual = Object.keys(ns).sort();`,
    `const expected = ${JSON.stringify(EXPECTED_PUBLIC_EXPORTS)};`,
    `if (JSON.stringify(actual) !== JSON.stringify(expected)) process.exit(1);`,
  ].join("\n");
  try {
    execFileSync("node", ["--input-type=module", "--eval", smoke], {
      cwd: root,
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (error) {
    const stderr = error?.stderr?.toString("utf8").trim();
    fail(`Node import smoke failed${stderr ? `: ${stderr}` : ""}`);
  }
}

function validateCli(root) {
  const relativePath = "bin/world.mjs";
  const absolutePath = path.join(root, relativePath);
  const stat = lstatSync(absolutePath);
  assert(stat.isFile() && !stat.isSymbolicLink(), `${relativePath} must be a regular file`);
  assert((stat.mode & 0o111) !== 0, `${relativePath} must be executable`);
  const firstLine = readFileSync(absolutePath, "utf8").split(/\r?\n/u, 1)[0];
  assert(firstLine === "#!/usr/bin/env bun", `${relativePath} must use the Bun shebang`);
}

export async function checkProcessSurface(root) {
  const canonicalRoot = realpathSync(root);
  const manifest = JSON.parse(readFileSync(path.join(canonicalRoot, "package.json"), "utf8"));
  validatePackageManifest(manifest);
  const entries = deriveGitWorkingInventory(canonicalRoot);
  validateRepositoryInventory(entries);
  const packageMembers = derivePackageInventory(entries, manifest);
  const reachableProduction = deriveReachableProduction(
    canonicalRoot,
    manifest,
    entries,
    packageMembers,
  );
  validateCli(canonicalRoot);
  await validatePublicNamespace(canonicalRoot);

  return Object.freeze({
    format: "world-process-surface-check/v1",
    packageName: manifest.name,
    packageVersion: manifest.version,
    publicExports: EXPECTED_PUBLIC_EXPORTS,
    packageMembers,
    reachableProduction,
    runtimeDependencyCount: 0,
    repositoryEvidence: EVIDENCE_FILES,
  });
}

function parseArguments(argv) {
  if (argv.length === 0) return process.cwd();
  if (argv.length === 2 && argv[0] === "--root") return argv[1];
  fail("usage: check_process_surface.mjs [--root PATH]");
}

if (import.meta.main) {
  try {
    const report = await checkProcessSurface(parseArguments(process.argv.slice(2)));
    process.stdout.write(`${JSON.stringify(report)}\n`);
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}
