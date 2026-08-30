import { describe, expect, test } from "bun:test";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  EXPECTED_PRODUCTION_BUILTINS,
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
        "bun run check:process-v1 && bun run build:runtime && bun run check:runtime && bun run conformance:runtime",
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
      ".ledger/negative-ledger/events.jsonl",
      ".ledger/review-fold/counterexamples/events.jsonl",
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
      ".ledger/negative-ledger/events.jsonl",
      ".ledger/review-fold/counterexamples/events.jsonl",
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
    expect(inventory).not.toContain(".ledger/negative-ledger/events.jsonl");
    expect(inventory).not.toContain(".ledger/review-fold/counterexamples/events.jsonl");
  });

  test("finds static, namespace re-export, and dynamic imports", () => {
    const imports = scanModuleSpecifiers(`
      import { x } from "./x.mjs";
      export { y } from "./y.mjs";
      export * as ns from "./ns.mjs";
      const z = import("./z.mjs");
      import "node:crypto";
    `);
    expect([...imports].sort()).toEqual([
      "./ns.mjs",
      "./x.mjs",
      "./y.mjs",
      "./z.mjs",
      "node:crypto",
    ]);
  });

  test("derives and rejects a namespace re-export from a bare package", () => {
    const imports = scanModuleSpecifiers('export * as ns from "left-pad";');
    expect(imports).toEqual(["left-pad"]);
    expect(() => validateProductionSpecifier(imports[0], "src/process_v1/a.mjs")).toThrow(
      "forbidden bare package",
    );
  });

  test("rejects bare packages in production", () => {
    for (const specifier of EXPECTED_PRODUCTION_BUILTINS) {
      expect(() => validateProductionSpecifier(specifier, "src/process_v1/a.mjs")).not.toThrow();
    }
    expect(() => validateProductionSpecifier("node:module", "src/process_v1/a.mjs")).toThrow(
      "forbidden builtin",
    );
    expect(() => validateProductionSpecifier("node:child_process", "src/process_v1/a.mjs")).toThrow(
      "forbidden builtin",
    );
    expect(() => validateProductionSpecifier("./b.mjs", "src/process_v1/a.mjs")).not.toThrow();
    expect(() => validateProductionSpecifier("left-pad", "src/process_v1/a.mjs")).toThrow(
      "forbidden bare package",
    );
  });

  test("rejects import routes the source graph cannot derive", () => {
    expect(() => validateModuleImportSyntax(
      "await import(candidate)",
      "src/process_v1/a.mjs",
    )).toThrow("dynamic import");
    expect(() => validateModuleImportSyntax(
      "await import/* resolved at runtime */(candidate)",
      "src/process_v1/a.mjs",
    )).toThrow("dynamic import");
    expect(() => validateModuleImportSyntax(
      "await import // resolved at runtime\n(candidate)",
      "src/process_v1/a.mjs",
    )).toThrow("dynamic import");
    expect(() => validateModuleImportSyntax(
      'const inert = "import(\\"node:fs\\")"',
      "src/process_v1/a.mjs",
    )).toThrow("dynamic import");
    expect(() => validateModuleImportSyntax(
      'const fs = require("node:fs")',
      "src/process_v1/a.mjs",
    )).toThrow("CommonJS require");
    expect(() => validateModuleImportSyntax(
      'const fs = require/* CommonJS */("node:fs")',
      "src/process_v1/a.mjs",
    )).toThrow("CommonJS require");
  });

  test("rejects aliased createRequire at syntax and specifier admission", () => {
    const source = [
      'import { createRequire as load } from "node:module";',
      "const requireFromHere = load(import.meta.url);",
    ].join("\n");
    expect(scanModuleSpecifiers(source)).toEqual(["node:module"]);
    expect(() => validateProductionSpecifier(
      scanModuleSpecifiers(source)[0],
      "src/process_v1/a.mjs",
    )).toThrow("forbidden builtin");
    expect(() => validateModuleImportSyntax(source, "src/process_v1/a.mjs")).toThrow(
      "createRequire",
    );
  });

  test("rejects ambient builtin and generated-code loader escapes", () => {
    for (const source of [
      'process.getBuiltinModule("fs")',
      'globalThis.process["getBuiltinModule"]("fs")',
    ]) {
      expect(() => validateModuleImportSyntax(source, "src/process_v1/a.mjs")).toThrow(
        "getBuiltinModule",
      );
    }
    for (const source of [
      'eval("import(\\"node:fs\\")")',
      'globalThis.eval("import(\\"node:fs\\")")',
      'const evaluate = eval; evaluate("import(\\"node:fs\\")")',
      'Function("return import(\\"node:fs\\")")()',
      'new globalThis.Function("return import(\\"node:fs\\")")()',
      'const Constructor = Function; Constructor("return import(\\"node:fs\\")")()',
    ]) {
      expect(() => validateModuleImportSyntax(source, "src/process_v1/a.mjs")).toThrow();
    }
  });

  test("rejects Bun loader and spawn API acquisition", () => {
    for (const source of [
      'Bun.resolve("left-pad", import.meta.dir)',
      'const plugin = Bun["plugin"]',
      'const spawn = Bun.spawn',
      'const { spawn: run } = Bun; run(["bun", "payload.mjs"])',
      'const runtime = Bun; runtime.spawn(["bun", "payload.mjs"])',
      'Bun?.spawnSync(["bun", "run", "payload.mjs"])',
    ]) {
      expect(() => validateModuleImportSyntax(source, "src/process_v1/a.mjs")).toThrow(
        "forbidden ambient capability",
      );
    }
  });

  test("rejects direct ambient network authority roots and their aliases", () => {
    const roots = new Map([
      ["fetch", 'fetch("https://example.invalid")'],
      ["WebSocket", 'new WebSocket("wss://example.invalid")'],
      ["navigator", "navigator.userAgent"],
      ["XMLHttpRequest", "new XMLHttpRequest()"],
      ["EventSource", 'new EventSource("https://example.invalid")'],
      ["WebTransport", 'new WebTransport("https://example.invalid")'],
    ]);

    for (const [rootName, directUse] of roots) {
      for (const source of [
        directUse,
        `const authority = ${rootName}; authority;`,
        `const { apply: invoke } = ${rootName}; invoke;`,
      ]) {
        expect(() => validateModuleImportSyntax(
          source,
          "src/process_v1/a.mjs",
        )).toThrow("forbidden ambient capability");
      }
    }
  });

  test("network authority names remain inert as data and property keys", () => {
    const inert = [
      'const quoted = "fetch WebSocket navigator XMLHttpRequest EventSource WebTransport";',
      "// fetch WebSocket navigator XMLHttpRequest EventSource WebTransport",
      "/* fetch WebSocket navigator XMLHttpRequest EventSource WebTransport */",
      "const record = { fetch: 1, WebSocket: 2, navigator: 3, XMLHttpRequest: 4, EventSource: 5, WebTransport: 6 };",
      "record.fetch; record.WebSocket; record.navigator; record.XMLHttpRequest; record.EventSource; record.WebTransport;",
      "const data = { Request, Response, URL };",
    ].join("\n");

    expect(() => validateModuleImportSyntax(
      inert,
      "src/process_v1/a.mjs",
    )).not.toThrow();
  });

  test("admits only the runtime's exact ambient process property chains", () => {
    expect(() => validateModuleImportSyntax(`
      process.argv.slice(2);
      process.exitCode = 1;
      process.platform;
      process.pid;
      process.versions.bun;
    `, "src/process_v1/a.mjs")).not.toThrow();

    for (const source of [
      "process.cwd()",
      "process.exitCodeAlias",
      "process.versions.node",
      'process["argv"]',
      "const runtime = process",
    ]) {
      expect(() => validateModuleImportSyntax(source, "src/process_v1/a.mjs")).toThrow(
        "outside the admitted runtime property chains",
      );
    }
  });

  test("rejects ambient capability aliases and Function constructor recovery", () => {
    for (const source of [
      'globalThis["pro" + "cess"]',
      "global.Bun",
      "self.Bun",
      "window.Bun",
      "const load = import.meta.require; load('left-pad')",
      "const { require: load } = import.meta; load('left-pad')",
      "helper(Bun)",
      "Reflect.get(Bun, candidate)",
      'Object.getOwnPropertyDescriptor(async function () {}, "constructor").value',
      "const objectRoot = Object; objectRoot.getPrototypeOf(async function () {});",
      "(async () => {}).constructor",
      "handler?.constructor",
      "handler['constructor']",
      '(async () => {})["constructor"]',
      "const { constructor: AsyncFunction } = async function () {};",
      "const { constructor } = async function () {};",
      "const registry = { constructor: async function () {} };",
      "handler[`constructor`]",
      "1n.constructor",
      "const escaped = left / Bun / right;",
    ]) {
      expect(() => validateModuleImportSyntax(source, "src/process_v1/a.mjs")).toThrow();
    }
    expect(() => validateModuleImportSyntax(
      "class Ordinary { constructor() {} }",
      "src/process_v1/a.mjs",
    )).not.toThrow();
  });

  test("the parser carrier distinguishes inert syntax from ambient references", () => {
    const inert = [
      'const quoted = "Bun globalThis Reflect eval Function Worker Deno process constructor";',
      "// Bun globalThis Reflect eval Function Worker Deno process constructor",
      "/* Bun globalThis Reflect eval Function Worker Deno process constructor */",
      "const raw = `Bun globalThis Reflect eval Function Worker Deno process constructor`;",
      "const expression = /Bun/.test(candidate);",
      "const registry = { Bun: 1, globalThis: 2, Reflect: 3, eval: 4, Function: 5, Worker: 6, Deno: 7 };",
    ].join("\n");
    expect(() => validateModuleImportSyntax(inert, "src/process_v1/a.mjs")).not.toThrow();

    const substitution = "const raw = `inert Bun ${Bun}`;";
    expect(() => validateModuleImportSyntax(
      substitution,
      "src/process_v1/a.mjs",
    )).toThrow("forbidden ambient capability");
  });

  test("derives but does not admit comment-separated dynamic imports after a hashbang", () => {
    const source = [
      "#!/usr/bin/env bun",
      'const block = import/* literal */("./block.mjs");',
      "const line = import // literal",
      '("./line.mjs");',
    ].join("\n");

    expect(() => validateModuleImportSyntax(source, "bin/world.mjs")).toThrow("dynamic import");
    expect([...scanModuleSpecifiers(source)].sort()).toEqual([
      "./block.mjs",
      "./line.mjs",
    ]);
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
  expect(report.builtinModules).toEqual([
    "node:crypto",
    "node:fs",
    "node:path",
    "node:url",
    "node:util",
  ]);
  expect(report.repositoryEvidence).toEqual([
    ".learnings.jsonl",
    ".ledger/learnings/events.jsonl",
    ".ledger/negative-ledger/events.jsonl",
    ".ledger/review-fold/counterexamples/events.jsonl",
  ]);
});
