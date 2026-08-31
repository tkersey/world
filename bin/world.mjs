#!/usr/bin/env bun

import fs from "node:fs";
import { fileURLToPath } from "node:url";

import { WorldProcessHostError } from "../src/process_v1/errors.mjs";
import {
  executeProcessStep,
  parseProcessStepArguments,
} from "../src/process_v1/file_input.mjs";

const bundledKernelPath = fileURLToPath(
  new URL("../boundary-process-kernel-v1.wasm", import.meta.url),
);

try {
  const options = parseProcessStepArguments(process.argv.slice(2), bundledKernelPath);
  await executeProcessStep(options);
} catch (error) {
  const admitted = error instanceof WorldProcessHostError;
  const code = admitted ? error.code : "WORLD_RUNTIME_BINDING_INVALID";
  const message = admitted
    ? error.message
    : "world process step failed without an admitted diagnostic";
  writeDiagnostic(`${code}: ${message}\n`);
  process.exitCode = code === "WORLD_CLI_USAGE" ? 2 : 1;
}

function writeDiagnostic(message) {
  const bytes = Buffer.from(message, "utf8");
  let offset = 0;
  while (offset < bytes.byteLength) {
    try {
      const written = fs.writeSync(
        fs.constants.STDERR_FILENO ?? 2,
        bytes,
        offset,
        bytes.byteLength - offset,
      );
      if (written === 0) break;
      offset += written;
    } catch {
      break;
    }
  }
}
