import fs from "node:fs";
import path from "node:path";
import { randomBytes } from "node:crypto";

import { WorldProcessHostError, worldError } from "./errors.mjs";
import { admitProcessKernel, advancePrepared } from "./kernel.mjs";

const MAXIMUM_KERNEL_BYTES = 64n * 1024n * 1024n;
const MAXIMUM_U64 = (1n << 64n) - 1n;
const SUPPORTED_PLATFORMS = new Set(["darwin", "linux"]);
const FLAG_NAMES = new Set([
  "--image",
  "--initial-args",
  "--state",
  "--result",
  "--kernel",
  "--out",
]);

export const PROCESS_STEP_USAGE =
  "usage: world process step --image PATH " +
  "(--initial-args PATH | --state PATH) " +
  "[--result PATH] [--kernel PATH] [--out PATH]";

/** Parse the complete public CLI grammar. Paths are opaque nonempty strings. */
export function parseProcessStepArguments(argv, bundledKernelPath) {
  if (!Array.isArray(argv) || argv[0] !== "process" || argv[1] !== "step") {
    throw usageError();
  }
  if (typeof bundledKernelPath !== "string" || bundledKernelPath.length === 0) {
    throw worldError(
      "WORLD_RUNTIME_BINDING_INVALID",
      "the bundled Process kernel path is unavailable",
    );
  }

  const options = new Map();
  for (let index = 2; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!FLAG_NAMES.has(flag) || typeof value !== "string" ||
        value.length === 0 || value.startsWith("--") || options.has(flag)) {
      throw usageError();
    }
    options.set(flag, value);
  }

  const imagePath = options.get("--image");
  const initialArgsPath = options.get("--initial-args");
  const statePath = options.get("--state");
  if (imagePath === undefined ||
      (initialArgsPath === undefined) === (statePath === undefined)) {
    throw usageError();
  }

  return Object.freeze({
    kernelPath: options.get("--kernel") ?? bundledKernelPath,
    imagePath,
    instanceKind: statePath === undefined ? 0 : 1,
    instancePath: statePath ?? initialArgsPath,
    instanceLabel: statePath === undefined ? "initialArgs" : "state",
    effectResultPath: options.get("--result") ?? null,
    outputPath: options.get("--out") ?? null,
  });
}

/**
 * Execute one descriptor-coherent Process step and publish its exact PKO1 bytes.
 *
 * The fixed kernel must be read in order to create the admitted host. Program
 * payloads are not read until `advancePrepared` has completed the kernel's
 * capacity preflight and supplied the exact guest payload view.
 */
export async function executeProcessStep(options) {
  ensureSupportedRuntime();

  const files = [];
  try {
    const kernel = openRegularInput(
      options.kernelPath,
      "kernel",
      files,
      MAXIMUM_KERNEL_BYTES,
    );
    const image = openRegularInput(options.imagePath, "image", files);
    const instance = openRegularInput(
      options.instancePath,
      options.instanceLabel,
      files,
    );
    const effectResult = options.effectResultPath === null
      ? null
      : openRegularInput(options.effectResultPath, "effectResult", files);

    if (options.outputPath === null) {
      inspectStdoutDestination(files);
    } else {
      inspectOutputDestination(options.outputPath, files);
    }

    const kernelBytes = readExactFile(kernel);
    const host = await admitProcessKernel(kernelBytes);

    let payloadWasRead = false;
    const outcome = await advancePrepared(host, {
      instanceKind: options.instanceKind,
      imageLength: checkedU64(image.generation.size, "image"),
      instanceLength: checkedU64(
        instance.generation.size,
        options.instanceLabel,
      ),
      effectResultPresent: effectResult !== null,
      effectResultLength: checkedU64(
        effectResult?.generation.size ?? 0n,
        "effectResult",
      ),
    }, async (payload) => {
      payloadWasRead = true;
      let offset = 0;
      offset = readExactInto(image, payload, offset);
      offset = readExactInto(instance, payload, offset);
      if (effectResult !== null) {
        offset = readExactInto(effectResult, payload, offset);
      }
      if (offset !== payload.byteLength) {
        throw worldError(
          "WORLD_RUNTIME_BINDING_INVALID",
          "the Process kernel exposed an inconsistent input payload range",
        );
      }
    }, () => {
      // This is the coherence cut. Core invokes it synchronously after any
      // payload-writer await and on the same turn immediately before execute.
      verifyGenerations(files);
    });

    // Capacity outcomes do not invoke the payload writer. Their reported sizes
    // are trusted only after the same all-input generation check.
    if (!payloadWasRead) verifyGenerations(files);

    if (options.outputPath === null) {
      writeStdoutExact(outcome.bytes);
    } else {
      publishAtomic(
        options.outputPath,
        outcome.bytes,
      );
    }
    return outcome;
  } finally {
    closeInputs(files);
  }
}

