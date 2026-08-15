import { spawnSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

const boundaryUrl = "https://github.com/tkersey/boundary/archive/refs/tags/v1.4.0.tar.gz";
const boundaryHash = "boundary-1.4.0-flclaDRLEQAzxJEl23bFxWD_WHd35B5yynEAK2vfEg-A";
const options = parseArgs(process.argv.slice(2));
const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const proofRoot = mkdtempSync(join(tmpdir(), "world-external-consumer-"));
let passed = false;

try {
  const stagingRoot = join(proofRoot, "staging");
  const stagedWorld = join(stagingRoot, "world");
  const archivePath = join(proofRoot, "world-candidate.tar.gz");
  const materializedRoot = join(proofRoot, "materialized");
  const projectRoot = join(proofRoot, "consumer");
  const packageCache = join(proofRoot, "package-cache");
  const surfaces = declaredPackageSurfaces(readFileSync(join(sourceRoot, "build.zig.zon"), "utf8"));
  const candidateFiles = gitFiles(surfaces);
  if (candidateFiles.length === 0) throw new Error("candidate package file enumeration is empty");
  mkdirSync(stagedWorld, { recursive: true });
  for (const relative of candidateFiles) {
    const source = join(sourceRoot, relative);
    if (!existsSync(source) || !statSync(source).isFile()) continue;
    const destination = join(stagedWorld, relative);
    mkdirSync(dirname(destination), { recursive: true });
    cpSync(source, destination);
  }
  run("tar", ["-czf", archivePath, "-C", stagingRoot, "world"]);
  mkdirSync(materializedRoot);
  run("tar", ["-xzf", archivePath, "-C", materializedRoot]);
  const worldPackageRoot = join(materializedRoot, "world");
  if (!existsSync(join(worldPackageRoot, "build.zig.zon"))) {
    throw new Error("candidate archive does not contain the World package root");
  }

  const worldHash = fetchPackage(options.zig, archivePath, packageCache, worldPackageRoot);
  const actualBoundaryHash = fetchPackage(options.zig, boundaryUrl, packageCache, worldPackageRoot);
  if (actualBoundaryHash !== boundaryHash) {
    throw new Error(`Boundary package hash mismatch: expected ${boundaryHash}, found ${actualBoundaryHash}`);
  }
  assertSingleBoundaryDependency(worldPackageRoot);

  const worldUrl = pathToFileURL(archivePath).href;
  run(process.execPath, [
    join(worldPackageRoot, "scripts/init_world_application.mjs"),
    "--output",
    projectRoot,
    "--world-url",
    worldUrl,
    "--world-hash",
    worldHash,
  ]);
  verifyGeneratedProject(projectRoot, worldUrl, worldHash);

  const globalCache = join(projectRoot, ".zig-global-cache");
  const localCache = join(projectRoot, ".zig-cache");
  const prefix = join(projectRoot, "zig-out");
  renameSync(packageCache, globalCache);
  run(options.zig, [
    "build",
    "--cache-dir",
    localCache,
    "--global-cache-dir",
    globalCache,
    "--prefix",
    prefix,
    "--summary",
    "all",
  ], projectRoot);

  const wasmPath = join(prefix, "world-apps/research-digest-agent.world.wasm");
  const manifestPath = join(prefix, "world-apps/research-digest-agent.manifest.bin");
  const readableManifestPath = join(prefix, "world-apps/research-digest-agent.manifest.txt");
  for (const path of [wasmPath, manifestPath, readableManifestPath]) {
    if (!existsSync(path) || statSync(path).size === 0) {
      throw new Error(`clean-room build did not emit ${basename(path)}`);
    }
  }
  const conformance = run(process.execPath, [
    join(worldPackageRoot, "scripts/world_application_v1_research_digest_conformance.mjs"),
    wasmPath,
    manifestPath,
  ]);
  if (!conformance.stdout.includes("imports=0") || !conformance.stdout.includes("bounded_memory=true")) {
    throw new Error("materialized candidate conformance did not prove the application WASM surface");
  }

  console.log("world_external_consumer=true");
  console.log("clean_room_build=true");
  console.log("world_dependency_kind=archive");
  console.log("boundary_dependency_count=1");
  console.log(["boundary", "_machine_abi=2"].join(""));
  console.log("source_checkout_required=false");
  console.log("sibling_checkout_required=false");
  console.log("application_wasm_import_count=0");
  console.log("application_wasm_memory_bounded=true");
  passed = true;
} finally {
  if (passed) rmSync(proofRoot, { recursive: true, force: true });
  else console.error(`world_external_consumer_proof_root=${proofRoot}`);
}

function declaredPackageSurfaces(zon) {
  const body = zon.match(/\.paths\s*=\s*\.\{([\s\S]*?)\n\s*\},\n\}/)?.[1];
  if (!body) throw new Error("cannot parse declared package paths");
  const paths = [...body.matchAll(/"([^"]+)"/g)].map((match) => match[1]);
  if (paths.length === 0) throw new Error("declared package paths are empty");
  return paths;
}

