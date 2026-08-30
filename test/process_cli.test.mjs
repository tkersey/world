import { afterEach, describe, expect, test } from "bun:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { WorldProcessHostError } from "../src/process_v1/errors.mjs";
import {
  executeProcessStep,
  parseProcessStepArguments,
  PROCESS_STEP_USAGE,
} from "../src/process_v1/file_input.mjs";

const CLI = fileURLToPath(new URL("../bin/world.mjs", import.meta.url));
const KERNEL = fileURLToPath(
  new URL("../boundary-process-kernel-v1.wasm", import.meta.url),
);
const REQUESTED_IMAGE = fileURLToPath(new URL(
  "../conformance/vectors/artifacts/typed-effect-initial.image",
  import.meta.url,
));
const REQUESTED_INITIAL_ARGS = fileURLToPath(new URL(
  "../conformance/vectors/artifacts/typed-effect-initial.instance",
  import.meta.url,
));
const REQUESTED_OUTCOME = fileURLToPath(new URL(
  "../conformance/vectors/artifacts/typed-effect-initial.outcome",
  import.meta.url,
));
const WIDE_LENGTH = 0x1_0000_0000;
const temporaryDirectories = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

describe("world process step argument grammar", () => {
  test("accepts exactly the initial and State forms", () => {
    expect(parseProcessStepArguments([
      "process",
      "step",
      "--image",
      "image.bpi1",
      "--initial-args",
      "initial.bin",
    ], "/bundled/kernel.wasm")).toEqual({
      kernelPath: "/bundled/kernel.wasm",
      imagePath: "image.bpi1",
      instanceKind: 0,
      instancePath: "initial.bin",
      instanceLabel: "initialArgs",
      effectResultPath: null,
      outputPath: null,
    });

    expect(parseProcessStepArguments([
      "process",
      "step",
      "--result",
      "result.ers1",
      "--out",
      "out.pko1",
      "--kernel",
      "kernel.wasm",
      "--state",
      "state.pst1",
      "--image",
      "image.bpi1",
    ], "/bundled/kernel.wasm")).toEqual({
      kernelPath: "kernel.wasm",
      imagePath: "image.bpi1",
      instanceKind: 1,
      instancePath: "state.pst1",
      instanceLabel: "state",
      effectResultPath: "result.ers1",
      outputPath: "out.pko1",
    });
  });

  test("rejects every token outside the exact grammar", () => {
    const invalid = [
      [],
      ["process"],
      ["process", "run"],
      ["process", "step"],
      ["process", "step", "--image", "image"],
      ["process", "step", "--initial-args", "initial"],
      [
        "process",
        "step",
        "--image",
        "image",
        "--initial-args",
        "initial",
        "--state",
        "state",
      ],
      [
        "process",
        "step",
        "--image",
        "image",
        "--initial-args",
        "initial",
        "--image",
        "again",
      ],
      [
        "process",
        "step",
        "--image",
        "--state",
        "--initial-args",
        "initial",
      ],
      [
        "process",
        "step",
        "--image",
        "image",
        "--initial-args",
        "initial",
        "--unknown",
        "value",
      ],
      [
        "process",
        "step",
        "--image",
        "image",
        "--initial-args",
        "initial",
        "trailing",
      ],
    ];

    for (const argv of invalid) {
      expect(() => parseProcessStepArguments(argv, "/kernel")).toThrow(
        expect.objectContaining({ code: "WORLD_CLI_USAGE" }),
      );
    }
  });

  test("maps usage errors to exit 2 without a stack trace", () => {
    const result = runCli([]);
    expect(result.exitCode).toBe(2);
    expect(Buffer.from(result.stdout)).toHaveLength(0);
    expect(text(result.stderr)).toBe(
      `WORLD_CLI_USAGE: ${PROCESS_STEP_USAGE}\n`,
    );
  });
});

