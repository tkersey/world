#!/usr/bin/env node
import { readRegularFile } from "../src/node/file-input.mjs";
import { Kernel, packageVersion } from "../src/embedding/index.mjs";
import { assertKernelByteLength } from "../src/embedding/wasm.mjs";

async function main(args) {
  if (args[0] === "runtime") {
    const { runtimeCommand } = await import("../src/node/runtime-command.mjs");
    console.log(JSON.stringify(await runtimeCommand(args.slice(1)), null, 2));
    return;
  }
  if (args.length === 1 && args[0] === "--version") { console.log(packageVersion); return; }
  if (args.length === 1 && args[0] === "--help") {
    console.log("world runtime prepare --source ABSOLUTE_CLEAN_WORLD --output ABSOLUTE_NEW_BUNDLE\nworld runtime verify --root BUNDLE --manifest-sha256 HEX [--smoke]");
    console.log("Usage: world invoke --kernel FILE --sha256 HEX --input PKI3 [--input-budget N --working-budget N --output-budget N]\nWrites canonical PKO3 bytes to stdout. Budgets are bytes; defaults are 65536/1048576/65536.");
    return;
  }
  if (args.shift() !== "invoke") throw new Error("expected invoke, --help or --version");
  const allowed = new Set(["--kernel", "--sha256", "--input", "--input-budget", "--working-budget", "--output-budget"]);
  const options = new Map();
  while (args.length) {
    const flag = args.shift(), value = args.shift();
    if (!allowed.has(flag) || options.has(flag) || !value || value.startsWith("--")) throw new Error(`invalid option ${flag}`);
    options.set(flag, value);
  }
  for (const required of ["--kernel", "--sha256", "--input"]) if (!options.has(required)) throw new Error(`missing ${required}`);
  const limits = { input: 65536n, working: 1048576n, output: 65536n };
  for (const name of Object.keys(limits)) if (options.has(`--${name}-budget`)) {
    const value = options.get(`--${name}-budget`);
    if (!/^(0|[1-9][0-9]*)$/.test(value) || BigInt(value) >= 1n << 64n) throw new Error(`invalid ${name} budget`);
    limits[name] = BigInt(value);
  }
  const read = path => readRegularFile(path, length => { if (length > (256n << 20n)) throw new RangeError("input file exceeds 256 MiB host limit"); });
  const kernel = await Kernel.create({ bytes: await readRegularFile(options.get("--kernel"), assertKernelByteLength), expectedSha256: options.get("--sha256") });
  kernel.setLimits(limits);
  process.stdout.write(kernel.invoke(await read(options.get("--input"))));
}
try { await main(process.argv.slice(2)); }
catch (error) {
  process.stderr.write(`${error.code ?? "WORLD_REJECTED"}: ${error.message}\n`);
  process.exitCode = 1;
}
