import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  copyFileSync,
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const RELEASES = Object.freeze({
  boundary: Object.freeze({
    tag: "v0.7.0",
    gitCommit: "7f2472100454aa2cd5c62e07db0c1e23eaf46a77",
    url: "https://github.com/tkersey/boundary/archive/refs/tags/v0.7.0.tar.gz",
    archiveName: "boundary-v0.7.0.tar.gz",
    archiveSha256:
      "25e5bd5ed45aac023ef99beee93f675ea4efb3f6eb1e98d2a13040d7451f0e9a",
    packageHash:
      "boundary-0.7.0-flclaCnjkABOSWaiSkxMBDQZsBEeA-Niai-l1u0q3A7_",
  }),
  world: Object.freeze({
    tag: "v1.0.0",
    gitCommit: "1bbd613ed4e9b1b6fbdaf79eec15cbff92d014ab",
    url: "https://github.com/tkersey/world/archive/refs/tags/v1.0.0.tar.gz",
    archiveName: "world-v1.0.0.tar.gz",
    archiveSha256:
      "9976802090738d61beb49522207c086cf1f529f2f39002de7b54d1c10808b944",
    packageHash:
      "world-1.0.0-XXTUeF0tiAC_5jqj2oVDvgGmmh8c7CRCnuaG8p2i9Zk_",
  }),
  worldHost: Object.freeze({
    tag: "v1.0.0",
    gitCommit: "f9c8a5b2713197eae00df7ea1acdbc1e99d3344d",
    url:
      "https://github.com/tkersey/world-host/releases/download/v1.0.0/" +
      "world-host-v1.0.0.tar.gz",
    archiveName: "world-host-v1.0.0.tar.gz",
    archiveSha256:
      "f881aaf3ada062ca3d80fc46d10cb001f38504d816ecd4995faf34bcd14ecc70",
    executableSourceCommit: "b66324515577323325deccf532efd85e370f51b3",
  }),
  worldCapabilities: Object.freeze({
    tag: "v1.0.0",
    gitCommit: "bb5ed3ebd695b0343d58e5ae2ff658653ff69997",
    url:
      "https://github.com/tkersey/world-capabilities/releases/download/v1.0.0/" +
      "world-capabilities-v1-runtime-v1.0.0.tar.gz",
    archiveName: "world-capabilities-v1-runtime-v1.0.0.tar.gz",
    archiveSha256:
      "1d9011faf1932de66ca4f7f24dcfaea41671175999bf278683bda4702854e0ca",
    researchPackFingerprint:
      "c3106b770e2d14237c981b4671da3d42dfbaed33eed81ccc78c257a42419354e",
  }),
});

const REQUIRED_NEGATIVE_CASES = Object.freeze([
  "alteredWasmBytes",
  "capabilityPolicyDenial",
  "excessiveResponseBytes",
  "frameForAnotherApplication",
  "insufficientReceiverLimits",
  "missingCapability",
  "staleOrDuplicateResult",
  "wrongApplicationManifest",
  "wrongEffectResultTarget",
  "wrongSchema",
]);

const options = parseArgs(process.argv.slice(2));
const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sdkRoot = options.out;
const temporaryRoot = mkdtempSync(join(tmpdir(), "world-sdk-v1-build-"));
let complete = false;