describe("descriptor and output admission", () => {
  test("rejects a FIFO without blocking", () => {
    const directory = temporaryDirectory();
    const image = writeFile(directory, "image.bpi1", new Uint8Array());
    const fifo = path.join(directory, "instance.fifo");
    const made = Bun.spawnSync({ cmd: ["mkfifo", fifo] });
    expect(made.exitCode).toBe(0);

    const result = runCli([
      "process",
      "step",
      "--image",
      image,
      "--initial-args",
      fifo,
    ]);
    expect(result.exitCode).toBe(1);
    expect(text(result.stderr)).toContain("WORLD_FILE_NOT_REGULAR");
    expect(text(result.stderr)).not.toContain(fifo);
  });

  test("rejects mutation of every admitted input generation during read", async () => {
    const scenarios = [
      { target: "kernel", instanceKind: 0, instanceLabel: "initialArgs", withResult: false },
      { target: "image", instanceKind: 0, instanceLabel: "initialArgs", withResult: false },
      { target: "state", instanceKind: 1, instanceLabel: "state", withResult: false },
      { target: "effectResult", instanceKind: 1, instanceLabel: "state", withResult: true },
    ];

    for (const scenario of scenarios) {
      const directory = temporaryDirectory();
      const kernel = path.join(directory, "kernel.wasm");
      fs.copyFileSync(KERNEL, kernel);
      const image = writeFile(directory, "image.bpi1", Uint8Array.of(1));
      const instance = writeFile(directory, "instance.bin", Uint8Array.of(2));
      const effectResult = writeFile(directory, "result.ers1", Uint8Array.of(3));
      const target = {
        kernel,
        image,
        state: instance,
        effectResult,
      }[scenario.target];

      const descriptorPaths = new Map();
      const originalOpenSync = fs.openSync;
      const originalReadSync = fs.readSync;
      let mutated = false;
      fs.openSync = function patchedOpenSync(file, ...args) {
        const descriptor = originalOpenSync.call(fs, file, ...args);
        if (typeof file === "string") descriptorPaths.set(descriptor, path.resolve(file));
        return descriptor;
      };
      fs.readSync = function patchedReadSync(descriptor, ...args) {
        const count = originalReadSync.call(fs, descriptor, ...args);
        if (!mutated && count > 0 && descriptorPaths.get(descriptor) === path.resolve(target)) {
          mutated = true;
          const writer = originalOpenSync.call(fs, target, fs.constants.O_WRONLY);
          try {
            fs.writeSync(writer, Uint8Array.of(0xff), 0, 1, 0);
            fs.fsyncSync(writer);
          } finally {
            fs.closeSync(writer);
          }
        }
        return count;
      };

      let failure;
      try {
        await executeProcessStep({
          kernelPath: kernel,
          imagePath: image,
          instanceKind: scenario.instanceKind,
          instancePath: instance,
          instanceLabel: scenario.instanceLabel,
          effectResultPath: scenario.withResult ? effectResult : null,
          outputPath: path.join(directory, "must-not-exist.pko1"),
        });
      } catch (error) {
        failure = error;
      } finally {
        fs.openSync = originalOpenSync;
        fs.readSync = originalReadSync;
      }

      expect(mutated).toBe(true);
      expect(failure).toBeInstanceOf(WorldProcessHostError);
      expect(failure.code).toBe("WORLD_FILE_CHANGED");
      expect(failure.details.artifact).toBe(scenario.target);
      expect(fs.existsSync(path.join(directory, "must-not-exist.pko1"))).toBe(false);
    }
  });

  test("rejects an output inode that aliases any input", () => {
    const directory = temporaryDirectory();
    const image = writeFile(directory, "image.bpi1", new Uint8Array());
    const initial = writeFile(directory, "initial.bin", new Uint8Array());
    const output = path.join(directory, "output.pko1");
    fs.linkSync(image, output);

    const result = runCli([
      "process",
      "step",
      "--image",
      image,
      "--initial-args",
      initial,
      "--out",
      output,
    ]);
    expect(result.exitCode).toBe(1);
    expect(text(result.stderr)).toContain("WORLD_FILE_ALIAS");
    expect(text(result.stderr)).not.toContain(image);
    expect(text(result.stderr)).not.toContain(output);
  });

  test("rejects append and read-write stdout aliases while allowing a pipe", () => {
    const directory = temporaryDirectory();
    const image = path.join(directory, "image.bpi1");
    const initial = path.join(directory, "initial.bin");
    fs.copyFileSync(REQUESTED_IMAGE, image);
    fs.copyFileSync(REQUESTED_INITIAL_ARGS, initial);
    const args = [
      "process",
      "step",
      "--image",
      image,
      "--initial-args",
      initial,
    ];

    const aliases = [
      {
        target: image,
        flags: fs.constants.O_WRONLY | fs.constants.O_APPEND,
      },
      {
        target: initial,
        flags: fs.constants.O_RDWR,
      },
    ];
    for (const { target, flags } of aliases) {
      const before = fs.readFileSync(target);
      const result = runCliWithStdoutDescriptor(args, target, flags);
      expect(result.exitCode).toBe(1);
      expect(text(result.stderr)).toContain("WORLD_FILE_ALIAS");
      expect(text(result.stderr)).not.toContain(target);
      expect(fs.readFileSync(target)).toEqual(before);
    }

    const piped = runCli(args);
    expect(piped.exitCode).toBe(0);
    expect(Buffer.from(piped.stderr)).toHaveLength(0);
    expect(Buffer.from(piped.stdout)).toEqual(fs.readFileSync(REQUESTED_OUTCOME));
  });

  test("rejects an output symlink rather than replacing through it", () => {
    const directory = temporaryDirectory();
    const image = writeFile(directory, "image.bpi1", new Uint8Array());
    const initial = writeFile(directory, "initial.bin", new Uint8Array());
    const target = writeFile(directory, "target.pko1", new Uint8Array([1]));
    const output = path.join(directory, "output.pko1");
    fs.symlinkSync(target, output);

    const result = runCli([
      "process",
      "step",
      "--image",
      image,
      "--initial-args",
      initial,
      "--out",
      output,
    ]);
    expect(result.exitCode).toBe(1);
    expect(text(result.stderr)).toContain("WORLD_FILE_NOT_REGULAR");
    expect(fs.readFileSync(target)).toEqual(Buffer.from([1]));
  });
});

