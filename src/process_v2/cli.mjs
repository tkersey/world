// Copyright (c) 2026 World contributors. MIT license.
import { writeFile, rename, rm, realpath } from "node:fs/promises";
import { resolve, dirname, basename, join } from "node:path";
import { randomUUID } from "node:crypto";
import { admitProcessKernel, encodeInput, packageVersion } from "./index.mjs";
import { readProcessKernelFile } from "./kernel_file.mjs";
import { readRegularFile } from "./file_input.mjs";

export const help = `Usage: world process <step|run> --image FILE (--initial FILE | --state FILE) --output FILE
  --kernel FILE --kernel-sha256 HEX  Use an explicitly digest-bound kernel
  --result FILE                     Supply an ERS2 for saved State
  --cancel TEXT                     Cancel saved State with a UTF-8 reason
  --cancel-bytes FILE                Cancel with an opaque byte reason

The default kernel is authenticated through the bundled runtime identity.
Output is one PKO2 record. Requested effects are returned to the caller.
  --help                            Show this help
  --version                         Show the package version
`;

function usage(message) { const error = new Error(message); error.code = "WORLD_CLI_USAGE"; throw error; }
export function parseArguments(args) {
  if (args.length === 1 && args[0] === "--help") return { help: true };
  if (args.length === 1 && args[0] === "--version") return { version: true };
  if (args[0] !== "process" || !["step", "run"].includes(args[1])) usage("expected process step or process run");
  const options = { mode: args[1] === "step" ? "advance" : "run" };
  const keys = new Map([["--image", "image"], ["--initial", "initialArgs"], ["--state", "state"],
    ["--result", "result"], ["--cancel", "cancel"], ["--cancel-bytes", "cancelBytes"],
    ["--output", "output"], ["--kernel", "kernelPath"], ["--kernel-sha256", "expectedSha256"]]);
  for (let i = 2; i < args.length; i += 2) {
    const key = keys.get(args[i]);
    if (!key || args[i + 1] === undefined || args[i + 1].startsWith("--")) usage(`unknown or incomplete option: ${args[i]}`);
    if (Object.hasOwn(options, key)) usage(`duplicate option: ${args[i]}`);
    options[key] = args[i + 1];
  }
  if (!options.image || !options.output || (options.initialArgs === undefined) === (options.state === undefined)) usage("provide image, output, and exactly one of initial or state");
  if ([options.result, options.cancel, options.cancelBytes].filter((value) => value !== undefined).length > 1) usage("result and cancellation options are mutually exclusive");
  if (options.initialArgs !== undefined && [options.result, options.cancel, options.cancelBytes].some((value) => value !== undefined)) usage("result and cancellation require saved State");
  if ((options.kernelPath === undefined) !== (options.expectedSha256 === undefined)) usage("custom kernel requires kernel and kernel-sha256 together");
  if (options.expectedSha256 !== undefined && !/^[a-f0-9]{64}$/.test(options.expectedSha256)) usage("kernel-sha256 must be 64 lowercase hexadecimal characters");
  return options;
}

export async function executeCli(args, stdout = process.stdout) {
  const options = parseArguments(args);
  if (options.help) { stdout.write(help); return; }
  if (options.version) { stdout.write(`${packageVersion}\n`); return; }
  const destination = resolve(options.output);
  const destinationIdentity = await realpath(destination).catch((error) => { if (error.code !== "ENOENT") throw error; return resolve(destination); });
  async function checkInputPath(path) {
    if (await realpath(path) === destinationIdentity) usage("output must differ from every input file");
  }
  const input = {};
  for (const key of ["image", "initialArgs", "state", "result", "cancelBytes"]) if (options[key] !== undefined) {
    await checkInputPath(options[key]);
    input[key === "cancelBytes" ? "cancel" : key] = await readRegularFile(options[key]);
  }
  if (options.cancel !== undefined) input.cancel = options.cancel;
  encodeInput({ ...input, mode: options.mode });
  const selected = await readProcessKernelFile(options, packageVersion);
  for (const path of selected.files) await checkInputPath(path);
  const host = await admitProcessKernel(selected.bytes, { expectedSha256: selected.expectedSha256 });
  const outcome = await host[options.mode](input);
  const temporary = join(dirname(destination), `.${basename(destination)}.${randomUUID()}.tmp`);
  try {
    await writeFile(temporary, outcome.bytes, { flag: "wx", mode: 0o600 });
    await rename(temporary, destination);
  } finally { await rm(temporary, { force: true }); }
}
