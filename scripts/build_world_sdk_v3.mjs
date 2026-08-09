import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const options = parseArgs(process.argv.slice(2));
const staging = mkdtempSync(join(tmpdir(), "world-sdk-v3-build-"));
const sdkRoot = options.output;
const components = Object.freeze({
  boundary: {
    version: "1.0.0",
    archiveSha256: "bf1ba841febf2b24b2bdafd75819a557ca8ad4bde4c463199e393c0ab7db52ab",
    packageHash: "boundary-1.0.0-flclaPgFEQBhYvlC3eqNVK3X67InkTuaX-pHFvRLzWJ8",
  },
  world: {
    version: "3.0.0",
    archiveSha256: "2e129819a9a578eea8919c000a6002dc56e0011abbcaeb36fadeb211d2a9da52",
    packageHash: "world-3.0.0-XXTUeH4tBgDQM9BYPERe-ZyxDaT3WnPr30k6UcPYY9Vz",
    commit: "537b3ff1c67f4422b882158d9e206848f1db99ad",
  },
  host: {
    version: "1.0.0",
    archiveSha256: "f881aaf3ada062ca3d80fc46d10cb001f38504d816ecd4995faf34bcd14ecc70",
  },
  capabilities: {
    version: "2.0.2",
    archiveSha256: "e1718f14ff6c2443b52a06e35650cf8530feb7863ef120950ee7c5c6f1c951a6",
    commit: "47596758e55b288b4d35d0f459c5a8cc31b40eb0",
    applicationId: "1880383510d2cb82892827245c206d7a98afd6779a3ce3a72d1776ce813ab1e3",
  },
});

try {
  requireEmptyDestination(sdkRoot);
  mkdirSync(sdkRoot, { recursive: true });
  cpSync(join(sourceRoot, "sdk/v3/README.md"), join(sdkRoot, "README.md"));
  cpSync(join(sourceRoot, "sdk/v3/conformance"), join(sdkRoot, "conformance"), { recursive: true });
  cpSync(join(sourceRoot, "sdk/v3/LICENSES"), join(sdkRoot, "LICENSES"), { recursive: true });

  const archives = {
    boundary: await download("https://github.com/tkersey/boundary/archive/refs/tags/v1.0.0.tar.gz"),
    world: await download("https://github.com/tkersey/world/archive/refs/tags/v3.0.0.tar.gz"),
    host: ghAsset("repos/tkersey/world-host/releases/assets/490040522"),
    capabilities: ghAsset("repos/tkersey/world-capabilities/releases/assets/507613227"),
  };
  const archiveDestinations = {
    boundary: join(sdkRoot, "boundary/archive/boundary-v1.0.0.tar.gz"),
    world: join(sdkRoot, "world/archive/world-v3.0.0.tar.gz"),
    host: join(sdkRoot, "world-host/archive/world-host-v1.0.0.tar.gz"),
    capabilities: join(sdkRoot, "world-capabilities/archive/world-capabilities-v2.0.2-effect-v1.tar.gz"),
  };
  for (const [owner, bytes] of Object.entries(archives)) {
    assert.equal(sha256(bytes), components[owner].archiveSha256, `${owner} release archive differs`);
    mkdirSync(dirname(archiveDestinations[owner]), { recursive: true });
    writeFileSync(archiveDestinations[owner], bytes);
  }

  const receipts = [
    {
      path: "world/world-v3.0.0.release.json",
      bytes: ghAsset("repos/tkersey/world/releases/assets/507605868"),
      sha256: "84f63f8b0cba243f93181c42b01275e81a05d116a5a95f65516ab498ffa16662",
    },
    {
      path: "world-host/world-host-v1.0.0.conformance.json",
      bytes: ghAsset("repos/tkersey/world-host/releases/assets/490040521"),
      sha256: "1ca83fd1a91f04a593a9d9bbc57120a4a70734ff8e70b26adc3c99e16433f333",
    },
    {
      path: "world-capabilities/world-capabilities-v2.0.2.release.json",
      bytes: ghAsset("repos/tkersey/world-capabilities/releases/assets/507610473"),
      sha256: "135901a911c216723460ac4cae4c513c9e5ec8ab6517a55f3f5d1bd7021c5c7b",
    },
  ];
  for (const receipt of receipts) {
    assert.equal(sha256(receipt.bytes), receipt.sha256, `${receipt.path} differs`);
    const path = join(sdkRoot, receipt.path);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, receipt.bytes);
  }
  writeJson(join(sdkRoot, "boundary/release.json"), {
    package: "Boundary",
    version: "1.0.0",
    tagCommit: "2277ba6d28f45c4a999b4f03a52c3a9eb5e95af4",
    sourceArchiveSha256: components.boundary.archiveSha256,
    zigPackageHash: components.boundary.packageHash,
  });

  const extractedWorld = extract(archiveDestinations.world, join(staging, "world"), "world-3.0.0");
  const extractedBoundary = extract(archiveDestinations.boundary, join(staging, "boundary"), "boundary-1.0.0");
  cpSync(join(extractedBoundary, "README.md"), join(sdkRoot, "boundary/README.md"));
  cpSync(join(extractedBoundary, "docs/program.md"), join(sdkRoot, "boundary/program.md"));
  cpSync(join(extractedBoundary, "docs/machine.md"), join(sdkRoot, "boundary/machine.md"));
  cpSync(join(extractedBoundary, "docs/compiler_pipeline.md"), join(sdkRoot, "boundary/compiler_pipeline.md"));
  cpSync(join(extractedBoundary, "LICENSE"), join(sdkRoot, "LICENSES/Boundary-v1.0.0-LICENSE"));
  cpSync(join(extractedWorld, "README.md"), join(sdkRoot, "world/README.md"));
  cpSync(join(extractedWorld, "docs/application_abi_v1.md"), join(sdkRoot, "world/application_abi_v1.md"));
  cpSync(join(extractedWorld, "docs/sdk.md"), join(sdkRoot, "world/sdk.md"));
  cpSync(join(extractedWorld, "build_support/application.zig"), join(sdkRoot, "world/application.zig"));
  cpSync(join(extractedWorld, "templates/application-v1"), join(sdkRoot, "world/application-template"), { recursive: true });
  cpSync(join(extractedWorld, "templates/application-v1"), join(sdkRoot, "examples/research-digest-v2"), { recursive: true });

  writeJson(join(sdkRoot, "manifest.json"), {
    schema: "world-sdk-v3/v1",
    sdkVersion: "3.0.0",
    components,
  });
  writeChecksums();
  run(process.execPath, [join(sdkRoot, "conformance/check-sdk.mjs")]);
  run(process.execPath, [
    join(sdkRoot, "conformance/external-consumer/run.mjs"),
    "--zig",
    options.zig,
    "--emit-receipt",
    join(sdkRoot, "conformance/world-v3-singularity-receipt.json"),
  ]);
  writeChecksums();
  run(process.execPath, [join(sdkRoot, "conformance/check-sdk.mjs")]);
  console.log(`world_sdk_v3=${sdkRoot}`);
  console.log("sdk_archives_authenticated=true");
  console.log("sdk_external_consumer=true");
} finally {
  rmSync(staging, { recursive: true, force: true });
}

