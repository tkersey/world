import { spawnSync } from "node:child_process";
import {
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
import { fileURLToPath } from "node:url";

const boundaryUrl =
  "https://github.com/tkersey/boundary/archive/refs/tags/v0.7.0.tar.gz";
const boundaryHash =
  "boundary-0.7.0-flclaCnjkABOSWaiSkxMBDQZsBEeA-Niai-l1u0q3A7_";
const boundaryMachineUrl =
  "https://github.com/tkersey/boundary/archive/refs/tags/v1.0.0-rc.1.tar.gz";
const boundaryMachineHash =
  "boundary-1.0.0-rc.1-flclaP0FEQApv6S-kj0cKVzgh8KgaV2afbb26rSJHF3O";
const options = parseArgs(process.argv.slice(2));
const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const proofRoot = mkdtempSync(join(tmpdir(), "world-external-consumer-"));
let passed = false;

try {
  const archivePath =
    options.worldArchive ?? join(proofRoot, "world-source.tar.gz");
  let worldUrl = options.worldUrl;
  if (options.worldArchive === null) {
    const status = run("git", [
      "-C",
      sourceRoot,
      "status",
      "--porcelain",
      "--untracked-files=all",
    ]).stdout.trim();
    if (status.length !== 0) {
      throw new Error(
        "check-world-external-consumer requires a clean committed World HEAD or --world-archive",
      );
    }
    const commit = run("git", ["-C", sourceRoot, "rev-parse", "HEAD"]).stdout.trim();
    run("git", [
      "-C",
      sourceRoot,
      "archive",
      "--format=tar.gz",
      "--prefix=world/",
      `--output=${archivePath}`,
      commit,
    ]);
    worldUrl ??=
      `https://github.com/tkersey/world/archive/${commit}.tar.gz`;
  }
  if (!existsSync(archivePath)) {
    throw new Error(`World archive does not exist: ${archivePath}`);
  }
  if (!worldUrl) {
    throw new Error("--world-url is required with --world-archive");
  }

  const materializedRoot = join(proofRoot, "materialized-world");
  mkdirSync(materializedRoot, { recursive: true });
  run("tar", ["-xzf", archivePath, "-C", materializedRoot]);
  const worldPackageRoot = locatePackageRoot(materializedRoot);
  const projectRoot = join(proofRoot, "consumer");
  const packageCache = join(proofRoot, "package-cache");

  const worldHash = fetchPackage(
    options.zig,
    archivePath,
    packageCache,
    worldPackageRoot,
  );
  const actualBoundaryHash = fetchPackage(
    options.zig,
    options.boundaryArchive ?? boundaryUrl,
    packageCache,
    worldPackageRoot,
  );
  if (actualBoundaryHash !== boundaryHash) {
    throw new Error(
      `Boundary package hash mismatch: expected ${boundaryHash}, found ${actualBoundaryHash}`,
    );
  }
  const usesBoundaryMachine = readFileSync(
    join(worldPackageRoot, "build.zig.zon"),
    "utf8",
  ).includes(".boundary_machine");
  let actualBoundaryMachineHash = null;
  if (usesBoundaryMachine) {
    actualBoundaryMachineHash = fetchPackage(
      options.zig,
      options.boundaryMachineArchive ?? boundaryMachineUrl,
      packageCache,
      worldPackageRoot,
    );
    if (actualBoundaryMachineHash !== boundaryMachineHash) {
      throw new Error(
        `Boundary Machine package hash mismatch: expected ${boundaryMachineHash}, found ${actualBoundaryMachineHash}`,
      );
    }
  }

  run("node", [
    join(worldPackageRoot, "scripts/init_world_application.mjs"),
    "--output",
    projectRoot,
    "--world-url",
    worldUrl,
    "--world-hash",
    worldHash,
  ]);
  const globalCache = join(projectRoot, ".zig-global-cache");
  const localCache = join(projectRoot, ".zig-cache");
  const prefix = join(projectRoot, "zig-out");
  verifyGeneratedProject(projectRoot);
  renameSync(packageCache, globalCache);
  run(
    options.zig,
    [
      "build",
      "--cache-dir",
      localCache,
      "--global-cache-dir",
      globalCache,
      "--prefix",
      prefix,
      "--summary",
      "all",
    ],
    projectRoot,
  );

  for (const relative of [
    "world-apps/research-digest-agent.world.wasm",
    "world-apps/research-digest-agent.manifest.bin",
    "world-apps/research-digest-agent.manifest.txt",
  ]) {
    const path = join(prefix, relative);
    if (!existsSync(path) || statSync(path).size === 0) {
      throw new Error(`clean-room build did not emit ${relative}`);
    }
  }
  run("node", [
    join(
      worldPackageRoot,
      "scripts/world_application_v1_research_digest_conformance.mjs",
    ),
    join(prefix, "world-apps/research-digest-agent.world.wasm"),
    join(prefix, "world-apps/research-digest-agent.manifest.bin"),
  ]);

  console.log(`world_archive=${archivePath}`);
  console.log(`world_release_url=${worldUrl}`);
  console.log(`world_release_hash=${worldHash}`);
  console.log(`boundary_release_url=${boundaryUrl}`);
  console.log(`boundary_release_hash=${boundaryHash}`);
  if (actualBoundaryMachineHash !== null) {
    console.log(`boundary_machine_release_url=${boundaryMachineUrl}`);
    console.log(`boundary_machine_release_hash=${actualBoundaryMachineHash}`);
  }
  console.log("clean_room_build=true");
  console.log("sibling_checkout_required=false");
  console.log("internal_import_count=0");
  console.log("application_wasm_import_count=0");
  console.log("custom_effect=true");
  console.log("internal_provider=true");
  console.log("fresh_instance_resume=true");
  console.log("deterministic_retry=true");
  console.log("branching=true");
  passed = true;
} finally {
  if (options.keep || !passed) {
    console.error(`world_external_consumer_proof_root=${proofRoot}`);
  } else {
    rmSync(proofRoot, { recursive: true, force: true });
  }
}

function fetchPackage(zig, source, globalCache, cwd) {
  return run(
    zig,
    [
      "fetch",
      "--global-cache-dir",
      globalCache,
      source,
    ],
    cwd,
  ).stdout.trim();
}

function locatePackageRoot(materializedRoot) {
  if (existsSync(join(materializedRoot, "build.zig.zon"))) {
    return materializedRoot;
  }
  const directories = readdirSync(materializedRoot)
    .map((name) => join(materializedRoot, name))
    .filter((path) => statSync(path).isDirectory());
  if (
    directories.length !== 1 ||
    !existsSync(join(directories[0], "build.zig.zon"))
  ) {
    throw new Error("World archive must contain one package root");
  }
  return directories[0];
}

function verifyGeneratedProject(projectRoot) {
  const forbidden = [
    "../boundary",
    "../world",
    "../world-host",
    "test/",
    "examples/",
    "private_modules",
    "application_v1_agent_fixtures",
  ];
  for (const path of walkFiles(projectRoot)) {
    const text = readFileSync(path, "utf8");
    for (const marker of forbidden) {
      if (text.includes(marker)) {
        throw new Error(
          `generated project contains forbidden source reference '${marker}' in ${basename(path)}`,
        );
      }
    }
  }
}

function walkFiles(root) {
  const result = [];
  for (const name of readdirSync(root)) {
    const path = join(root, name);
    const stat = statSync(path);
    if (stat.isDirectory()) result.push(...walkFiles(path));
    else if (stat.isFile()) result.push(path);
  }
  return result;
}

function run(command, args, cwd = undefined) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with status ${result.status}`,
    );
  }
  return result;
}

function parseArgs(args) {
  const options = {
    boundaryArchive: null,
    boundaryMachineArchive: null,
    keep: false,
    worldArchive: null,
    worldUrl: null,
    zig: "zig",
  };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    if (key === "--keep") {
      options.keep = true;
      continue;
    }
    const value = args[++index];
    if (!value) throw new Error(`missing value for ${key}`);
    switch (key) {
      case "--boundary-archive":
        options.boundaryArchive = resolve(value);
        break;
      case "--boundary-machine-archive":
        options.boundaryMachineArchive = resolve(value);
        break;
      case "--world-archive":
        options.worldArchive = resolve(value);
        break;
      case "--world-url":
        options.worldUrl = value;
        break;
      case "--zig":
        options.zig = value.includes("/") ? resolve(value) : value;
        break;
      default:
        throw new Error(`unknown option: ${key}`);
    }
  }
  return options;
}