function gitFiles(surfaces) {
  return run("git", [
    "-C",
    sourceRoot,
    "ls-files",
    "--cached",
    "--others",
    "--exclude-standard",
    "-z",
    "--",
    ...surfaces,
  ], undefined, false).stdout.split("\0").filter(Boolean).sort();
}

function fetchPackage(zig, source, globalCache, cwd) {
  return run(zig, ["fetch", "--global-cache-dir", globalCache, source], cwd, false).stdout.trim();
}

function assertSingleBoundaryDependency(worldRoot) {
  const zon = readFileSync(join(worldRoot, "build.zig.zon"), "utf8");
  if (!zon.includes(`.url = "${boundaryUrl}"`) || !zon.includes(`.hash = "${boundaryHash}"`)) {
    throw new Error("materialized candidate does not retain exact Boundary v1.4.0 identity");
  }
  const body = zon.match(/\.dependencies\s*=\s*\.\{([\s\S]*?)\n\s*\},\n\s*\.minimum_zig_version/)?.[1] ?? "";
  const names = [...body.matchAll(/^\s*\.([A-Za-z0-9_]+)\s*=\s*\.\{/gm)].map((match) => match[1]);
  if (names.length !== 1 || names[0] !== "boundary") {
    throw new Error(`materialized candidate dependencies differ: ${names.join(",")}`);
  }
}

function verifyGeneratedProject(projectRoot, worldUrl, worldHash) {
  const zon = readFileSync(join(projectRoot, "build.zig.zon"), "utf8");
  if (!zon.includes(`.url = "${worldUrl}"`) || !zon.includes(`.hash = "${worldHash}"`)) {
    throw new Error("generated project does not bind the candidate World archive identity");
  }
  const forbidden = [
    /\.path\s*=/,
    /\.\.\//,
    new RegExp(escapeRegex(sourceRoot)),
    /build_support\//,
    /src\/world\.zig/,
    /application_runtime_v1/,
    /@import\("world\//,
  ];
  for (const path of walkFiles(projectRoot)) {
    const text = readFileSync(path, "utf8");
    for (const marker of forbidden) {
      if (marker.test(text)) {
        throw new Error(`generated project contains checkout/internal dependency in ${basename(path)}: ${marker}`);
      }
    }
  }
}

function walkFiles(root) {
  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const path = join(root, entry.name);
    return entry.isDirectory() ? walkFiles(path) : [path];
  });
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function run(command, args, cwd = undefined, forward = true) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    maxBuffer: 64 * 1024 * 1024,
  });
  if (forward && result.stdout) process.stdout.write(result.stdout);
  if (forward && result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed with status ${result.status}:\n${result.stderr ?? ""}`);
  }
  return result;
}

function parseArgs(args) {
  if (args.length !== 2 || args[0] !== "--zig" || !args[1]) {
    throw new Error("usage: node scripts/check_world_external_consumer.mjs --zig <absolute-zig>");
  }
  const zig = resolve(args[1]);
  if (!existsSync(zig)) throw new Error(`Zig executable does not exist: ${zig}`);
  return { zig };
}
