import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
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

const ARCHIVES = Object.freeze({
  "boundary/boundary-v0.7.0.tar.gz":
    "25e5bd5ed45aac023ef99beee93f675ea4efb3f6eb1e98d2a13040d7451f0e9a",
  "world/world-v1.0.0.tar.gz":
    "9976802090738d61beb49522207c086cf1f529f2f39002de7b54d1c10808b944",
  "world-host/world-host-v1.0.0.tar.gz":
    "f881aaf3ada062ca3d80fc46d10cb001f38504d816ecd4995faf34bcd14ecc70",
  "world-capabilities/world-capabilities-v1-runtime-v1.0.0.tar.gz":
    "1d9011faf1932de66ca4f7f24dcfaea41671175999bf278683bda4702854e0ca",
});

const VERIFIER_SHA256 = Object.freeze({
  "conformance/external-consumer/verifier/scripts/check_world_1_0_externality.mjs":
    "1e4ad89c93c7337b0e30608a81e783b586a29bd1353d85aeafe9e7502cdee043",
  "conformance/external-consumer/verifier/scripts/check_world_external_consumer.mjs":
    "8e91544440b442bdca20d1feb8ee3b1e47661a725a3b53d2c87c8f5889c63a82",
});

const COMPLETION_RECEIPT = Object.freeze({
  world_1_0_externality_gate: "true",
  clean_room_build: "true",
  sibling_checkout_required: "false",
  internal_import_count: "0",
  application_wasm_import_count: "0",
  custom_effect: "true",
  internal_provider: "true",
  external_capability: "true",
  fresh_instance_resume: "true",
  deterministic_retry: "true",
  replay_fresh_effect_count: "0",
  branching: "true",
  migration: "true",
  source_independent_host: "true",
});

const options = commandOptions();
const root = options.sdk;
assert.equal(basename(root), "world-sdk-v1.0.0");
assert(lstatSync(root).isDirectory(), "SDK root must be a directory");

const files = listFiles(root).sort();
const checksums = parseChecksums(
  readFileSync(join(root, "checksums.sha256"), "utf8"),
);
assert.deepEqual(
  [...checksums.keys()].sort(),
  files.filter((path) => path !== "checksums.sha256"),
  "SDK checksum coverage mismatch",
);
for (const [path, expected] of checksums) {
  assert.equal(sha256File(join(root, path)), expected, `SDK checksum mismatch: ${path}`);
}

assertReleaseProjections();
for (const [path, expected] of Object.entries(VERIFIER_SHA256)) {
  assert.equal(
    sha256File(join(root, path)),
    expected,
    `externality verifier identity mismatch: ${path}`,
  );
}

for (const path of [
  "README.md",
  "LICENSES/README.md",
  "LICENSES/boundary-MIT.txt",
  "boundary/release.json",
  "boundary/docs/static_machine.md",
  "world/release.json",
  "world/application-template/build.zig.zon",
  "world/application_manifest_schema.md",
  "world/docs/application_abi_v1.md",
  "world/docs/zero_to_world_application.md",
  "world-host/release.json",
  "world-host/distribution/host/bin/world-host-v1.mjs",
  "world-host/distribution/conformance/check-pack.mjs",
  "world-capabilities/release.json",
  "world-capabilities/distribution/templates/capability-v1/manifest.json",
  "world-capabilities/distribution/harness/check-pack.mjs",
  "examples/research-digest-agent/src/effects.zig",
  "conformance/external-consumer/run.mjs",
  "conformance/external-consumer/verifier/scripts/check_world_1_0_externality.mjs",
  "conformance/external-consumer/verifier/scripts/check_world_external_consumer.mjs",
  "conformance/external-consumer/receipt.txt",
  "conformance/lifecycle/receipt.json",
  "conformance/negative/receipt.json",
]) {
  assert(files.includes(path), `missing SDK file: ${path}`);
}