try {
  assert.equal(
    basename(sdkRoot),
    "world-sdk-v1.0.0",
    "SDK output directory must be named world-sdk-v1.0.0",
  );
  assert(!existsSync(sdkRoot), `SDK output already exists: ${sdkRoot}`);

  const inputs = Object.freeze({
    boundary: verifiedArchive(
      options.boundaryArchive,
      RELEASES.boundary.archiveSha256,
    ),
    world: verifiedArchive(
      options.worldArchive,
      RELEASES.world.archiveSha256,
    ),
    worldHost: verifiedArchive(
      options.worldHostArchive,
      RELEASES.worldHost.archiveSha256,
    ),
    worldCapabilities: verifiedArchive(
      options.worldCapabilitiesRuntimeArchive,
      RELEASES.worldCapabilities.archiveSha256,
    ),
  });

  const materialized = join(temporaryRoot, "materialized");
  const boundaryMaterialized = join(materialized, "boundary");
  const worldMaterialized = join(materialized, "world");
  const hostMaterialized = join(materialized, "world-host");
  const capabilitiesMaterialized = join(materialized, "world-capabilities");
  extractArchive(inputs.boundary, boundaryMaterialized);
  extractArchive(inputs.world, worldMaterialized);
  extractArchive(inputs.worldHost, hostMaterialized);
  extractArchive(inputs.worldCapabilities, capabilitiesMaterialized);

  const boundaryRoot = locateRoot(
    boundaryMaterialized,
    (candidate) =>
      existsSync(join(candidate, "LICENSE")) &&
      existsSync(join(candidate, "docs/static_machine.md")),
    "Boundary release",
  );
  const worldRoot = locateRoot(
    worldMaterialized,
    (candidate) =>
      existsSync(join(candidate, "build.zig.zon")) &&
      existsSync(join(candidate, "templates/application-v1/build.zig.zon")),
    "World release",
  );
  const hostRoot = locateRoot(
    hostMaterialized,
    (candidate) => {
      const manifest = readJsonIfPresent(join(candidate, "manifest.json"));
      return manifest?.formatVersion === "agent-runtime-v1-pack/v1";
    },
    "world-host release",
  );
  const capabilitiesRoot = locateRoot(
    capabilitiesMaterialized,
    (candidate) => {
      const packageJson = readJsonIfPresent(join(candidate, "package.json"));
      return (
        packageJson?.name === "@tkersey/world-capabilities" &&
        packageJson?.version === "1.0.0" &&
        existsSync(join(candidate, "templates/capability-v1/manifest.json"))
      );
    },
    "world-capabilities release",
  );

  mkdirSync(sdkRoot, { recursive: true });
  materializeBoundary(sdkRoot, boundaryRoot, inputs.boundary);
  materializeWorld(sdkRoot, worldRoot, inputs.world);
  materializeWorldHost(sdkRoot, hostRoot, inputs.worldHost);
  materializeWorldCapabilities(
    sdkRoot,
    capabilitiesRoot,
    inputs.worldCapabilities,
  );
  materializeExample(sdkRoot, worldRoot);
  materializeConformance(sdkRoot, options.zig);
  materializeLicenses(sdkRoot, boundaryRoot);
  writeFileSync(join(sdkRoot, "README.md"), sdkReadme());
  writeChecksums(sdkRoot);

  run("node", [join(sdkRoot, "conformance/check-sdk.mjs")], sdkRoot);
  complete = true;
  process.stdout.write(
    `${JSON.stringify(
      {
        command: "build-world-sdk-v1",
        output: sdkRoot,
        release: "v1.0.0",
        sourceCheckoutRequiredForVerification: false,
        complete: true,
      },
      null,
      2,
    )}\n`,
  );
} finally {
  rmSync(temporaryRoot, { recursive: true, force: true });
  if (!complete) rmSync(sdkRoot, { recursive: true, force: true });
}

function materializeBoundary(root, releaseRoot, archive) {
  const target = join(root, "boundary");
  mkdirSync(join(target, "docs"), { recursive: true });
  copyFileSync(archive, join(target, RELEASES.boundary.archiveName));
  for (const name of [
    "compatibility.md",
    "static_machine.md",
    "static_machine_parity.md",
    "static_machine_state.md",
  ]) {
    copyFileSync(join(releaseRoot, "docs", name), join(target, "docs", name));
  }
  writeJson(join(target, "release.json"), releaseMetadata(RELEASES.boundary));
}