describe("canonical Process outcome publication", () => {
  test("preflights sparse inputs and supports bundled and exact override kernels", () => {
    const directory = temporaryDirectory();
    const image = writeFile(directory, "image.bpi1", new Uint8Array());
    const initial = path.join(directory, "wide.initial");
    writeSparseFile(initial, WIDE_LENGTH);

    const stdoutResult = runCli([
      "process",
      "step",
      "--image",
      image,
      "--initial-args",
      initial,
    ]);
    expect(stdoutResult.exitCode).toBe(0);
    expect(Buffer.from(stdoutResult.stderr)).toHaveLength(0);
    const expectedOutcome = Buffer.from(stdoutResult.stdout);
    expectNeedsCapacity(expectedOutcome, BigInt(WIDE_LENGTH) + 40n);

    const overrideKernel = path.join(directory, "kernel.wasm");
    fs.copyFileSync(KERNEL, overrideKernel);
    const output = writeFile(directory, "outcome.pko1", new Uint8Array([9]));
    fs.chmodSync(output, 0o644);
    const outputResult = runCli([
      "process",
      "step",
      "--kernel",
      overrideKernel,
      "--image",
      image,
      "--initial-args",
      initial,
      "--out",
      output,
    ]);
    expect(outputResult.exitCode).toBe(0);
    expect(Buffer.from(outputResult.stdout)).toHaveLength(0);
    expect(Buffer.from(outputResult.stderr)).toHaveLength(0);
    expect(fs.readFileSync(output)).toEqual(expectedOutcome);
    expect(fs.statSync(output).mode & 0o777).toBe(0o600);
    expect(
      fs.readdirSync(directory).filter((name) => name.startsWith(".world-")),
    ).toEqual([]);

    const differentKernel = path.join(directory, "different-kernel.wasm");
    fs.writeFileSync(differentKernel, Buffer.concat([
      fs.readFileSync(KERNEL),
      // A valid empty-name custom section changes identity without changing
      // the kernel's callable ABI shape.
      Buffer.from([0x00, 0x01, 0x00]),
    ]));
    const rejected = runCli([
      "process",
      "step",
      "--kernel",
      differentKernel,
      "--image",
      image,
      "--initial-args",
      initial,
    ]);
    expect(rejected.exitCode).toBe(1);
    expect(text(rejected.stderr)).toContain("WORLD_KERNEL_DIGEST_MISMATCH");
    expect(Buffer.from(rejected.stdout)).toHaveLength(0);
  });

  test("rechecks every descriptor after the writer await and before execute", async () => {
    const directory = temporaryDirectory();
    const image = writeFile(directory, "image.bpi1", new Uint8Array());
    const initial = writeFile(directory, "initial.bin", new Uint8Array([1]));
    const descriptorPaths = new Map();
    const originalOpenSync = fs.openSync;
    const originalFstatSync = fs.fstatSync;
    let mutated = false;
    let initialGenerationChecks = 0;

    fs.openSync = function patchedOpenSync(file, ...args) {
      const descriptor = originalOpenSync.call(fs, file, ...args);
      if (typeof file === "string") {
        descriptorPaths.set(descriptor, path.resolve(file));
      }
      return descriptor;
    };
    fs.fstatSync = function patchedFstatSync(descriptor, ...args) {
      const stat = originalFstatSync.call(fs, descriptor, ...args);
      if (descriptorPaths.get(descriptor) === path.resolve(initial)) {
        initialGenerationChecks += 1;
        // The third check closes readExactInto. Queue a mutation into the exact
        // await gap that used to follow the payload writer. The core-owned
        // beforeExecute cut must observe it before invoking the kernel.
        if (initialGenerationChecks === 3) {
          queueMicrotask(() => {
            mutated = true;
            fs.appendFileSync(image, Buffer.from([1]));
          });
        }
      }
      return stat;
    };

    let failure;
    try {
      await executeProcessStep({
        kernelPath: KERNEL,
        imagePath: image,
        instanceKind: 0,
        instancePath: initial,
        instanceLabel: "initialArgs",
        effectResultPath: null,
        outputPath: path.join(directory, "must-not-exist.pko1"),
      });
    } catch (error) {
      failure = error;
    } finally {
      fs.openSync = originalOpenSync;
      fs.fstatSync = originalFstatSync;
    }

    expect(mutated).toBe(true);
    // Admission, pre-read, and post-read completed for InitialArgs. The queued
    // image mutation then fires in the writer's await gap; the final all-input
    // cut rejects that earlier image before it reaches InitialArgs again.
    expect(initialGenerationChecks).toBe(3);
    expect(failure).toBeInstanceOf(WorldProcessHostError);
    expect(failure.code).toBe("WORLD_FILE_CHANGED");
    expect(failure.details.artifact).toBe("image");
    expect(fs.existsSync(path.join(directory, "must-not-exist.pko1"))).toBe(false);
  });

  test("retains a renamed output when directory durability is uncertain", async () => {
    const directory = temporaryDirectory();
    const image = writeFile(directory, "image.bpi1", new Uint8Array());
    const initial = path.join(directory, "wide.initial");
    const output = path.join(directory, "outcome.pko1");
    writeSparseFile(initial, WIDE_LENGTH);

    const originalFsyncSync = fs.fsyncSync;
    fs.fsyncSync = function patchedFsyncSync(descriptor) {
      if (fs.fstatSync(descriptor).isDirectory()) {
        const failure = new Error("injected directory fsync failure");
        failure.code = "EIO";
        throw failure;
      }
      return originalFsyncSync.call(fs, descriptor);
    };

    let failure;
    try {
      await executeProcessStep({
        kernelPath: KERNEL,
        imagePath: image,
        instanceKind: 0,
        instancePath: initial,
        instanceLabel: "initialArgs",
        effectResultPath: null,
        outputPath: output,
      });
    } catch (error) {
      failure = error;
    } finally {
      fs.fsyncSync = originalFsyncSync;
    }

    expect(failure).toBeInstanceOf(WorldProcessHostError);
    expect(failure.code).toBe("WORLD_OUTPUT_DURABILITY_UNCERTAIN");
    expectNeedsCapacity(fs.readFileSync(output), BigInt(WIDE_LENGTH) + 40n);
    expect(fs.statSync(output).mode & 0o777).toBe(0o600);
  });
});