function usageError() {
  return worldError("WORLD_CLI_USAGE", PROCESS_STEP_USAGE);
}

function ensureSupportedRuntime() {
  if (!SUPPORTED_PLATFORMS.has(process.platform) ||
      !bunVersionAtLeast(process.versions.bun, 1, 4)) {
    throw worldError(
      "WORLD_PLATFORM_UNSUPPORTED",
      "world process step requires Bun 1.4 or newer on macOS or Linux",
      { platform: process.platform },
    );
  }
}

function bunVersionAtLeast(version, requiredMajor, requiredMinor) {
  if (typeof version !== "string") return false;
  const match = /^(\d+)\.(\d+)(?:\.|$)/.exec(version);
  if (match === null) return false;
  const major = Number(match[1]);
  const minor = Number(match[2]);
  return major > requiredMajor ||
    (major === requiredMajor && minor >= requiredMinor);
}

function openRegularInput(filePath, label, files, maximumBytes = null) {
  const flags = fs.constants.O_RDONLY |
    fs.constants.O_NONBLOCK |
    (fs.constants.O_CLOEXEC ?? 0);
  let descriptor;
  try {
    descriptor = fs.openSync(filePath, flags);
  } catch (error) {
    throw inputOperationError(label, "open", error);
  }

  try {
    const stat = fs.fstatSync(descriptor, { bigint: true });
    if (!stat.isFile()) {
      throw worldError(
        "WORLD_FILE_NOT_REGULAR",
        `${label} must resolve to a regular file`,
        { artifact: label },
      );
    }
    const file = {
      descriptor,
      generation: generationOf(stat),
      label,
    };
    if (maximumBytes !== null && file.generation.size > maximumBytes) {
      throw worldError(
        "WORLD_KERNEL_TOO_LARGE",
        `${label} exceeds the host byte limit`,
        { artifact: label, maximumBytes },
      );
    }
    files.push(file);
    return file;
  } catch (error) {
    try {
      fs.closeSync(descriptor);
    } catch {
      // The original admission failure is authoritative.
    }
    if (error instanceof WorldProcessHostError) throw error;
    throw inputOperationError(label, "inspect", error);
  }
}

function generationOf(stat) {
  const fields = [stat.dev, stat.ino, stat.size, stat.mtimeNs, stat.ctimeNs];
  if (fields.some((field) => typeof field !== "bigint") || stat.size < 0n) {
    throw worldError(
      "WORLD_PLATFORM_UNSUPPORTED",
      "the runtime cannot provide exact file-generation metadata",
      { platform: process.platform },
    );
  }
  return Object.freeze({
    device: stat.dev,
    inode: stat.ino,
    size: stat.size,
    mtimeNs: stat.mtimeNs,
    ctimeNs: stat.ctimeNs,
  });
}

function sameGeneration(left, right) {
  return left.device === right.device &&
    left.inode === right.inode &&
    left.size === right.size &&
    left.mtimeNs === right.mtimeNs &&
    left.ctimeNs === right.ctimeNs;
}

function sameFile(left, right) {
  return left.device === right.device && left.inode === right.inode;
}

function verifyGeneration(file) {
  let current;
  try {
    current = generationOf(fs.fstatSync(file.descriptor, { bigint: true }));
  } catch (error) {
    if (error instanceof WorldProcessHostError) throw error;
    throw inputOperationError(file.label, "recheck", error);
  }
  if (!sameGeneration(file.generation, current)) {
    throw worldError(
      "WORLD_FILE_CHANGED",
      `${file.label} changed after preflight`,
      { artifact: file.label },
    );
  }
}

