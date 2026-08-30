import { describe, expect, test } from "bun:test";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  checkProcessSurface,
  derivePackageInventory,
  scanModuleSpecifiers,
  validateModuleImportSyntax,
  validatePackageManifest,
  validatePublicExportNames,
  validateProductionSpecifier,
  validateRepositoryInventory,
} from "../scripts/check_process_surface.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function manifest(overrides = {}) {
  return {
    name: "@tkersey/world",
    version: "4.0.0",
    type: "module",
    private: false,
    license: "MIT",
    exports: { "./process-v1": "./src/process_v1/index.mjs" },
    bin: { world: "./bin/world.mjs" },
    engines: { bun: ">=1.4.0" },
    files: [
      "LICENSE",
      "README.md",
      "bin/",
      "src/process_v1/",
      "boundary-process-kernel-v1.wasm",
    ],
    scripts: {
      check:
        "bun run check:process-v1 && bun run check:runtime && bun run conformance:runtime",
      "check:process-v1": "bun scripts/check_process_surface.mjs && bun test",
      "build:runtime": "bun scripts/build_runtime_archive.mjs",
      "check:runtime": "bun scripts/check_runtime_archive.mjs",
      "conformance:runtime": "bun scripts/run_clean_room_conformance.mjs",
    },
    ...overrides,
  };
}

describe("World 4 package identity", () => {
  test("accepts only the exact manifest surface", () => {
    expect(() => validatePackageManifest(manifest())).not.toThrow();
  });

  test("rejects an added public root or executable", () => {
    expect(() =>
      validatePackageManifest(manifest({
        exports: {
          ".": "./src/process_v1/index.mjs",
          "./process-v1": "./src/process_v1/index.mjs",
        },
      })),
    ).toThrow("exports keys");
    expect(() =>
      validatePackageManifest(manifest({
        bin: { world: "./bin/world.mjs", drive: "./bin/drive.mjs" },
      })),
    ).toThrow("bin keys");
  });

  test("rejects a missing or additional JavaScript export", () => {
    expect(() => validatePublicExportNames([
      "WorldProcessHostError",
      "admitProcessKernel",
      "decodeEffectRequest",
      "decodeEffectResult",
      "decodeProcessOutcome",
    ])).toThrow("public namespace");
    expect(() => validatePublicExportNames([
      "WorldProcessHostError",
      "admitProcessKernel",
      "decodeEffectRequest",
      "decodeEffectResult",
      "decodeProcessOutcome",
      "encodeEffectResult",
      "runToCompletion",
    ])).toThrow("runToCompletion");
  });

  test("rejects every dependency or alternate package surface", () => {
    expect(() =>
      validatePackageManifest(manifest({ dependencies: { example: "1.0.0" } })),
    ).toThrow("dependencies");
    expect(() =>
      validatePackageManifest(manifest({ devDependencies: {} })),
    ).toThrow("devDependencies");
    expect(() =>
      validatePackageManifest(manifest({ main: "./src/process_v1/index.mjs" })),
    ).toThrow("main");
  });
});

describe("source-derived topology", () => {
  test("rejects retired Zig and SDK paths", () => {
    const required = [
      ".gitignore",
      ".learnings.jsonl",
      ".ledger/learnings/events.jsonl",
      "README.md",
      "LICENSE",
      "package.json",
      "boundary-process-kernel-v1.wasm",
      "docs/migration_from_world_3.md",
      "docs/process_host_v1.md",
      "docs/security_model.md",
      "scripts/acquire_boundary_process_assets.mjs",
      "scripts/acquire_process_conformance_assets.mjs",
      "scripts/acquire_repository_repair_transcript.mjs",
      "scripts/build_runtime_archive.mjs",
      "scripts/check_process_surface.mjs",
      "scripts/check_runtime_archive.mjs",
      "scripts/run_clean_room_conformance.mjs",
      "scripts/write_release_receipt.mjs",
    ].map((entry) => ({ path: entry, tracked: true, regular: true, symlink: false, mode: 0o100644 }));

    expect(() =>
      validateRepositoryInventory([
        ...required,
        { path: "build.zig", tracked: true, regular: true, symlink: false, mode: 0o100644 },
      ]),
    ).toThrow("World 3 build surface");
    expect(() =>
      validateRepositoryInventory([
        ...required,
        { path: "sdk/v3/index.mjs", tracked: true, regular: true, symlink: false, mode: 0o100644 },
      ]),
    ).toThrow("World 3 source root");
  });

  test("repository evidence never enters the package inventory", () => {
    const entries = [
      ".learnings.jsonl",
      ".ledger/learnings/events.jsonl",
      "package.json",
      "LICENSE",
      "README.md",
      "bin/world.mjs",
      "src/process_v1/index.mjs",
      "boundary-process-kernel-v1.wasm",
    ].map((entry) => ({ path: entry, tracked: true, regular: true, symlink: false, mode: 0o100644 }));
    const inventory = derivePackageInventory(entries, manifest());
    expect(inventory).not.toContain(".learnings.jsonl");
    expect(inventory).not.toContain(".ledger/learnings/events.jsonl");
  });

  test("finds static, re-export, and dynamic imports", () => {
    const imports = scanModuleSpecifiers(`
      import { x } from "./x.mjs";
      export { y } from "./y.mjs";
      const z = import("./z.mjs");
      import "node:crypto";
    `);
    expect([...imports].sort()).toEqual([
      "./x.mjs",
      "./y.mjs",
      "./z.mjs",
      "node:crypto",
    ]);
  });

  test("rejects bare packages in production", () => {
    expect(() => validateProductionSpecifier("node:crypto", "src/process_v1/a.mjs")).not.toThrow();
    expect(() => validateProductionSpecifier("./b.mjs", "src/process_v1/a.mjs")).not.toThrow();
    expect(() => validateProductionSpecifier("left-pad", "src/process_v1/a.mjs")).toThrow(
      "forbidden bare package",
    );
  });

  test("rejects import routes the source graph cannot derive", () => {
    expect(() => validateModuleImportSyntax(
      "await import(candidate)",
      "src/process_v1/a.mjs",
    )).toThrow("non-literal dynamic import");
    expect(() => validateModuleImportSyntax(
      'const fs = require("node:fs")',
      "src/process_v1/a.mjs",
    )).toThrow("CommonJS require");
  });
});

test("the current World tree is exactly the admitted thin-host surface", async () => {
  const report = await checkProcessSurface(root);
  expect(report.publicExports).toEqual([
    "WorldProcessHostError",
    "admitProcessKernel",
    "decodeEffectRequest",
    "decodeEffectResult",
    "decodeProcessOutcome",
    "encodeEffectResult",
  ]);
  expect(report.runtimeDependencyCount).toBe(0);
  expect(report.repositoryEvidence).toEqual([
    ".learnings.jsonl",
    ".ledger/learnings/events.jsonl",
  ]);
});
