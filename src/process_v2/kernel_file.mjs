// Copyright (c) 2026 World contributors. MIT license.
import { constants } from "node:fs";
import { open, readFile } from "node:fs/promises";
import { assertProcessKernelByteLength } from "./wasm.mjs";
import { worldError } from "./errors.mjs";

async function readKernelBytes(path) {
  const file = await open(path, constants.O_RDONLY | constants.O_NONBLOCK | (constants.O_CLOEXEC ?? 0));
  try {
    const before = await file.stat({ bigint: true });
    if (!before.isFile()) throw worldError("WORLD_FILE_NOT_REGULAR", "Process kernel must resolve to a regular file");
    assertProcessKernelByteLength(before.size);
    const bytes = Buffer.alloc(Number(before.size));
    let offset = 0;
    while (offset < bytes.length) {
      const { bytesRead } = await file.read(bytes, offset, bytes.length - offset, offset);
      if (bytesRead === 0) throw worldError("WORLD_FILE_CHANGED", "Process kernel changed while reading");
      offset += bytesRead;
    }
    const after = await file.stat({ bigint: true });
    assertProcessKernelByteLength(after.size);
    if (before.size !== after.size || before.mtimeNs !== after.mtimeNs || before.ctimeNs !== after.ctimeNs) {
      throw worldError("WORLD_FILE_CHANGED", "Process kernel changed while reading");
    }
    return bytes;
  } finally { await file.close(); }
}

/** Retain every selected file alongside the bytes and their digest authority. */
export async function readProcessKernelFile({ kernelPath, expectedSha256 } = {}, packageVersion) {
  const files = [];
  if (kernelPath === undefined) {
    const identityPath = new URL("../../world-runtime-identity.json", import.meta.url);
    const identity = JSON.parse(await readFile(identityPath, "utf8"));
    files.push(identityPath);
    if (identity.format !== "world-runtime-identity/v2" || identity.version !== packageVersion ||
        identity.kernel?.file !== "world-process-kernel-v2.wasm" || identity.abi !== 2) throw new Error("InvalidRuntimeIdentity");
    if (expectedSha256 !== undefined && expectedSha256 !== identity.kernel.sha256) throw new Error("KernelIdentityMismatch");
    expectedSha256 = identity.kernel.sha256;
    kernelPath = new URL("../../world-process-kernel-v2.wasm", import.meta.url);
  }
  const bytes = await readKernelBytes(kernelPath);
  files.push(kernelPath);
  return { bytes, expectedSha256, files };
}