function verifyGenerations(files) {
  for (const file of files) verifyGeneration(file);
}

function checkedU64(value, label) {
  if (typeof value !== "bigint" || value < 0n || value > MAXIMUM_U64) {
    throw worldError(
      "WORLD_LENGTH_UNSAFE",
      `${label} length is outside the Process ABI range`,
      { artifact: label },
    );
  }
  return value;
}

function safeMaterializedLength(value, label) {
  if (value > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw worldError(
      "WORLD_LENGTH_UNSAFE",
      `${label} is too large to materialize after capacity preflight`,
      { artifact: label },
    );
  }
  return Number(value);
}

function readExactFile(file) {
  const length = safeMaterializedLength(file.generation.size, file.label);
  const bytes = new Uint8Array(length);
  readExactInto(file, bytes, 0);
  return bytes;
}

function readExactInto(file, target, offset) {
  verifyGeneration(file);
  const length = safeMaterializedLength(file.generation.size, file.label);
  if (!(target instanceof Uint8Array) || !Number.isSafeInteger(offset) ||
      offset < 0 || length > target.byteLength - offset) {
    throw worldError(
      "WORLD_RUNTIME_BINDING_INVALID",
      "the Process kernel exposed an inconsistent input payload range",
    );
  }

  let consumed = 0;
  try {
    while (consumed < length) {
      const count = fs.readSync(
        file.descriptor,
        target,
        offset + consumed,
        length - consumed,
        consumed,
      );
      if (count === 0) {
        throw worldError(
          "WORLD_FILE_CHANGED",
          `${file.label} changed after preflight`,
          { artifact: file.label },
        );
      }
      consumed += count;
    }

    const growthProbe = new Uint8Array(1);
    if (fs.readSync(file.descriptor, growthProbe, 0, 1, length) !== 0) {
      throw worldError(
        "WORLD_FILE_CHANGED",
        `${file.label} changed after preflight`,
        { artifact: file.label },
      );
    }
  } catch (error) {
    if (error instanceof WorldProcessHostError) throw error;
    throw inputOperationError(file.label, "read", error);
  }
  verifyGeneration(file);
  return offset + length;
}

function inspectOutputDestination(outputPath, inputFiles) {
  let stat;
  try {
    stat = fs.lstatSync(outputPath, { bigint: true });
  } catch (error) {
    if (error?.code === "ENOENT") return null;
    throw outputOperationError("inspect", error);
  }

  if (stat.isSymbolicLink() || !stat.isFile()) {
    throw worldError(
      "WORLD_FILE_NOT_REGULAR",
      "output must be absent or an exact regular file",
      { artifact: "output" },
    );
  }
  const outputGeneration = generationOf(stat);
  for (const input of inputFiles) {
    if (sameFile(outputGeneration, input.generation)) {
      throw worldError(
        "WORLD_FILE_ALIAS",
        `output aliases the ${input.label} input`,
        { artifact: input.label },
      );
    }
  }
  return outputGeneration;
}

function inspectStdoutDestination(inputFiles) {
  let stat;
  try {
    stat = fs.fstatSync(fs.constants.STDOUT_FILENO ?? 1, { bigint: true });
  } catch (error) {
    throw outputOperationError("inspect", error);
  }
  if (!stat.isFile()) return;

  const outputGeneration = generationOf(stat);
  for (const input of inputFiles) {
    if (sameFile(outputGeneration, input.generation)) {
      throw worldError(
        "WORLD_FILE_ALIAS",
        `stdout aliases the ${input.label} input`,
        { artifact: input.label },
      );
    }
  }
}