const boundary = readJson(root, "boundary/release.json");
const world = readJson(root, "world/release.json");
const hostRelease = readJson(root, "world-host/release.json");
const capabilitiesRelease = readJson(root, "world-capabilities/release.json");
assert.equal(boundary.tag, "v0.7.0");
assert.equal(
  boundary.packageHash,
  "boundary-0.7.0-flclaCnjkABOSWaiSkxMBDQZsBEeA-Niai-l1u0q3A7_",
);
assert.equal(world.tag, "v1.0.0");
assert.equal(
  world.packageHash,
  "world-1.0.0-XXTUeF0tiAC_5jqj2oVDvgGmmh8c7CRCnuaG8p2i9Zk_",
);
assert(/^[0-9a-f]{40}$/.test(world.documentationCommit));
assert.equal(hostRelease.tag, "v1.0.0");
assert.equal(
  hostRelease.executableSourceCommit,
  "b66324515577323325deccf532efd85e370f51b3",
);
assert.equal(capabilitiesRelease.tag, "v1.0.0");
assert.equal(
  capabilitiesRelease.researchPackFingerprint,
  "c3106b770e2d14237c981b4671da3d42dfbaed33eed81ccc78c257a42419354e",
);

const hostManifest = readJson(
  root,
  "world-host/distribution/manifest.json",
);
assert.equal(hostManifest.releaseStatus, "released");
assert.equal(hostManifest.sourcePins.worldRelease.tag, "v1.0.0");
assert.equal(
  hostManifest.sourcePins.worldRelease.packageHash,
  world.packageHash,
);
assert.equal(
  hostManifest.sourcePins.boundaryRelease.packageHash,
  boundary.packageHash,
);
assert.equal(
  hostManifest.sourcePins.worldCapabilitiesRelease.runtimeAssetSha256,
  capabilitiesRelease.archiveSha256,
);
assert.equal(
  hostManifest.sourcePins.worldCapabilitiesRelease.researchPackFingerprint,
  capabilitiesRelease.researchPackFingerprint,
);

assertTreesEqual(
  join(root, "world/application-template"),
  join(root, "examples/research-digest-agent"),
  new Set(["build.zig.zon"]),
  "generated example",
);
const exampleZon = readFileSync(
  join(root, "examples/research-digest-agent/build.zig.zon"),
  "utf8",
);
assert(exampleZon.includes(world.url));
assert(exampleZon.includes(world.packageHash));
assert(!exampleZon.includes("__WORLD_RELEASE_"));

const lifecycle = readJson(root, "conformance/lifecycle/receipt.json");
assert.equal(lifecycle.releaseStatus, "released");
assert.equal(lifecycle.sourceCheckoutRequired, false);
assert.equal(lifecycle.sourceIndependentHost, true);
assert.equal(lifecycle.capabilityAuthoredFrame, false);
assert.equal(lifecycle.applicationSpecificHostLogic, false);
assert.equal(lifecycle.scenarios.researchCapabilityInvocations, 1);
assert.equal(lifecycle.scenarios.researchReplayFreshEffects, 0);

const negative = readJson(root, "conformance/negative/receipt.json");
assert.equal(negative.receiptVersion, "world-sdk-negative/v1");
assert.deepEqual(negative.cases, lifecycle.scenarios.researchNegativeCases);
assert(Object.values(negative.cases).every((value) => value === true));

const externality = keyValueReceipt(
  readFileSync(
    join(root, "conformance/external-consumer/receipt.txt"),
    "utf8",
  ),
);
for (const [key, expected] of Object.entries(COMPLETION_RECEIPT)) {
  assert.equal(externality[key], expected, `externality receipt mismatch: ${key}`);
}
assert.equal(
  externality.world_host_archive_sha256,
  ARCHIVES["world-host/world-host-v1.0.0.tar.gz"],
);
assert.equal(
  externality.world_capabilities_runtime_archive_sha256,
  ARCHIVES[
    "world-capabilities/world-capabilities-v1-runtime-v1.0.0.tar.gz"
  ],
);

process.stdout.write(
  `${JSON.stringify(
    {
      receiptVersion: "world-sdk-v1-check/v1",
      sdkVersion: "1.0.0",
      checksumCount: checksums.size,
      releaseArchiveCount: Object.keys(ARCHIVES).length,
      cleanRoomBuild: true,
      sourceCheckoutRequired: false,
      sourceIndependentHost: true,
      complete: true,
    },
    null,
    2,
  )}\n`,
);

