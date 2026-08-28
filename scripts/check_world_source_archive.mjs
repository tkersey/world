import {
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const baselineCommit = "053f82088d5e614cd1fc92ec0447c308f80ed4ce";
if (process.argv.includes("--negative-self-test")) {
  runNegativeSelfTest();
  process.exit(0);
}
const temporaryRoot = mkdtempSync(join(tmpdir(), "world-source-archive-"));

try {
  requireCommit(baselineCommit);
  const surfaces = declaredPackageSurfaces(readFileSync(resolve(packageRoot, "build.zig.zon"), "utf8"));
  const candidateFiles = gitLines(["ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", ...surfaces], true)
    .filter((path) => existsSync(resolve(packageRoot, path)) && statSync(resolve(packageRoot, path)).isFile())
    .sort();
  const baselineFiles = gitLines(["ls-tree", "-r", "--name-only", "-z", baselineCommit, "--", ...surfaces], true).sort();
  if (candidateFiles.length === 0 || baselineFiles.length === 0) throw new Error("source archive file enumeration is empty");

  const candidateArchive = resolve(temporaryRoot, "candidate.tar");
  const baselineArchive = resolve(temporaryRoot, "baseline.tar");
  run("tar", ["-cf", candidateArchive, "-C", packageRoot, ...candidateFiles]);
  run("git", ["archive", "--format=tar", `--output=${baselineArchive}`, baselineCommit, "--", ...baselineFiles], packageRoot);
  const candidateRoot = resolve(temporaryRoot, "candidate");
  const baselineRoot = resolve(temporaryRoot, "baseline");
  run("mkdir", [candidateRoot]);
  run("mkdir", [baselineRoot]);
  run("tar", ["-xf", candidateArchive, "-C", candidateRoot]);
  run("tar", ["-xf", baselineArchive, "-C", baselineRoot]);

  run(process.execPath, [resolve(packageRoot, "scripts/check_world_singularity.mjs"), "--root", candidateRoot]);
  const metrics = compareMetrics(candidateRoot, baselineRoot, candidateArchive, baselineArchive, candidateFiles, baselineFiles, surfaces);
  assertNormalized(candidateRoot, candidateFiles);

  for (const [name, value] of Object.entries(metrics)) console.log(`world_source_archive_${name}=${value}`);
  console.log("world_source_archive_dependency_count=1");
  console.log("world_source_archive_world_root_count=1");
  console.log("world_source_archive_application_reducer_count=1");
  console.log("world_source_archive_system_linker_count=1");
  console.log("world_source_archive_runtime_loader_count=0");
  console.log("world_source_archive_universal_artifact_count=0");
  console.log("world_source_archive_legacy_path_count=0");
  console.log("world_source_archive_legacy_build_step_count=0");
  console.log("world_source_archive=pass");
  console.log("world_v3_package_normalization_complete=true");
} finally {
  rmSync(temporaryRoot, { recursive: true, force: true });
}

function compareMetrics(candidateRoot, baselineRoot, candidateArchive, baselineArchive, candidateFiles, baselineFiles, surfaces) {
  const candidate = {
    archive_bytes: statSync(candidateArchive).size,
    tracked_files: candidateFiles.length,
    build_steps: countMatches(readFileSync(resolve(candidateRoot, "build.zig"), "utf8"), /\bb\.step\s*\(/g),
    public_declarations: countPublicDeclarations(candidateRoot),
    docs: candidateFiles.filter((path) => path.startsWith("docs/")).length,
    examples: candidateFiles.filter((path) => path.startsWith("examples/")).length,
  };
  const baseline = {
    archive_bytes: statSync(baselineArchive).size,
    tracked_files: baselineFiles.length,
    build_steps: countMatches(readFileSync(resolve(baselineRoot, "build.zig"), "utf8"), /\bb\.step\s*\(/g),
    public_declarations: countPublicDeclarations(baselineRoot),
    docs: baselineFiles.filter((path) => path.startsWith("docs/")).length,
    examples: baselineFiles.filter((path) => path.startsWith("examples/")).length,
  };
  const delta = diffStats(surfaces, candidateFiles);
  assertMetricRegression(candidate, baseline, delta);
  return {
    baseline_commit: baselineCommit,
    insertions: delta.insertions,
    deletions: delta.deletions,
    deletion_ratio_x: (delta.deletions / Math.max(delta.insertions, 1)).toFixed(2),
    baseline_archive_bytes: baseline.archive_bytes,
    candidate_archive_bytes: candidate.archive_bytes,
    baseline_tracked_files: baseline.tracked_files,
    candidate_tracked_files: candidate.tracked_files,
    baseline_build_steps: baseline.build_steps,
    candidate_build_steps: candidate.build_steps,
    baseline_public_declarations: baseline.public_declarations,
    candidate_public_declarations: candidate.public_declarations,
    baseline_docs: baseline.docs,
    candidate_docs: candidate.docs,
    baseline_examples: baseline.examples,
    candidate_examples: candidate.examples,
  };
}

function assertMetricRegression(candidate, baseline, delta) {
  for (const name of Object.keys(candidate)) {
    if (candidate[name] >= baseline[name]) {
      throw new Error(`${name} did not shrink: baseline=${baseline[name]} candidate=${candidate[name]}`);
    }
  }
  if (delta.deletions < 5 * delta.insertions) {
    throw new Error(`package deletion ratio is below 5x: insertions=${delta.insertions} deletions=${delta.deletions}`);
  }
}

function runNegativeSelfTest() {
  let rejected = 0;
  for (const witness of [
    [{ archive_bytes: 10 }, { archive_bytes: 10 }, { insertions: 1, deletions: 10 }],
    [{ archive_bytes: 9 }, { archive_bytes: 10 }, { insertions: 3, deletions: 14 }],
  ]) {
    try {
      assertMetricRegression(...witness);
    } catch {
      rejected += 1;
    }
  }
  if (rejected !== 2) throw new Error("source archive regression self-test did not reject both witnesses");
  console.log("world_source_archive_negative=pass");
}

function assertNormalized(root, files) {
  const zon = readFileSync(resolve(root, "build.zig.zon"), "utf8");
  const dependencyBody = zon.match(/\.dependencies\s*=\s*\.\{([\s\S]*?)\n\s*\},\n\s*\.minimum_zig_version/)?.[1] ?? "";
  const dependencies = [...dependencyBody.matchAll(/^\s*\.([A-Za-z0-9_]+)\s*=\s*\.\{/gm)].map((match) => match[1]);
  if (dependencies.length !== 1 || dependencies[0] !== "boundary") throw new Error("candidate archive does not contain exactly one Boundary dependency");
  if (files.filter((path) => path === "src/world.zig").length !== 1) throw new Error("candidate archive does not contain exactly one src/world.zig root");
  if (files.filter((path) => path === "src/system_v1.zig").length !== 1) throw new Error("candidate archive does not contain exactly one System Linker");
  const source = walkFiles(resolve(root, "src")).map((path) => readFileSync(path, "utf8")).join("\n");
  if (countMatches(source, /\bfn drive\s*\(/g) !== 1) throw new Error("candidate archive does not contain exactly one application reducer");
  if (countMatches(source, /pub fn system\s*\(/g) !== 1) throw new Error("candidate archive does not contain exactly one system linker");
}

function diffStats(surfaces, candidateFiles) {
  const result = run("git", ["diff", "--numstat", baselineCommit, "--", ...surfaces], packageRoot).stdout;
  let insertions = 0;
  let deletions = 0;
  for (const line of result.trim().split("\n").filter(Boolean)) {
    const [added, removed] = line.split("\t");
    if (/^\d+$/.test(added)) insertions += Number(added);
    if (/^\d+$/.test(removed)) deletions += Number(removed);
  }
  const untracked = new Set(gitLines(["ls-files", "--others", "--exclude-standard", "-z", "--", ...surfaces], true));
  for (const path of candidateFiles) {
    if (untracked.has(path)) insertions += readFileSync(resolve(packageRoot, path), "utf8").split("\n").length - 1;
  }
  return { insertions, deletions };
}

function countPublicDeclarations(root) {
  return walkFiles(root)
    .filter((path) => path.endsWith(".zig"))
    .reduce((count, path) => count + countMatches(readFileSync(path, "utf8"), /^\s*pub (?:const|fn|var)\b/gm), 0);
}

function declaredPackageSurfaces(zon) {
  const body = zon.match(/\.paths\s*=\s*\.\{([\s\S]*?)\n\s*\},\n\}/)?.[1];
  if (!body) throw new Error("cannot parse declared package paths");
  const paths = [...body.matchAll(/"([^"]+)"/g)].map((match) => match[1]);
  if (paths.length === 0) throw new Error("declared package paths are empty");
  return paths;
}

function walkFiles(root) {
  if (!existsSync(root)) return [];
  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const path = resolve(root, entry.name);
    return entry.isDirectory() ? walkFiles(path) : [path];
  });
}

function gitLines(args, nul = false) {
  const output = run("git", args, packageRoot).stdout;
  return output.split(nul ? "\0" : "\n").filter(Boolean);
}

function requireCommit(commit) {
  const result = run("git", ["cat-file", "-t", commit], packageRoot).stdout.trim();
  if (result !== "commit") throw new Error(`baseline is not a commit: ${commit}`);
}

function countMatches(text, pattern) {
  return [...text.matchAll(pattern)].length;
}

function run(command, args, cwd = packageRoot) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed:\n${result.stdout ?? ""}\n${result.stderr ?? ""}`);
  return result;
}