function publishAtomic(outputPath, bytes) {
  const directory = path.dirname(path.resolve(outputPath));
  let temporaryPath = null;
  let descriptor = null;
  let renamed = false;
  try {
    ({ path: temporaryPath, descriptor } = openSiblingTemporary(directory));
    fs.fchmodSync(descriptor, 0o600);
    writeDescriptorExact(descriptor, bytes);
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor);
    descriptor = null;

    fs.renameSync(temporaryPath, outputPath);
    renamed = true;
    temporaryPath = null;
  } catch (error) {
    if (error instanceof WorldProcessHostError) throw error;
    throw outputOperationError("publish", error);
  } finally {
    if (descriptor !== null) {
      try {
        fs.closeSync(descriptor);
      } catch {
        // The publication error, if any, remains authoritative.
      }
    }
    if (!renamed && temporaryPath !== null) {
      try {
        fs.unlinkSync(temporaryPath);
      } catch {
        // Best-effort cleanup of an unpublished temporary file.
      }
    }
  }

  // Once rename succeeds the new output must remain in place even when the
  // embedding filesystem cannot establish directory durability.
  let directoryDescriptor = null;
  try {
    directoryDescriptor = fs.openSync(
      directory,
      fs.constants.O_RDONLY |
        (fs.constants.O_DIRECTORY ?? 0) |
        (fs.constants.O_CLOEXEC ?? 0),
    );
    fs.fsyncSync(directoryDescriptor);
  } catch (error) {
    throw worldError(
      "WORLD_OUTPUT_DURABILITY_UNCERTAIN",
      "output was renamed but directory durability could not be confirmed",
      { artifact: "output", operation: "directory-fsync" },
    );
  } finally {
    if (directoryDescriptor !== null) {
      try {
        fs.closeSync(directoryDescriptor);
      } catch {
        // Closing a directory descriptor cannot undo the completed fsync.
      }
    }
  }
}

function openSiblingTemporary(directory) {
  const flags = fs.constants.O_WRONLY |
    fs.constants.O_CREAT |
    fs.constants.O_EXCL |
    (fs.constants.O_NOFOLLOW ?? 0) |
    (fs.constants.O_CLOEXEC ?? 0);
  for (let attempt = 0; attempt < 16; attempt += 1) {
    const temporaryPath = path.join(
      directory,
      `.world-${process.pid}-${randomBytes(16).toString("hex")}.tmp`,
    );
    try {
      return {
        path: temporaryPath,
        descriptor: fs.openSync(temporaryPath, flags, 0o600),
      };
    } catch (error) {
      if (error?.code === "EEXIST") continue;
      throw error;
    }
  }
  throw worldError(
    "WORLD_OUTPUT_PUBLISH_FAILED",
    "could not allocate a sibling output temporary file",
    { artifact: "output" },
  );
}

function writeDescriptorExact(descriptor, bytes) {
  if (!(bytes instanceof Uint8Array)) {
    throw worldError(
      "WORLD_RUNTIME_BINDING_INVALID",
      "the Process host returned a non-byte outcome",
    );
  }
  let offset = 0;
  while (offset < bytes.byteLength) {
    const written = fs.writeSync(
      descriptor,
      bytes,
      offset,
      bytes.byteLength - offset,
      null,
    );
    if (written === 0) {
      throw worldError(
        "WORLD_OUTPUT_PUBLISH_FAILED",
        "output could not be written completely",
        { artifact: "output" },
      );
    }
    offset += written;
  }
}

function writeStdoutExact(bytes) {
  try {
    writeDescriptorExact(fs.constants.STDOUT_FILENO ?? 1, bytes);
  } catch (error) {
    if (error instanceof WorldProcessHostError) throw error;
    throw outputOperationError("write", error);
  }
}

function closeInputs(files) {
  for (let index = files.length - 1; index >= 0; index -= 1) {
    try {
      fs.closeSync(files[index].descriptor);
    } catch {
      // Input descriptors own no durable state. Never mask the actual result.
    }
  }
}

function inputOperationError(label, operation, cause) {
  return worldError(
    "WORLD_INPUT_INVALID",
    `${label} could not be ${operation === "read" ? "read" : "admitted"}`,
    {
      artifact: label,
      operation,
      systemCode: safeSystemCode(cause),
    },
  );
}

function outputOperationError(operation, cause) {
  return worldError(
    "WORLD_OUTPUT_PUBLISH_FAILED",
    "output could not be published",
    {
      artifact: "output",
      operation,
      systemCode: safeSystemCode(cause),
    },
  );
}

function safeSystemCode(error) {
  return typeof error?.code === "string" ? error.code : "UNKNOWN";
}