function temporaryDirectory() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "world-process-cli-"));
  temporaryDirectories.push(directory);
  return directory;
}

function writeFile(directory, name, bytes) {
  const file = path.join(directory, name);
  fs.writeFileSync(file, bytes);
  return file;
}

function writeSparseFile(file, length) {
  const descriptor = fs.openSync(file, "w");
  try {
    fs.ftruncateSync(descriptor, length);
  } finally {
    fs.closeSync(descriptor);
  }
}

function runCli(args) {
  return Bun.spawnSync({
    cmd: [process.execPath, CLI, ...args],
    env: process.env,
    stdout: "pipe",
    stderr: "pipe",
  });
}

function runCliWithStdoutDescriptor(args, outputPath, flags) {
  const descriptor = fs.openSync(outputPath, flags);
  try {
    return Bun.spawnSync({
      cmd: [process.execPath, CLI, ...args],
      env: process.env,
      stdout: descriptor,
      stderr: "pipe",
    });
  } finally {
    fs.closeSync(descriptor);
  }
}

function expectNeedsCapacity(bytes, minimumInputBytes) {
  const buffer = Buffer.from(bytes);
  expect(buffer).toHaveLength(64);
  expect(buffer.subarray(0, 8).toString("ascii")).toBe("ABL_PKO1");
  expect(buffer.readUInt16LE(8)).toBe(1);
  expect(buffer[10]).toBe(5);
  expect(buffer[11]).toBe(0);
  expect(buffer.readBigUInt64LE(12)).toBe(32n);
  expect(buffer.readBigUInt64LE(20)).toBe(0n);
  expect(buffer.readUInt32LE(28)).toBe(0);
  expect(buffer.readBigUInt64LE(32)).toBe(minimumInputBytes);
}

function text(bytes) {
  return new TextDecoder().decode(bytes);
}
