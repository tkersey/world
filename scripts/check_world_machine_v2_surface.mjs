import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const packageSource = readFileSync(join(root, "build.zig.zon"), "utf8");
const packageVersion = packageSource.match(/\.version = "([^"]+)"/)?.[1];
assert(packageVersion, "build.zig.zon is missing the World package version");
const surfaces = new Map([
  ["README.md", ["Boundary Machine ABI v2", "world.application"]],
  [
    "docs/application_v1.md",
    [
      "Boundary Machine ABI v2",
      "RNF Machine state",
      "world.v1.handle(\n            RootMachine,\n            0,\n            \"example.lookup.v1\",\n            ProviderMachine,",
      "world.v1.external(ProviderMachine, 0, .{\n            .site_identity = \"host.example.request.v1\"",
      "`InitialArgs` must exactly equal the handled site's\n`Payload`",
    ],
  ],
  [
    "docs/static_handlers.md",
    [
      "Boundary Machine ABI v2",
      "world.v1.handle(\n    ParentMachine,\n    site_ordinal,\n    expected_site_identity,\n    ProviderMachine,\n)",
      "world.v1.external(OwnerMachine, site_ordinal, .{\n    .site_identity = \"file.read.v1\"",
      "`InitialArgs` is\nexactly the handled site's `Payload`",
    ],
  ],
  ["templates/application-v1/README.md", ["research.lookup.v2", "Vector"]],
]);
const forbidden = [
  "StaticMachine",
  "Program.Session",
  "world.v1.handle(ParentSite, ProviderMachine)",
  "world.v1.external(Site,",
  "tuple{ParentSite.Payload}",
];

for (const [path, required] of surfaces) {
  const source = readFileSync(join(root, path), "utf8");
  for (const marker of required) {
    assert(source.includes(marker), `${path} is missing ${marker}`);
  }
  for (const marker of forbidden) {
    assert(!source.includes(marker), `${path} retains ${marker}`);
  }
}

const applicationDocs = readFileSync(
  join(root, "docs/application_v1.md"),
  "utf8",
);
const applicationRuntime = readFileSync(
  join(root, "src/application_runtime_v1.zig"),
  "utf8",
);
const externalResultSignature = applicationRuntime.match(
  /pub fn encodeExternalResult\([\s\S]*?\) protocol\.Error!\[\]u8 \{/,
)?.[0];
assert(externalResultSignature, "World is missing App.encodeExternalResult");
assert(
  !externalResultSignature.includes("expected_site_identity"),
  "App.encodeExternalResult retains redundant caller site-identity authority",
);
const buildSource = readFileSync(join(root, "build.zig"), "utf8");
assert(
  !buildSource.includes(
    "application_v1_external_result_site_identity_mismatch",
  ),
  "World retains the wound-specific external-result identity fixture",
);
assert(
  applicationDocs.includes(`World \`v${packageVersion}\` embeds`),
  "docs/application_v1.md release identity differs from build.zig.zon",
);

console.log("boundary_machine_abi=2");
console.log(`world_release_version=${packageVersion}`);
console.log("static_machine_primary_docs=false");
console.log("program_session_primary_docs=false");