function assertReleaseProjections() {
  const proofRoot = mkdtempSync(join(tmpdir(), "world-sdk-release-projections-"));
  try {
    const releaseRoots = {};
    for (const [path, expected] of Object.entries(ARCHIVES)) {
      const archiveBytes = readFileSync(join(root, path));
      assert.equal(
        createHash("sha256").update(archiveBytes).digest("hex"),
        expected,
        `release identity mismatch: ${path}`,
      );
      const name = path.split("/")[0];
      const snapshot = join(proofRoot, `${name}.tar.gz`);
      writeFileSync(snapshot, archiveBytes, {
        flag: "wx",
        mode: 0o400,
      });
      const extracted = join(proofRoot, name);
      mkdirSync(extracted, { mode: 0o700 });
      run("tar", ["-xzf", snapshot, "-C", extracted]);
      releaseRoots[name] = singleDirectoryRoot(extracted, path);
    }

    assertTreesEqual(
      releaseRoots["world-host"],
      join(root, "world-host/distribution"),
    );
    assertTreesEqual(
      releaseRoots["world-capabilities"],
      join(root, "world-capabilities/distribution"),
    );
    assertTreesEqual(
      join(releaseRoots.world, "templates/application-v1"),
      join(root, "world/application-template"),
    );

    for (const name of [
      "compatibility.md",
      "static_machine.md",
      "static_machine_parity.md",
      "static_machine_state.md",
    ]) {
      assertFilesEqual(
        join(releaseRoots.boundary, "docs", name),
        join(root, "boundary/docs", name),
      );
    }
    assertFilesEqual(
      join(releaseRoots.boundary, "LICENSE"),
      join(root, "LICENSES/boundary-MIT.txt"),
    );
    for (const name of [
      "application_v1.md",
      "application_abi_v1.md",
      "effect_protocol_v1.md",
      "frame_v1.md",
    ]) {
      assertFilesEqual(
        join(releaseRoots.world, "docs", name),
        join(root, "world/docs", name),
      );
    }
  } finally {
    rmSync(proofRoot, { recursive: true, force: true });
  }
}

function assertTreesEqual(
  left,
  right,
  ignored = new Set(),
  label = "release projection",
) {
  const leftFiles = listFiles(left)
    .filter((path) => !ignored.has(path))
    .sort();
  const rightFiles = listFiles(right)
    .filter((path) => !ignored.has(path))
    .sort();
  assert.deepEqual(rightFiles, leftFiles, `${label} file set differs`);
  for (const path of leftFiles) {
    assert.equal(
      sha256File(join(right, path)),
      sha256File(join(left, path)),
      `${label} differs from reviewed source: ${path}`,
    );
  }
}

function assertFilesEqual(left, right) {
  assert.equal(
    sha256File(right),
    sha256File(left),
    `release projection differs from archive: ${relative(root, right)}`,
  );
}

function singleDirectoryRoot(extracted, archivePath) {
  const entries = readdirSync(extracted, { withFileTypes: true });
  assert.equal(
    entries.length,
    1,
    `release archive must contain one root: ${archivePath}`,
  );
  assert(
    entries[0].isDirectory(),
    `release archive root must be a directory: ${archivePath}`,
  );
  return join(extracted, entries[0].name);
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

function parseChecksums(text) {
  const result = new Map();
  for (const line of text.trimEnd().split("\n")) {
    const match = /^([0-9a-f]{64})  ([^\n]+)$/.exec(line);
    assert(match, `invalid SDK checksum line: ${line}`);
    assert(!result.has(match[2]), `duplicate SDK checksum path: ${match[2]}`);
    result.set(match[2], match[1]);
  }
  return result;
}

function keyValueReceipt(text) {
  const result = {};
  for (const line of text.split("\n")) {
    const index = line.indexOf("=");
    if (index > 0) result[line.slice(0, index)] = line.slice(index + 1);
  }
  return result;
}

function readJson(root, path) {
  return JSON.parse(readFileSync(join(root, path), "utf8"));
}

function sha256File(path) {
  assert(existsSync(path), `missing SDK path: ${path}`);
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function run(command, args) {
  const result = spawnSync(command, args, {
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
}

function commandOptions() {
  const current = resolve(fileURLToPath(import.meta.url));
  const embedded = basename(dirname(current)) === "conformance";
  const args = process.argv.slice(2);
  if (args.length > 1) throw new Error("usage: check_world_sdk_v1.mjs [SDK_ROOT]");
  return {
    sdk:
      args.length === 1
        ? resolve(args[0])
        : embedded
          ? resolve(dirname(current), "..")
          : resolve("world-sdk-v1.0.0"),
  };
}