function materializeWorld(root, releaseRoot, archive) {
  const target = join(root, "world");
  mkdirSync(join(target, "docs"), { recursive: true });
  copyFileSync(archive, join(target, RELEASES.world.archiveName));
  cpSync(
    join(releaseRoot, "templates/application-v1"),
    join(target, "application-template"),
    { recursive: true },
  );
  for (const name of [
    "application_v1.md",
    "application_abi_v1.md",
    "effect_protocol_v1.md",
    "frame_v1.md",
  ]) {
    copyFileSync(join(releaseRoot, "docs", name), join(target, "docs", name));
  }
  copyFileSync(
    join(sourceRoot, "docs/zero_to_world_application.md"),
    join(target, "docs/zero_to_world_application.md"),
  );
  writeFileSync(
    join(target, "application_manifest_schema.md"),
    applicationManifestSchemaPointer(),
  );
  writeJson(join(target, "release.json"), {
    ...releaseMetadata(RELEASES.world),
    documentationCommit: documentationCommit(),
  });
}

function materializeWorldHost(root, releaseRoot, archive) {
  const target = join(root, "world-host");
  mkdirSync(target, { recursive: true });
  copyFileSync(archive, join(target, RELEASES.worldHost.archiveName));
  cpSync(releaseRoot, join(target, "distribution"), { recursive: true });
  writeJson(
    join(target, "release.json"),
    releaseMetadata(RELEASES.worldHost),
  );
}

function materializeWorldCapabilities(root, releaseRoot, archive) {
  const target = join(root, "world-capabilities");
  mkdirSync(target, { recursive: true });
  copyFileSync(
    archive,
    join(target, RELEASES.worldCapabilities.archiveName),
  );
  cpSync(releaseRoot, join(target, "distribution"), { recursive: true });
  writeJson(
    join(target, "release.json"),
    releaseMetadata(RELEASES.worldCapabilities),
  );
}

function materializeExample(root, worldRoot) {
  const examples = join(root, "examples");
  mkdirSync(examples, { recursive: true });
  run("node", [
    join(worldRoot, "scripts/init_world_application.mjs"),
    "--output",
    join(examples, "research-digest-agent"),
    "--world-url",
    RELEASES.world.url,
    "--world-hash",
    RELEASES.world.packageHash,
  ]);
}

function materializeConformance(root, zig) {
  const conformance = join(root, "conformance");
  const externalConsumer = join(conformance, "external-consumer");
  const lifecycle = join(conformance, "lifecycle");
  const negative = join(conformance, "negative");
  mkdirSync(externalConsumer, { recursive: true });
  mkdirSync(lifecycle, { recursive: true });
  mkdirSync(negative, { recursive: true });
  copyFileSync(
    join(sourceRoot, "scripts/check_world_sdk_v1.mjs"),
    join(conformance, "check-sdk.mjs"),
  );
  copyFileSync(
    join(sourceRoot, "scripts/run_world_sdk_externality.mjs"),
    join(externalConsumer, "run.mjs"),
  );
  const verifierScripts = join(externalConsumer, "verifier/scripts");
  mkdirSync(verifierScripts, { recursive: true });
  for (const name of [
    "check_world_1_0_externality.mjs",
    "check_world_external_consumer.mjs",
  ]) {
    copyFileSync(
      join(sourceRoot, "scripts", name),
      join(verifierScripts, name),
    );
  }

  const lifecycleReceipt = JSON.parse(
    run(
      "bun",
      [join(root, "world-host/distribution/conformance/run.mjs")],
      root,
    ).stdout,
  );
  assert.equal(lifecycleReceipt.releaseStatus, "released");
  assert.equal(lifecycleReceipt.sourceCheckoutRequired, false);
  assert.equal(lifecycleReceipt.sourceIndependentHost, true);
  writeJson(join(lifecycle, "receipt.json"), lifecycleReceipt);
  writeFileSync(join(lifecycle, "README.md"), lifecycleReadme());

  const negativeCases = lifecycleReceipt.scenarios.researchNegativeCases;
  assert.deepEqual(
    Object.keys(negativeCases).sort(),
    [...REQUIRED_NEGATIVE_CASES].sort(),
  );
  assert(Object.values(negativeCases).every((value) => value === true));
  writeJson(join(negative, "receipt.json"), {
    receiptVersion: "world-sdk-negative/v1",
    sourceReceipt: "../lifecycle/receipt.json",
    cases: negativeCases,
  });
  writeFileSync(join(negative, "README.md"), negativeReadme());

  const externality = run(
    "node",
    [join(externalConsumer, "run.mjs"), "--zig", zig],
    root,
  ).stdout;
  assert(externality.includes("world_1_0_externality_gate=true\n"));
  assert(externality.includes("source_independent_host=true\n"));
  writeFileSync(join(externalConsumer, "receipt.txt"), externality);
  writeFileSync(join(externalConsumer, "README.md"), externalConsumerReadme());
}

