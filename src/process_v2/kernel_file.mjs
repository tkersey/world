// Copyright (c) 2026 World contributors. MIT license.
import { assertProcessKernelByteLength } from "./wasm.mjs";
import { readRegularFile } from "./file_input.mjs";

/** Retain every selected file alongside the bytes and their digest authority. */
export async function readProcessKernelFile({ kernelPath, expectedSha256 } = {}, packageVersion) {
  const files = [];
  if (kernelPath === undefined) {
    const identityPath = new URL("../../world-runtime-identity.json", import.meta.url);
    const identity = JSON.parse((await readRegularFile(identityPath)).toString("utf8"));
    files.push(identityPath);
    if (identity.format !== "world-runtime-identity/v2" || identity.version !== packageVersion ||
        identity.kernel?.file !== "world-process-kernel-v2.wasm" || identity.abi !== 2) throw new Error("InvalidRuntimeIdentity");
    if (expectedSha256 !== undefined && expectedSha256 !== identity.kernel.sha256) throw new Error("KernelIdentityMismatch");
    expectedSha256 = identity.kernel.sha256;
    kernelPath = new URL("../../world-process-kernel-v2.wasm", import.meta.url);
  }
  const bytes = await readRegularFile(kernelPath, assertProcessKernelByteLength);
  files.push(kernelPath);
  return { bytes, expectedSha256, files };
}