function writeChecksums() {
  const rows = walkFiles(sdkRoot)
    .filter((path) => relative(sdkRoot, path) !== "checksums.sha256")
    .map((path) => `${sha256(readFileSync(path))}  ${relative(sdkRoot, path)}`)
    .sort();
  writeFileSync(join(sdkRoot, "checksums.sha256"), `${rows.join("\n")}\n`);
}

function requireEmptyDestination(path) {
  if (!existsSync(path)) return;
  if (!statSync(path).isDirectory() || readdirSync(path).length !== 0) {
    throw new Error(`SDK output must be absent or empty: ${path}`);
  }
}

async function download(url) {
  const response = await fetch(url, { redirect: "follow" });
  if (!response.ok) throw new Error(`release download failed: ${url} HTTP ${response.status}`);
  return Buffer.from(await response.arrayBuffer());
}

function ghAsset(apiPath) {
  const result = spawnSync("gh", ["api", "-H", "Accept: application/octet-stream", apiPath], {
    encoding: null,
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.status !== 0) throw new Error(`release asset download failed: ${apiPath}\n${result.stderr?.toString("utf8") ?? ""}`);
  return Buffer.from(result.stdout);
}

function extract(archive, destination, expectedRoot) {
  mkdirSync(destination, { recursive: true });
  run("tar", ["-xzf", archive, "-C", destination]);
  const entries = readdirSync(destination, { withFileTypes: true });
  assert.equal(entries.length, 1);
  assert(entries[0].isDirectory() && entries[0].name === expectedRoot, `release root differs: ${expectedRoot}`);
  return join(destination, expectedRoot);
}

function writeJson(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function walkFiles(root) {
  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const path = join(root, entry.name);
    return entry.isDirectory() ? walkFiles(path) : [path];
  }).sort();
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function run(command, args, cwd = sourceRoot) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed:\n${result.stdout ?? ""}\n${result.stderr ?? ""}`);
  return result;
}

function parseArgs(args) {
  const result = { output: null, zig: "zig" };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    const value = args[++index];
    if (!value) throw new Error(`${key} requires a value`);
    if (key === "--output") result.output = resolve(value);
    else if (key === "--zig") result.zig = value.includes("/") ? resolve(value) : value;
    else throw new Error(`unknown option: ${key}`);
  }
  if (result.output === null) throw new Error("--output is required");
  return result;
}