function materializeLicenses(root, boundaryRoot) {
  const licenses = join(root, "LICENSES");
  mkdirSync(licenses, { recursive: true });
  copyFileSync(
    join(boundaryRoot, "LICENSE"),
    join(licenses, "boundary-MIT.txt"),
  );
  writeFileSync(join(licenses, "README.md"), licensesReadme());
}

function releaseMetadata(release) {
  return {
    schemaVersion: "world-sdk-release/v1",
    ...release,
  };
}

function verifiedArchive(path, expectedSha256) {
  assert(existsSync(path), `release archive does not exist: ${path}`);
  const info = lstatSync(path);
  assert(
    info.isFile() && !info.isSymbolicLink(),
    `release archive must be a regular file: ${path}`,
  );
  assert.equal(
    sha256File(path),
    expectedSha256,
    `release archive checksum mismatch: ${path}`,
  );
  return path;
}

function extractArchive(archive, target) {
  mkdirSync(target, { recursive: true });
  run("tar", ["-xzf", archive, "-C", target]);
  rejectLinks(target);
}

function rejectLinks(root, current = root) {
  for (const entry of readdirSync(current, { withFileTypes: true })) {
    const path = join(current, entry.name);
    const info = lstatSync(path);
    assert(!info.isSymbolicLink(), `release archive contains a link: ${path}`);
    if (info.isDirectory()) rejectLinks(root, path);
  }
}

function locateRoot(root, predicate, label) {
  const matches = [];
  walkDirectories(root, (candidate) => {
    if (predicate(candidate)) matches.push(candidate);
  });
  assert.equal(matches.length, 1, `${label} package root is ambiguous`);
  return matches[0];
}

function walkDirectories(root, visit) {
  visit(root);
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    if (entry.isDirectory()) walkDirectories(join(root, entry.name), visit);
  }
}

function readJsonIfPresent(path) {
  if (!existsSync(path)) return null;
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

function documentationCommit() {
  const status = run("git", [
    "-C",
    sourceRoot,
    "status",
    "--porcelain=v1",
    "--",
    "docs/zero_to_world_application.md",
  ]).stdout;
  assert.equal(status, "", "stable externality guide must be committed");
  return run("git", [
    "-C",
    sourceRoot,
    "log",
    "-1",
    "--format=%H",
    "--",
    "docs/zero_to_world_application.md",
  ]).stdout.trim();
}

function writeChecksums(root) {
  const files = listFiles(root)
    .filter((path) => path !== "checksums.sha256")
    .sort();
  const lines = files.map((path) => `${sha256File(join(root, path))}  ${path}`);
  writeFileSync(join(root, "checksums.sha256"), `${lines.join("\n")}\n`);
}

function listFiles(root, current = root, result = []) {
  for (const entry of readdirSync(current, { withFileTypes: true })) {
    const absolute = join(current, entry.name);
    const info = lstatSync(absolute);
    assert(!info.isSymbolicLink(), `SDK contains a link: ${absolute}`);
    if (info.isDirectory()) {
      listFiles(root, absolute, result);
    } else {
      result.push(relative(root, absolute).split("\\").join("/"));
    }
  }
  return result;
}

function run(command, args, cwd = undefined) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with status ${result.status}\n` +
        `${result.stdout}${result.stderr}`,
    );
  }
  return result;
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function sha256File(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function parseArgs(args) {
  const result = {
    boundaryArchive: null,
    out: null,
    worldArchive: null,
    worldCapabilitiesRuntimeArchive: null,
    worldHostArchive: null,
    zig: "zig",
  };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    const value = args[++index];
    if (!value) throw new Error(`missing value for ${key}`);
    switch (key) {
      case "--boundary-archive":
        result.boundaryArchive = resolve(value);
        break;
      case "--out":
        result.out = resolve(value);
        break;
      case "--world-archive":
        result.worldArchive = resolve(value);
        break;
      case "--world-capabilities-runtime-archive":
        result.worldCapabilitiesRuntimeArchive = resolve(value);
        break;
      case "--world-host-archive":
        result.worldHostArchive = resolve(value);
        break;
      case "--zig":
        result.zig = value;
        break;
      default:
        throw new Error(`unknown option: ${key}`);
    }
  }
  for (const [name, value] of Object.entries({
    "--boundary-archive": result.boundaryArchive,
    "--out": result.out,
    "--world-archive": result.worldArchive,
    "--world-capabilities-runtime-archive":
      result.worldCapabilitiesRuntimeArchive,
    "--world-host-archive": result.worldHostArchive,
  })) {
    if (value === null) throw new Error(`${name} is required`);
  }
  return result;
}

function sdkReadme() {
  return `# World SDK v1.0.0

This checksum-bound bundle composes the reviewed Boundary v0.7.0, World
v1.0.0, world-host v1.0.0, and world-capabilities v1.0.0 artifacts. It is a
release bundle, not a package registry.

The application template and Research Digest example use only public World
and Boundary APIs. The host distribution contains no application-specific
logic, and the capability distribution cannot author World Frames.

## Verify

\`\`\`sh
node conformance/check-sdk.mjs
(cd world-capabilities/distribution && bun run proof)
bun world-host/distribution/conformance/check-pack.mjs
bun world-host/distribution/conformance/run.mjs
node conformance/external-consumer/run.mjs
\`\`\`

The static SDK check and host lifecycle need Node.js and Bun. The final
empty-directory authoring proof additionally needs Zig 0.16.0. Running the
finished host does not require Zig or any source checkout.

See \`world/docs/zero_to_world_application.md\` for the complete walkthrough.
`;
}

function applicationManifestSchemaPointer() {
  return `# ApplicationManifest v1 schema

The canonical binary schema is owned by World v1.0.0 at
\`src/application_v1.zig:ApplicationManifest\` inside
\`world-v1.0.0.tar.gz\`. This SDK does not fork or restate that semantic
source.

The supported host-facing ABI is documented in
\`docs/application_abi_v1.md\`; application construction and manifest
identity are documented in \`docs/application_v1.md\`.
`;
}

function externalConsumerReadme() {
  return `# External consumer conformance

\`run.mjs\` invokes the bundled, reviewed World externality verifier with the
four exact release archives. The verifier authenticates every archive before
extracting or executing it, uses isolated Zig caches, and requires no sibling
checkout.
`;
}

function lifecycleReadme() {
  return `# Lifecycle conformance

\`receipt.json\` is emitted by the bundled world-host v1.0.0 lifecycle proof.
Revalidate it with:

\`\`\`sh
bun ../../world-host/distribution/conformance/run.mjs
\`\`\`
`;
}

function negativeReadme() {
  return `# Negative conformance

\`receipt.json\` projects the ten required rejection cases from the bundled
host lifecycle receipt. Capability-level malformed and policy corpora remain
owned by \`../../world-capabilities/distribution/corpus/negative\`.
`;
}

function licensesReadme() {
  return `# License inventory

Boundary v0.7.0 publishes the MIT license copied here as
\`boundary-MIT.txt\`.

The reviewed World v1.0.0, world-host v1.0.0, and world-capabilities v1.0.0
artifacts did not contain license files when this SDK was assembled. This
inventory records that upstream state and does not invent or extend
redistribution terms.
`;
}
